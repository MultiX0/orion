// LVGL's allocator, pointed at PSRAM. With the C library allocator every
// object and style under 4 KB still landed in internal RAM, because of
// CONFIG_SPIRAM_MALLOC_ALWAYSINTERNAL, and internal RAM is what the full
// firmware runs out of. The display draw buffers are not affected:
// esp_lvgl_port allocates those itself, in internal DMA memory, as it must.
#include "lvgl.h"

#if LV_USE_STDLIB_MALLOC == LV_STDLIB_CUSTOM

#include <stdlib.h>
#include "esp_heap_caps.h"

#define UI_MEM_CAPS (MALLOC_CAP_SPIRAM | MALLOC_CAP_8BIT)

void lv_mem_init(void)
{
}

void lv_mem_deinit(void)
{
}

lv_mem_pool_t lv_mem_add_pool(void *mem, size_t bytes)
{
    LV_UNUSED(mem);
    LV_UNUSED(bytes);
    return NULL;
}

void lv_mem_remove_pool(lv_mem_pool_t pool)
{
    LV_UNUSED(pool);
}

// Falls back to the default heap only if PSRAM is full, so a leak shows up as
// a slow internal RAM drain rather than a crash.
void *lv_malloc_core(size_t size)
{
    void *p = heap_caps_malloc(size, UI_MEM_CAPS);
    return p ? p : malloc(size);
}

void *lv_realloc_core(void *p, size_t new_size)
{
    void *q = heap_caps_realloc(p, new_size, UI_MEM_CAPS);
    return q ? q : realloc(p, new_size);
}

void lv_free_core(void *p)
{
    free(p);
}

void lv_mem_monitor_core(lv_mem_monitor_t *mon_p)
{
    LV_UNUSED(mon_p);
}

lv_result_t lv_mem_test_core(void)
{
    return LV_RESULT_OK;
}

#endif
