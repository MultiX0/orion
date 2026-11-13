// Orion Hub, the client side. hub/README.md has the hub; docs/DEVICE_PROTOCOL.md
// has the brain interface the hub answers on (the same one as the PC brain).
//
// Pairing follows the hub's own flow: POST /api/v1/pair/request with
// the board's name. The first device a hub ever sees becomes its owner and gets
// a token at once. Any later one gets a 4 digit code and waits up to five
// minutes, polling, while the owner approves it (from a paired device or with
// `orion-hub-cli approve <code>` on the hub). The code is on this board's
// screen so the person approving can match it.
//
// The token, address, name, this board's id on the hub and the hub's own id go
// to NVS (hub_token, hub_url, hub_name, hub_dev, hub_id). orion_cloud reloads
// them, and from then on every turn goes to the hub first.

#include "orion_hub.h"

#include <stdio.h>
#include <string.h>

#include "cJSON.h"
#include "esp_console.h"
#include "esp_heap_caps.h"
#include "esp_http_client.h"
#include "esp_log.h"
#include "esp_netif_ip_addr.h"
#include "freertos/FreeRTOS.h"
#include "freertos/queue.h"
#include "freertos/semphr.h"
#include "freertos/task.h"
#include "esp_netif.h"
#include "esp_timer.h"
#include "lwip/sockets.h"
#include <errno.h>
#include <fcntl.h>
#include "mdns.h"

#include "orion_cloud.h"
#include "orion_config.h"
#include "orion_net.h"
#include "orion_prov.h"
#include "orion_settings.h"

static const char *TAG = "hub";

#define K_URL   "hub_url"
#define K_TOKEN "hub_token"
#define K_NAME  "hub_name"
#define K_DEV   "hub_dev"
#define K_ID    "hub_id"     // the hub's Orion Link id (docs/ORION_LINK.md)

#define SCAN_MS        3000      // one mDNS query
#define FIRST_LOOK_MS  8000      // after boot, once Wi-Fi and mDNS are settled
#define REDISCOVER_MS  120000    // unpaired: look again this often; paired but offline: look for its new address
#define POLL_MS        2000
#define WAIT_MAX_MS    (5 * 60 * 1000)
#define HTTP_MS        6000
#define BODY_MAX       768
#define SWEEP_BATCH    4         // sockets at once: lwIP has 16, most taken
#define SWEEP_WAIT_MS  300       // per batch: a LAN host answers a connect in a few ms
#define IDENT_MS       1500

typedef enum { CMD_SCAN, CMD_CONNECT, CMD_FORGET } cmd_kind_t;

typedef struct {
    cmd_kind_t kind;
    char url[48];
} cmd_t;

static QueueHandle_t s_q;
static SemaphoreHandle_t s_mu;
static orion_hub_status_t s_st;
static void (*s_cb)(void *ctx);
static void *s_cb_ctx;
static bool s_paired;
static char s_id[24];       // the paired hub's id; empty for a pairing from before ids
// Just paired: the cloud has not checked it yet, so "not answering" means
// nothing for a few seconds.
static TickType_t s_fresh_until;

const char *orion_hub_state_name(orion_hub_state_t s)
{
    static const char *N[] = { "none", "scanning", "found", "pairing", "waiting", "connected", "offline", "failed" };
    return (unsigned) s < sizeof(N) / sizeof(N[0]) ? N[s] : "?";
}

static void changed(void)
{
    if (s_cb) s_cb(s_cb_ctx);
}

// Under the lock; announces the change after it.
static void set_state(orion_hub_state_t st, const char *message)
{
    xSemaphoreTake(s_mu, portMAX_DELAY);
    s_st.state = st;
    strlcpy(s_st.message, message ? message : "", sizeof(s_st.message));
    if (st != HUB_WAITING) s_st.code[0] = '\0';
    xSemaphoreGive(s_mu);
    ESP_LOGI(TAG, "%s%s%s", orion_hub_state_name(st), message && message[0] ? ": " : "", message ? message : "");
    changed();
}

void orion_hub_on_change(void (*cb)(void *ctx), void *ctx)
{
    s_cb = cb;
    s_cb_ctx = ctx;
}

void orion_hub_status(orion_hub_status_t *out)
{
    if (!s_mu) {
        memset(out, 0, sizeof(*out));
        return;
    }
    xSemaphoreTake(s_mu, portMAX_DELAY);
    *out = s_st;
    xSemaphoreGive(s_mu);
}

bool orion_hub_paired(void)
{
    return s_paired;
}

const char *orion_hub_id(void)
{
    return s_paired ? s_id : "";
}

