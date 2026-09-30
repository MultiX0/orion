// Discovery (mDNS and the UDP beacon), the token, the state cache the REST
// and WebSocket sides read, and the events pushed to /ws.
#include "orion_api.h"
#include "api_priv.h"

#include <stdio.h>
#include <string.h>
#include <time.h>

#include "esp_app_desc.h"
#include "esp_check.h"
#include "esp_event.h"
#include "esp_heap_caps.h"
#include "esp_log.h"
#include "esp_netif_sntp.h"
#include "esp_timer.h"
#include "lwip/sockets.h"
#include "mdns.h"

#include "orion_config.h"
#include "orion_net.h"
#include "orion_settings.h"
#include "orion_prov.h"

static const char *TAG = "orion_api";

ESP_EVENT_DEFINE_BASE(ORION_API_EVENT);
enum { API_EV_PROVISION, API_EV_TOKEN };

static orion_state_t s_state = OS_BOOT;
static uint32_t s_turns;
static int64_t s_turn_started_us;
#define API_TOKENS_MAX 4
static char s_tokens[API_TOKENS_MAX][65];
static esp_timer_handle_t s_beacon;
static int s_beacon_sock = -1;
static bool s_serving;
static bool s_sntp_started;

const char *api_device_id(void)
{
    return orion_prov_device_id();
}

// Cached: an NVS read runs with the flash cache off, which a task whose
// stack is in PSRAM (the HTTP server) must never do.
static char s_name[33] = "Orion";
static int32_t s_volume = 70;

void api_device_name(char *out, size_t len)
{
    strlcpy(out, s_name, len);
}

const char *api_fw_version(void)
{
    return esp_app_get_description()->version;
}

void api_iso_time(char *out, size_t len)
{
    time_t now = time(NULL);
    struct tm tm;
    gmtime_r(&now, &tm);
    strftime(out, len, "%Y-%m-%dT%H:%M:%SZ", &tm);
}

void api_json_escape(char *dst, size_t len, const char *src)
{
    size_t o = 0;
    for (const unsigned char *p = (const unsigned char *) src; *p && o + 7 < len; p++) {
        if (*p == '"' || *p == '\\') {
            dst[o++] = '\\';
            dst[o++] = (char) *p;
        } else if (*p == '\n') {
            dst[o++] = '\\';
            dst[o++] = 'n';
        } else if (*p < 0x20) {
            o += snprintf(dst + o, len - o, "\\u%04x", *p);
        } else {
            dst[o++] = (char) *p;
        }
    }
    dst[o] = '\0';
}

bool api_token_ok(const char *token)
{
    if (!token || !token[0]) {
        return false;
    }
    for (int i = 0; i < API_TOKENS_MAX; i++) {
        if (s_tokens[i][0] && strcmp(token, s_tokens[i]) == 0) {
            return true;
        }
    }
    return false;
}

static void save_tokens(void)
{
    char list[API_TOKENS_MAX * 66] = "";
    for (int i = 0; i < API_TOKENS_MAX && s_tokens[i][0]; i++) {
        if (i) {
            strlcat(list, ",", sizeof(list));
        }
        strlcat(list, s_tokens[i], sizeof(list));
    }
    orion_config_set_str(ORION_CFG_APP_TOKENS, list);
    memset(list, 0, sizeof(list));
}

// Newest first, the oldest falls off the end, a token already there moves up.
static void push_token(const char *token)
{
    char keep[API_TOKENS_MAX][65];
    int n = 0;
    strlcpy(keep[n++], token, sizeof(keep[0]));
    for (int i = 0; i < API_TOKENS_MAX && n < API_TOKENS_MAX; i++) {
        if (s_tokens[i][0] && strcmp(s_tokens[i], token) != 0) {
            strlcpy(keep[n++], s_tokens[i], sizeof(keep[0]));
        }
    }
    memset(s_tokens, 0, sizeof(s_tokens));
    memcpy(s_tokens, keep, (size_t) n * sizeof(keep[0]));
    memset(keep, 0, sizeof(keep));
}

