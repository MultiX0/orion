// The reply pipeline. Three things block independently, so three tasks:
//
//   LLM worker   reads the chat stream, cuts it into pieces
//   TTS worker   turns each piece into PCM, into a ring in PSRAM
//   caller       plays the ring the moment it has anything in it
//
// So the speaker starts on the first clause, and the next piece is
// synthesized while the first one plays. Both workers keep their stacks in
// PSRAM, which rules out NVS reads on them: they only read cloud_cfg().

#include "cloud_private.h"

#include <string.h>

#include "freertos/FreeRTOS.h"
#include "freertos/event_groups.h"
#include "freertos/idf_additions.h"
#include "freertos/queue.h"
#include "freertos/stream_buffer.h"
#include "freertos/task.h"

#include "esp_heap_caps.h"
#include "esp_log.h"

static const char *TAG = "cloud_stream";

// The TTS socket must never wait for the speaker. Fish sends about twice as
// fast as real time. A small ring (192 KB is 3 s at 32 kHz) fills on long
// answers, the worker stops reading, the TCP window closes, and the stream
// comes back seconds later: silence mid sentence. 1.5 MB is 24 s at 32 kHz,
// in PSRAM, which has over 7 MB free.
#define RING_BYTES   (1536 * 1024)
#define DRAIN_BYTES  2048
#define LLM_STACK    (12 * 1024)
#define TTS_STACK    (10 * 1024)
#define WORKER_PRIO  4

#define B_LLM_IDLE   BIT0
#define B_TTS_IDLE   BIT1
#define B_LLM_DONE   BIT2
#define B_TTS_DONE   BIT3

typedef enum { JOB_PREWARM, JOB_REPLY } job_kind_t;
typedef struct {
    job_kind_t kind;
    const char *text;
} job_t;

// Travels the piece queue like a piece, asks the TTS worker to prewarm.
#define PIECE_PREWARM ((char *) 1)

// Audio the speaker waits for before a piece starts, and after it ran dry in
// the middle of one. Played the moment anything arrives, Fish's stream falls
// behind at the start of pieces and the speaker plays the DMA's silence mid
// word: a click and a lost syllable. 0 turns the cushion off.
#define PREROLL_MS    350
#define REBUFFER_MS   700
static uint32_t s_preroll_ms = PREROLL_MS;
static volatile bool s_piece_open;  // the TTS worker is receiving a piece

void cloud_stream_set_preroll(uint32_t ms)
{
    s_preroll_ms = ms;
}

uint32_t cloud_stream_preroll(void)
{
    return s_preroll_ms;
}

static QueueHandle_t s_jobs;
static QueueHandle_t s_pieces;      // PSRAM strings; NULL ends a reply
static StreamBufferHandle_t s_ring;
static EventGroupHandle_t s_ev;
static volatile bool s_cancel;
static cloud_reply_state_t s_st;
static char *s_drain;
static uint32_t s_handoff_at;       // first piece went to the TTS worker
static bool s_first_pcm;

bool cloud_cancelled(void)
{
    return s_cancel;
}

void cloud_speak_piece(cloud_reply_state_t *st, const char *piece)
{
    if (!st->speak) {
        return;
    }
    char *copy = cloud_psram_strdup(piece);
    if (!copy) {
        return;
    }
    if (st->pieces++ == 0) {
        s_handoff_at = cloud_now_ms();
    }
    ESP_LOGI(TAG, "piece %d: %s", st->pieces, piece);
    xQueueSend(s_pieces, &copy, portMAX_DELAY);
}