void orion_hub_set_online(bool online)
{
    if (!s_paired || !s_mu) return;
    if (!online && (int32_t) (s_fresh_until - xTaskGetTickCount()) > 0) return;
    orion_hub_state_t want = online ? HUB_CONNECTED : HUB_OFFLINE;
    xSemaphoreTake(s_mu, portMAX_DELAY);
    const bool busy = s_st.state == HUB_PAIRING || s_st.state == HUB_WAITING;
    const bool differs = s_st.state != want;
    xSemaphoreGive(s_mu);
    if (!busy && differs) set_state(want, NULL);
}

static esp_err_t post(cmd_kind_t kind, const char *url)
{
    if (!s_q) return ESP_ERR_INVALID_STATE;
    cmd_t c = { .kind = kind };
    if (url) strlcpy(c.url, url, sizeof(c.url));
    return xQueueSend(s_q, &c, 0) == pdTRUE ? ESP_OK : ESP_ERR_NO_MEM;
}

// ---------------------------------------------------------------------------
// Flash. The worker's stack is in PSRAM: internal RAM is what this board runs
// short of, and when it runs out the screen's SPI DMA fails and LVGL hangs.
// An NVS read or write turns the flash cache off, which asserts on a PSRAM
// stack, so each one runs on the main task (orion_hub_serve), whose internal
// stack exists anyway and idles, while the worker waits. A new task for it
// would need 4 KB in one piece, which this heap often does not have. Rare:
// pairing, forgetting, and a hub that moved.
// ---------------------------------------------------------------------------
typedef struct {
    void (*fn)(void *arg);
    void *arg;
    TaskHandle_t waiter;
} flash_job_t;

static QueueHandle_t s_flash;

static bool on_internal_stack(void (*fn)(void *arg), void *arg)
{
    flash_job_t job = { .fn = fn, .arg = arg, .waiter = xTaskGetCurrentTaskHandle() };
    flash_job_t *p = &job;
    if (!s_flash || xQueueSend(s_flash, &p, pdMS_TO_TICKS(5000)) != pdTRUE) {
        ESP_LOGE(TAG, "the NVS job was not taken");
        return false;
    }
    ulTaskNotifyTake(pdTRUE, portMAX_DELAY);
    return true;
}

void orion_hub_serve(uint32_t ms)
{
    const TickType_t end = xTaskGetTickCount() + pdMS_TO_TICKS(ms);
    while (true) {
        const TickType_t now = xTaskGetTickCount();
        const TickType_t left = (TickType_t) (end - now);
        if (left == 0 || left > pdMS_TO_TICKS(ms)) return;
        flash_job_t *job = NULL;
        if (!s_flash) {
            vTaskDelay(left);
            return;
        }
        if (xQueueReceive(s_flash, &job, left) == pdTRUE && job) {
            job->fn(job->arg);
            xTaskNotifyGive(job->waiter);
        }
    }
}

typedef struct {
    const char *url, *token, *name, *dev, *id;
    esp_err_t err;
} save_job_t;

static void save_fn(void *p)
{
    save_job_t *j = p;
    j->err = ESP_OK;
    if (j->url) j->err = orion_config_set_str(K_URL, j->url);
    if (j->err == ESP_OK && j->token) j->err = orion_config_set_str(K_TOKEN, j->token);
    if (j->err == ESP_OK && j->name) j->err = orion_config_set_str(K_NAME, j->name);
    if (j->err == ESP_OK && j->dev) j->err = orion_config_set_str(K_DEV, j->dev);
    if (j->err == ESP_OK && j->id) j->err = orion_config_set_str(K_ID, j->id);
}

static esp_err_t store(const char *url, const char *token, const char *name, const char *dev,
                       const char *id)
{
    save_job_t j = { url, token, name, dev, id, ESP_FAIL };
    return on_internal_stack(save_fn, &j) ? j.err : ESP_ERR_NO_MEM;
}

typedef struct {
    char url[160], token[96], dev[24];
} read_job_t;

static void read_fn(void *p)
{
    read_job_t *j = p;
    orion_config_get_str(K_URL, j->url, sizeof(j->url));
    orion_config_get_str(K_TOKEN, j->token, sizeof(j->token));
    orion_config_get_str(K_DEV, j->dev, sizeof(j->dev));
}

static void erase_fn(void *p)
{
    (void) p;
    orion_config_erase(K_URL);
    orion_config_erase(K_TOKEN);
    orion_config_erase(K_NAME);
    orion_config_erase(K_DEV);
    orion_config_erase(K_ID);
}

static void reload_fn(void *p)
{
    *(esp_err_t *) p = orion_cloud_reload();
}

// The cloud reads NVS again. It refuses mid turn, so this tries for a while.
static esp_err_t reload_cloud(int tries)
{
    esp_err_t err = ESP_FAIL;
    for (int i = 0; i < tries; i++) {
        if (!on_internal_stack(reload_fn, &err)) return ESP_ERR_NO_MEM;
        if (err != ESP_ERR_INVALID_STATE) break;
        vTaskDelay(pdMS_TO_TICKS(1000));
    }
    return err;
}