// Only ever called from the main task or the event loop task, both internal.
// app_token is what Bluetooth pairing and provision.py write: when it is not
// in the list yet, it is a new pairing and joins it as the newest.
static void load_token(void)
{
    char list[API_TOKENS_MAX * 66] = "";
    char newest[65] = "";
    memset(s_tokens, 0, sizeof(s_tokens));
    orion_config_copy_str(ORION_CFG_APP_TOKENS, list, sizeof(list), "");
    orion_config_copy_str(ORION_CFG_APP_TOKEN, newest, sizeof(newest), "");
    int n = 0;
    char *save = NULL;
    for (char *t = strtok_r(list, ",", &save); t && n < API_TOKENS_MAX; t = strtok_r(NULL, ",", &save)) {
        strlcpy(s_tokens[n++], t, sizeof(s_tokens[0]));
    }
    if (newest[0] && !api_token_ok(newest)) {
        push_token(newest);
        save_tokens();
    }
    memset(list, 0, sizeof(list));
    memset(newest, 0, sizeof(newest));
    orion_config_copy_str(ORION_CFG_DEVICE_NAME, s_name, sizeof(s_name), "Orion");
    if (orion_config_get_i32(ORION_CFG_VOLUME, &s_volume) != ESP_OK) {
        s_volume = 70;
    }
    int count = 0;
    while (count < API_TOKENS_MAX && s_tokens[count][0]) {
        count++;
    }
    if (count) {
        ESP_LOGI(TAG, "%d paired app%s", count, count == 1 ? "" : "s");
    } else {
        ESP_LOGW(TAG, "no paired app: every request gets 401 until one pairs");
    }
}

static const char *mode_name(orion_state_t st)
{
    switch (st) {
    case OS_WAKE:
    case OS_LISTENING: return "listening";
    case OS_THINKING:  return "thinking";
    case OS_SPEAKING:  return "speaking";
    case OS_ERROR:     return "error";
    case OS_BOOT:
    case OS_OFFLINE:   return "offline";
    default:           return "idle";
    }
}

void api_state_fields(char *out, size_t len)
{
    int32_t volume = s_volume;
    bool wake_word = true;
    orion_settings_basic(NULL, 0, NULL, &wake_word);
    snprintf(out, len,
             "\"mode\":\"%s\",\"wifi_rssi\":%d,\"battery_pct\":null,\"volume\":%d,"
             "\"wake_word_enabled\":%s,\"muted\":false,\"last_turn_id\":\"t_%05u\",\"error\":null",
             mode_name(s_state), orion_net_rssi(), (int) volume, wake_word ? "true" : "false",
             (unsigned) s_turns);
}

static void push(const char *type, const char *extra)
{
    char ts[24];
    api_iso_time(ts, sizeof(ts));
    char body[320];
    snprintf(body, sizeof(body), "{\"type\":\"%s\",\"ts\":\"%s\"%s%s}", type, ts,
             extra[0] ? "," : "", extra);
    api_ws_broadcast(body);
}

void orion_api_publish_state(orion_state_t st)
{
    orion_state_t prev = s_state;
    s_state = st;
    if (!s_serving || st == prev) {
        return;
    }
    bool was_idle = prev == OS_IDLE || prev == OS_OFFLINE || prev == OS_BOOT;
    bool is_idle = st == OS_IDLE || st == OS_OFFLINE;
    char extra[240];
    if (was_idle && !is_idle) {
        s_turns++;
        s_turn_started_us = esp_timer_get_time();
        const char *source = api_take_source();
        snprintf(extra, sizeof(extra), "\"turn_id\":\"t_%05u\",\"source\":\"%s\"", (unsigned) s_turns,
                 source);
        push("turn.start", extra);
        api_history_turn_start(s_turns, source);
    }
    snprintf(extra, sizeof(extra), "\"turn_id\":\"t_%05u\"", (unsigned) s_turns);
    if (st == OS_SPEAKING) {
        push("tts.start", extra);
    } else if (prev == OS_SPEAKING) {
        push("tts.end", extra);
    }
    api_state_fields(extra, sizeof(extra));
    push("state", extra);
    if (!was_idle && is_idle && s_turns) {
        const int64_t total = (esp_timer_get_time() - s_turn_started_us) / 1000;
        snprintf(extra, sizeof(extra), "\"turn_id\":\"t_%05u\",\"timings_ms\":{\"total\":%lld}",
                 (unsigned) s_turns, total);
        push("turn.end", extra);
        api_history_turn_end(s_turns, (uint32_t) total);
    }
}

