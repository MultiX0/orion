// MP34DT05-A on I2S0 in PDM RX. One task reads 10 ms chunks, keeps the RMS
// and noise floor stats, and writes the chunk into the ring in audio_ring.c.
#include "orion_audio.h"

#include <math.h>
#include <string.h>
#include "audio_priv.h"
#include "board_pins.h"
#include "driver/i2s_pdm.h"
#include "esp_check.h"
#include "esp_log.h"
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"

static const char *TAG = "mic";

#define RING_SECONDS        4
#define CHUNK_SAMPLES       160    // 10 ms, the wake word feature step
#define SETTLE_CHUNKS       30     // PDM filter settling after start
#define FLOOR_CHUNKS        100    // one second of boot silence
#define UNMUTE_DROP_CHUNKS  10     // room tail after the speaker stops
#define FLOOR_MIN           20

static orion_mic_reader_t *s_default;
static i2s_chan_handle_t s_rx;
static volatile bool s_running;
static volatile bool s_muted;
static volatile bool s_hold_open;
static volatile int32_t s_rms;
static volatile int32_t s_floor = FLOOR_MIN;
static volatile float s_level;
static bool s_floor_done;
static uint32_t s_chunks;
static uint32_t s_muted_chunks;

static int32_t rms_of(const int16_t *s, size_t n)
{
    uint64_t acc = 0;
    for (size_t i = 0; i < n; i++) {
        acc += (int32_t) s[i] * s[i];
    }
    return n ? (int32_t) sqrt((double) acc / n) : 0;
}

// The PDM path sits at about -220 for minutes after boot while the real room
// noise is 13 rms, so without this every threshold measures the offset. One
// pole tracker, 16 ms time constant, about 10 Hz corner.
static void remove_dc(int16_t *s, size_t n)
{
    static int32_t dc_q8;
    for (size_t i = 0; i < n; i++) {
        dc_q8 += ((int32_t) s[i] * 256 - dc_q8) >> 8;
        int32_t v = s[i] - (dc_q8 >> 8);
        s[i] = (int16_t) (v < -32768 ? -32768 : (v > 32767 ? 32767 : v));
    }
}

static void update_stats(int32_t rms)
{
    s_rms = rms;
    if (s_floor_done) {
        // Falls fast, rises slowly, so speech does not drag the floor up.
        int32_t f = s_floor;
        f += rms < f ? (rms - f) / 8 : (rms - f) / 512;
        s_floor = f < FLOOR_MIN ? FLOOR_MIN : f;
    }
    float db = 20.0f * log10f((float) (rms + 1) / (float) s_floor);
    float target = db / 30.0f;
    target = target < 0 ? 0 : (target > 1 ? 1 : target);
    s_level += (target > s_level ? 0.5f : 0.1f) * (target - s_level);
}

static void finish_floor(int32_t *hist, int count)
{
    for (int i = 1; i < count; i++) {
        int32_t v = hist[i];
        int j = i - 1;
        while (j >= 0 && hist[j] > v) {
            hist[j + 1] = hist[j];
            j--;
        }
        hist[j + 1] = v;
    }
    int32_t median = hist[count / 2];
    s_floor = median < FLOOR_MIN ? FLOOR_MIN : median;
    s_floor_done = true;
    ESP_LOGI(TAG, "noise floor at boot: rms median %d, min %d, max %d over %d chunks",
             (int) median, (int) hist[0], (int) hist[count - 1], count);
}

static void mic_task(void *arg)
{
    int16_t chunk[CHUNK_SAMPLES];
    int32_t hist[FLOOR_CHUNKS];
    int nhist = 0;
    int skip = SETTLE_CHUNKS;
    int drop = 0;

    while (s_running) {
        size_t got = 0;
        if (i2s_channel_read(s_rx, chunk, sizeof(chunk), &got, 1000) != ESP_OK || got == 0) {
            continue;
        }
        size_t n = got / sizeof(int16_t);
        s_chunks++;
        remove_dc(chunk, n);

        if (s_muted) {
            s_muted_chunks++;
            drop = UNMUTE_DROP_CHUNKS;
            continue;
        }
        if (drop > 0) {
            drop--;
            continue;
        }
        if (skip > 0) {
            skip--;
            continue;
        }

        int32_t rms = rms_of(chunk, n);
        // The self test holds the mic open through its own tone. Let into the
        // floor history, it puts the boot floor at 1121 instead of 200.
        if (!s_hold_open && !s_floor_done && nhist < FLOOR_CHUNKS) {
            hist[nhist++] = rms;
            if (nhist == FLOOR_CHUNKS) {
                finish_floor(hist, nhist);
            }
        }
        update_stats(rms);
        audio_ring_write(chunk, n);
    }
    vTaskDelete(NULL);
}