esp_err_t orion_hub_scan(void)            { return post(CMD_SCAN, NULL); }
esp_err_t orion_hub_connect(const char *u) { return post(CMD_CONNECT, u); }
esp_err_t orion_hub_forget(void)          { return post(CMD_FORGET, NULL); }

// ---------------------------------------------------------------------------
// HTTP, plain, small JSON bodies. Worker only.
// ---------------------------------------------------------------------------
static esp_err_t http_json(esp_http_client_method_t method, const char *url, const char *auth,
                           const char *body, char *out, size_t out_len, int *status)
{
    out[0] = '\0';
    *status = 0;
    esp_http_client_config_t cfg = {
        .url = url,
        .method = method,
        .timeout_ms = HTTP_MS,
        .buffer_size = 512,      // internal RAM: small allocations stay there
        .buffer_size_tx = 512,
        .keep_alive_enable = false,
    };
    esp_http_client_handle_t c = esp_http_client_init(&cfg);
    if (!c) return ESP_ERR_NO_MEM;
    if (body) esp_http_client_set_header(c, "Content-Type", "application/json");
    if (auth) esp_http_client_set_header(c, "Authorization", auth);
    const int len = body ? (int) strlen(body) : 0;
    esp_err_t err = esp_http_client_open(c, len);
    if (err == ESP_OK && len && esp_http_client_write(c, body, len) != len) err = ESP_FAIL;
    if (err == ESP_OK) {
        esp_http_client_fetch_headers(c);
        *status = esp_http_client_get_status_code(c);
        size_t got = 0;
        while (got + 1 < out_len) {
            const int n = esp_http_client_read(c, out + got, (int) (out_len - 1 - got));
            if (n <= 0) break;
            got += (size_t) n;
        }
        out[got] = '\0';
    }
    esp_http_client_close(c);
    esp_http_client_cleanup(c);
    return err;
}

static const char *jstr(const cJSON *o, const char *key)
{
    const cJSON *v = cJSON_GetObjectItemCaseSensitive(o, key);
    return cJSON_IsString(v) ? v->valuestring : NULL;
}

// ---------------------------------------------------------------------------
// Discovery
// ---------------------------------------------------------------------------
static int scan_once(orion_hub_found_t *out, int max)
{
    mdns_result_t *res = NULL;
    esp_err_t err = mdns_query_ptr("_orionhub", "_tcp", SCAN_MS, max * 2, &res);
    if (err != ESP_OK) {
        ESP_LOGW(TAG, "mdns query: %s", esp_err_to_name(err));
        return 0;
    }
    // A Docker host also announces its bridges, which this board cannot reach:
    // the address on this board's subnet, else the first announced (listed last).
    esp_netif_ip_info_t me = { 0 };
    esp_netif_t *nif = esp_netif_get_handle_from_ifkey("WIFI_STA_DEF");
    if (nif) esp_netif_get_ip_info(nif, &me);
    int n = 0;
    for (mdns_result_t *r = res; r && n < max; r = r->next) {
        uint32_t ip4 = 0;
        for (mdns_ip_addr_t *a = r->addr; a; a = a->next) {
            if (a->addr.type != ESP_IPADDR_TYPE_V4) continue;
            ip4 = a->addr.u_addr.ip4.addr;
            if (me.netmask.addr && (ip4 & me.netmask.addr) == (me.ip.addr & me.netmask.addr)) break;
        }
        if (!ip4 || !r->port) continue;
        char url[48];
        snprintf(url, sizeof(url), "http://" IPSTR ":%u", IP2STR((esp_ip4_addr_t *) &ip4), (unsigned) r->port);
        bool dup = false;
        for (int i = 0; i < n; i++) dup |= strcmp(out[i].url, url) == 0;
        if (dup) continue;
        strlcpy(out[n].url, url, sizeof(out[n].url));
        strlcpy(out[n].name, r->instance_name ? r->instance_name : "Orion Hub", sizeof(out[n].name));
        out[n].id[0] = '\0';
        for (size_t t = 0; t < r->txt_count; t++) {
            if (r->txt[t].key && strcmp(r->txt[t].key, "id") == 0 && r->txt[t].value) {
                strlcpy(out[n].id, r->txt[t].value, sizeof(out[n].id));
            }
        }
        n++;
    }
    mdns_query_results_free(res);
    return n;
}

static bool interrupted(void);

// Is this the hub this board is paired with? Only by its id once this board
// knows one; by name only for a pairing from before ids.
static bool ours(const char *id, const char *name)
{
    if (s_id[0]) return id && strcmp(s_id, id) == 0;
    char mine[48];
    xSemaphoreTake(s_mu, portMAX_DELAY);
    strlcpy(mine, s_st.name, sizeof(mine));
    xSemaphoreGive(s_mu);
    return name && mine[0] && strcmp(name, mine) == 0;
}

