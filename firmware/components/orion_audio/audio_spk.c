// MAX98357A on I2S1, standard Philips, 16-bit, the mono sample sent to BOTH
// slots. The amp is strapped to (L+R)/2, so leaving the right slot empty, which
// is what the IDF mono default does, throws away 6 dB before anything plays.
// The DMA auto-clears, so once the channel is enabled BCLK runs forever and
// the amp only ever sees silence or a faded stream. That is the whole anti-pop
// strategy: no clock edges, no DC steps.
#include "orion_audio.h"

#include <math.h>
#include <string.h>
#include "audio_priv.h"
#include "board.h"
#include "board_pins.h"
#include "driver/i2s_std.h"
#include "esp_check.h"
#include "esp_heap_caps.h"
#include "esp_log.h"
#include "freertos/FreeRTOS.h"
#include "freertos/semphr.h"
#include "freertos/task.h"

static const char *TAG = "spk";

#define DMA_DESC_NUM   8
#define DMA_FRAME_NUM  480     // 15 ms per descriptor at 32 kHz, 120 ms in all
#define FADE_SAMPLES   160     // 5 ms ramp at 32 kHz, 10 ms at 16 kHz
#define CHUNK          256
#define TONE_AMPLITUDE 12000

static i2s_chan_handle_t s_tx;
static SemaphoreHandle_t s_lock;
static uint32_t s_rate = ORION_AUDIO_SAMPLE_RATE;   // the stream's rate
static uint32_t s_clock = ORION_AUDIO_SAMPLE_RATE;  // what the amp is clocked at
// The MAX98357A cannot lock to 11.025, 12, 22.05 or 24 kHz. Those streams
// play at twice the rate, each sample followed by its midpoint to the next.
static uint8_t s_up = 1;
static int16_t s_up_prev;
static uint8_t s_volume = 100;
static bool s_both_slots = true;
static volatile bool s_playing;
static uint32_t s_written;
static int16_t s_last;

// Square law: 50 percent is about -12 dB, which is what a volume knob feels
// like. 100 is unity, nothing is thrown away at the top.
static float volume_gain(void)
{
    return (s_volume / 100.0f) * (s_volume / 100.0f);
}

// The level for now only. The saved volume belongs to orion_config (an i32
// under "volume", applied by main at boot), so a test's "vol 0" never
// replaces the level the user chose.
void orion_audio_set_volume(uint8_t percent)
{
    s_volume = percent > 100 ? 100 : percent;
}

uint8_t orion_audio_get_volume(void)
{
    return s_volume;
}

void orion_audio_set_boost(bool on)
{
    audio_dsp_set_enabled(on);
}

bool orion_audio_boost(void)
{
    return audio_dsp_enabled();
}

bool orion_audio_is_playing(void)
{
    return s_playing;
}

// Silent: the whole pipeline runs at the real volume but the amp gets zeros,
// so the voice can be checked without a sound in the room. Capture: every
// sample the amp would get, kept in PSRAM for `spk dump`.
static bool s_silent;
#define CAP_SAMPLES (30 * 32000)
static int16_t *s_cap;
static size_t s_cap_n;
static bool s_capture;

static esp_err_t write_raw(const int16_t *pcm, size_t samples)
{
    if (s_capture && s_cap) {
        const size_t room = (size_t) CAP_SAMPLES - s_cap_n;
        const size_t take = samples < room ? samples : room;
        memcpy(s_cap + s_cap_n, pcm, take * sizeof(int16_t));
        s_cap_n += take;
    }
    size_t written = 0;
    if (s_silent) {
        static const int16_t zeros[CHUNK];
        size_t left = samples * s_up;
        while (left) {
            const size_t take = left < CHUNK ? left : CHUNK;
            ESP_RETURN_ON_ERROR(i2s_channel_write(s_tx, zeros, take * sizeof(int16_t), &written,
                                                  portMAX_DELAY), TAG, "write");
            left -= take;
        }
        return ESP_OK;
    }
    if (s_up == 1) {
        return i2s_channel_write(s_tx, pcm, samples * sizeof(int16_t), &written, portMAX_DELAY);
    }
    int16_t up[CHUNK];
    while (samples) {
        const size_t take = samples < CHUNK / 2 ? samples : CHUNK / 2;
        for (size_t i = 0; i < take; i++) {
            up[2 * i] = (int16_t) (((int32_t) s_up_prev + pcm[i]) / 2);
            up[2 * i + 1] = pcm[i];
            s_up_prev = pcm[i];
        }
        ESP_RETURN_ON_ERROR(i2s_channel_write(s_tx, up, take * 2 * sizeof(int16_t), &written,
                                              portMAX_DELAY), TAG, "write");
        pcm += take;
        samples -= take;
    }
    return ESP_OK;
}

