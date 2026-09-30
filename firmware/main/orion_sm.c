#include "orion_sm.h"

#include <inttypes.h>
#include <string.h>

#include "freertos/FreeRTOS.h"
#include "freertos/task.h"
#include "freertos/queue.h"
#include "esp_log.h"
#include "esp_timer.h"
#include "esp_heap_caps.h"

#include "board.h"
#include "orion_net.h"
#include "orion_audio.h"
#include "orion_wakeword.h"
#include "orion_ui.h"
#include "orion_turn.h"
#include "orion_config.h"
#include "orion_camera.h"
#include "orion_api.h"

#include "orion_cloud.h"
#include "orion_settings.h"

static const char *TAG = "sm";

#define TURN_DEADLINE_MS 30000
#define BOOT_NET_MS      20000
#define LEVEL_PERIOD_MS  30
// DeepInfra drops an idle connection after 60 to 90 s, and a new TLS session
// costs this chip 1.5 to 3.3 s. A HEAD on each kept alive socket this often
// means the first question after a quiet spell pays nothing.
#define HEARTBEAT_MS     40000

typedef struct {
    orion_event_t ev;
    int32_t arg;
} sm_msg_t;

static QueueHandle_t s_q;
static orion_state_t s_state = OS_BOOT;
static esp_timer_handle_t s_deadline;
static esp_timer_handle_t s_boot;
static esp_timer_handle_t s_heartbeat;
static uint32_t s_turns;

// ---------------------------------------------------------------------------
// Inputs. Each runs on somebody else's task and only posts.
// ---------------------------------------------------------------------------
void sm_post(orion_event_t ev, int32_t arg)
{
    sm_msg_t m = { .ev = ev, .arg = arg };
    if (s_q && xQueueSend(s_q, &m, 0) != pdTRUE) {
        ESP_LOGW(TAG, "queue full, dropped event %d", ev);
    }
}

static void on_wakeword(void *ctx)                     { sm_post(EV_WAKE, 0); }
static void on_tap(void *ctx)                          { sm_post(EV_TAP, 0); }
static void on_deadline(void *ctx)                     { sm_post(EV_TIMEOUT, 0); }
static void on_boot_timer(void *ctx)                   { sm_post(EV_NET_DOWN, 1); }

// Only posts to idle cloud workers, never blocks, so it is safe on the timer task.
static void on_heartbeat(void *ctx)
{
    if (s_state == OS_IDLE && orion_net_is_up()) {
        orion_cloud_prewarm();
        sm_post(EV_PC_INFO, 0);
    }
}

static void on_button(board_btn_event_t e, void *ctx)
{
    sm_post(e == BOARD_BTN_LONG ? EV_CANCEL : EV_BUTTON, 0);
}

static void on_net(orion_net_state_t st, void *ctx)
{
    sm_post(st == ORION_NET_UP ? EV_NET_UP : EV_NET_DOWN, 0);
}

// ---------------------------------------------------------------------------
// Transitions
// ---------------------------------------------------------------------------
static void enter(orion_state_t st)
{
    if (st != s_state) {
        ESP_LOGI(TAG, "%s -> %s", orion_state_name(s_state), orion_state_name(st));
        s_state = st;
    }
    ui_set_state(st);
    orion_api_publish_state(st);
}

static void push_net_info(void)
{
    char ip[20] = "";
    char ssid[33] = "";
    bool up = orion_net_is_up();
    if (up) {
        orion_net_ip(ip, sizeof(ip));
    }
    orion_config_copy_str(ORION_CFG_WIFI_SSID, ssid, sizeof(ssid), "");
    ui_set_net_info(up, ssid, up ? ip : NULL, up ? orion_net_rssi() : 0);
}

// The PC card: connected while the PC brain answers its health check (every
// prewarm: the wake word and the 40 s heartbeat). The app turns PC control on.
static void push_pc_info(void)
{
    char host[64];
    const bool online = orion_cloud_pc_online(host, sizeof(host));
    ui_set_pc_info(online, online, online ? "PC" : NULL, host[0] ? host : NULL);
}

static void on_pc_refresh(void *ctx)
{
    orion_cloud_prewarm();
    push_pc_info();
}

static bool wake_word_on(void)
{
    bool on = true;
    orion_settings_basic(NULL, 0, NULL, &on);
    return on;
}