// The paired hub answers at a new address: remember it, and the cloud follows.
static void follow(const char *url, const char *id)
{
    ESP_LOGI(TAG, "the paired hub moved to %s", url);
    store(url, NULL, NULL, NULL, id && id[0] && !s_id[0] ? id : NULL);
    if (id && id[0] && !s_id[0]) strlcpy(s_id, id, sizeof(s_id));
    xSemaphoreTake(s_mu, portMAX_DELAY);
    strlcpy(s_st.url, url, sizeof(s_st.url));
    xSemaphoreGive(s_mu);
    reload_cloud(20);
    orion_cloud_prewarm();
}

// Who answers at this address (docs/ORION_LINK.md): GET /.well-known/orion,
// or /api/v1/info on a hub from before Orion Link. True for a hub.
static bool identify(const char *base, char *id, size_t id_len, char *name, size_t name_len)
{
    static const char *const paths[] = { "/.well-known/orion", "/api/v1/info" };
    char ep[96];
    char *buf = heap_caps_malloc(BODY_MAX, MALLOC_CAP_SPIRAM);
    if (!buf) return false;
    bool hub = false;
    for (int i = 0; i < 2 && !hub; i++) {
        snprintf(ep, sizeof(ep), "%s%s", base, paths[i]);
        esp_http_client_config_t cfg = {
            .url = ep, .timeout_ms = IDENT_MS, .buffer_size = 512, .buffer_size_tx = 512,
            .keep_alive_enable = false,
        };
        esp_http_client_handle_t c = esp_http_client_init(&cfg);
        if (!c) break;
        int got = 0;
        if (esp_http_client_open(c, 0) == ESP_OK && esp_http_client_fetch_headers(c) >= 0 &&
            esp_http_client_get_status_code(c) == 200) {
            int n;
            while (got < BODY_MAX - 1 && (n = esp_http_client_read(c, buf + got, BODY_MAX - 1 - got)) > 0) got += n;
        }
        esp_http_client_close(c);
        esp_http_client_cleanup(c);
        buf[got] = '\0';
        cJSON *j = got ? cJSON_Parse(buf) : NULL;
        const char *kind = j ? jstr(j, "kind") : NULL;
        if (kind && (strcmp(kind, "hub") == 0 || strcmp(kind, "orion-hub") == 0)) {
            hub = true;
            strlcpy(id, jstr(j, "id") ? jstr(j, "id") : "", id_len);
            strlcpy(name, jstr(j, "name") ? jstr(j, "name") : "", name_len);
        }
        cJSON_Delete(j);
        if (got && !hub) break;   // something else answers there: not a hub
    }
    free(buf);
    return hub;
}

// Every address of this board's /24 with the port open, for a hub that mDNS
// cannot announce (Docker Desktop, a router that drops multicast). A few
// sockets at a time; refused and silent hosts cost a batch's wait at most.
static int sweep(uint16_t port, char (*out)[48], int max)
{
    esp_netif_t *nif = esp_netif_get_handle_from_ifkey("WIFI_STA_DEF");
    esp_netif_ip_info_t ip;
    if (!nif || esp_netif_get_ip_info(nif, &ip) != ESP_OK || !ip.ip.addr) return 0;
    const uint32_t self = ntohl(ip.ip.addr);
    const uint32_t base = self & 0xFFFFFF00u;
    int n = 0;
    uint32_t next = 1;
    int starved = 0;
    while (next < 255 && n < max && !interrupted()) {
        int fds[SWEEP_BATCH];
        uint32_t addrs[SWEEP_BATCH];
        int m = 0;
        while (m < SWEEP_BATCH && next < 255) {
            const uint32_t a = base | next;
            if (a == self) { next++; continue; }
            const int fd = socket(AF_INET, SOCK_STREAM, IPPROTO_TCP);
            if (fd < 0) break;                       // all sockets in use: probe what we have
            fcntl(fd, F_SETFL, fcntl(fd, F_GETFL, 0) | O_NONBLOCK);
            struct sockaddr_in to = { .sin_family = AF_INET, .sin_port = htons(port), .sin_addr.s_addr = htonl(a) };
            if (connect(fd, (struct sockaddr *) &to, sizeof(to)) != 0 && errno != EINPROGRESS) {
                close(fd);
                next++;
                continue;
            }
            fds[m] = fd;
            addrs[m] = a;
            m++;
            next++;
        }
        if (m == 0) {
            if (++starved > 20) break;               // no socket for 4 s: give up this round
            vTaskDelay(pdMS_TO_TICKS(200));
            continue;
        }
        starved = 0;
        bool done[SWEEP_BATCH] = { false };
        int left = m;
        const int64_t end = esp_timer_get_time() + SWEEP_WAIT_MS * 1000LL;
        while (left > 0) {
            const int64_t now = esp_timer_get_time();
            if (now >= end) break;
            fd_set w;
            FD_ZERO(&w);
            int maxfd = -1;
            for (int i = 0; i < m; i++) {
                if (!done[i]) {
                    FD_SET(fds[i], &w);
                    if (fds[i] > maxfd) maxfd = fds[i];
                }
            }
            struct timeval tv = { .tv_sec = 0, .tv_usec = (suseconds_t) (end - now) };
            if (select(maxfd + 1, NULL, &w, NULL, &tv) <= 0) break;
            for (int i = 0; i < m; i++) {
                if (done[i] || !FD_ISSET(fds[i], &w)) continue;
                done[i] = true;
                left--;
                int e = 0;
                socklen_t l = sizeof(e);
                getsockopt(fds[i], SOL_SOCKET, SO_ERROR, &e, &l);
                if (e == 0 && n < max) {
                    const uint32_t a = addrs[i];
                    snprintf(out[n++], 48, "http://%u.%u.%u.%u:%u", (unsigned) (a >> 24) & 255,
                             (unsigned) (a >> 16) & 255, (unsigned) (a >> 8) & 255, (unsigned) a & 255,
                             (unsigned) port);
                }
            }
        }
        for (int i = 0; i < m; i++) close(fds[i]);
    }
    return n;
}

