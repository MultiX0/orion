// Boot order matters here. The board must own the I2C bus before the screen
// touches it, the screen goes up before the slow things so the logo shows
// early, audio starts its clocks before the amp is enabled, and the state
// machine is last because it starts Wi-Fi and every callback lands in it.
#include <inttypes.h>
#include <stdio.h>

#include "freertos/FreeRTOS.h"
#include "freertos/task.h"
#include "esp_app_desc.h"
#include "esp_chip_info.h"
#include "esp_flash.h"
#include "esp_heap_caps.h"
#include "esp_log.h"
#include "esp_psram.h"
#include "esp_system.h"
#include "esp_timer.h"
#include "esp_wifi.h"

#include "board.h"
#include "orion_config.h"
#include "orion_net.h"
#include "orion_audio.h"
#include "orion_wakeword.h"
#include "orion_camera.h"
#include "orion_cloud.h"
#include "orion_ui.h"
#include "orion_console.h"
#include "orion_sm.h"
#include "orion_turn.h"
#include "orion_prov.h"
#include "orion_api.h"
#include "orion_settings.h"

static const char *TAG = "orion";

#define DEFAULT_VOLUME 70
#define SETUP_MODE_MS  (10 * 60 * 1000)
#define BOOT_SETUP_MS  30000

static void report_chip(void)
{
    esp_chip_info_t chip;
    esp_chip_info(&chip);
    uint32_t flash = 0;
    esp_flash_get_size(NULL, &flash);
    ESP_LOGI(TAG, "Orion %s by MultiX0, https://github.com/MultiX0, PolyForm Noncommercial 1.0.0",
             esp_app_get_description()->version);
    // Why the last run ended. A brownout or a power-on reset in the middle of
    // speech is the supply giving way under the speaker, not a crash.
    static const char *const why[] = {
        [ESP_RST_UNKNOWN] = "unknown", [ESP_RST_POWERON] = "power on",
        [ESP_RST_EXT] = "reset pin", [ESP_RST_SW] = "software restart",
        [ESP_RST_PANIC] = "panic", [ESP_RST_INT_WDT] = "interrupt watchdog",
        [ESP_RST_TASK_WDT] = "task watchdog", [ESP_RST_WDT] = "watchdog",
        [ESP_RST_DEEPSLEEP] = "deep sleep", [ESP_RST_BROWNOUT] = "brownout",
        [ESP_RST_SDIO] = "sdio", [ESP_RST_USB] = "usb", [ESP_RST_JTAG] = "jtag",
    };
    const esp_reset_reason_t r = esp_reset_reason();
    ESP_LOGW(TAG, "reset reason: %s (%d)",
             (unsigned) r < sizeof(why) / sizeof(why[0]) && why[r] ? why[r] : "other", (int) r);
    ESP_LOGI(TAG, "esp32-s3 rev %d.%d, flash %" PRIu32 " MB, psram %u MB, heap int %u",
             chip.revision / 100, chip.revision % 100, flash / (1024 * 1024),
             (unsigned) (esp_psram_get_size() / (1024 * 1024)),
             (unsigned) heap_caps_get_free_size(MALLOC_CAP_INTERNAL));
}

// A subsystem that fails to start is logged and skipped. The board keeps
// booting so the screen can say what is wrong instead of sitting dark.
static void try_init(const char *what, esp_err_t (*fn)(void))
{
    esp_err_t err = fn();
    if (err != ESP_OK) {
        ESP_LOGE(TAG, "%s failed: %s", what, esp_err_to_name(err));
    }
    ESP_LOGI(TAG, "after %-8s heap int %u, largest dma %u", what,
             (unsigned) heap_caps_get_free_size(MALLOC_CAP_INTERNAL),
             (unsigned) heap_caps_get_largest_free_block(MALLOC_CAP_DMA));
}

static void apply_settings(void)
{
    int32_t volume = DEFAULT_VOLUME;
    if (orion_config_get_i32(ORION_CFG_VOLUME, &volume) != ESP_OK) {
        volume = DEFAULT_VOLUME;
    }
    orion_audio_set_volume((uint8_t) volume);
    orion_wakeword_set_debug_clips(orion_config_get_bool(ORION_CFG_DEBUG_CLIPS, false));
    ESP_LOGI(TAG, "volume %" PRId32 ", wake phrase \"%s\", debug clips %s",
             volume, orion_wakeword_phrase(),
             orion_wakeword_debug_clips() ? "on" : "off");
}

// Runs on the event loop task; the ui_ calls take the LVGL lock themselves.
static void on_setup(orion_prov_state_t st, const char *detail, void *ctx)
{
    (void) ctx;
    switch (st) {
    case ORION_PROV_WAITING:    ui_set_setup_status(UI_SETUP_WAITING, NULL);      break;
    case ORION_PROV_CONNECTING: ui_set_setup_status(UI_SETUP_CONNECTING, detail); break;
    case ORION_PROV_FAILED:     ui_set_setup_status(UI_SETUP_FAILED, detail);     break;
    case ORION_PROV_DONE:       ui_set_setup_status(UI_SETUP_DONE, detail);       break;
    default: break;
    }
}

