// TFLite Micro wrapper for one streaming microWakeWord model. A port of
// StreamingModel from ESPHome's micro_wake_word component: same op list,
// same stride handling, same sliding window and cool-off logic.
#include "ww_priv.h"

#include <algorithm>
#include <cstring>
#include <new>
#include "esp_heap_caps.h"
#include "esp_log.h"
#include "esp_timer.h"
#include "tensorflow/lite/micro/micro_allocator.h"
#include "tensorflow/lite/micro/micro_interpreter.h"
#include "tensorflow/lite/micro/micro_mutable_op_resolver.h"
#include "tensorflow/lite/micro/micro_resource_variable.h"
#include "tensorflow/lite/schema/schema_generated.h"

static const char *TAG = "ww_model";

static const size_t VAR_ARENA_SIZE = 1024;
// The model needs this many slices after a load or a detection before its
// output means anything again.
static const int16_t MIN_SLICES_BEFORE_DETECTION = 100;

struct ww_model {
    tflite::MicroMutableOpResolver<20> resolver;
    tflite::MicroInterpreter *interp = nullptr;
    tflite::MicroAllocator *ma = nullptr;
    tflite::MicroResourceVariables *mrv = nullptr;
    uint8_t *arena = nullptr;
    size_t arena_size = 0;
    uint8_t *var_arena = nullptr;
    uint8_t *probs = nullptr;
    size_t window = 1;
    size_t last_n = 0;
    uint8_t stride = 1;
    uint8_t stride_step = 0;
    uint8_t cutoff = 255;
    int16_t ignore_windows = -MIN_SLICES_BEFORE_DETECTION;
    bool unprocessed = false;
};

static bool register_ops(tflite::MicroMutableOpResolver<20> &r)
{
    return r.AddCallOnce() == kTfLiteOk && r.AddVarHandle() == kTfLiteOk &&
           r.AddReshape() == kTfLiteOk && r.AddReadVariable() == kTfLiteOk &&
           r.AddStridedSlice() == kTfLiteOk && r.AddConcatenation() == kTfLiteOk &&
           r.AddAssignVariable() == kTfLiteOk && r.AddConv2D() == kTfLiteOk &&
           r.AddMul() == kTfLiteOk && r.AddAdd() == kTfLiteOk && r.AddMean() == kTfLiteOk &&
           r.AddFullyConnected() == kTfLiteOk && r.AddLogistic() == kTfLiteOk &&
           r.AddQuantize() == kTfLiteOk && r.AddDepthwiseConv2D() == kTfLiteOk &&
           r.AddAveragePool2D() == kTfLiteOk && r.AddMaxPool2D() == kTfLiteOk &&
           r.AddPad() == kTfLiteOk && r.AddPack() == kTfLiteOk && r.AddSplitV() == kTfLiteOk;
}

static void destroy(ww_model_t *m)
{
    delete m->interp;
    heap_caps_free(m->arena);
    heap_caps_free(m->var_arena);
    delete[] m->probs;
    delete m;
}

static uint8_t *alloc_arena(size_t size)
{
    // Internal RAM first: the arena is touched on every inference and PSRAM
    // roughly doubles the invoke time. Fall back to PSRAM if internal is gone.
    uint8_t *p = (uint8_t *) heap_caps_aligned_alloc(16, size, MALLOC_CAP_INTERNAL | MALLOC_CAP_8BIT);
    if (!p) {
        p = (uint8_t *) heap_caps_aligned_alloc(16, size, MALLOC_CAP_SPIRAM | MALLOC_CAP_8BIT);
        ESP_LOGW(TAG, "arena of %u bytes went to psram", (unsigned) size);
    }
    return p;
}