// The paired hub does not answer and mDNS did not find it: is it still at its
// address (then it is only down), and if not, where on this network is it?
static void relocate(void)
{
    char url[48], id[24], name[48];
    xSemaphoreTake(s_mu, portMAX_DELAY);
    strlcpy(url, s_st.url, sizeof(url));
    xSemaphoreGive(s_mu);
    if (identify(url, id, sizeof(id), name, sizeof(name)) && ours(id, name)) {
        if (id[0] && !s_id[0]) {               // a pairing from before ids learns it
            strlcpy(s_id, id, sizeof(s_id));
            store(NULL, NULL, NULL, NULL, id);
        }
        return;
    }
    const char *colon = strrchr(url, ':');
    const int port = colon && colon > url + 6 ? atoi(colon + 1) : 8780;
    const int64_t t0 = esp_timer_get_time();
    char (*cand)[48] = heap_caps_malloc(16 * 48, MALLOC_CAP_SPIRAM);
    if (!cand) return;
    const int n = sweep((uint16_t) port, cand, 16);
    ESP_LOGI(TAG, "swept the network for the hub in %lld ms: %d open on port %d",
             (esp_timer_get_time() - t0) / 1000, n, port);
    for (int i = 0; i < n; i++) {
        if (strcmp(cand[i], url) == 0) continue;
        if (identify(cand[i], id, sizeof(id), name, sizeof(name)) && ours(id, name)) {
            follow(cand[i], id);
            break;
        }
    }
    free(cand);
}

static void do_scan(bool quiet)
{
    if (!orion_net_is_up()) return;
    if (!quiet && !s_paired) set_state(HUB_SCANNING, NULL);
    orion_hub_found_t found[ORION_HUB_MAX_FOUND];
    int n = scan_once(found, ORION_HUB_MAX_FOUND);
    // Asked to search and mDNS found nothing: a hub under Docker Desktop, or
    // behind a router that drops multicast, only answers on its port.
    if (n == 0 && !quiet && !s_paired) {
        char (*cand)[48] = heap_caps_malloc(16 * 48, MALLOC_CAP_SPIRAM);
        const int m = cand ? sweep(8780, cand, 16) : 0;
        for (int i = 0; i < m && n < ORION_HUB_MAX_FOUND; i++) {
            char id[24], name[48];
            if (!identify(cand[i], id, sizeof(id), name, sizeof(name))) continue;
            strlcpy(found[n].url, cand[i], sizeof(found[n].url));
            strlcpy(found[n].name, name[0] ? name : "Orion Hub", sizeof(found[n].name));
            strlcpy(found[n].id, id, sizeof(found[n].id));
            n++;
        }
        free(cand);
    }
    xSemaphoreTake(s_mu, portMAX_DELAY);
    s_st.found = n;
    memcpy(s_st.hubs, found, sizeof(found));
    char was[48];
    strlcpy(was, s_st.url, sizeof(was));
    xSemaphoreGive(s_mu);
    for (int i = 0; i < n; i++) ESP_LOGI(TAG, "found \"%s\" at %s%s%s", found[i].name, found[i].url,
                                         found[i].id[0] ? ", " : "", found[i].id);
    // A paired hub that moved (DHCP gave it another address) is found again by
    // its id (its name before ids), and followed once that address says so too.
    if (s_paired) {
        for (int i = 0; i < n; i++) {
            if (ours(found[i].id, found[i].name) && strcmp(found[i].url, was) != 0) {
                char id[24], name[48];
                if (!identify(found[i].url, id, sizeof(id), name, sizeof(name)) || !ours(id, name)) continue;
                follow(found[i].url, id);
                break;
            }
        }
    }
    if (!s_paired) {
        set_state(n ? HUB_FOUND : HUB_NONE, NULL);
    } else {
        changed();
    }
}

