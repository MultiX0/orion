// /capture: one JPEG. /stream: MJPEG at about 10 fps, served from its own
// task so the HTTP task keeps answering everything else. Up to two viewers
// share each captured frame, so the phone and the PC can watch at once
// instead of one waiting on a lens the other holds.
#include "api_priv.h"

#include <stdio.h>
#include <string.h>

#include "freertos/FreeRTOS.h"
#include "freertos/task.h"
#include "esp_check.h"
#include "esp_heap_caps.h"
#include "esp_log.h"
#include "esp_timer.h"

#include "orion_camera.h"

static const char *TAG = "orion_api";

#define STREAM_STACK 6144
#define FRAME_GAP_MS 20
#define VIEWERS_MAX  2

static volatile bool s_streaming;
static volatile bool s_stop;
static TaskHandle_t s_task;
// Viewers join from the HTTP task and leave from the stream task.
static httpd_req_t *s_viewers[VIEWERS_MAX];
static portMUX_TYPE s_lock = portMUX_INITIALIZER_UNLOCKED;

static int viewer_count(void)
{
    int n = 0;
    taskENTER_CRITICAL(&s_lock);
    for (int i = 0; i < VIEWERS_MAX; i++) {
        n += s_viewers[i] != NULL;
    }
    taskEXIT_CRITICAL(&s_lock);
    return n;
}

static void drop_viewer(int i, bool tell)
{
    taskENTER_CRITICAL(&s_lock);
    httpd_req_t *req = s_viewers[i];
    s_viewers[i] = NULL;
    taskEXIT_CRITICAL(&s_lock);
    if (req) {
        if (tell) {
            httpd_resp_send_chunk(req, NULL, 0);
        }
        httpd_req_async_handler_complete(req);
    }
}

static bool send_frame(httpd_req_t *req, const uint8_t *jpg, size_t len)
{
    char head[96];
    int n = snprintf(head, sizeof(head),
                     "--frame\r\nContent-Type: image/jpeg\r\nContent-Length: %u\r\n\r\n",
                     (unsigned) len);
    return httpd_resp_send_chunk(req, head, n) == ESP_OK &&
           httpd_resp_send_chunk(req, (const char *) jpg, len) == ESP_OK &&
           httpd_resp_send_chunk(req, "\r\n", 2) == ESP_OK;
}

static esp_err_t h_capture(httpd_req_t *req)
{
    if (!api_authorized(req)) {
        return ESP_OK;
    }
    if (s_streaming) {
        api_send_json(req, "409 Conflict", "{\"error\":\"busy\",\"message\":\"a stream is running\"}");
        return ESP_OK;
    }
    uint8_t *jpg = NULL;
    size_t len = 0;
    int64_t t0 = esp_timer_get_time();
    esp_err_t err = orion_camera_capture_jpeg(&jpg, &len);
    if (err != ESP_OK) {
        api_send_json(req, "503 Service Unavailable", "{\"error\":\"camera\",\"message\":\"capture failed\"}");
        return ESP_OK;
    }
    httpd_resp_set_type(req, "image/jpeg");
    httpd_resp_set_hdr(req, "Cache-Control", "no-store");
    err = httpd_resp_send(req, (const char *) jpg, len);
    orion_camera_release();
    ESP_LOGI(TAG, "capture %u bytes in %lld ms", (unsigned) len, (esp_timer_get_time() - t0) / 1000);
    return err;
}

// One task for the life of the server, parked on a notification between
// streams. A task with a PSRAM stack should not delete itself, so it never
// exits.
static void stream_task(void *arg)
{
    (void) arg;
    while (true) {
        ulTaskNotifyTake(pdTRUE, portMAX_DELAY);
        uint32_t frames = 0;
        size_t bytes = 0;
        int64_t t0 = esp_timer_get_time();
        while (!s_stop && viewer_count() > 0) {
            uint8_t *jpg = NULL;
            size_t len = 0;
            if (orion_camera_capture_jpeg(&jpg, &len) != ESP_OK) {
                break;
            }
            // One capture, every viewer. A viewer whose send fails has gone.
            for (int i = 0; i < VIEWERS_MAX; i++) {
                taskENTER_CRITICAL(&s_lock);
                httpd_req_t *req = s_viewers[i];
                taskEXIT_CRITICAL(&s_lock);
                if (req && !send_frame(req, jpg, len)) {
                    drop_viewer(i, false);
                }
            }
            orion_camera_release();
            frames++;
            bytes += len;
            vTaskDelay(pdMS_TO_TICKS(FRAME_GAP_MS));
        }
        for (int i = 0; i < VIEWERS_MAX; i++) {
            drop_viewer(i, true);
        }
        int64_t ms = (esp_timer_get_time() - t0) / 1000;
        ESP_LOGI(TAG, "stream ended: %u frames, %u KB, %lld ms, %.1f fps",
                 (unsigned) frames, (unsigned) (bytes / 1024), ms,
                 ms > 0 ? frames * 1000.0 / ms : 0.0);
        s_streaming = false;
    }
}

static esp_err_t h_stream(httpd_req_t *req)
{
    if (!api_authorized(req)) {
        return ESP_OK;
    }
    if (!s_task || viewer_count() >= VIEWERS_MAX) {
        api_send_json(req, "409 Conflict", "{\"error\":\"busy\",\"message\":\"two viewers already\"}");
        return ESP_OK;
    }
    httpd_req_t *async = NULL;
    if (httpd_req_async_handler_begin(req, &async) != ESP_OK) {
        api_send_json(req, "500 Internal Server Error", "{\"error\":\"async\",\"message\":\"no async slot\"}");
        return ESP_OK;
    }
    httpd_resp_set_type(async, "multipart/x-mixed-replace; boundary=frame");
    httpd_resp_set_hdr(async, "Cache-Control", "no-store");
    bool placed = false;
    taskENTER_CRITICAL(&s_lock);
    for (int i = 0; i < VIEWERS_MAX && !placed; i++) {
        if (!s_viewers[i]) {
            s_viewers[i] = async;
            placed = true;
        }
    }
    taskEXIT_CRITICAL(&s_lock);
    if (!placed) {
        httpd_req_async_handler_complete(async);
        return ESP_OK;
    }
    // The first viewer starts the loop; a second joins the one running.
    if (!s_streaming) {
        s_stop = false;
        s_streaming = true;
        xTaskNotifyGive(s_task);
    }
    return ESP_OK;
}

void api_cam_stop(void)
{
    s_stop = true;
    for (int i = 0; i < 100 && s_streaming; i++) {
        vTaskDelay(pdMS_TO_TICKS(10));
    }
}

esp_err_t api_cam_register(httpd_handle_t hd)
{
    // The stack is PSRAM: the loop only captures, formats and sends.
    if (!s_task && xTaskCreateWithCaps(stream_task, "mjpeg", STREAM_STACK, NULL, 4, &s_task,
                                       MALLOC_CAP_SPIRAM | MALLOC_CAP_8BIT) != pdPASS) {
        ESP_LOGE(TAG, "no memory for the stream task");
        s_task = NULL;
    }
    const httpd_uri_t uris[] = {
        { .uri = "/capture", .method = HTTP_GET, .handler = h_capture },
        { .uri = "/stream",  .method = HTTP_GET, .handler = h_stream },
    };
    for (size_t i = 0; i < sizeof(uris) / sizeof(uris[0]); i++) {
        ESP_RETURN_ON_ERROR(httpd_register_uri_handler(hd, &uris[i]), TAG, "register %s", uris[i].uri);
    }
    return ESP_OK;
}