void audio_spk_set_silent(bool on)
{
    s_silent = on;
}

bool audio_spk_silent(void)
{
    return s_silent;
}

esp_err_t audio_spk_set_capture(bool on)
{
    if (on && !s_cap) {
        s_cap = heap_caps_malloc((size_t) CAP_SAMPLES * sizeof(int16_t), MALLOC_CAP_SPIRAM);
        if (!s_cap) {
            return ESP_ERR_NO_MEM;
        }
    }
    s_capture = on;
    s_cap_n = 0;
    return ESP_OK;
}

// The last stream as captured, in base64 lines behind a marker, for
// tools/audio/voice_check.py. Everything else on the console passes by.
void audio_spk_dump(void)
{
    static const char b64[] = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
    printf("SPKDUMP BEGIN rate=%u samples=%u\n", (unsigned) s_rate, (unsigned) s_cap_n);
    const uint8_t *p = (const uint8_t *) s_cap;
    const size_t bytes = s_cap ? s_cap_n * sizeof(int16_t) : 0;
    char line[16 + 4 * 256 + 2];
    // Numbered and paced: the USB console drops what the host does not read
    // in time, and an unnumbered lost line would shift everything after it.
    for (size_t at = 0, n = 0; at < bytes; n++) {
        size_t w = 0;
        w += (size_t) snprintf(line, 16, "@%x,", (unsigned) n);
        for (int g = 0; g < 256 && at < bytes; g++) {
            const size_t left = bytes - at;
            const uint32_t v = (uint32_t) p[at] << 16 | (left > 1 ? (uint32_t) p[at + 1] << 8 : 0) |
                               (left > 2 ? p[at + 2] : 0);
            line[w++] = b64[(v >> 18) & 63];
            line[w++] = b64[(v >> 12) & 63];
            line[w++] = left > 1 ? b64[(v >> 6) & 63] : '=';
            line[w++] = left > 2 ? b64[v & 63] : '=';
            at += left > 2 ? 3 : left;
        }
        line[w++] = '\n';
        line[w] = '\0';
        fputs(line, stdout);
        fflush(stdout);
        vTaskDelay(1);
    }
    printf("SPKDUMP END\n");
    fflush(stdout);
}

static esp_err_t set_rate(uint32_t rate)
{
    const bool odd = rate == 11025 || rate == 12000 || rate == 22050 || rate == 24000;
    const uint32_t clock = odd ? rate * 2 : rate;
    s_rate = rate;
    s_up = odd ? 2 : 1;
    s_up_prev = 0;
    if (clock == s_clock) {
        return ESP_OK;
    }
    // The only place the clock stops: earcons are 16 kHz, speech 32 kHz.
    ESP_RETURN_ON_ERROR(i2s_channel_disable(s_tx), TAG, "disable");
    i2s_std_clk_config_t clk = I2S_STD_CLK_DEFAULT_CONFIG(clock);
    ESP_RETURN_ON_ERROR(i2s_channel_reconfig_std_clock(s_tx, &clk), TAG, "clock %u", (unsigned) clock);
    ESP_RETURN_ON_ERROR(i2s_channel_enable(s_tx), TAG, "enable");
    s_clock = clock;
    return ESP_OK;
}

esp_err_t audio_spk_set_both_slots(bool both)
{
    if (both == s_both_slots) {
        return ESP_OK;
    }
    ESP_RETURN_ON_ERROR(i2s_channel_disable(s_tx), TAG, "disable");
    i2s_std_slot_config_t slot = I2S_STD_PHILIPS_SLOT_DEFAULT_CONFIG(I2S_DATA_BIT_WIDTH_16BIT, I2S_SLOT_MODE_MONO);
    slot.slot_mask = both ? I2S_STD_SLOT_BOTH : I2S_STD_SLOT_LEFT;
    ESP_RETURN_ON_ERROR(i2s_channel_reconfig_std_slot(s_tx, &slot), TAG, "slot");
    ESP_RETURN_ON_ERROR(i2s_channel_enable(s_tx), TAG, "enable");
    s_both_slots = both;
    return ESP_OK;
}

bool audio_spk_both_slots(void)
{
    return s_both_slots;
}

