// The star: the Orion mark at the centre of listening, thinking and speaking,
// with echo rings around it. Listening and speaking ripple outward with the
// voice, the user's or Orion's own; thinking has no audio, so the star turns
// slowly inside two still rings that shimmer. Everything is computed in one
// tick and eased, so a change of state bends the motion instead of cutting it.
#include "ui_internal.h"

#include <math.h>

#include "esp_timer.h"

#define STAR   56
#define RINGS  3
#define R_MIN  22   // rings are born just inside the star's arms
#define TICK_MS 16

typedef struct {
    float r, opa, phase;
} ring_t;

static lv_obj_t *s_star, *s_ring[RINGS];
static ring_t s_rg[RINGS];
static orion_state_t s_state = OS_BOOT;
static lv_timer_t *s_timer;
static float s_level_target, s_level;
static float s_fade, s_fade_to;     // 0..1 crossfade with the orb and the idle mark
static float s_angle, s_scale = 1;  // degrees, and 1.0 is the native 56 px
static int64_t s_last_us, s_changed_us;

static bool owns(orion_state_t st)
{
    return st == OS_LISTENING || st == OS_THINKING || st == OS_SPEAKING;
}

static lv_obj_t *ring_new(lv_obj_t *parent)
{
    lv_obj_t *o = lv_obj_create(parent);
    ui_no_touch(o);
    lv_obj_set_style_radius(o, LV_RADIUS_CIRCLE, 0);
    lv_obj_set_style_bg_opa(o, LV_OPA_TRANSP, 0);
    lv_obj_set_style_pad_all(o, 0, 0);
    lv_obj_set_style_border_width(o, 1, 0); // the brand has no 2 px border
    lv_obj_set_style_border_color(o, lv_color_hex(UI_ACCENT), 0);
    lv_obj_set_style_border_opa(o, LV_OPA_TRANSP, 0);
    lv_obj_add_flag(o, LV_OBJ_FLAG_HIDDEN);
    return o;
}

// The brand curve, cubic-bezier(0.16, 1, 0.3, 1), is an ease out with a long
// settle. A cubic ease out is close enough for a ring and costs nothing.
static float ease_out(float p)
{
    float q = 1.0f - p;
    return 1.0f - q * q * q;
}

// Ripple: each ring runs its own phase from 0 to 1, born small and bright,
// dying wide and dark. The voice sets how bright and how far.
static void ripple(float dt, float period_ms, float r_max, float peak)
{
    for (int i = 0; i < RINGS; i++) {
        ring_t *g = &s_rg[i];
        g->phase += dt / period_ms;
        g->phase -= floorf(g->phase);
        float p = g->phase;
        float r = R_MIN + (r_max - R_MIN) * ease_out(p);
        float o = peak * (1.0f - p) * (1.0f - p);
        bool settling = (esp_timer_get_time() - s_changed_us) < UI_DUR_MED * 1000;
        float k = settling ? 0.18f : 1.0f;
        g->r += (r - g->r) * k;
        g->opa += (o - g->opa) * k;
    }
}

// Thinking: two still rings breathing out of step, the third put away.
static void shimmer(float t_ms)
{
    for (int i = 0; i < RINGS; i++) {
        ring_t *g = &s_rg[i];
        float r = (i < 2) ? 38.0f + 16.0f * i : R_MIN;
        float o = (i < 2) ? 34.0f + 30.0f * (0.5f + 0.5f * sinf(6.2832f * (t_ms / UI_DUR_PULSE + i * 0.5f))) : 0;
        g->r += (r - g->r) * 0.08f;
        g->opa += (o - g->opa) * 0.08f;
    }
}

static void apply(void)
{
    lv_image_set_scale(s_star, (int32_t) (LV_SCALE_NONE * s_scale));
    lv_image_set_rotation(s_star, (int32_t) (s_angle * 10.0f));
    lv_obj_set_style_image_opa(s_star, (lv_opa_t) (255 * s_fade), 0);
    for (int i = 0; i < RINGS; i++) {
        int32_t r = (int32_t) s_rg[i].r;
        lv_obj_set_size(s_ring[i], r * 2, r * 2);
        lv_obj_set_pos(s_ring[i], UI_ORB_CX - r, UI_ORB_CY - r);
        lv_obj_set_style_border_opa(s_ring[i], (lv_opa_t) LV_CLAMP(0, s_rg[i].opa * s_fade, 255), 0);
    }
}