static void llm_task(void *arg)
{
    job_t job;
    for (;;) {
        xEventGroupSetBits(s_ev, B_LLM_IDLE);
        if (xQueueReceive(s_jobs, &job, portMAX_DELAY) != pdTRUE) {
            continue;
        }
        xEventGroupClearBits(s_ev, B_LLM_IDLE);
        if (job.kind == JOB_PREWARM) {
            // Speech to text is needed first, so it is warmed first.
            cloud_prewarm_slot(CLOUD_SLOT_STT);
            cloud_prewarm_slot(CLOUD_SLOT_LLM);
            // With PC control on: is the PC brain there for the next turn?
            cloud_pc_check();
            continue;
        }
        s_st.llm_err = cloud_reply_run(job.text, &s_st);
        if (s_st.llm_err == ESP_OK && s_st.reply_len) {
            cloud_history_push(job.text, s_st.reply);
        }
        if (s_st.speak) {
            char *end = NULL;
            xQueueSend(s_pieces, &end, portMAX_DELAY);
        }
        xEventGroupSetBits(s_ev, B_LLM_DONE);
    }
}

static void ring_put(const uint8_t *p, size_t bytes)
{
    while (bytes && !s_cancel) {
        const size_t n = xStreamBufferSend(s_ring, p, bytes, pdMS_TO_TICKS(100));
        p += n;
        bytes -= n;
    }
}

// Every piece is its own TTS request, so pieces meet end to start. Each one
// fades in over its first 120 samples (5 ms at 24 kHz, 4 ms at 32 kHz): one
// that starts away from zero would click at the join. Bytes can arrive split
// mid sample, hence the half.
#define PIECE_FADE 120
static size_t s_piece_bytes;
static uint8_t s_half;

// PCM into the ring; blocks only when synthesis is far ahead of the speaker.
static bool ring_sink(const void *pcm, size_t bytes, void *ctx)
{
    (void) ctx;
    if (!s_first_pcm) {
        s_first_pcm = true;
        s_st.tts_first_ms = cloud_now_ms() - s_handoff_at;
    }
    const uint8_t *p = pcm;
    while (bytes && s_piece_bytes < PIECE_FADE * 2 && !s_cancel) {
        if ((s_piece_bytes & 1) == 0) {
            s_half = *p++;
        } else {
            const int32_t k = (int32_t) (s_piece_bytes / 2);
            const int16_t v = (int16_t) (s_half | (uint16_t) *p++ << 8);
            const int16_t faded = (int16_t) ((int32_t) v * k / PIECE_FADE);
            const uint8_t out[2] = { (uint8_t) (faded & 0xff), (uint8_t) ((uint16_t) faded >> 8) };
            ring_put(out, 2);
        }
        s_piece_bytes++;
        bytes--;
    }
    if (bytes) {
        s_piece_bytes += bytes;
        ring_put(p, bytes);
    }
    return !s_cancel;
}

static void tts_task(void *arg)
{
    char *piece;
    for (;;) {
        xEventGroupSetBits(s_ev, B_TTS_IDLE);
        if (xQueueReceive(s_pieces, &piece, portMAX_DELAY) != pdTRUE) {
            continue;
        }
        xEventGroupClearBits(s_ev, B_TTS_IDLE);
        if (piece == PIECE_PREWARM) {
            cloud_prewarm_slot(CLOUD_SLOT_TTS);
            continue;
        }
        const uint32_t t0 = cloud_now_ms();
        while (piece) {
            if (piece != PIECE_PREWARM) {
                if (!s_cancel && s_st.tts_err == ESP_OK) {
                    uint32_t connect = 0;
                    s_piece_open = true;
                    s_piece_bytes = 0;
                    const esp_err_t e = cloud_tts_run(piece, ring_sink, NULL, NULL, &connect);
                    s_piece_open = false;
                    s_st.tts_connect_ms += connect;
                    if (e != ESP_OK && !s_cancel) {
                        s_st.tts_err = e;
                    }
                }
                free(piece);
            }
            xQueueReceive(s_pieces, &piece, portMAX_DELAY);
        }
        s_st.tts_total_ms = cloud_now_ms() - t0;
        xEventGroupSetBits(s_ev, B_TTS_DONE);
    }
}

