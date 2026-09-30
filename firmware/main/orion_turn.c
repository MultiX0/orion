#include "orion_turn.h"

#include <stdlib.h>
#include <string.h>

#include "freertos/FreeRTOS.h"
#include "freertos/task.h"
#include "freertos/queue.h"
#include "esp_log.h"
#include "esp_timer.h"

#include "orion_audio.h"
#include "orion_cloud.h"
#include "orion_sm.h"

static const char *TAG = "turn";

#define RECORD_MAX_MS   10000
#define TRANSCRIPT_MAX  512
#define REPLY_MAX       1024

typedef enum {
    TURN_VOICE,
    TURN_TEXT,
    TURN_SAY,       // POST /api/say: speak the text, no model
} turn_kind_t;

static QueueHandle_t s_req;
static volatile bool s_cancel;
static bool s_first_chunk;
static bool s_llm_ok;
static int64_t s_t0;
static int64_t s_speech_end;    // the user stopped talking, or the text arrived
static uint32_t s_end_to_audio;
static turn_timing_t s_t;
static char s_pending[TRANSCRIPT_MAX];
static char s_transcript[TRANSCRIPT_MAX];
static char s_reply[REPLY_MAX];

static uint32_t ms_since(int64_t t0)
{
    return (uint32_t) ((esp_timer_get_time() - t0) / 1000);
}

// Runs on the turn task, inside orion_cloud_reply. The speaker is already open.
static bool tts_sink(const void *pcm, size_t bytes, void *ctx)
{
    if (s_cancel) {
        return false;
    }
    if (!s_first_chunk) {
        s_first_chunk = true;
        // The number that decides how fast Orion feels: the user stops
        // talking, and this long later the first word comes out.
        s_end_to_audio = ms_since(s_speech_end);
        sm_post(EV_TTS_CHUNK, 0);
    }
    return orion_audio_play_write(pcm, bytes) == ESP_OK;
}

// The recording goes to speech to text while the user is still talking. Any
// failure here only means the whole recording is uploaded at the end instead.
static bool s_asr_streaming;

static bool asr_sink(const int16_t *pcm, size_t samples, void *ctx)
{
    if (s_cancel) {
        return false;
    }
    if (!s_asr_streaming) {
        if (orion_cloud_asr_stream_begin() != ESP_OK) {
            return false;
        }
        s_asr_streaming = true;
    }
    if (orion_cloud_asr_stream_write(pcm, samples) != ESP_OK) {
        s_asr_streaming = false;    // already closed by the write
        return false;
    }
    return true;
}

