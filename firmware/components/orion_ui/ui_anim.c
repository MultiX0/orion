// Every animation on the screen goes through here so the brand curves and
// durations are the only ones in use. Nothing bounces, nothing overshoots.
#include "ui_internal.h"

static void set_ease(lv_anim_t *a, bool brand)
{
    lv_anim_set_path_cb(a, lv_anim_path_custom_bezier3);
    if (brand) {
        lv_anim_set_bezier3_param(a, UI_EASE_BRAND);
    } else {
        lv_anim_set_bezier3_param(a, UI_EASE_UI);
    }
}

void ui_anim_to(void *var, lv_anim_exec_xcb_t exec, int32_t from, int32_t to,
                uint32_t ms, uint32_t delay, bool brand_ease, lv_anim_completed_cb_t done)
{
    lv_anim_t a;
    lv_anim_init(&a);
    lv_anim_set_var(&a, var);
    lv_anim_set_exec_cb(&a, exec);
    lv_anim_set_values(&a, from, to);
    lv_anim_set_duration(&a, ms);
    lv_anim_set_delay(&a, delay);
    lv_anim_set_completed_cb(&a, done);
    set_ease(&a, brand_ease);
    lv_anim_start(&a);
}

// Breathing and pulsing: a to b and back, forever, eased both ways.
void ui_anim_loop(void *var, lv_anim_exec_xcb_t exec, int32_t a_val, int32_t b_val, uint32_t half_ms)
{
    lv_anim_t a;
    lv_anim_init(&a);
    lv_anim_set_var(&a, var);
    lv_anim_set_exec_cb(&a, exec);
    lv_anim_set_values(&a, a_val, b_val);
    lv_anim_set_duration(&a, half_ms);
    lv_anim_set_playback_duration(&a, half_ms);
    lv_anim_set_repeat_count(&a, LV_ANIM_REPEAT_INFINITE);
    lv_anim_set_path_cb(&a, lv_anim_path_ease_in_out);
    lv_anim_start(&a);
}

// exec NULL stops every animation on that variable.
void ui_anim_stop(void *var, lv_anim_exec_xcb_t exec)
{
    lv_anim_delete(var, exec);
}

// Continuous rotation: linear, no playback, forever. The only place the brand
// allows linear easing.
void ui_anim_spin(void *var, lv_anim_exec_xcb_t exec, int32_t a_val, int32_t b_val, uint32_t ms)
{
    lv_anim_t a;
    lv_anim_init(&a);
    lv_anim_set_var(&a, var);
    lv_anim_set_exec_cb(&a, exec);
    lv_anim_set_values(&a, a_val, b_val);
    lv_anim_set_duration(&a, ms);
    lv_anim_set_repeat_count(&a, LV_ANIM_REPEAT_INFINITE);
    lv_anim_set_path_cb(&a, lv_anim_path_linear);
    lv_anim_start(&a);
}

static void exec_opa(void *obj, int32_t v)
{
    lv_obj_set_style_opa(obj, (lv_opa_t) v, 0);
}

static void exec_y(void *obj, int32_t v)
{
    lv_obj_set_style_translate_y(obj, v, 0);
}

void ui_fade(lv_obj_t *obj, lv_opa_t to, uint32_t ms, uint32_t delay, lv_anim_completed_cb_t done)
{
    lv_anim_delete(obj, exec_opa);
    ui_anim_to(obj, exec_opa, lv_obj_get_style_opa(obj, 0), to, ms, delay, false, done);
}

// The brand's fadeInUp keyframe: 18 px on the web, 8 px on a 240 px screen.
void ui_rise_in(lv_obj_t *obj, uint32_t delay)
{
    lv_anim_delete(obj, exec_opa);
    lv_anim_delete(obj, exec_y);
    lv_obj_set_style_opa(obj, LV_OPA_TRANSP, 0);
    lv_obj_set_style_translate_y(obj, UI_SPACE_2, 0);
    ui_anim_to(obj, exec_opa, LV_OPA_TRANSP, LV_OPA_COVER, UI_DUR_KEYFRAME, delay, false, NULL);
    ui_anim_to(obj, exec_y, UI_SPACE_2, 0, UI_DUR_KEYFRAME, delay, false, NULL);
}