esp_err_t orion_audio_play_begin(uint32_t sample_rate)
{
    if (!s_tx) {
        return ESP_ERR_INVALID_STATE;
    }
    if (xSemaphoreTake(s_lock, pdMS_TO_TICKS(5000)) != pdTRUE) {
        return ESP_ERR_TIMEOUT;
    }
    audio_mic_set_muted(true);
    esp_err_t err = set_rate(sample_rate ? sample_rate : ORION_AUDIO_SAMPLE_RATE);
    if (err != ESP_OK) {
        audio_mic_set_muted(false);
        xSemaphoreGive(s_lock);
        return err;
    }
    audio_dsp_begin(s_rate, volume_gain());
    if (s_capture) {
        s_cap_n = 0;    // one stream per capture: the latest reply
    }
    s_written = 0;
    s_last = 0;
    s_playing = true;
    return ESP_OK;
}

// Pipeline, then the fade in over the first FADE_SAMPLES that reach the DMA.
static esp_err_t push(const int16_t *in, size_t n)
{
    int16_t buf[CHUNK];
    while (n > 0) {
        size_t take = n < CHUNK ? n : CHUNK;
        audio_dsp_process(in, buf, take);
        for (size_t i = 0; i < take && s_written < FADE_SAMPLES; i++, s_written++) {
            buf[i] = (int16_t) ((int32_t) buf[i] * (int32_t) s_written / FADE_SAMPLES);
        }
        s_last = buf[take - 1];
        ESP_RETURN_ON_ERROR(write_raw(buf, take), TAG, "write");
        in += take;
        n -= take;
    }
    return ESP_OK;
}

static volatile float s_out_level;

// Measured as the chunk is queued, so it leads the sound by the DMA depth,
// a few tens of ms, which the eye does not catch.
static void track_out_level(const int16_t *s, size_t n)
{
    int64_t acc = 0;
    for (size_t i = 0; i < n; i++) {
        acc += (int32_t) s[i] * s[i];
    }
    float rms = n ? sqrtf((float) acc / (float) n) : 0.0f;
    float target = (20.0f * log10f(rms / 32768.0f + 1e-6f) + 50.0f) / 50.0f;
    target = target < 0.0f ? 0.0f : (target > 1.0f ? 1.0f : target);
    s_out_level += (target - s_out_level) * (target > s_out_level ? 0.6f : 0.2f);
}

float orion_audio_out_level(void)
{
    return s_playing ? s_out_level : 0.0f;
}

// The stream paused (the network fell behind): the limiter's look-ahead is
// drained, the wave goes down to zero over FADE_SAMPLES, and the next write
// fades back in. The DMA then plays silence, not a step from mid-wave to
// zero, which clicks.
static esp_err_t pause_fade(void)
{
    if (s_written == 0) {
        return ESP_OK;    // already paused, or nothing played yet
    }
    static const int16_t zeros[160] = { 0 };   // the longest look-ahead
    push(zeros, audio_dsp_latency());
    int16_t ramp[FADE_SAMPLES];
    for (int i = 0; i < FADE_SAMPLES; i++) {
        ramp[i] = (int16_t) ((int32_t) s_last * (FADE_SAMPLES - 1 - i) / FADE_SAMPLES);
    }
    esp_err_t err = write_raw(ramp, FADE_SAMPLES);
    s_last = 0;
    s_written = 0;
    return err;
}

esp_err_t orion_audio_play_write(const void *pcm, size_t bytes)
{
    if (!s_playing) {
        return ESP_ERR_INVALID_STATE;
    }
    if (bytes == 0) {
        return pause_fade();
    }
    track_out_level((const int16_t *) pcm, bytes / sizeof(int16_t));
    return push(pcm, bytes / sizeof(int16_t));
}

esp_err_t orion_audio_play_end(void)
{
    if (!s_playing) {
        return ESP_ERR_INVALID_STATE;
    }
    // Drain the limiter's look-ahead so the last 2 ms of audio come out.
    static const int16_t zeros[160] = { 0 };   // the longest look-ahead
    push(zeros, audio_dsp_latency());

    int16_t ramp[FADE_SAMPLES];
    for (int i = 0; i < FADE_SAMPLES; i++) {
        ramp[i] = (int16_t) ((int32_t) s_last * (FADE_SAMPLES - 1 - i) / FADE_SAMPLES);
    }
    write_raw(ramp, FADE_SAMPLES);

    // i2s_channel_write returns once the data is queued, not once it has left
    // the pin. Wait out the DMA depth so the caller knows the sound is over.
    vTaskDelay(pdMS_TO_TICKS(DMA_DESC_NUM * DMA_FRAME_NUM * 1000 / s_clock + 20));

    // One line per stream, so a quiet stretch can be told apart from the guard.
    audio_dsp_stats_t st;
    audio_dsp_get_stats(&st);
    if (st.samples > s_rate) {
        ESP_LOGI(TAG, "played %.1f s, out %.1f dBFS rms, guard min %.1f dB, %u samples tripped",
                 (float) st.samples / s_rate,
                 10.0f * log10f(st.out_sq / st.samples + 1e-12f), st.min_guard_db,
                 (unsigned) st.guard_trips);
    }

    s_playing = false;
    audio_mic_set_muted(false);
    xSemaphoreGive(s_lock);
    return ESP_OK;
}

