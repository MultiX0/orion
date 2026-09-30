// The extended brains (docs/HARNESS.md, "PC brain"): the desktop app and the
// phone app each serve an OpenAI style endpoint that runs a turn with the date,
// the web, what was said before and, on the PC, the PC's own tools, and
// streams back only the spoken answer. The board stays the voice: it wakes,
// listens, shows the orb and speaks; a brain only writes the words.
//
// The PC comes from the config (pc.enabled) and is checked with GET /tools on
// every prewarm (the wake word and the 40 s heartbeat), with a short timeout.
// The phone comes from its live /ws link and is there exactly while it stays
// linked. cloud_reply.c asks the PC first, then the phone, then the board's
// own model, and moves on the moment a brain fails.

#include "cloud_private.h"

#include <stdio.h>
#include <string.h>

#include "esp_log.h"
#include "freertos/FreeRTOS.h"
#include "freertos/semphr.h"

#include "orion_cloud.h"

static const char *TAG = "cloud_pc";

#define CHECK_TIMEOUT_MS 3000
#define TURN_TIMEOUT_MS  25000   // tools can run before the first word; the turn has 30 s

static volatile bool s_pc_ok;
static volatile bool s_phone_ok;

// The phone's endpoint. Only the LLM worker reads s_phone, which runs the
// checks and the turns; the link callback writes s_next under s_mu, and the
// worker takes it over at its next check or turn.
static cloud_stage_cfg_t s_phone;
static cloud_stage_cfg_t s_next;
static bool s_next_set;
static SemaphoreHandle_t s_mu;

static SemaphoreHandle_t mu(void)
{
    if (!s_mu) {
        s_mu = xSemaphoreCreateMutex();
    }
    return s_mu;
}

void orion_cloud_set_phone_brain(const char *host_port, const char *token)
{
    cloud_stage_cfg_t st = {0};
    st.prov = CLOUD_PROV_OPENAI;
    if (host_port && host_port[0] && token && token[0]) {
        snprintf(st.origin, sizeof(st.origin), "http://%s", host_port);
        snprintf(st.url, sizeof(st.url), "%s/v1/chat/completions", st.origin);
        snprintf(st.auth, sizeof(st.auth), "Bearer %s", token);
    }
    xSemaphoreTake(mu(), portMAX_DELAY);
    s_next = st;
    s_next_set = true;
    // A phone that just linked is there; one that left is not. No check needed.
    s_phone_ok = st.url[0] != '\0';
    xSemaphoreGive(mu());
    memset(&st, 0, sizeof(st));
    ESP_LOGI(TAG, "phone brain %s%s", host_port && host_port[0] ? "at " : "gone",
             host_port && host_port[0] ? host_port : "");
}

// LLM worker only.
static void take_phone(void)
{
    xSemaphoreTake(mu(), portMAX_DELAY);
    if (s_next_set) {
        s_phone = s_next;
        s_next_set = false;
        memset(&s_next, 0, sizeof(s_next));
    }
    xSemaphoreGive(mu());
    cloud_net_set_timeout(CLOUD_SLOT_PHONE, TURN_TIMEOUT_MS);
}

const cloud_stage_cfg_t *cloud_phone_stage(void)
{
    return &s_phone;
}

bool cloud_brain_ready(cloud_slot_t slot)
{
    if (slot == CLOUD_SLOT_PHONE) {
        take_phone();
        return s_phone_ok && s_phone.url[0];
    }
    const cloud_cfg_t *cfg = cloud_cfg();
    return s_pc_ok && cfg && cfg->pc.url[0];
}

void cloud_brain_failed(cloud_slot_t slot)
{
    volatile bool *ok = slot == CLOUD_SLOT_PHONE ? &s_phone_ok : &s_pc_ok;
    if (*ok) {
        ESP_LOGW(TAG, "%s brain stopped answering, the next brain answers",
                 slot == CLOUD_SLOT_PHONE ? "phone" : "pc");
    }
    *ok = false;
}

// GET /tools with a short timeout. True on 200.
static bool check_one(cloud_slot_t slot, const cloud_stage_cfg_t *st)
{
    char url[sizeof(st->origin) + 8];
    snprintf(url, sizeof(url), "%s/tools", st->origin);
    cloud_req_t req = {
        .url = url,
        .method = HTTP_METHOD_GET,
        .auth = st->auth,
    };
    cloud_net_set_timeout(slot, CHECK_TIMEOUT_MS);
    cloud_resp_t resp;
    bool ok = false;
    if (cloud_send(slot, &req, &resp) == ESP_OK) {
        ok = resp.status == 200;
        cloud_finish(slot, &resp, true);
    }
    cloud_net_set_timeout(slot, TURN_TIMEOUT_MS);
    return ok;
}

void cloud_pc_check(void)
{
    const cloud_cfg_t *cfg = cloud_cfg();
    bool ok = false;
    if (cfg && cfg->pc.url[0]) {
        ok = check_one(CLOUD_SLOT_PC, &cfg->pc);
    }
    if (ok != s_pc_ok && cfg) {
        ESP_LOGI(TAG, "pc brain at %s %s", cfg->pc.origin, ok ? "online" : "offline");
    }
    s_pc_ok = ok;

    // A phone that failed a turn gets another chance here while it is linked.
    take_phone();
    if (s_phone.url[0] && !s_phone_ok) {
        s_phone_ok = check_one(CLOUD_SLOT_PHONE, &s_phone);
        if (s_phone_ok) {
            ESP_LOGI(TAG, "phone brain at %s back", s_phone.origin);
        }
    }
}

bool orion_cloud_pc_online(char *host, size_t host_len)
{
    const cloud_cfg_t *cfg = cloud_cfg();
    if (host && host_len) {
        host[0] = '\0';
        if (cfg && cfg->pc.origin[0]) {
            const char *h = strstr(cfg->pc.origin, "://");
            strlcpy(host, h ? h + 3 : cfg->pc.origin, host_len);
        }
    }
    return cloud_brain_ready(CLOUD_SLOT_PC);
}