// Setup mode is a boot mode, see orion_prov.h. The camera, wake word and
// cloud are not started until it ends, so NimBLE has the whole heap.
static void run_setup_mode(void)
{
    if (orion_prov_start(on_setup, NULL) == ESP_OK) {
        ui_show_setup(orion_prov_device_name(), orion_prov_code());
        esp_err_t err = orion_prov_wait(SETUP_MODE_MS);
        orion_prov_stop();
        ESP_LOGI(TAG, "setup mode over: %s", esp_err_to_name(err));
    }
    ui_hide_setup();
    // Adopts the connection the phone made, or retries the saved network.
    try_init("wifi", orion_net_start);
}

// The menu's Wi-Fi setup button. Called on the LVGL task, so the NVS write
// and the restart happen on a timer instead.
static void on_wifi_setup(void *ctx)
{
    (void) ctx;
    orion_prov_request_async("menu");
}

// Which apps are here right now: the lights on the idle screen, and the
// phone's brain for the next turn. A PC that just linked is checked at once,
// so it answers the next turn without waiting for the 40 s heartbeat.
static void on_links(const orion_api_links_t *links)
{
    static bool pc_before;
    ui_set_links(links->pc, links->phone);
    orion_cloud_set_phone_brain(links->phone_brain, links->phone_token);
    if (links->pc && !pc_before) {
        orion_cloud_prewarm();
        sm_post(EV_PC_INFO, 0);
    }
    pc_before = links->pc;
}

// The app's Talk screen, "ask about this", say and stop. Only from idle,
// except stop; the answer tells the app when the board is busy.
static bool on_app_request(orion_api_request_t what, const char *text)
{
    if (what == ORION_API_STOP) {
        sm_post(EV_CANCEL, 0);
        return true;
    }
    if (sm_state() != OS_IDLE) {
        return false;
    }
    switch (what) {
    case ORION_API_SAY:
        turn_set_pending_text(text);
        sm_post(EV_SAY, 0);
        break;
    case ORION_API_SNAPSHOT:
        orion_cloud_look_next();
        turn_set_pending_text(text ? text : "What is in front of you?");
        sm_post(EV_ASK, 0);
        break;
    default:
        if (text) {
            turn_set_pending_text(text);
            sm_post(EV_ASK, 0);
        } else {
            sm_post(EV_BUTTON, 0);
        }
        break;
    }
    return true;
}

static void on_reply_progress(void)
{
    sm_post(EV_PROGRESS, 0);
}

// A setting stored from an app: the wake word switch takes effect at once.
static void on_settings_changed(void)
{
    sm_post(EV_SETTINGS, 0);
}

static void on_pair_code(const char *code, int seconds)
{
    ui_show_pair_code(code, seconds);
}

// Every key, the Wi-Fi the driver keeps too, then a restart with nothing:
// setup mode, as on the first boot. On a timer, not the LVGL task.
static void factory_reset(void *arg)
{
    (void) arg;
    ESP_LOGW(TAG, "factory reset from the menu");
    orion_config_erase_all();
    esp_wifi_restore();
    esp_restart();
}

static void on_reset(void *ctx)
{
    (void) ctx;
    static esp_timer_handle_t t;
    const esp_timer_create_args_t a = { .callback = factory_reset, .name = "factory_reset" };
    if (t || esp_timer_create(&a, &t) == ESP_OK) {
        esp_timer_start_once(t, 300000);
    }
}

void app_main(void)
{
    report_chip();

    ESP_ERROR_CHECK(board_init());
    try_init("config", orion_config_init);
    orion_config_report();
    if (!orion_config_is_provisioned()) {
        ESP_LOGW(TAG, "not provisioned, run tools/cloud/provision.py");
    }

    // Wi-Fi first. Its receive buffers need DMA capable internal RAM, and once
    // the screen, camera and wake word are up there is none left:
    // esp_wifi_init fails with ESP_ERR_NO_MEM.
    try_init("wifi", orion_net_start);

    try_init("ui", ui_init);
    ui_set_state(OS_BOOT);

    // The console comes up before setup mode so `prov stop` works there.
    try_init("console", console_start);
    if (orion_prov_should_run()) {
        run_setup_mode();
    } else {
        orion_prov_release_bt();
    }
    // A saved network that never answers means the board moved: setup mode.
    if (orion_config_has(ORION_CFG_WIFI_SSID) && !orion_net_is_up()) {
        orion_prov_watch(BOOT_SETUP_MS);
    }

    try_init("audio", orion_audio_init);
    try_init("wakeword", orion_wakeword_init);
    try_init("camera", orion_camera_init);
    try_init("cloud", orion_cloud_init);
    apply_settings();

    ESP_ERROR_CHECK(sm_start());
    ui_on_wifi_setup(on_wifi_setup, NULL);
    ui_on_reset(on_reset, NULL);
    orion_api_on_links(on_links);
    orion_api_on_pair_code(on_pair_code);
    orion_api_on_request(on_app_request);
    orion_settings_on_change(on_settings_changed);
    orion_cloud_on_progress(on_reply_progress);
    try_init("api", orion_api_start);

    while (true) {
        vTaskDelay(pdMS_TO_TICKS(60000));
        ESP_LOGI(TAG, "state %s, turns %" PRIu32 ", heap int %u, psram %u",
                 orion_state_name(sm_state()), sm_turn_count(),
                 (unsigned) heap_caps_get_free_size(MALLOC_CAP_INTERNAL),
                 (unsigned) heap_caps_get_free_size(MALLOC_CAP_SPIRAM));
    }
}