size_t orion_audio_mic_read(int16_t *dst, size_t max_samples, uint32_t wait_ms)
{
    return orion_audio_mic_reader_read(s_default, dst, max_samples, wait_ms);
}

float orion_audio_level(void)
{
    return s_level;
}

int32_t orion_audio_mic_rms(void)
{
    return s_rms;
}

int32_t orion_audio_noise_floor(void)
{
    return s_floor;
}

void audio_mic_set_muted(bool muted)
{
    if (!s_hold_open) {
        s_muted = muted;
    }
}

void audio_mic_hold_open(bool hold)
{
    s_hold_open = hold;
    if (hold) {
        s_muted = false;
    }
}

void audio_mic_stats(uint32_t *chunks, uint32_t *muted_chunks, uint32_t *dropped)
{
    *chunks = s_chunks;
    *muted_chunks = s_muted_chunks;
    *dropped = audio_ring_dropped();
}

esp_err_t orion_audio_mic_start(void)
{
    if (s_running) {
        return ESP_OK;
    }
    ESP_RETURN_ON_ERROR(i2s_channel_enable(s_rx), TAG, "enable");
    s_running = true;
    if (xTaskCreatePinnedToCore(mic_task, "mic", 4096, NULL, 10, NULL, 1) != pdPASS) {
        s_running = false;
        i2s_channel_disable(s_rx);
        return ESP_ERR_NO_MEM;
    }
    if (!s_default) {
        s_default = orion_audio_mic_reader_open();
    }
    return ESP_OK;
}

esp_err_t orion_audio_mic_stop(void)
{
    if (!s_running) {
        return ESP_OK;
    }
    s_running = false;
    esp_err_t err = i2s_channel_disable(s_rx);
    vTaskDelay(pdMS_TO_TICKS(30));
    return err;
}

esp_err_t audio_mic_init(void)
{
    ESP_RETURN_ON_ERROR(audio_ring_init(ORION_AUDIO_SAMPLE_RATE * RING_SECONDS), TAG, "ring");

    i2s_chan_config_t cc = I2S_CHANNEL_DEFAULT_CONFIG(BOARD_MIC_I2S_PORT, I2S_ROLE_MASTER);
    cc.dma_desc_num = 8;
    cc.dma_frame_num = 320;   // 160 ms of slack before a starved mic task loses audio
    ESP_RETURN_ON_ERROR(i2s_new_channel(&cc, NULL, &s_rx), TAG, "channel");

    i2s_pdm_rx_config_t cfg = {
        .clk_cfg = I2S_PDM_RX_CLK_DEFAULT_CONFIG(ORION_AUDIO_SAMPLE_RATE),
        .slot_cfg = I2S_PDM_RX_SLOT_DEFAULT_CONFIG(I2S_DATA_BIT_WIDTH_16BIT, I2S_SLOT_MODE_MONO),
        .gpio_cfg = {
            .clk = BOARD_MIC_CLK,
            .din = BOARD_MIC_DATA,
        },
    };
    // 16 kHz times 128 is a 2.048 MHz PDM clock, inside the MP34DT05's normal
    // range. The 8x mode would clock it at 1.024 MHz, below its 1.2 MHz minimum.
    cfg.clk_cfg.dn_sample_mode = I2S_PDM_DSR_16S;
    ESP_RETURN_ON_ERROR(i2s_channel_init_pdm_rx_mode(s_rx, &cfg), TAG, "pdm rx");

    ESP_LOGI(TAG, "i2s%d pdm rx clk %d data %d, %d Hz, ring %d s in psram",
             BOARD_MIC_I2S_PORT, BOARD_MIC_CLK, BOARD_MIC_DATA, ORION_AUDIO_SAMPLE_RATE, RING_SECONDS);
    return orion_audio_mic_start();
}