// Idle and offline both listen for the wake word, unless the owner turned it
// off in the app; then only a tap or the button starts a turn. Offline only
// answers with the offline earcon, so the user learns why it is not working.
static void listen_for_wake_word(void)
{
    const bool on = wake_word_on();
    ui_set_wake_word(on);
    if (on) {
        orion_wakeword_start(on_wakeword, NULL);
    } else {
        orion_wakeword_stop();
    }
}

static void go_idle(void)
{
    esp_timer_stop(s_deadline);
    ui_set_text("");
    enter(orion_net_is_up() ? OS_IDLE : OS_OFFLINE);
    listen_for_wake_word();
    push_pc_info();
}

static const char *earcon_for(orion_error_t err)
{
    switch (err) {
    case ERR_OFFLINE:   return "earcons/offline.wav";
    case ERR_NO_SPEECH: return "earcons/repeat.wav";
    default:            return "earcons/error.wav";
    }
}

static void fail(orion_error_t err)
{
    ESP_LOGW(TAG, "turn %" PRIu32 " failed: %d", s_turns, err);
    esp_timer_stop(s_deadline);
    turn_cancel();
    enter(OS_ERROR);
    orion_audio_play_asset(earcon_for(err));
    go_idle();
}

// POST /api/say. Thinking until the first audio, then speaking, then idle,
// like any reply, so the screen and the app follow it the same way.
static void begin_say(void)
{
    if (s_state != OS_IDLE || !orion_net_is_up()) {
        return;
    }
    s_turns++;
    orion_wakeword_stop();
    enter(OS_WAKE);
    esp_timer_start_once(s_deadline, (uint64_t) TURN_DEADLINE_MS * 1000);
    enter(OS_THINKING);
    turn_begin_say();
}

static void begin_turn(bool from_text)
{
    if (s_state != OS_IDLE && s_state != OS_OFFLINE) {
        return;
    }
    if (!orion_net_is_up()) {
        enter(OS_ERROR);
        orion_audio_play_asset("earcons/offline.wav");
        go_idle();
        return;
    }
    s_turns++;
    if (!from_text) {
        // The recording starts here, at the wake word, not after the chime, so
        // "Orion, what time is it" in one breath keeps its first word.
        orion_audio_mark_utterance();
    }
    // TLS handshakes start now, while the user is still talking. Returns at once.
    orion_cloud_prewarm();
    orion_wakeword_stop();
    enter(OS_WAKE);
    esp_timer_start_once(s_deadline, (uint64_t) TURN_DEADLINE_MS * 1000);
    if (from_text) {
        enter(OS_THINKING);
        turn_begin_text();
        return;
    }
    enter(OS_LISTENING);
    turn_begin();
    // Over the recording, with the mic open. The recorder knows the speaker is
    // playing and never takes the chime for speech.
    orion_audio_play_asset_mic_open("earcons/wake.wav");
}

static void log_turn(void)
{
    turn_timing_t t;
    turn_last_timing(&t);
    ESP_LOGI(TAG, "turn=%" PRIu32 " asr_ms=%" PRIu32 " llm_ms=%" PRIu32
             " tts_first_ms=%" PRIu32 " tts_total_ms=%" PRIu32 " total_ms=%" PRIu32
             " heap_int=%u psram_free=%u%s",
             s_turns, t.asr_ms, t.llm_ms, t.tts_first_ms, t.tts_total_ms, t.total_ms,
             (unsigned) heap_caps_get_free_size(MALLOC_CAP_INTERNAL),
             (unsigned) heap_caps_get_free_size(MALLOC_CAP_SPIRAM),
             t.used_camera ? " camera=1" : "");
}

