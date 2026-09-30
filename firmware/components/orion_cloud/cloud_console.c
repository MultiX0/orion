// Serial commands, so the whole cloud path can be tested without anyone
// speaking at the board.
//
//   talk What is the capital of France?     LLM and TTS, streamed, spoken
//   talk hex:d8b4d98820...                  the same for Arabic: the console's
//                                           argv splitter drops non-ASCII bytes,
//                                           so Arabic goes in as UTF-8 hex
//   asr_test [file.wav]                     ASR on a WAV in the assets partition
//   asr_test f.wav 3 5 voice                the same streamed, as a spoken turn
//   prewarm                                 open the TLS connections now
//   cloud_status                            keys present, last turn's timings
//   cloud_selftest                          chunker and SSE parser, on the chip
//   cloud_reload, cloud_test llm|stt|tts    what the LAN API calls
//
// tools/cloud/talk_hex.py turns a sentence into the hex form.

#include "cloud_private.h"

#include <ctype.h>
#include <stdlib.h>
#include <string.h>

#include "freertos/FreeRTOS.h"
#include "freertos/idf_additions.h"
#include "freertos/semphr.h"
#include "freertos/task.h"

#include "esp_console.h"
#include "esp_log.h"

#include "cloud_chunk.h"
#include "cloud_sse.h"
#include "orion_audio.h"
#include "orion_config.h"
#include "orion_net.h"

static const char *TAG = "cloud_cmd";

#define TEXT_MAX 512

static int hexval(char c)
{
    if (c >= '0' && c <= '9') return c - '0';
    c = (char) tolower((unsigned char) c);
    return (c >= 'a' && c <= 'f') ? c - 'a' + 10 : -1;
}

// argv back into one sentence, decoding hex: when it is there.
static bool join_args(int argc, char **argv, char *out, size_t out_len)
{
    out[0] = '\0';
    if (argc >= 2 && strncmp(argv[1], "hex:", 4) == 0) {
        const char *h = argv[1] + 4;
        size_t w = 0;
        while (h[0] && h[1] && w + 1 < out_len) {
            const int hi = hexval(h[0]), lo = hexval(h[1]);
            if (hi < 0 || lo < 0) return false;
            out[w++] = (char) (hi * 16 + lo);
            h += 2;
        }
        out[w] = '\0';
        return w > 0;
    }
    for (int i = 1; i < argc; i++) {
        if (i > 1) strlcat(out, " ", out_len);
        strlcat(out, argv[i], out_len);
    }
    return out[0] != '\0';
}

// tts_cushion [ms]: the audio a reply waits for before it plays, and after
// the stream ran dry mid piece. 0 plays at once, for comparing.
static int cmd_cushion(int argc, char **argv)
{
    if (argc > 1) {
        cloud_stream_set_preroll((uint32_t) atoi(argv[1]));
    }
    printf("tts_cushion %u ms\n", (unsigned) cloud_stream_preroll());
    return 0;
}

static bool speak_sink(const void *pcm, size_t bytes, void *ctx)
{
    (void) ctx;
    return orion_audio_play_write(pcm, bytes) == ESP_OK;
}

typedef struct {
    char *text;
    char *reply;
    int rc;
} talk_job_t;

static void talk_job(void *arg)
{
    talk_job_t *j = arg;
    const bool spk = orion_audio_play_begin(orion_cloud_tts_rate()) == ESP_OK;
    esp_err_t err = orion_cloud_reply(j->text, j->reply, CLOUD_REPLY_MAX,
                                      spk ? speak_sink : NULL, NULL, NULL, NULL);
    if (spk) orion_audio_play_end();

    orion_cloud_timing_t t;
    orion_cloud_last_timing(&t);
    printf("reply: %s\n", j->reply);
    printf("talk llm_first_ms=%u llm_ms=%u tts_first_ms=%u first_audio_ms=%u gap_ms=%u "
           "pieces=%u connect_llm=%u connect_tts=%u camera=%d result=%s\n",
           (unsigned) t.llm_first_ms, (unsigned) t.llm_ms, (unsigned) t.tts_first_ms,
           (unsigned) t.first_audio_ms, (unsigned) t.gap_ms, (unsigned) t.pieces,
           (unsigned) t.llm_connect_ms, (unsigned) t.tts_connect_ms, (int) t.used_camera,
           esp_err_to_name(err));
    j->rc = err == ESP_OK ? 0 : 1;
}

// say: one fixed line through TTS and the speaker, no model, so two sound
// settings can be compared on exactly the same words. The line is downloaded
// whole first: a socket read at the speaker's pace stalls (see RING_BYTES).
#define SAY_MAX_BYTES (1536 * 1024)

typedef struct {
    uint8_t *buf;
    size_t len;
} say_buf_t;

static bool say_collect(const void *pcm, size_t bytes, void *ctx)
{
    say_buf_t *b = ctx;
    if (b->len + bytes > SAY_MAX_BYTES) return false;
    memcpy(b->buf + b->len, pcm, bytes);
    b->len += bytes;
    return true;
}