// Returns false when the turn is over, either failed or cancelled. On failure
// the state machine has already been told.
static bool record_and_transcribe(void)
{
    int16_t *pcm = NULL;
    size_t samples = 0;
    s_asr_streaming = false;
    int64_t t = esp_timer_get_time();
    esp_err_t err = orion_audio_record_utterance_stream(&pcm, &samples, RECORD_MAX_MS, asr_sink, NULL);
    s_t.record_ms = ms_since(t);

    if (err != ESP_OK || s_cancel || !pcm || samples == 0) {
        if (s_asr_streaming) {
            orion_cloud_asr_stream_abort();
            s_asr_streaming = false;
        }
    }
    if (s_cancel) {
        free(pcm);
        return false;
    }
    if (err == ESP_ERR_NOT_FOUND || !pcm || samples == 0) {
        free(pcm);
        sm_post(EV_ERROR, ERR_NO_SPEECH);
        return false;
    }
    if (err != ESP_OK) {
        free(pcm);
        ESP_LOGE(TAG, "record: %s", esp_err_to_name(err));
        sm_post(EV_ERROR, ERR_ASR);
        return false;
    }
    s_speech_end = esp_timer_get_time();
    sm_post(EV_SPEECH_END, (int32_t) (samples / (ORION_AUDIO_SAMPLE_RATE / 1000)));

    t = esp_timer_get_time();
    s_transcript[0] = '\0';
    err = ESP_FAIL;
    if (s_asr_streaming) {
        s_asr_streaming = false;
        err = orion_cloud_asr_stream_end(s_transcript, sizeof(s_transcript));
        if (err != ESP_OK && err != ESP_ERR_NOT_ALLOWED) {
            ESP_LOGW(TAG, "streamed asr: %s, uploading the recording instead", esp_err_to_name(err));
        }
    }
    if (err != ESP_OK && err != ESP_ERR_NOT_ALLOWED) {
        s_transcript[0] = '\0';
        err = orion_cloud_asr(pcm, samples, s_transcript, sizeof(s_transcript));
    }
    s_t.asr_ms = ms_since(t);
    free(pcm);

    if (s_cancel) {
        return false;
    }
    if (err != ESP_OK) {
        ESP_LOGE(TAG, "asr: %s", esp_err_to_name(err));
        sm_post(EV_ERROR, ERR_ASR);
        return false;
    }
    if (s_transcript[0] == '\0') {
        // Audio went up and came back empty: silence, or nothing the
        // recognizer could use. Same answer for the user either way.
        sm_post(EV_ERROR, ERR_NO_SPEECH);
        return false;
    }
    ESP_LOGI(TAG, "heard: %s", s_transcript);
    sm_post(EV_ASR_DONE, 0);
    return true;
}

// The reply text is complete. Its audio may already be playing: the answer is
// streamed, so the first clause is often spoken before the model has written
// the last one.
static void on_reply(const char *reply, void *ctx)
{
    (void) ctx;
    s_llm_ok = true;
    strlcpy(s_reply, reply, sizeof(s_reply));
    ESP_LOGI(TAG, "reply: %s", s_reply);
    sm_post(EV_LLM_DONE, 0);
}

// Think and speak in one call: orion_cloud_reply streams the model, cuts its
// reply into clauses and synthesizes each while the next is being written.
static bool respond(void)
{
    // An earcon may still be playing. One speaker, one stream: wait for it
    // rather than talk over it.
    while (orion_audio_is_playing() && !s_cancel) {
        vTaskDelay(pdMS_TO_TICKS(10));
    }
    if (s_cancel) {
        return false;
    }
    // The TTS decides the rate: 32 kHz from Fish by default, 24 kHz from an
    // OpenAI compatible server. play_begin retunes the I2S clock and the DSP.
    if (orion_audio_play_begin(orion_cloud_tts_rate()) != ESP_OK) {
        sm_post(EV_ERROR, ERR_TTS);
        return false;
    }

    s_first_chunk = false;
    s_llm_ok = false;
    s_reply[0] = '\0';
    esp_err_t err = orion_cloud_reply(s_transcript, s_reply, sizeof(s_reply),
                                      tts_sink, NULL, on_reply, NULL);
    orion_audio_play_end();
    s_t.total_ms = ms_since(s_t0);

    orion_cloud_timing_t ct;
    orion_cloud_last_timing(&ct);
    s_t.llm_ms = ct.llm_ms;
    s_t.tts_first_ms = ct.tts_first_ms;
    s_t.tts_total_ms = ct.tts_total_ms;
    s_t.used_camera = ct.used_camera;
    ESP_LOGI(TAG, "turn_perf speech_end_to_audio_ms=%u asr_ms=%u asr_connect_ms=%u "
             "llm_first_ms=%u llm_ms=%u tts_first_ms=%u first_audio_ms=%u gap_ms=%u "
             "pieces=%u connect_llm=%u connect_tts=%u total_ms=%u",
             (unsigned) s_end_to_audio, (unsigned) s_t.asr_ms, (unsigned) ct.asr_connect_ms,
             (unsigned) ct.llm_first_ms, (unsigned) ct.llm_ms, (unsigned) ct.tts_first_ms,
             (unsigned) ct.first_audio_ms, (unsigned) ct.gap_ms, (unsigned) ct.pieces,
             (unsigned) ct.llm_connect_ms, (unsigned) ct.tts_connect_ms,
             (unsigned) s_t.total_ms);

    if (s_cancel) {
        return false;
    }
    if (err != ESP_OK || !s_first_chunk) {
        ESP_LOGE(TAG, "reply: %s", err == ESP_OK ? "no audio" : esp_err_to_name(err));
        sm_post(EV_ERROR, s_llm_ok ? ERR_TTS : ERR_LLM);
        return false;
    }
    sm_post(EV_TTS_DONE, 0);
    return true;
}