// ---------------------------------------------------------------------------
// Pairing
// ---------------------------------------------------------------------------
static void board_name(char *out, size_t len)
{
    char name[33] = "Orion";
    orion_settings_basic(name, sizeof(name), NULL, NULL);
    const char *id = orion_prov_device_id();
    const size_t idl = id ? strlen(id) : 0;
    snprintf(out, len, "%s %s", name[0] ? name : "Orion", idl > 4 ? id + idl - 4 : (id ? id : ""));
}

static esp_err_t save(const char *url, const char *token, const char *name, const char *dev,
                      const char *id)
{
    esp_err_t err = store(url, token, name, dev ? dev : "", id ? id : "");
    return err == ESP_OK ? reload_cloud(30) : err;
}

// Right after boot a command can come before Wi-Fi has an address.
static bool wait_net(int ms)
{
    for (int t = 0; !orion_net_is_up() && t < ms; t += 250) vTaskDelay(pdMS_TO_TICKS(250));
    return orion_net_is_up();
}

// True when a forget or a new connect is waiting: the current pairing stops.
static bool interrupted(void)
{
    cmd_t c;
    return xQueuePeek(s_q, &c, 0) == pdTRUE && (c.kind == CMD_CONNECT || c.kind == CMD_FORGET);
}

static void do_connect(const char *url_in)
{
    // One hub at a time. A pairing that failed here would leave the status
    // showing its address while NVS and the cloud still use the paired hub.
    if (s_paired) {
        set_state(HUB_FAILED, "forget the paired hub first");
        return;
    }
    char url[48];
    strlcpy(url, url_in, sizeof(url));
    if (!url[0]) {
        xSemaphoreTake(s_mu, portMAX_DELAY);
        if (s_st.found) strlcpy(url, s_st.hubs[0].url, sizeof(url));
        xSemaphoreGive(s_mu);
        if (!url[0]) {
            do_scan(false);
            xSemaphoreTake(s_mu, portMAX_DELAY);
            if (s_st.found) strlcpy(url, s_st.hubs[0].url, sizeof(url));
            xSemaphoreGive(s_mu);
        }
        if (!url[0]) {
            set_state(HUB_FAILED, "no hub found on this network");
            return;
        }
    }
    size_t n = strlen(url);
    while (n && url[n - 1] == '/') url[--n] = '\0';
    if (strncmp(url, "http://", 7) != 0) {
        set_state(HUB_FAILED, "the address must start with http://");
        return;
    }

    xSemaphoreTake(s_mu, portMAX_DELAY);
    strlcpy(s_st.url, url, sizeof(s_st.url));
    s_st.name[0] = '\0';
    xSemaphoreGive(s_mu);
    set_state(HUB_PAIRING, NULL);

    char *buf = heap_caps_malloc(BODY_MAX, MALLOC_CAP_SPIRAM);
    char *ep = heap_caps_malloc(160, MALLOC_CAP_SPIRAM);
    if (!buf || !ep) {
        free(buf);
        free(ep);
        set_state(HUB_FAILED, "out of memory");
        return;
    }
    int status = 0;
    cJSON *j = NULL;
    char hub_name[48] = "Orion Hub";
    char hub_id[24] = "";

    // Is it a hub at all, and what is it called.
    snprintf(ep, 160, "%s/api/v1/info", url);
    // Up to three tries: the first connect after boot sometimes fails.
    wait_net(20000);
    esp_err_t got = http_json(HTTP_METHOD_GET, ep, NULL, NULL, buf, BODY_MAX, &status);
    for (int i = 0; i < 2 && got != ESP_OK && !interrupted(); i++) {
        ESP_LOGW(TAG, "%s: %s, trying again", ep, esp_err_to_name(got));
        vTaskDelay(pdMS_TO_TICKS(2000));
        got = http_json(HTTP_METHOD_GET, ep, NULL, NULL, buf, BODY_MAX, &status);
    }
    if (status != 200) {
        ESP_LOGW(TAG, "%s: %s, http %d", ep, esp_err_to_name(got), status);
        set_state(HUB_FAILED, "the hub does not answer");
        goto out;
    }
    j = cJSON_Parse(buf);
    if (!j || !jstr(j, "kind") || strcmp(jstr(j, "kind"), "orion-hub") != 0) {
        set_state(HUB_FAILED, "that address is not an Orion Hub");
        goto out;
    }
    if (jstr(j, "name")) strlcpy(hub_name, jstr(j, "name"), sizeof(hub_name));
    if (jstr(j, "id")) strlcpy(hub_id, jstr(j, "id"), sizeof(hub_id));
    cJSON_Delete(j);
    j = NULL;
    xSemaphoreTake(s_mu, portMAX_DELAY);
    strlcpy(s_st.name, hub_name, sizeof(s_st.name));
    xSemaphoreGive(s_mu);

    char me[48];
    board_name(me, sizeof(me));
    cJSON *req = cJSON_CreateObject();
    cJSON_AddStringToObject(req, "name", me);
    cJSON_AddStringToObject(req, "kind", "board");
    // Stable across forgets and resets: the hub replaces this board's old entry.
    cJSON_AddStringToObject(req, "hw", orion_prov_device_id());
    char *body = cJSON_PrintUnformatted(req);
    cJSON_Delete(req);
    snprintf(ep, 160, "%s/api/v1/pair/request", url);
    esp_err_t err = body ? http_json(HTTP_METHOD_POST, ep, NULL, body, buf, BODY_MAX, &status) : ESP_ERR_NO_MEM;
    cJSON_free(body);
    if (err != ESP_OK || status != 200) {
        set_state(HUB_FAILED, status == 503 ? "the hub refuses pairing right now" : status == 429 ? "too many devices are waiting" : "pairing failed");
        goto out;
    }
    j = cJSON_Parse(buf);
    const char *st = j ? jstr(j, "status") : NULL;
    if (st && strcmp(st, "pending") == 0 && jstr(j, "request_id")) {
        char rid[72];
        strlcpy(rid, jstr(j, "request_id"), sizeof(rid));
        xSemaphoreTake(s_mu, portMAX_DELAY);
        strlcpy(s_st.code, jstr(j, "code") ? jstr(j, "code") : "", sizeof(s_st.code));
        s_st.state = HUB_WAITING;
        xSemaphoreGive(s_mu);
        ESP_LOGI(TAG, "waiting for approval on the hub, code %s", s_st.code);
        changed();
        cJSON_Delete(j);
        j = NULL;
        snprintf(ep, 160, "%s/api/v1/pair/request/%s", url, rid);
        for (int waited = 0; waited < WAIT_MAX_MS && !interrupted(); waited += POLL_MS) {
            vTaskDelay(pdMS_TO_TICKS(POLL_MS));
            if (http_json(HTTP_METHOD_GET, ep, NULL, NULL, buf, BODY_MAX, &status) != ESP_OK || status != 200) continue;
            j = cJSON_Parse(buf);
            st = j ? jstr(j, "status") : NULL;
            if (st && strcmp(st, "pending") != 0) break;
            cJSON_Delete(j);
            j = NULL;
            st = NULL;
        }
        if (!st) {
            set_state(HUB_FAILED, interrupted() ? "stopped" : "nobody approved it in time");
            goto out;
        }
    }
    if (!st || strcmp(st, "approved") != 0 || !jstr(j, "token")) {
        set_state(HUB_FAILED, st && strcmp(st, "denied") == 0    ? "the hub owner said no"
                              : st && strcmp(st, "expired") == 0 ? "nobody approved it in time"
                                                                 : "pairing failed");
        goto out;
    }
    if (save(url, jstr(j, "token"), hub_name, jstr(j, "device_id"), hub_id) != ESP_OK) {
        set_state(HUB_FAILED, "could not save the pairing");
        goto out;
    }
    s_paired = true;
    strlcpy(s_id, hub_id, sizeof(s_id));
    s_fresh_until = xTaskGetTickCount() + pdMS_TO_TICKS(15000);
    ESP_LOGI(TAG, "paired with \"%s\" at %s", hub_name, url);
    set_state(HUB_CONNECTED, NULL);
    // The cloud's health check sees it at once; the state machine follows.
    orion_cloud_prewarm();

out:
    cJSON_Delete(j);
    free(buf);
    free(ep);
}