uint32_t api_next_turn(void)
{
    return s_turns + 1;
}

void orion_api_publish_text(const char *role, const char *text)
{
    if (!text) {
        return;
    }
    api_history_text(s_turns, strcmp(role, "user") == 0, text);
    if (!s_serving) {
        return;
    }
    const size_t cap = 1536;
    char *esc = heap_caps_malloc(cap, MALLOC_CAP_SPIRAM | MALLOC_CAP_8BIT);
    char *extra = heap_caps_malloc(cap + 64, MALLOC_CAP_SPIRAM | MALLOC_CAP_8BIT);
    if (!esc || !extra) {
        free(esc);
        free(extra);
        return;
    }
    api_json_escape(esc, cap, text);
    snprintf(extra, cap + 64, "\"turn_id\":\"t_%05u\",\"text\":\"%s\"", (unsigned) s_turns, esc);
    char ts[24];
    api_iso_time(ts, sizeof(ts));
    char *body = esc;   // reuse, the escaped text is now inside extra
    snprintf(body, cap, "{\"type\":\"%s\",\"ts\":\"%s\",%s}",
             strcmp(role, "user") == 0 ? "turn.transcript" : "turn.reply", ts, extra);
    api_ws_broadcast(body);
    free(esc);
    free(extra);
}

// ---------------------------------------------------------------------------
// Discovery
// ---------------------------------------------------------------------------
static void beacon_cb(void *arg)
{
    (void) arg;
    if (s_beacon_sock < 0) {
        return;
    }
    char ip[16] = "";
    char name[33];
    char esc[80];
    orion_net_ip(ip, sizeof(ip));
    api_device_name(name, sizeof(name));
    api_json_escape(esc, sizeof(esc), name);
    char msg[200];
    int n = snprintf(msg, sizeof(msg),
                     "{\"orion\":1,\"device_id\":\"%s\",\"name\":\"%s\",\"fw\":\"%s\",\"ip\":\"%s\",\"port\":%d}",
                     api_device_id(), esc, api_fw_version(), ip, API_PORT);
    struct sockaddr_in to = {
        .sin_family = AF_INET,
        .sin_port = htons(API_BEACON_PORT),
        .sin_addr.s_addr = htonl(INADDR_BROADCAST),
    };
    sendto(s_beacon_sock, msg, n, 0, (struct sockaddr *) &to, sizeof(to));
}

static void beacon_start(void)
{
    s_beacon_sock = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP);
    if (s_beacon_sock < 0) {
        ESP_LOGE(TAG, "beacon socket failed");
        return;
    }
    int yes = 1;
    setsockopt(s_beacon_sock, SOL_SOCKET, SO_BROADCAST, &yes, sizeof(yes));
    if (!s_beacon) {
        const esp_timer_create_args_t a = { .callback = beacon_cb, .name = "orion_beacon" };
        ESP_ERROR_CHECK(esp_timer_create(&a, &s_beacon));
    }
    esp_timer_start_periodic(s_beacon, 2000000);
    beacon_cb(NULL);
}

static void beacon_stop(void)
{
    if (s_beacon) {
        esp_timer_stop(s_beacon);
    }
    if (s_beacon_sock >= 0) {
        close(s_beacon_sock);
        s_beacon_sock = -1;
    }
}

static void mdns_start(void)
{
    esp_err_t err = mdns_init();
    if (err != ESP_OK) {
        ESP_LOGE(TAG, "mdns init: %s", esp_err_to_name(err));
        return;
    }
    char name[33];
    api_device_name(name, sizeof(name));
    mdns_hostname_set("orion");
    mdns_instance_name_set(name);
    mdns_txt_item_t txt[] = {
        { "id", api_device_id() },
        { "name", name },
        { "fw", api_fw_version() },
    };
    err = mdns_service_add(NULL, "_orion", "_tcp", API_PORT, txt, 3);
    ESP_LOGI(TAG, "mdns orion.local, _orion._tcp id=%s name=%s fw=%s: %s",
             api_device_id(), name, api_fw_version(), esp_err_to_name(err));
}