static void say_job(void *arg)
{
    talk_job_t *j = arg;
    say_buf_t b = { .buf = cloud_psram_alloc(SAY_MAX_BYTES) };
    esp_err_t err = b.buf ? orion_cloud_tts(j->text, say_collect, &b) : ESP_ERR_NO_MEM;
    if (err == ESP_OK && orion_audio_play_begin(orion_cloud_tts_rate()) == ESP_OK) {
        orion_audio_play_write(b.buf, b.len);
        orion_audio_play_end();
    }
    free(b.buf);
    printf("say done: %s at %u Hz\n", esp_err_to_name(err), (unsigned) orion_cloud_tts_rate());
    j->rc = err == ESP_OK ? 0 : 1;
}

static int cmd_say(int argc, char **argv)
{
    talk_job_t j = { .text = cloud_psram_alloc(TEXT_MAX), .rc = 1 };
    if (j.text && join_args(argc, argv, j.text, TEXT_MAX)) {
        cloud_run_big(say_job, &j);
    } else {
        printf("usage: say <text>  or  say hex:<utf8 hex>\n");
    }
    free(j.text);
    return j.rc;
}

static int cmd_tts_rate(int argc, char **argv)
{
    if (argc > 1) {
        cloud_cfg_set_fish_rate((uint32_t) atoi(argv[1]));
    }
    printf("tts rate %u Hz\n", (unsigned) orion_cloud_tts_rate());
    return 0;
}

static int cmd_talk(int argc, char **argv)
{
    talk_job_t j = {
        .text = cloud_psram_alloc(TEXT_MAX),
        .reply = cloud_psram_alloc(CLOUD_REPLY_MAX),
        .rc = 1,
    };
    if (j.text && j.reply) {
        if (!join_args(argc, argv, j.text, TEXT_MAX)) {
            printf("usage: talk <text>  or  talk hex:<utf8 hex>\n");
        } else if (!orion_net_is_up()) {
            printf("no network\n");
        } else {
            printf("heard: %s\n", j.text);
            j.reply[0] = '\0';
            cloud_run_big(talk_job, &j);
        }
    }
    free(j.text);
    free(j.reply);
    return j.rc;
}

typedef struct {
    int16_t *pcm;
    size_t samples;
    char text[TEXT_MAX];
    esp_err_t err;
    bool voice;
    uint32_t tail_ms;
} asr_job_t;

// "voice": what a spoken turn does. The prewarm fires at the wake, the clip
// streams in real time as if spoken, and tail_ms is from its last sample to
// the transcript, the part of the wait the user feels.
static void asr_job(void *arg)
{
    asr_job_t *j = arg;
    if (!j->voice) {
        j->err = orion_cloud_asr(j->pcm, j->samples, j->text, sizeof(j->text));
        return;
    }
    orion_cloud_prewarm();
    vTaskDelay(pdMS_TO_TICKS(300));     // the user starts talking
    j->err = orion_cloud_asr_stream_begin();
    for (size_t at = 0; j->err == ESP_OK && at < j->samples; at += 320) {
        const size_t n = j->samples - at < 320 ? j->samples - at : 320;
        j->err = orion_cloud_asr_stream_write(j->pcm + at, n);
        vTaskDelay(pdMS_TO_TICKS(20));
    }
    const uint32_t t0 = cloud_now_ms();
    if (j->err == ESP_OK) j->err = orion_cloud_asr_stream_end(j->text, sizeof(j->text));
    j->tail_ms = cloud_now_ms() - t0;
}

static int cmd_asr_test(int argc, char **argv)
{
    // The file is read here, on the console task: SPIFFS reads flash, which
    // the helper task, with its stack in PSRAM, must never do.
    char path[96];
    snprintf(path, sizeof(path), ASSETS_BASE "/%s", argc > 1 ? argv[1] : "asr_test.wav");
    FILE *f = fopen(path, "rb");
    if (!f) {
        printf("no such asset: %s\n", path);
        return 1;
    }
    fseek(f, 0, SEEK_END);
    const long pcm_bytes = ftell(f) - 44;     // after the RIFF header
    fseek(f, 44, SEEK_SET);
    asr_job_t *j = cloud_psram_alloc(sizeof(*j));
    int16_t *pcm = (j && pcm_bytes > 0) ? cloud_psram_alloc((size_t) pcm_bytes) : NULL;
    const size_t got = pcm ? fread(pcm, 1, (size_t) pcm_bytes, f) : 0;
    fclose(f);
    if (!got) {
        free(pcm);
        free(j);
        printf("%s is empty or too big\n", path);
        return 1;
    }
    j->pcm = pcm;
    j->samples = got / 2;

    // asr_test <file> [runs] [gap_s]: the same clip again and again, with a
    // pause between, the way turns arrive. asr_perf lines carry the breakdown.
    const int runs = argc > 2 ? atoi(argv[2]) : 1;
    const int gap_s = argc > 3 ? atoi(argv[3]) : 3;
    j->voice = argc > 4 && strcmp(argv[4], "voice") == 0;
    int rc = 0;
    for (int i = 0; i < (runs > 0 ? runs : 1); i++) {
        if (i) vTaskDelay(pdMS_TO_TICKS(gap_s * 1000));
        j->text[0] = '\0';
        j->err = ESP_FAIL;
        cloud_run_big(asr_job, j);
        orion_cloud_timing_t t;
        orion_cloud_last_timing(&t);
        printf("asr %d/%d %.1f s audio, %u ms (connect %u, tail %u) %s\ntranscript: %s\n", i + 1,
               runs, (float) got / 32000.0f, (unsigned) t.asr_ms, (unsigned) t.asr_connect_ms,
               (unsigned) j->tail_ms,
               esp_err_to_name(j->err), j->err == ESP_OK ? j->text : "");
        rc |= j->err == ESP_OK ? 0 : 1;
    }
    free(pcm);
    free(j);
    return rc;
}