static void handle(const sm_msg_t *m)
{
    switch (m->ev) {
    case EV_WAKE:
    case EV_BUTTON:
    case EV_TAP:
        if (s_state == OS_SPEAKING) {
            // A tap while it talks means "stop", there is no barge in by voice.
            turn_cancel();
            go_idle();
        } else {
            begin_turn(false);
        }
        break;

    case EV_ASK:
        begin_turn(true);
        break;

    case EV_SAY:
        begin_say();
        break;

    // A PC brain opening an app, searching it and clicking a result can take
    // a minute; the deadline is 30 s without a sign of life, not 30 s in all.
    case EV_PROGRESS:
        if (s_state == OS_THINKING || s_state == OS_SPEAKING) {
            esp_timer_stop(s_deadline);
            esp_timer_start_once(s_deadline, (uint64_t) TURN_DEADLINE_MS * 1000);
        }
        break;

    case EV_SPEECH_END:
        if (s_state == OS_LISTENING) {
            ESP_LOGI(TAG, "recorded %" PRId32 " ms", m->arg);
            enter(OS_THINKING);
        }
        break;

    case EV_ASR_DONE:
        ui_set_text(turn_last_transcript());
        orion_api_publish_text("user", turn_last_transcript());
        break;

    case EV_LLM_DONE:
        ui_set_text(turn_last_reply());
        orion_api_publish_text("assistant", turn_last_reply());
        break;

    case EV_TTS_CHUNK:
        if (s_state == OS_THINKING) {
            enter(OS_SPEAKING);
        }
        break;

    case EV_TTS_DONE:
        log_turn();
        go_idle();
        break;

    case EV_ERROR:
        fail((orion_error_t) m->arg);
        break;

    case EV_TIMEOUT:
        fail(ERR_TIMEOUT);
        break;

    case EV_CANCEL:
        if (s_state != OS_IDLE && s_state != OS_OFFLINE && s_state != OS_BOOT) {
            ESP_LOGI(TAG, "cancelled");
            turn_cancel();
            go_idle();
        }
        break;

    case EV_SETTINGS:
        if (s_state == OS_IDLE || s_state == OS_OFFLINE) {
            listen_for_wake_word();
        }
        break;

    case EV_PC_INFO:
        push_pc_info();
        break;

    case EV_NET_UP:
        esp_timer_stop(s_boot);
        push_net_info();
        orion_cloud_prewarm();
        if (s_state == OS_BOOT || s_state == OS_OFFLINE) {
            go_idle();
        }
        break;

    case EV_NET_DOWN:
        push_net_info();
        if (s_state == OS_BOOT || s_state == OS_IDLE) {
            go_idle();
        }
        // Mid turn, the cloud call fails on its own and reports EV_ERROR.
        break;
    }
}

static void sm_task(void *arg)
{
    sm_msg_t m;
    while (true) {
        // While listening, the mic level feeds the orb from this task, so
        // every ui_ call in the firmware comes from one place.
        bool live = s_state == OS_LISTENING || s_state == OS_SPEAKING;
        TickType_t wait = live ? pdMS_TO_TICKS(LEVEL_PERIOD_MS) : portMAX_DELAY;
        if (xQueueReceive(s_q, &m, wait) == pdTRUE) {
            handle(&m);
        } else if (s_state == OS_LISTENING) {
            ui_set_level(orion_audio_level());
        } else if (s_state == OS_SPEAKING) {
            ui_set_level(orion_audio_out_level());
        }
    }
}

esp_err_t sm_start(void)
{
    s_q = xQueueCreate(16, sizeof(sm_msg_t));
    if (!s_q) {
        return ESP_ERR_NO_MEM;
    }

    const esp_timer_create_args_t dl = { .callback = on_deadline, .name = "turn_deadline" };
    const esp_timer_create_args_t bt = { .callback = on_boot_timer, .name = "boot_net" };
    const esp_timer_create_args_t hb = { .callback = on_heartbeat, .name = "cloud_heartbeat" };
    ESP_ERROR_CHECK(esp_timer_create(&dl, &s_deadline));
    ESP_ERROR_CHECK(esp_timer_create(&bt, &s_boot));
    ESP_ERROR_CHECK(esp_timer_create(&hb, &s_heartbeat));
    ESP_ERROR_CHECK(esp_timer_start_periodic(s_heartbeat, (uint64_t) HEARTBEAT_MS * 1000));

    ESP_ERROR_CHECK(turn_task_start());
    board_button_register(on_button, NULL);
    ui_on_tap(on_tap, NULL);
    ui_on_pc_refresh(on_pc_refresh, NULL);
    ui_set_pc_info(false, false, NULL, NULL);
    ui_set_camera_source(orion_camera_capture_jpeg, orion_camera_release);
    ui_set_camera_preview(orion_camera_capture_preview, orion_camera_release);
    orion_net_register_cb(on_net, NULL);

    enter(OS_BOOT);
    if (xTaskCreate(sm_task, "orion_sm", 6144, NULL, 5, NULL) != pdPASS) {
        return ESP_ERR_NO_MEM;
    }

    // main started Wi-Fi early. It may already be up by now, before the
    // callback above was registered.
    if (orion_net_is_up()) {
        sm_post(EV_NET_UP, 0);
    } else {
        esp_timer_start_once(s_boot, (uint64_t) BOOT_NET_MS * 1000);
    }
    return ESP_OK;
}

orion_state_t sm_state(void)      { return s_state; }
uint32_t sm_turn_count(void)      { return s_turns; }
