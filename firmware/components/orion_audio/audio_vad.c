// Energy end-of-speech detector on 20 ms frames. Thresholds hang off the
// adaptive noise floor: start at four times the floor, end at twice it.
#include "orion_audio.h"

#include <math.h>
#include <string.h>
#include "audio_priv.h"
#include "esp_check.h"
#include "esp_heap_caps.h"
#include "esp_log.h"
#include "esp_timer.h"

static const char *TAG = "vad";

#define FRAME            320    // 20 ms
#define FRAME_MS         20
#define START_FRAMES     2
// Every millisecond here is added to every answer. 600 is where assistants
// usually sit, and a mid sentence pause long enough to trip it is rare in a
// spoken question.
#define END_SILENCE_MS   600
#define NO_SPEECH_MS     4000
#define PREROLL_MS       300
#define TAIL_MS          400
#define MAX_UTTERANCE_MS 10000
#define START_MIN        100
#define END_MIN          50
// The speaker's own sound and the room's tail after it: never the start of speech.
#define ECHO_TAIL_MS     150
// Speech that starts this soon after the echo began under it: keep from the mark.
#define OVERLAP_MS       300
#define MS_TO_SAMPLES(ms) ((size_t) (ms) * ORION_AUDIO_SAMPLE_RATE / 1000)

static volatile bool s_marked;
static volatile uint32_t s_mark;

void orion_audio_mark_utterance(void)
{
    s_mark = audio_ring_wpos();
    s_marked = true;
}

static int32_t frame_rms(const int16_t *s, size_t n)
{
    uint64_t acc = 0;
    for (size_t i = 0; i < n; i++) {
        acc += (int32_t) s[i] * s[i];
    }
    return (int32_t) sqrt((double) acc / n);
}

// Fills a whole frame, or gives up after a second without audio (mic muted or stopped).
static bool read_frame(orion_mic_reader_t *r, int16_t *dst)
{
    size_t have = 0;
    int stalls = 0;
    while (have < FRAME) {
        size_t n = orion_audio_mic_reader_read(r, dst + have, FRAME - have, 200);
        if (n == 0 && ++stalls > 5) {
            return false;
        }
        have += n;
    }
    return true;
}

// Where the kept audio starts once speech has started at speech_start.
static size_t keep_from(size_t speech_start, size_t echo_end)
{
    if (echo_end && speech_start <= echo_end + MS_TO_SAMPLES(OVERLAP_MS)) {
        // Speech began over the chime: its first syllables are in there.
        return 0;
    }
    return speech_start > MS_TO_SAMPLES(PREROLL_MS) ? speech_start - MS_TO_SAMPLES(PREROLL_MS) : 0;
}

esp_err_t orion_audio_record_utterance(int16_t **pcm, size_t *samples, uint32_t max_ms)
{
    return orion_audio_record_utterance_stream(pcm, samples, max_ms, NULL, NULL);
}

esp_err_t orion_audio_record_utterance_stream(int16_t **pcm, size_t *samples, uint32_t max_ms,
                                              orion_utterance_sink_t sink, void *ctx)
{
    *pcm = NULL;
    *samples = 0;
    if (max_ms == 0 || max_ms > MAX_UTTERANCE_MS) {
        max_ms = MAX_UTTERANCE_MS;
    }
    size_t cap = MS_TO_SAMPLES(max_ms);
    int16_t *buf = heap_caps_malloc(cap * sizeof(int16_t), MALLOC_CAP_SPIRAM);
    ESP_RETURN_ON_FALSE(buf, ESP_ERR_NO_MEM, TAG, "buffer");

    const bool marked = s_marked;
    s_marked = false;
    orion_mic_reader_t *r = marked ? audio_mic_reader_open_at(s_mark) : orion_audio_mic_reader_open();
    if (!r) {
        free(buf);
        return ESP_ERR_NO_MEM;
    }
    // The chime starts after the mark and the reader keeps up in real time, so
    // is_playing() at read time says whether this frame is the speaker's.
    int64_t echo_until = 0;
    size_t echo_end = 0;

    int32_t floor = orion_audio_noise_floor();
    int32_t start_thr = floor * 4 < START_MIN ? START_MIN : floor * 4;
    int32_t end_thr = floor * 2 < END_MIN ? END_MIN : floor * 2;

    size_t len = 0;
    size_t speech_start = 0;
    bool in_speech = false;
    int above = 0;
    uint32_t silence_ms = 0;
    uint32_t elapsed_ms = 0;
    int32_t peak = 0;
    esp_err_t result = ESP_OK;
    size_t from = 0;
    size_t sent = 0;
    bool sink_ok = sink != NULL;

    while (len + FRAME <= cap) {
        if (!read_frame(r, buf + len)) {
            result = ESP_ERR_TIMEOUT;
            break;
        }
        int32_t rms = frame_rms(buf + len, FRAME);
        len += FRAME;
        elapsed_ms += FRAME_MS;
        if (rms > peak) {
            peak = rms;
        }
        const int64_t now = esp_timer_get_time();
        if (orion_audio_is_playing()) {
            echo_until = now + ECHO_TAIL_MS * 1000;
        }
        const bool echo = now < echo_until;
        if (echo) {
            echo_end = len;
        }
        if (!in_speech) {
            above = rms > start_thr && !echo ? above + 1 : 0;
            if (above >= START_FRAMES) {
                in_speech = true;
                speech_start = len - START_FRAMES * FRAME;
                from = keep_from(speech_start, echo_end);
                sent = from;
            } else if (elapsed_ms >= NO_SPEECH_MS) {
                result = ESP_ERR_NOT_FOUND;
                break;
            }
        } else if (rms < end_thr) {
            silence_ms += FRAME_MS;
            if (silence_ms >= END_SILENCE_MS) {
                break;
            }
        } else {
            silence_ms = 0;
        }
        if (in_speech && sink_ok && len > sent) {
            sink_ok = sink(buf + sent, len - sent, ctx);
            sent = len;
        }
    }
    orion_audio_mic_reader_close(r);

    if (result != ESP_OK) {
        free(buf);
        ESP_LOGI(TAG, "no utterance: %s after %u ms, floor %d start %d peak %d",
                 esp_err_to_name(result), (unsigned) elapsed_ms, (int) floor, (int) start_thr, (int) peak);
        return result;
    }

    size_t end = len;
    if (silence_ms > TAIL_MS) {
        end -= MS_TO_SAMPLES(silence_ms - TAIL_MS);
    }
    if (from > 0) {
        memmove(buf, buf + from, (end - from) * sizeof(int16_t));
    }
    *samples = end - from;
    *pcm = buf;

    ESP_LOGI(TAG, "utterance %u ms, speech from %u ms, echo until %u ms, kept from %u ms%s, %s, ended by %s, "
             "floor %d start %d end %d peak %d",
             (unsigned) (*samples * 1000 / ORION_AUDIO_SAMPLE_RATE),
             (unsigned) (speech_start * 1000 / ORION_AUDIO_SAMPLE_RATE),
             (unsigned) (echo_end * 1000 / ORION_AUDIO_SAMPLE_RATE),
             (unsigned) (from * 1000 / ORION_AUDIO_SAMPLE_RATE), marked ? " of the mark" : "",
             !sink ? "not streamed" : sink_ok ? "streamed" : "stream dropped",
             silence_ms >= END_SILENCE_MS ? "silence" : "cap",
             (int) floor, (int) start_thr, (int) end_thr, (int) peak);
    return ESP_OK;
}