static void do_forget(void)
{
    read_job_t r = { .url = "" };
    on_internal_stack(read_fn, &r);
    const char *url = r.url, *dev = r.dev;
    char *token = r.token;
    // Best effort: tell the hub to drop this board too. If it cannot hear
    // it, pairing again later replaces the entry anyway (the "hw" id).
    if (url[0] && token[0] && dev[0] && wait_net(20000)) {
        char ep[200], auth[120], buf[128];
        int status = 0;
        snprintf(ep, sizeof(ep), "%s/api/v1/devices/%s", url, dev);
        snprintf(auth, sizeof(auth), "Bearer %s", token);
        http_json(HTTP_METHOD_DELETE, ep, auth, NULL, buf, sizeof(buf), &status);
        ESP_LOGI(TAG, "hub said %d to forgetting this board", status);
        memset(auth, 0, sizeof(auth));
    }
    memset(r.token, 0, sizeof(r.token));
    if (!on_internal_stack(erase_fn, NULL)) {
        set_state(HUB_FAILED, "out of memory, try again");
        return;
    }
    s_paired = false;
    s_id[0] = '\0';
    reload_cloud(30);
    xSemaphoreTake(s_mu, portMAX_DELAY);
    s_st.name[0] = s_st.url[0] = '\0';
    xSemaphoreGive(s_mu);
    set_state(HUB_NONE, NULL);
}

