// The Orion Hub, for the app (docs/DEVICE_PROTOCOL.md, "Orion Hub"):
//
//   GET  /api/hub                       state, the paired hub, the hubs found
//   POST /api/hub {"action":"scan"}
//   POST /api/hub {"action":"connect", "url":"http://host:8780"}   url optional: the first hub found
//   POST /api/hub {"action":"forget"}
//
// The board does the pairing itself (orion_hub.c), the same as from its menu;
// the app only asks and watches the state. Nothing here touches flash: the
// hub client queues the work on its own task.

#include "api_priv.h"

#include <stdio.h>
#include <string.h>

#include "cJSON.h"

#include "orion_hub.h"

static esp_err_t h_get(httpd_req_t *req)
{
    if (!api_authorized(req)) {
        return ESP_OK;
    }
    orion_hub_status_t st;
    orion_hub_status(&st);
    cJSON *o = cJSON_CreateObject();
    cJSON_AddStringToObject(o, "state", orion_hub_state_name(st.state));
    cJSON_AddBoolToObject(o, "paired", orion_hub_paired());
    if (st.name[0]) cJSON_AddStringToObject(o, "name", st.name);
    if (st.url[0]) cJSON_AddStringToObject(o, "url", st.url);
    if (orion_hub_id()[0]) cJSON_AddStringToObject(o, "id", orion_hub_id());
    if (st.code[0]) cJSON_AddStringToObject(o, "code", st.code);
    if (st.message[0]) cJSON_AddStringToObject(o, "message", st.message);
    cJSON *found = cJSON_AddArrayToObject(o, "found");
    for (int i = 0; i < st.found; i++) {
        cJSON *h = cJSON_CreateObject();
        cJSON_AddStringToObject(h, "name", st.hubs[i].name);
        cJSON_AddStringToObject(h, "url", st.hubs[i].url);
        cJSON_AddItemToArray(found, h);
    }
    char *json = cJSON_PrintUnformatted(o);
    cJSON_Delete(o);
    api_send_json(req, "200 OK", json ? json : "{}");
    cJSON_free(json);
    return ESP_OK;
}

static esp_err_t h_post(httpd_req_t *req)
{
    if (!api_authorized(req)) {
        return ESP_OK;
    }
    char body[256];
    const int len = req->content_len < sizeof(body) - 1 ? (int) req->content_len : (int) sizeof(body) - 1;
    int got = 0;
    while (got < len) {
        const int n = httpd_req_recv(req, body + got, len - got);
        if (n <= 0) break;
        got += n;
    }
    body[got] = '\0';
    cJSON *o = cJSON_Parse(body);
    const cJSON *action = o ? cJSON_GetObjectItemCaseSensitive(o, "action") : NULL;
    const cJSON *url = o ? cJSON_GetObjectItemCaseSensitive(o, "url") : NULL;
    esp_err_t err = ESP_ERR_INVALID_ARG;
    if (cJSON_IsString(action)) {
        if (strcmp(action->valuestring, "scan") == 0) {
            err = orion_hub_scan();
        } else if (strcmp(action->valuestring, "connect") == 0) {
            const char *u = cJSON_IsString(url) ? url->valuestring : "";
            err = strlen(u) < 48 ? orion_hub_connect(u) : ESP_ERR_INVALID_SIZE;
        } else if (strcmp(action->valuestring, "forget") == 0) {
            err = orion_hub_forget();
        }
    }
    cJSON_Delete(o);
    if (err == ESP_ERR_INVALID_ARG || err == ESP_ERR_INVALID_SIZE) {
        api_send_json(req, "400 Bad Request",
                      "{\"error\":\"bad_request\",\"message\":\"action must be scan, connect (with an optional url) or forget\"}");
    } else if (err != ESP_OK) {
        api_send_json(req, "409 Conflict", "{\"error\":\"busy\",\"message\":\"the hub client is busy, try again\"}");
    } else {
        api_send_json(req, "200 OK", "{\"ok\":true}");
    }
    return ESP_OK;
}

void api_hub_register(httpd_handle_t hd)
{
    const httpd_uri_t uris[] = {
        { .uri = "/api/hub", .method = HTTP_GET,  .handler = h_get },
        { .uri = "/api/hub", .method = HTTP_POST, .handler = h_post },
    };
    for (size_t i = 0; i < sizeof(uris) / sizeof(uris[0]); i++) {
        httpd_register_uri_handler(hd, &uris[i]);
    }
}