static void tick(lv_timer_t *t)
{
    (void) t;
    int64_t now = esp_timer_get_time();
    float dt = (now - s_last_us) / 1000.0f;
    s_last_us = now;
    if (dt > 100) {
        dt = 100; // a stalled frame should not fling the rings
    }

    // Fast rise, slower fall, so a syllable lands at once and dies away.
    float k = s_level_target > s_level ? 0.45f : 0.12f;
    s_level += (s_level_target - s_level) * k;
    float v = LV_CLAMP(0.0f, s_level, 1.0f);

    s_fade += (s_fade_to - s_fade) * 0.12f;
    float angle_to = s_angle;
    float scale_to = 1.0f;
    switch (s_state) {
    case OS_LISTENING:
        ripple(dt, 1000, 50 + 8 * v, 45 + 190 * v);
        scale_to = 1.0f + 0.14f * v;
        angle_to = roundf(s_angle / 90.0f) * 90.0f;
        break;
    case OS_SPEAKING:
        ripple(dt, 1400, 54 + 8 * v, 60 + 180 * v);
        scale_to = 1.0f + 0.18f * v;
        angle_to = roundf(s_angle / 90.0f) * 90.0f;
        break;
    case OS_THINKING:
        shimmer(now / 1000.0f);
        s_angle += dt * 360.0f / 7000.0f; // one turn in 7 s, linear, like an orbit
        angle_to = s_angle;
        scale_to = 0.92f;
        break;
    default:
        break;
    }
    // Out of thinking the star comes to rest on its nearest upright pose, not
    // wherever the turn happened to stop. A four point star repeats every 90.
    s_angle += (angle_to - s_angle) * 0.12f;
    if (s_angle >= 360.0f) {
        s_angle -= 360.0f;
    }
    s_scale += (scale_to - s_scale) * 0.25f;
    apply();

    if (s_fade_to == 0 && s_fade < 0.01f) {
        s_fade = 0;
        apply();
        lv_obj_add_flag(s_star, LV_OBJ_FLAG_HIDDEN);
        for (int i = 0; i < RINGS; i++) {
            lv_obj_add_flag(s_ring[i], LV_OBJ_FLAG_HIDDEN);
        }
        lv_timer_pause(s_timer); // nothing to draw, nothing to burn
    }
}

void ui_star_create(lv_obj_t *parent)
{
    for (int i = 0; i < RINGS; i++) {
        s_ring[i] = ring_new(parent);
        s_rg[i] = (ring_t) { .r = R_MIN, .opa = 0, .phase = (float) i / RINGS };
    }
    s_star = lv_image_create(parent);
    ui_no_touch(s_star);
    lv_image_set_src(s_star, &ui_img_star_56);
    lv_obj_set_pos(s_star, UI_ORB_CX - STAR / 2, UI_ORB_CY - STAR / 2);
    lv_image_set_pivot(s_star, STAR / 2, STAR / 2);
    // White on dark: brand/logo.md. The accent lives only in the rings and
    // the glow around it, never inside the mark.
    lv_obj_set_style_image_recolor(s_star, lv_color_hex(UI_TEXT_WHITE), 0);
    lv_obj_set_style_image_recolor_opa(s_star, LV_OPA_COVER, 0);
    lv_obj_set_style_image_opa(s_star, LV_OPA_TRANSP, 0);
    lv_obj_add_flag(s_star, LV_OBJ_FLAG_HIDDEN);

    s_timer = lv_timer_create(tick, TICK_MS, NULL);
    lv_timer_pause(s_timer);
}

void ui_star_set_state(orion_state_t st)
{
    s_state = st;
    s_changed_us = esp_timer_get_time();
    if (st == OS_LISTENING || st == OS_SPEAKING) {
        s_level = s_level_target = 0; // each voice starts from silence
    }
    s_fade_to = owns(st) ? 1.0f : 0.0f;
    if (s_fade_to > 0) {
        lv_obj_remove_flag(s_star, LV_OBJ_FLAG_HIDDEN);
        for (int i = 0; i < RINGS; i++) {
            lv_obj_remove_flag(s_ring[i], LV_OBJ_FLAG_HIDDEN);
        }
        s_last_us = esp_timer_get_time();
        lv_timer_resume(s_timer);
    }
}

void ui_star_set_level(float level)
{
    s_level_target = level;
}