// ---------------------------------------------------------------------------
// The worker
// ---------------------------------------------------------------------------
static void hub_task(void *arg)
{
    (void) arg;
    TickType_t wait = pdMS_TO_TICKS(FIRST_LOOK_MS);
    int gap = 1, skipped = 0;   // sweeps at 2, 4 ... 32 minute gaps while the hub stays away
    while (true) {
        cmd_t c;
        if (xQueueReceive(s_q, &c, wait) == pdTRUE) {
            switch (c.kind) {
            case CMD_SCAN: do_scan(false); break;
            case CMD_CONNECT: do_connect(c.url); break;
            case CMD_FORGET: do_forget(); break;
            }
        } else if (!s_paired || !orion_cloud_hub_online(NULL, 0, NULL, 0)) {
            // Unpaired: is there a hub now? Paired but offline: did it move?
            char was[48];
            xSemaphoreTake(s_mu, portMAX_DELAY);
            strlcpy(was, s_st.url, sizeof(was));
            xSemaphoreGive(s_mu);
            do_scan(true);
            // mDNS did not find it at a new address: look the slow way, less
            // often the longer it stays away (a hub switched off for good).
            if (s_paired && strcmp(was, s_st.url) == 0 && !orion_cloud_hub_online(NULL, 0, NULL, 0) &&
                ++skipped >= gap) {
                relocate();
                skipped = 0;
                if (gap < 16) gap *= 2;
            }
        } else {
            gap = 1;
            skipped = 0;
        }
        wait = pdMS_TO_TICKS(REDISCOVER_MS);
    }
}

// ---------------------------------------------------------------------------
// Console: hub [scan | connect [url] | forget | status]
// ---------------------------------------------------------------------------
static int cmd_hub(int argc, char **argv)
{
    const char *sub = argc > 1 ? argv[1] : "status";
    if (strcmp(sub, "scan") == 0) {
        orion_hub_scan();
    } else if (strcmp(sub, "connect") == 0) {
        orion_hub_connect(argc > 2 ? argv[2] : "");
    } else if (strcmp(sub, "forget") == 0) {
        orion_hub_forget();
    } else if (strcmp(sub, "status") == 0) {
        orion_hub_status_t st;
        orion_hub_status(&st);
        printf("hub %s%s%s%s%s, paired %s, %d found\n", orion_hub_state_name(st.state),
               st.name[0] ? " \"" : "", st.name, st.name[0] ? "\" " : "", st.url, s_paired ? "yes" : "no", st.found);
        if (s_id[0]) printf("  id %s\n", s_id);
        if (st.code[0]) printf("  approval code %s\n", st.code);
        if (st.message[0]) printf("  %s\n", st.message);
        for (int i = 0; i < st.found; i++) printf("  [%d] %s at %s\n", i, st.hubs[i].name, st.hubs[i].url);
    } else {
        printf("usage: hub [scan | connect [http://host:port] | forget | status]\n");
        return 1;
    }
    return 0;
}

esp_err_t orion_hub_start(void)
{
    if (s_q) return ESP_OK;
    s_mu = xSemaphoreCreateMutex();
    s_q = xQueueCreate(4, sizeof(cmd_t));
    s_flash = xQueueCreate(1, sizeof(flash_job_t *));
    if (!s_mu || !s_q || !s_flash) return ESP_ERR_NO_MEM;

    // A board paired before this boot starts as offline until the first check.
    char url[48] = "";
    orion_config_get_str(K_URL, url, sizeof(url));
    s_paired = url[0] && orion_config_has(K_TOKEN);
    if (s_paired) {
        strlcpy(s_st.url, url, sizeof(s_st.url));
        orion_config_copy_str(K_NAME, s_st.name, sizeof(s_st.name), "Orion Hub");
        orion_config_copy_str(K_ID, s_id, sizeof(s_id), "");
        s_st.state = HUB_OFFLINE;
    }

    orion_prov_device_id();   // reads the MAC once, here, not on the worker
    // PSRAM stack: see on_internal_stack(). Never deleted.
    if (xTaskCreatePinnedToCoreWithCaps(hub_task, "orion_hub", 6144, NULL, 3, NULL, tskNO_AFFINITY,
                                        MALLOC_CAP_SPIRAM) != pdPASS) {
        return ESP_ERR_NO_MEM;
    }

    const esp_console_cmd_t cmd = {
        .command = "hub",
        .help = "Orion Hub: hub [scan | connect [http://host:port] | forget | status]",
        .func = cmd_hub,
    };
    esp_console_cmd_register(&cmd);
    ESP_LOGI(TAG, "started, %s", s_paired ? "paired" : "not paired");
    return ESP_OK;
}
