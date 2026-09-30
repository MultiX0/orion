// Console commands for the audio path. The loopback one is the demo.
#include "orion_audio.h"

#include <dirent.h>
#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "audio_priv.h"
#include "esp_check.h"
#include "esp_console.h"
#include "esp_heap_caps.h"
#include "esp_timer.h"
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"

static const char *TAG = "audio";

#define SELFTEST_HZ 1000
#define SELFTEST_MS 1000

static int arg_int(int argc, char **argv, int idx, int fallback)
{
    return argc > idx ? atoi(argv[idx]) : fallback;
}

static int32_t rms_of(const int16_t *s, size_t n)
{
    uint64_t acc = 0;
    for (size_t i = 0; i < n; i++) {
        acc += (int32_t) s[i] * s[i];
    }
    return n ? (int32_t) sqrt((double) acc / n) : 0;
}

static int cmd_tone(int argc, char **argv)
{
    int hz = arg_int(argc, argv, 1, 1000);
    int ms = arg_int(argc, argv, 2, 500);
    int64_t t0 = esp_timer_get_time();
    esp_err_t err = orion_audio_play_tone(hz, ms);
    printf("tone %d Hz %d ms: %s, took %d ms\n", hz, ms, esp_err_to_name(err),
           (int) ((esp_timer_get_time() - t0) / 1000));
    return err == ESP_OK ? 0 : 1;
}

static int cmd_wav(int argc, char **argv)
{
    if (argc < 2) {
        printf("usage: wav <file in /assets>\n");
        return 1;
    }
    // "wav <name> open" keeps the mic running so `ww clip` afterwards holds
    // the room's view of the last 2 s of playback, for judging the pipeline.
    bool open = argc > 2 && !strcmp(argv[2], "open");
    audio_mic_hold_open(open);
    esp_err_t err = orion_audio_play_asset(argv[1]);
    audio_mic_hold_open(false);
    printf("wav %s: %s\n", argv[1], esp_err_to_name(err));
    return err == ESP_OK ? 0 : 1;
}

static int cmd_vol(int argc, char **argv)
{
    if (argc > 1) {
        orion_audio_set_volume(atoi(argv[1]));
    }
    printf("volume %u\n", orion_audio_get_volume());
    return 0;
}

static int cmd_assets(int argc, char **argv)
{
    esp_err_t err = audio_assets_mount();
    if (err != ESP_OK) {
        printf("assets: %s\n", esp_err_to_name(err));
        return 1;
    }
    DIR *d = opendir("/assets");
    if (!d) {
        printf("assets: cannot open /assets\n");
        return 1;
    }
    struct dirent *e;
    int n = 0;
    while ((e = readdir(d)) != NULL) {
        printf("  %s\n", e->d_name);
        n++;
    }
    closedir(d);
    printf("%d files\n", n);
    return 0;
}

static int cmd_mic(int argc, char **argv)
{
    uint32_t chunks, muted, dropped;
    audio_mic_stats(&chunks, &muted, &dropped);
    printf("mic floor %d rms %d level %.2f chunks %u muted %u dropped %u\n",
           (int) orion_audio_noise_floor(), (int) orion_audio_mic_rms(), orion_audio_level(),
           (unsigned) chunks, (unsigned) muted, (unsigned) dropped);
    return 0;
}

// Prints one line per 250 ms: mean and max chunk RMS. For silence vs music.
static int cmd_micmon(int argc, char **argv)
{
    int sec = arg_int(argc, argv, 1, 5);
    for (int w = 0; w < sec * 4; w++) {
        int32_t max = 0;
        int64_t sum = 0;
        for (int i = 0; i < 25; i++) {
            int32_t r = orion_audio_mic_rms();
            sum += r;
            if (r > max) {
                max = r;
            }
            vTaskDelay(pdMS_TO_TICKS(10));
        }
        printf("micmon t=%d.%02d rms mean %d max %d floor %d level %.2f\n", w / 4, (w % 4) * 25,
               (int) (sum / 25), (int) max, (int) orion_audio_noise_floor(), orion_audio_level());
    }
    return 0;
}

static int cmd_loopback(int argc, char **argv)
{
    int sec = arg_int(argc, argv, 1, 3);
    sec = sec < 1 ? 1 : (sec > 10 ? 10 : sec);
    size_t total = (size_t) sec * ORION_AUDIO_SAMPLE_RATE;
    int16_t *buf = heap_caps_malloc(total * sizeof(int16_t), MALLOC_CAP_SPIRAM);
    if (!buf) {
        printf("loopback: no memory\n");
        return 1;
    }
    orion_mic_reader_t *r = orion_audio_mic_reader_open();
    printf("loopback: recording %d s, speak now\n", sec);
    size_t got = 0;
    int stalls = 0;
    while (got < total) {
        size_t n = orion_audio_mic_reader_read(r, buf + got, total - got, 500);
        if (n == 0 && ++stalls > 6) {
            break;
        }
        got += n;
    }
    orion_audio_mic_reader_close(r);

    printf("loopback: recorded %u samples, rms %d, playing back\n", (unsigned) got, (int) rms_of(buf, got));
    // "loopback 3 open" keeps the mic running through the playback so `ww clip`
    // afterwards holds what the room heard, for checking the pipeline on the PC.
    bool open = argc > 2 && !strcmp(argv[2], "open");
    audio_mic_hold_open(open);
    esp_err_t err = orion_audio_play_pcm(buf, got, ORION_AUDIO_SAMPLE_RATE);
    audio_mic_hold_open(false);
    printf("loopback: done, %s\n", esp_err_to_name(err));
    free(buf);
    return err == ESP_OK ? 0 : 1;
}