esp_err_t orion_audio_play_pcm(const int16_t *pcm, size_t samples, uint32_t sample_rate)
{
    ESP_RETURN_ON_ERROR(orion_audio_play_begin(sample_rate), TAG, "begin");
    esp_err_t err = orion_audio_play_write(pcm, samples * sizeof(int16_t));
    orion_audio_play_end();
    return err;
}

esp_err_t orion_audio_play_tone(uint32_t hz, uint32_t ms)
{
    ESP_RETURN_ON_ERROR(orion_audio_play_begin(ORION_AUDIO_SAMPLE_RATE), TAG, "begin");

    int16_t buf[CHUNK];
    uint32_t total = ms * ORION_AUDIO_SAMPLE_RATE / 1000;
    float phase = 0.0f;
    float step = 2.0f * (float) M_PI * (float) hz / ORION_AUDIO_SAMPLE_RATE;
    esp_err_t err = ESP_OK;

    for (uint32_t done = 0; done < total && err == ESP_OK; ) {
        size_t n = total - done < CHUNK ? total - done : CHUNK;
        for (size_t i = 0; i < n; i++) {
            buf[i] = (int16_t) (sinf(phase) * TONE_AMPLITUDE);
            phase += step;
            if (phase > 2.0f * (float) M_PI) {
                phase -= 2.0f * (float) M_PI;
            }
        }
        err = orion_audio_play_write(buf, n * sizeof(int16_t));
        done += n;
    }
    orion_audio_play_end();
    return err;
}

esp_err_t audio_spk_init(void)
{
    s_lock = xSemaphoreCreateMutex();
    ESP_RETURN_ON_FALSE(s_lock, ESP_ERR_NO_MEM, TAG, "lock");

    i2s_chan_config_t cc = I2S_CHANNEL_DEFAULT_CONFIG(BOARD_SPK_I2S_PORT, I2S_ROLE_MASTER);
    cc.dma_desc_num = DMA_DESC_NUM;
    cc.dma_frame_num = DMA_FRAME_NUM;
    cc.auto_clear_after_cb = true;
    ESP_RETURN_ON_ERROR(i2s_new_channel(&cc, &s_tx, NULL), TAG, "channel");

    i2s_std_config_t std = {
        .clk_cfg = I2S_STD_CLK_DEFAULT_CONFIG(ORION_AUDIO_SAMPLE_RATE),
        .slot_cfg = I2S_STD_PHILIPS_SLOT_DEFAULT_CONFIG(I2S_DATA_BIT_WIDTH_16BIT, I2S_SLOT_MODE_MONO),
        .gpio_cfg = {
            .mclk = I2S_GPIO_UNUSED,
            .bclk = BOARD_SPK_BCLK,
            .ws = BOARD_SPK_LRCLK,
            .dout = BOARD_SPK_DOUT,
            .din = I2S_GPIO_UNUSED,
        },
    };
    std.slot_cfg.slot_mask = I2S_STD_SLOT_BOTH;
    ESP_RETURN_ON_ERROR(i2s_channel_init_std_mode(s_tx, &std), TAG, "std mode");
    ESP_RETURN_ON_ERROR(i2s_channel_enable(s_tx), TAG, "enable");

    // Clock is running and the DMA is sending zeros. Now wake the amp.
    vTaskDelay(pdMS_TO_TICKS(30));
    ESP_RETURN_ON_ERROR(board_audio_enable(true), TAG, "audio enable");

    ESP_LOGI(TAG, "i2s%d tx bclk %d ws %d dout %d, %u Hz, both slots, volume %u, boost %s",
             BOARD_SPK_I2S_PORT, BOARD_SPK_BCLK, BOARD_SPK_LRCLK, BOARD_SPK_DOUT,
             (unsigned) s_rate, s_volume, audio_dsp_enabled() ? "on" : "off");
    return ESP_OK;
}