// ---------------------------------------------------------------------------
// Lifecycle
// ---------------------------------------------------------------------------
static void log_heap(const char *when)
{
    ESP_LOGI(TAG, "heap %-12s int %6u, largest int %6u",
             when, (unsigned) heap_caps_get_free_size(MALLOC_CAP_INTERNAL),
             (unsigned) heap_caps_get_largest_free_block(MALLOC_CAP_INTERNAL));
}

static void serve(bool on)
{
    if (on == s_serving) {
        return;
    }
    if (on) {
        load_token();
        log_heap("before http");
        if (api_http_start() != ESP_OK) {
            return;
        }
        log_heap("after http");
        mdns_start();
        log_heap("after mdns");
        beacon_start();
        api_ws_links_start();
        if (!s_sntp_started) {
            // ISO timestamps on the ws events need a clock.
            esp_sntp_config_t c = ESP_NETIF_SNTP_DEFAULT_CONFIG("pool.ntp.org");
            s_sntp_started = esp_netif_sntp_init(&c) == ESP_OK;
        }
        s_serving = true;
        log_heap("serving");
    } else {
        s_serving = false;
        api_ws_links_stop();
        beacon_stop();
        mdns_free();
        api_http_stop();
        ESP_LOGI(TAG, "stopped, heap int %u", (unsigned) heap_caps_get_free_size(MALLOC_CAP_INTERNAL));
    }
}

static void on_net(orion_net_state_t st, void *ctx)
{
    (void) ctx;
    serve(st == ORION_NET_UP);
}

static void on_provision(void *arg, esp_event_base_t base, int32_t id, void *data)
{
    (void) arg;
    (void) base;
    (void) id;
    api_provision_t *m = data;
    orion_config_set_str(ORION_CFG_WIFI_SSID, m->ssid);
    orion_config_set_str(ORION_CFG_WIFI_PASS, m->pass);
    if (m->token[0]) {
        orion_config_set_str(ORION_CFG_APP_TOKEN, m->token);
        push_token(m->token);
        save_tokens();
    }
    if (m->name[0]) {
        orion_config_set_str(ORION_CFG_DEVICE_NAME, m->name);
    }
    memset(m, 0, sizeof(*m));
    ESP_LOGI(TAG, "credentials changed over the LAN, switching networks");
    // If the new network never answers, setup mode after 30 s, per the contract.
    orion_prov_watch(30000);
    orion_net_reconnect();
}

static void on_token(void *arg, esp_event_base_t base, int32_t id, void *data)
{
    (void) arg;
    (void) base;
    (void) id;
    char *token = data;
    orion_config_set_str(ORION_CFG_APP_TOKEN, token);
    push_token(token);
    save_tokens();
    memset(token, 0, 65);
    ESP_LOGI(TAG, "an app paired over the LAN with the code on the screen");
}

esp_err_t api_post_token(const char *token)
{
    char t[65];
    strlcpy(t, token, sizeof(t));
    esp_err_t err = esp_event_post(ORION_API_EVENT, API_EV_TOKEN, t, sizeof(t), pdMS_TO_TICKS(500));
    memset(t, 0, sizeof(t));
    return err;
}

esp_err_t api_post_provision(const api_provision_t *m)
{
    return esp_event_post(ORION_API_EVENT, API_EV_PROVISION, m, sizeof(*m), pdMS_TO_TICKS(500));
}

// After POST /api/config: the name and volume the state and beacon show.
void api_settings_changed(void)
{
    orion_settings_basic(s_name, sizeof(s_name), &s_volume, NULL);
}

esp_err_t orion_api_start(void)
{
    ESP_RETURN_ON_ERROR(orion_settings_init(), TAG, "settings");
    orion_settings_use_cloud();
    ESP_RETURN_ON_ERROR(esp_event_handler_register(ORION_API_EVENT, API_EV_PROVISION, on_provision, NULL),
                        TAG, "event handler");
    ESP_RETURN_ON_ERROR(esp_event_handler_register(ORION_API_EVENT, API_EV_TOKEN, on_token, NULL),
                        TAG, "event handler");
    ESP_RETURN_ON_ERROR(orion_net_register_cb(on_net, NULL), TAG, "net callback");
    if (orion_net_is_up()) {
        serve(true);
    }
    return ESP_OK;
}

esp_err_t orion_api_stop(void)
{
    serve(false);
    return ESP_OK;
}
