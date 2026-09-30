#include "orion_audio.h"

#include "audio_priv.h"
#include "esp_check.h"
#include "esp_log.h"

static const char *TAG = "audio";

esp_err_t orion_audio_init(void)
{
    // Speaker first: it starts the I2S clock and then turns the shared enable
    // line on. The mic sits behind the same line, so it comes second.
    ESP_RETURN_ON_ERROR(audio_spk_init(), TAG, "speaker");
    ESP_RETURN_ON_ERROR(audio_mic_init(), TAG, "mic");
    return ESP_OK;
}
