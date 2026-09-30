// The model partition holds one image written by tools/pack_model.py:
//   0   "ORWW"
//   4   u32 format version (1)
//   8   u32 json length
//   12  u32 model length
//   16  u32 model offset from the start of the image, 16 aligned
//   32  json manifest, then the .tflite at the model offset
#include "ww_priv.h"

#include <string.h>
#include "cJSON.h"
#include "esp_check.h"
#include "esp_log.h"
#include "esp_partition.h"

static const char *TAG = "ww_manifest";

#define HEADER_LEN 32

static uint32_t le32(const uint8_t *p)
{
    return p[0] | (p[1] << 8) | (p[2] << 16) | ((uint32_t) p[3] << 24);
}

static esp_err_t parse(const char *json, size_t len, ww_manifest_t *mf)
{
    cJSON *root = cJSON_ParseWithLength(json, len);
    ESP_RETURN_ON_FALSE(root, ESP_ERR_INVALID_ARG, TAG, "manifest is not json");

    memset(mf, 0, sizeof(*mf));
    const cJSON *word = cJSON_GetObjectItem(root, "wake_word");
    if (cJSON_IsString(word)) {
        strlcpy(mf->wake_word, word->valuestring, sizeof(mf->wake_word));
    }
    const cJSON *version = cJSON_GetObjectItem(root, "version");
    mf->version = cJSON_IsNumber(version) ? version->valueint : 0;

    const cJSON *micro = cJSON_GetObjectItem(root, "micro");
    esp_err_t err = ESP_OK;
    if (cJSON_IsObject(micro)) {
        const cJSON *cutoff = cJSON_GetObjectItem(micro, "probability_cutoff");
        const cJSON *step = cJSON_GetObjectItem(micro, "feature_step_size");
        const cJSON *window = cJSON_GetObjectItem(micro, "sliding_window_size");
        const cJSON *arena = cJSON_GetObjectItem(micro, "tensor_arena_size");
        mf->probability_cutoff = cJSON_IsNumber(cutoff) ? (float) cutoff->valuedouble : 0;
        mf->feature_step_size = cJSON_IsNumber(step) ? step->valueint : 0;
        mf->sliding_window_size = cJSON_IsNumber(window) ? window->valueint : 0;
        mf->tensor_arena_size = cJSON_IsNumber(arena) ? arena->valueint : 0;
    } else {
        err = ESP_ERR_NOT_FOUND;
    }
    cJSON_Delete(root);
    ESP_RETURN_ON_ERROR(err, TAG, "manifest has no micro section");

    ESP_RETURN_ON_FALSE(mf->probability_cutoff > 0 && mf->probability_cutoff <= 1.0f, ESP_ERR_INVALID_ARG,
                        TAG, "bad probability_cutoff");
    ESP_RETURN_ON_FALSE(mf->feature_step_size > 0 && mf->feature_step_size <= 30, ESP_ERR_INVALID_ARG,
                        TAG, "bad feature_step_size");
    ESP_RETURN_ON_FALSE(mf->sliding_window_size > 0 && mf->sliding_window_size <= 64, ESP_ERR_INVALID_ARG,
                        TAG, "bad sliding_window_size");
    ESP_RETURN_ON_FALSE(mf->tensor_arena_size > 0, ESP_ERR_INVALID_ARG, TAG, "bad tensor_arena_size");
    return ESP_OK;
}

esp_err_t ww_partition_map(const uint8_t **model, size_t *model_len, ww_manifest_t *mf)
{
    const esp_partition_t *part = esp_partition_find_first(ESP_PARTITION_TYPE_DATA,
                                                           ESP_PARTITION_SUBTYPE_ANY, "model");
    ESP_RETURN_ON_FALSE(part, ESP_ERR_NOT_FOUND, TAG, "no model partition");

    const void *base = NULL;
    esp_partition_mmap_handle_t handle;
    ESP_RETURN_ON_ERROR(esp_partition_mmap(part, 0, part->size, ESP_PARTITION_MMAP_DATA, &base, &handle),
                        TAG, "mmap");

    const uint8_t *img = base;
    ESP_RETURN_ON_FALSE(!memcmp(img, "ORWW", 4), ESP_ERR_NOT_FOUND, TAG,
                        "model partition is empty or not packed by pack_model.py");
    uint32_t format = le32(img + 4);
    uint32_t json_len = le32(img + 8);
    uint32_t mlen = le32(img + 12);
    uint32_t moff = le32(img + 16);
    ESP_RETURN_ON_FALSE(format == 1, ESP_ERR_INVALID_VERSION, TAG, "image format %u", (unsigned) format);
    ESP_RETURN_ON_FALSE(HEADER_LEN + json_len < moff && moff + mlen <= part->size, ESP_ERR_INVALID_SIZE, TAG,
                        "image does not fit: json %u model %u at %u", (unsigned) json_len, (unsigned) mlen,
                        (unsigned) moff);

    ESP_RETURN_ON_ERROR(parse((const char *) img + HEADER_LEN, json_len, mf), TAG, "manifest");
    *model = img + moff;
    *model_len = mlen;
    ESP_LOGI(TAG, "\"%s\" v%d: %u byte model, cutoff %.2f, step %d ms, window %d, arena %d",
             mf->wake_word, mf->version, (unsigned) mlen, mf->probability_cutoff, mf->feature_step_size,
             mf->sliding_window_size, mf->tensor_arena_size);
    return ESP_OK;
}