// POST /api/say: the text as it is, through the same speaker path as a reply.
static void say(void)
{
    while (orion_audio_is_playing() && !s_cancel) {
        vTaskDelay(pdMS_TO_TICKS(10));
    }
    if (s_cancel) {
        return;
    }
    strlcpy(s_reply, s_pending, sizeof(s_reply));
    sm_post(EV_LLM_DONE, 0);
    if (orion_audio_play_begin(orion_cloud_tts_rate()) != ESP_OK) {
        sm_post(EV_ERROR, ERR_TTS);
        return;
    }
    s_first_chunk = false;
    s_speech_end = esp_timer_get_time();
    esp_err_t err = orion_cloud_tts(s_reply, tts_sink, NULL);
    orion_audio_play_end();
    if (s_cancel) {
        return;
    }
    sm_post(err == ESP_OK && s_first_chunk ? EV_TTS_DONE : EV_ERROR, err == ESP_OK ? 0 : ERR_TTS);
}

static void run(turn_kind_t kind)
{
    memset(&s_t, 0, sizeof(s_t));
    s_cancel = false;
    s_end_to_audio = 0;
    s_t0 = esp_timer_get_time();

    if (kind == TURN_SAY) {
        say();
        return;
    }
    if (kind == TURN_VOICE) {
        // The TLS handshakes to every host happen while the user is still
        // talking, not after. 1.5 to 2.4 s each on this chip, measured.
        orion_cloud_prewarm();
        if (!record_and_transcribe()) {
            return;
        }
    } else {
        s_speech_end = esp_timer_get_time();
        strlcpy(s_transcript, s_pending, sizeof(s_transcript));
        sm_post(EV_SPEECH_END, 0);
        sm_post(EV_ASR_DONE, 0);
    }
    respond();
}

static void turn_task(void *arg)
{
    turn_kind_t kind;
    while (true) {
        if (xQueueReceive(s_req, &kind, portMAX_DELAY) == pdTRUE) {
            run(kind);
        }
    }
}

esp_err_t turn_task_start(void)
{
    s_req = xQueueCreate(2, sizeof(turn_kind_t));
    if (!s_req) {
        return ESP_ERR_NO_MEM;
    }
    // TLS handshakes for the cloud calls happen on this stack.
    if (xTaskCreate(turn_task, "orion_turn", 12288, NULL, 4, NULL) != pdPASS) {
        return ESP_ERR_NO_MEM;
    }
    return ESP_OK;
}

void turn_begin(void)
{
    turn_kind_t k = TURN_VOICE;
    xQueueSend(s_req, &k, 0);
}

void turn_begin_text(void)
{
    turn_kind_t k = TURN_TEXT;
    xQueueSend(s_req, &k, 0);
}

void turn_begin_say(void)
{
    turn_kind_t k = TURN_SAY;
    xQueueSend(s_req, &k, 0);
}

void turn_set_pending_text(const char *text)
{
    strlcpy(s_pending, text ? text : "", sizeof(s_pending));
}

void turn_cancel(void)               { s_cancel = true; }
bool turn_is_cancelled(void)         { return s_cancel; }
void turn_last_timing(turn_timing_t *out) { *out = s_t; }
const char *turn_last_transcript(void) { return s_transcript; }
const char *turn_last_reply(void)      { return s_reply; }