extern "C" ww_model_t *ww_model_create(const uint8_t *flatbuffer, size_t arena_size, uint8_t cutoff,
                                       size_t window)
{
    const tflite::Model *model = tflite::GetModel(flatbuffer);
    if (model->version() != TFLITE_SCHEMA_VERSION) {
        ESP_LOGE(TAG, "schema %u, want %d", (unsigned) model->version(), TFLITE_SCHEMA_VERSION);
        return nullptr;
    }
    ww_model_t *m = new (std::nothrow) ww_model();
    if (!m || !register_ops(m->resolver)) {
        ESP_LOGE(TAG, "op resolver");
        return nullptr;
    }

    m->var_arena = (uint8_t *) heap_caps_malloc(VAR_ARENA_SIZE, MALLOC_CAP_INTERNAL | MALLOC_CAP_8BIT);
    m->arena_size = (arena_size + 15) & ~(size_t) 15;
    m->arena = alloc_arena(m->arena_size);
    if (!m->var_arena || !m->arena) {
        ESP_LOGE(TAG, "arena %u: no memory", (unsigned) m->arena_size);
        destroy(m);
        return nullptr;
    }
    m->ma = tflite::MicroAllocator::Create(m->var_arena, VAR_ARENA_SIZE);
    m->mrv = tflite::MicroResourceVariables::Create(m->ma, 20);

    m->interp = new (std::nothrow) tflite::MicroInterpreter(model, m->resolver, m->arena, m->arena_size, m->mrv);
    if (!m->interp || m->interp->AllocateTensors() != kTfLiteOk) {
        ESP_LOGE(TAG, "AllocateTensors failed with a %u byte arena", (unsigned) m->arena_size);
        destroy(m);
        return nullptr;
    }

    TfLiteTensor *in = m->interp->input(0);
    TfLiteTensor *out = m->interp->output(0);
    if (in->dims->size != 3 || in->dims->data[0] != 1 || in->dims->data[2] != WW_FEATURES ||
        in->type != kTfLiteInt8) {
        ESP_LOGE(TAG, "input is not [1, stride, %d] int8", WW_FEATURES);
        destroy(m);
        return nullptr;
    }
    if (out->dims->size != 2 || out->dims->data[0] != 1 || out->dims->data[1] != 1 ||
        out->type != kTfLiteUInt8) {
        ESP_LOGE(TAG, "output is not [1, 1] uint8");
        destroy(m);
        return nullptr;
    }

    m->stride = (uint8_t) in->dims->data[1];
    m->cutoff = cutoff;
    m->window = window ? window : 1;
    m->probs = new (std::nothrow) uint8_t[m->window];
    if (!m->probs) {
        destroy(m);
        return nullptr;
    }
    ww_model_reset(m);
    ESP_LOGI(TAG, "loaded: stride %u, arena %u used of %u, cutoff %u, window %u",
             m->stride, (unsigned) m->interp->arena_used_bytes(), (unsigned) m->arena_size,
             m->cutoff, (unsigned) m->window);
    return m;
}

extern "C" bool ww_model_feed(ww_model_t *m, const int8_t *features, uint32_t *invoke_us)
{
    TfLiteTensor *in = m->interp->input(0);
    m->stride_step = m->stride_step % m->stride;
    std::memcpy(tflite::GetTensorData<int8_t>(in) + WW_FEATURES * m->stride_step, features, WW_FEATURES);
    m->stride_step++;

    bool ran = false;
    if (m->stride_step >= m->stride) {
        int64_t t0 = esp_timer_get_time();
        if (m->interp->Invoke() != kTfLiteOk) {
            ESP_LOGW(TAG, "invoke failed");
            return false;
        }
        *invoke_us = (uint32_t) (esp_timer_get_time() - t0);
        m->last_n++;
        if (m->last_n == m->window) {
            m->last_n = 0;
        }
        m->probs[m->last_n] = m->interp->output(0)->data.uint8[0];
        m->unprocessed = true;
        ran = true;
    }
    // Only slices below the cutoff count toward the cool-off, so a detection
    // that keeps ringing cannot fire twice.
    if (m->probs[m->last_n] < m->cutoff) {
        m->ignore_windows = std::min<int16_t>(m->ignore_windows + 1, 0);
    }
    return ran;
}

extern "C" bool ww_model_detected(ww_model_t *m, uint8_t *avg, uint8_t *max)
{
    if (!m->unprocessed) {
        return false;
    }
    m->unprocessed = false;
    if (m->ignore_windows < 0) {
        return false;
    }
    uint32_t sum = 0;
    uint8_t mx = 0;
    for (size_t i = 0; i < m->window; i++) {
        sum += m->probs[i];
        mx = std::max(mx, m->probs[i]);
    }
    *avg = (uint8_t) (sum / m->window);
    *max = mx;
    return sum > (uint32_t) m->cutoff * m->window;
}

extern "C" void ww_model_reset(ww_model_t *m)
{
    std::memset(m->probs, 0, m->window);
    m->ignore_windows = -MIN_SLICES_BEFORE_DETECTION;
}

extern "C" void ww_model_set_cutoff(ww_model_t *m, uint8_t cutoff)
{
    m->cutoff = cutoff;
}

extern "C" uint8_t ww_model_cutoff(ww_model_t *m)
{
    return m->cutoff;
}

extern "C" size_t ww_model_arena_used(ww_model_t *m)
{
    return m->interp->arena_used_bytes();
}

extern "C" int ww_model_stride(ww_model_t *m)
{
    return m->stride;
}