esp_err_t cloud_stream_init(void)
{
    s_jobs = xQueueCreate(4, sizeof(job_t));
    s_pieces = xQueueCreate(12, sizeof(char *));
    s_ev = xEventGroupCreate();
    s_ring = xStreamBufferCreateWithCaps(RING_BYTES, 1, MALLOC_CAP_SPIRAM);
    s_drain = heap_caps_malloc(DRAIN_BYTES, MALLOC_CAP_SPIRAM);
    s_st.reply = heap_caps_malloc(CLOUD_REPLY_MAX, MALLOC_CAP_SPIRAM);
    if (!s_jobs || !s_pieces || !s_ev || !s_ring || !s_drain || !s_st.reply) {
        return ESP_ERR_NO_MEM;
    }
    s_st.reply[0] = '\0';
    if (xTaskCreatePinnedToCoreWithCaps(llm_task, "cloud_llm", LLM_STACK, NULL, WORKER_PRIO,
                                        NULL, tskNO_AFFINITY, MALLOC_CAP_SPIRAM) != pdPASS ||
        xTaskCreatePinnedToCoreWithCaps(tts_task, "cloud_tts", TTS_STACK, NULL, WORKER_PRIO,
                                        NULL, tskNO_AFFINITY, MALLOC_CAP_SPIRAM) != pdPASS) {
        return ESP_ERR_NO_MEM;
    }
    return ESP_OK;
}

void orion_cloud_prewarm(void)
{
    // Not while a reload is rewriting the settings the prewarm would read.
    if (!s_ev || !cloud_gate_lock(0)) {
        return;
    }
    const EventBits_t b = xEventGroupGetBits(s_ev);
    if ((b & B_LLM_IDLE) && uxQueueMessagesWaiting(s_jobs) == 0) {
        const job_t job = { .kind = JOB_PREWARM };
        xQueueSend(s_jobs, &job, 0);
    }
    // A shared text to speech connection is the one the job above warms.
    if ((b & B_TTS_IDLE) && uxQueueMessagesWaiting(s_pieces) == 0 &&
        !cloud_net_shared(CLOUD_SLOT_TTS)) {
        char *p = PIECE_PREWARM;
        xQueueSend(s_pieces, &p, 0);
    }
    cloud_gate_unlock();
}

bool cloud_workers_idle(uint32_t wait_ms)
{
    const EventBits_t want = B_LLM_IDLE | B_TTS_IDLE;
    return (xEventGroupWaitBits(s_ev, want, pdFALSE, pdTRUE, pdMS_TO_TICKS(wait_ms)) & want) == want;
}