// Goertzel power at one frequency, as a fraction of the total power.
static float tone_fraction(const int16_t *s, size_t n, int hz)
{
    float k = 2.0f * cosf(2.0f * (float) M_PI * hz / ORION_AUDIO_SAMPLE_RATE);
    float q0 = 0, q1 = 0, q2 = 0;
    double total = 0;
    for (size_t i = 0; i < n; i++) {
        float x = s[i] / 32768.0f;
        q0 = k * q1 - q2 + x;
        q2 = q1;
        q1 = q0;
        total += x * x;
    }
    float power = q1 * q1 + q2 * q2 - k * q1 * q2;
    // For a pure sine of amplitude A the Goertzel power is (N*A/2)^2 and the
    // total is N*A^2/2, so power*2/N over the total is exactly 1.0.
    float tone = power * 2.0f / n;
    return total > 0 ? (float) (tone / total) : 0;
}

// Plays a tone with the mic held open, then looks at what the mic heard.
// A speaker that works puts most of the mic energy at the tone frequency.
static int cmd_selftest(int argc, char **argv)
{
    // One 10 ms chunk is too jumpy to divide by. Average 200 ms of room first.
    int64_t sum = 0;
    for (int i = 0; i < 20; i++) {
        sum += orion_audio_mic_rms();
        vTaskDelay(pdMS_TO_TICKS(10));
    }
    int32_t quiet = (int32_t) (sum / 20);
    audio_mic_hold_open(true);
    esp_err_t err = orion_audio_play_tone(SELFTEST_HZ, SELFTEST_MS);
    audio_mic_hold_open(false);
    if (err != ESP_OK) {
        printf("selftest: tone failed, %s\n", esp_err_to_name(err));
        return 1;
    }
    // play_end waited out the DMA and the mic drops nothing while held open,
    // so the newest 1.3 s of the ring holds the tone plus a little tail.
    size_t n = ORION_AUDIO_SAMPLE_RATE * 13 / 10;
    int16_t *buf = heap_caps_malloc(n * sizeof(int16_t), MALLOC_CAP_SPIRAM);
    if (!buf) {
        printf("selftest: no memory\n");
        return 1;
    }
    n = orion_audio_mic_history(buf, n);
    size_t mid = n / 2;
    int32_t loud = rms_of(buf + mid - 4000, 8000);
    float frac = tone_fraction(buf + mid - 4000, 8000, SELFTEST_HZ);
    free(buf);
    bool pass = loud > quiet * 4 && frac > 0.5f;
    printf("selftest: mic rms quiet %d, during tone %d, %d%% of the energy at %d Hz: %s\n",
           (int) quiet, (int) loud, (int) (frac * 100), SELFTEST_HZ, pass ? "PASS" : "FAIL");
    return pass ? 0 : 1;
}

static int cmd_record(int argc, char **argv)
{
    int16_t *pcm = NULL;
    size_t samples = 0;
    printf("record: listening, speak then stop\n");
    int64_t t0 = esp_timer_get_time();
    esp_err_t err = orion_audio_record_utterance(&pcm, &samples, 10000);
    printf("record: %s, %u samples (%u ms) after %d ms\n", esp_err_to_name(err), (unsigned) samples,
           (unsigned) (samples / 16), (int) ((esp_timer_get_time() - t0) / 1000));
    if (err == ESP_OK) {
        orion_audio_play_pcm(pcm, samples, ORION_AUDIO_SAMPLE_RATE);
        free(pcm);
    }
    return err == ESP_OK ? 0 : 1;
}

esp_err_t orion_audio_register_cmds(void)
{
    const esp_console_cmd_t cmds[] = {
        { .command = "tone", .help = "tone [hz] [ms]: sine through the speaker", .func = cmd_tone },
        { .command = "wav", .help = "wav <name>: play /assets/<name>", .func = cmd_wav },
        { .command = "vol", .help = "vol [0..100]: software volume", .func = cmd_vol },
        { .command = "assets", .help = "list the assets partition", .func = cmd_assets },
        { .command = "mic", .help = "mic stats: floor, rms, level, counters", .func = cmd_mic },
        { .command = "micmon", .help = "micmon [sec]: rms every 250 ms", .func = cmd_micmon },
        { .command = "loopback", .help = "loopback [sec]: record then play it back", .func = cmd_loopback },
        { .command = "record", .help = "record one utterance with the silence detector, play it back", .func = cmd_record },
        { .command = "selftest", .help = "speaker to mic acoustic check with a 1 kHz tone", .func = cmd_selftest },
    };
    for (size_t i = 0; i < sizeof(cmds) / sizeof(cmds[0]); i++) {
        ESP_RETURN_ON_ERROR(esp_console_cmd_register(&cmds[i]), TAG, "register %s", cmds[i].command);
    }
    return audio_spk_register_cmd();
}