static int cmd_prewarm(int argc, char **argv)
{
    (void) argc;
    (void) argv;
    orion_cloud_prewarm();
    printf("prewarm posted; the result is logged by cloud_net\n");
    return 0;
}

static int cmd_status(int argc, char **argv)
{
    (void) argc;
    (void) argv;
    char ip[16];
    orion_net_ip(ip, sizeof(ip));
    printf("net %s ip %s rssi %d drops %u\n", orion_net_is_up() ? "up" : "down", ip,
           orion_net_rssi(), (unsigned) orion_net_disconnect_count());
    orion_config_report();
    orion_cloud_timing_t t;
    orion_cloud_last_timing(&t);
    printf("last: asr_ms=%u asr_connect=%u llm_first_ms=%u llm_ms=%u tts_first_ms=%u "
           "first_audio_ms=%u gap_ms=%u pieces=%u\n",
           (unsigned) t.asr_ms, (unsigned) t.asr_connect_ms, (unsigned) t.llm_first_ms,
           (unsigned) t.llm_ms, (unsigned) t.tts_first_ms, (unsigned) t.first_audio_ms,
           (unsigned) t.gap_ms, (unsigned) t.pieces);
    return 0;
}

static int cmd_selftest(int argc, char **argv)
{
    (void) argc;
    (void) argv;
    const int failed = chunker_selftest() + sse_selftest() + prompt_selftest();
    printf("cloud_selftest %s\n", failed ? "FAILED" : "passed");
    return failed ? 1 : 0;
}

// The same two calls the LAN API makes after a config change.
static int cmd_reload(int argc, char **argv)
{
    (void) argc;
    (void) argv;
    const esp_err_t err = orion_cloud_reload();
    printf("cloud_reload %s\n", esp_err_to_name(err));
    return err == ESP_OK ? 0 : 1;
}

static int cmd_test(int argc, char **argv)
{
    uint32_t ms = 0;
    char why[32];
    const esp_err_t err = orion_cloud_test(argc > 1 ? argv[1] : "", &ms, why, sizeof(why));
    printf("cloud_test %s ok=%d ms=%u error=%s\n", argc > 1 ? argv[1] : "",
           err == ESP_OK, (unsigned) ms, why);
    return err == ESP_OK ? 0 : 1;
}

static void reg(const char *name, const char *help, esp_console_cmd_func_t fn)
{
    const esp_console_cmd_t c = { .command = name, .help = help, .func = fn };
    if (esp_console_cmd_register(&c) != ESP_OK) {
        ESP_LOGE(TAG, "could not register %s", name);
    }
}

esp_err_t orion_cloud_register_console(void)
{
    reg("talk", "talk <text> | talk hex:<utf8 hex>: stream a reply and speak it", cmd_talk);
    reg("tts_cushion", "tts_cushion [ms]: audio a reply waits for before it plays; 0 is off", cmd_cushion);
    reg("say", "say <text> | say hex:<utf8 hex>: speak this exact line, no model", cmd_say);
    reg("tts_rate", "tts_rate [16000|24000|32000|44100]: the sample rate asked of Fish", cmd_tts_rate);
    reg("asr_test", "asr_test [file.wav]: ASR on a WAV in the assets partition", cmd_asr_test);
    reg("prewarm", "open the TLS connections to every cloud host now", cmd_prewarm);
    reg("cloud_status", "network, provisioned keys and the last turn's timings", cmd_status);
    cloud_cfg_register_cmds();
    reg("cloud_reload", "reread the cloud settings from NVS, as the API does", cmd_reload);
    reg("cloud_test", "cloud_test llm|stt|tts: the smallest real request", cmd_test);
    reg("cloud_selftest", "chunker and SSE parser cases, run on the chip", cmd_selftest);
    return ESP_OK;
}