esp_err_t cloud_reply_stream(const char *text, char *reply, size_t reply_len,
                             orion_tts_sink_t sink, void *sink_ctx,
                             orion_reply_cb_t on_reply, void *reply_ctx)
{
    if (!text || !text[0] || !s_ev) {
        return ESP_ERR_INVALID_ARG;
    }
    // A cancelled turn may still be unwinding on the workers.
    if (!cloud_workers_idle(35000)) {
        return ESP_ERR_TIMEOUT;
    }
    char *buf = s_st.reply;
    memset(&s_st, 0, sizeof(s_st));
    s_st.reply = buf;
    s_st.reply[0] = '\0';
    s_st.speak = sink != NULL;
    s_cancel = false;
    s_first_pcm = false;
    xStreamBufferReset(s_ring);
    xEventGroupClearBits(s_ev, B_LLM_DONE | B_TTS_DONE);

    const uint32_t t0 = cloud_now_ms();
    if (sink) {
        // Check the TTS connection while the model is still thinking.
        char *warm = PIECE_PREWARM;
        xQueueSend(s_pieces, &warm, 0);
    }
    const job_t job = { .kind = JOB_REPLY, .text = text };
    xQueueSend(s_jobs, &job, portMAX_DELAY);

    bool reported = false;
    bool audio = false;
    uint32_t first_audio = 0, gap = 0, dry_since = 0;
    // A read can end mid sample; the speaker would drop the odd byte and shift
    // every later sample into noise, so it waits here for its other half.
    size_t carry = 0;
    // 16-bit mono: bytes of audio per millisecond.
    const size_t per_ms = cloud_cfg()->tts_rate * 2 / 1000;
    const bool cushion = sink && s_preroll_ms > 0;
    bool buffering = cushion;
    size_t need = s_preroll_ms * per_ms;
    // Ran dry while a piece was still arriving: how often, and for how long.
    uint32_t starved = 0, starved_ms = 0, starved_at = 0;
    bool dry_mid_piece = false;
    for (;;) {
        if (buffering) {
            const size_t have = xStreamBufferBytesAvailable(s_ring);
            if (have >= need || (have > 0 && !s_piece_open)) {
                buffering = false;
                if (starved_at) {
                    starved_ms += cloud_now_ms() - starved_at;
                    starved_at = 0;
                }
            }
        }
        size_t n = sink && !buffering
            ? xStreamBufferReceive(s_ring, s_drain + carry, DRAIN_BYTES - carry, pdMS_TO_TICKS(20))
            : 0;
        if (n) {
            n += carry;
            carry = n & 1;
            n -= carry;
            if (!audio) {
                audio = true;
                first_audio = cloud_now_ms() - t0;
            }
            if (dry_since) {
                const uint32_t dry = cloud_now_ms() - dry_since;
                gap += dry;
                // Without the cushion, a stall mid piece longer than the DMA's
                // 120 ms is a dropout the listener hears. Counted to compare.
                if (!cushion && dry_mid_piece && dry > 100) {
                    starved++;
                    starved_ms += dry;
                }
                dry_since = 0;
            }
            if (n && !sink(s_drain, n, sink_ctx)) {
                s_cancel = true;
                break;
            }
            if (carry) {
                s_drain[0] = s_drain[n];
            }
            continue;
        }
        const EventBits_t bits = xEventGroupGetBits(s_ev);
        if ((bits & B_LLM_DONE) && !reported) {
            reported = true;
            if (on_reply && s_st.llm_err == ESP_OK) {
                on_reply(s_st.reply, reply_ctx);
            }
        }
        const bool tts_over = !sink || (bits & B_TTS_DONE);
        if ((bits & B_LLM_DONE) && tts_over && xStreamBufferIsEmpty(s_ring)) {
            break;
        }
        if (audio && !dry_since) {
            dry_since = cloud_now_ms();    // ran out between pieces
            dry_mid_piece = s_piece_open;
        }
        if (cushion && audio && !buffering) {
            // Out of audio: fade to silence now, while the DMA still has some,
            // then wait for a cushion. Mid piece it is the network falling
            // behind, so the cushion is bigger.
            sink(NULL, 0, sink_ctx);
            buffering = true;
            if (s_piece_open) {
                starved++;
                starved_at = cloud_now_ms();
                need = REBUFFER_MS * per_ms;
            } else {
                need = s_preroll_ms * per_ms;
            }
        }
        if (!sink) {
            xEventGroupWaitBits(s_ev, B_LLM_DONE, pdFALSE, pdFALSE, pdMS_TO_TICKS(100));
        } else if (buffering) {
            vTaskDelay(pdMS_TO_TICKS(10));
        }
    }
    if (sink && audio) {
        ESP_LOGI(TAG, "playback: starved %u times mid piece, %u ms, cushion %u ms",
                 (unsigned) starved, (unsigned) starved_ms, (unsigned) s_preroll_ms);
    }
    if (s_cancel) cloud_workers_idle(5000);

    strlcpy(reply, s_st.reply, reply_len);
    orion_cloud_timing_t *t = cloud_timing();
    t->llm_ms = s_st.llm_ms;
    t->llm_first_ms = s_st.llm_first_ms;
    t->llm_connect_ms = s_st.llm_connect_ms;
    t->tts_first_ms = s_st.tts_first_ms;
    t->tts_connect_ms = s_st.tts_connect_ms;
    t->tts_total_ms = s_st.tts_total_ms;
    t->first_audio_ms = first_audio;
    t->gap_ms = gap;
    t->pieces = (uint8_t) s_st.pieces;
    t->used_camera = s_st.used_camera;

    if (s_cancel) return ESP_ERR_INVALID_STATE;
    if (s_st.llm_err != ESP_OK) return s_st.llm_err;
    if (sink && s_st.tts_err != ESP_OK) return s_st.tts_err;
    return (sink && !audio) ? ESP_FAIL : ESP_OK;
}
