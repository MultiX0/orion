// The orb: wake, error and offline, plus the glow every state stands in.
// Listening, thinking and speaking belong to the star in ui_star.c; here they
// only fade the ring and core away and let the voice brighten the glow.
// Everything drawn is a hairline ring, a small disc or emitted light.
#include "ui_internal.h"

#include "esp_timer.h"

#define HALO_R    48   // the showcase ring from brand/logo.md, active states only

typedef struct {
    int16_t ring_r, ring_opa, glow_opa, core_r, core_opa, halo_opa, tint;
} orb_look_t;

// tint 255 is the accent, 0 is the neutral ramp. Error and offline stay
// neutral: the brand has no status colours.
//
// Idle has no ring and no core on purpose. The mark from ui_idle.c stands
// there instead, over the same breathing glow, and the two crossfade.
static const orb_look_t LOOK[OS_STATE_COUNT] = {
    [OS_BOOT]      = { 34,   0,   0,  0,   0,   0, 255 },
    [OS_IDLE]      = { 34,   0,  40,  6,   0,   0, 255 },
    [OS_WAKE]      = { 44, 150, 120, 10, 180,  30, 255 },
    [OS_LISTENING] = { 30,   0,  46,  4,   0,   0, 255 },
    [OS_THINKING]  = { 30,   0,  52,  4,   0,   0, 255 },
    [OS_SPEAKING]  = { 30,   0,  60,  4,   0,   0, 255 },
    [OS_ERROR]     = { 34, 110,   0,  6, 110,  24,   0 },
    [OS_OFFLINE]   = { 30,  80,   0,  5,  70,  20,   0 },
};

static lv_obj_t *s_box, *s_halo, *s_ring, *s_core, *s_glow;
static orb_look_t s_now;
static orion_state_t s_state = OS_BOOT;
static int64_t s_settled_at;
static float s_level_target, s_level;

static void circle(lv_obj_t *o, int32_t r)
{
    lv_obj_set_size(o, r * 2, r * 2);
    lv_obj_set_pos(o, UI_ORB_CX - r, UI_ORB_CY - r);
}

static void apply(void)
{
    lv_color_t c = lv_color_mix(lv_color_hex(UI_ACCENT), lv_color_hex(UI_TEXT_MUTED), s_now.tint);
    circle(s_ring, s_now.ring_r);
    lv_obj_set_style_border_color(s_ring, c, 0);
    lv_obj_set_style_border_opa(s_ring, s_now.ring_opa, 0);
    circle(s_core, s_now.core_r);
    lv_obj_set_style_bg_color(s_core, c, 0);
    lv_obj_set_style_bg_opa(s_core, s_now.core_opa, 0);
    lv_obj_set_style_image_opa(s_glow, s_now.glow_opa, 0);
    lv_obj_set_style_border_opa(s_halo, s_now.halo_opa, 0);
}

#define FIELD(name)                            \
    static void set_##name(void *v, int32_t x) \
    {                                          \
        (void) v;                              \
        s_now.name = (int16_t) x;              \
        apply();                               \
    }
FIELD(ring_r)
FIELD(ring_opa)
FIELD(glow_opa)
FIELD(core_r)
FIELD(core_opa)
FIELD(halo_opa)
FIELD(tint)

static void set_shake(void *v, int32_t x)
{
    lv_obj_set_style_translate_x(v, x, 0);
}

static lv_obj_t *ring_obj(lv_obj_t *parent, int32_t r, uint32_t color)
{
    lv_obj_t *o = lv_obj_create(parent);
    ui_no_touch(o);
    circle(o, r);
    lv_obj_set_style_radius(o, LV_RADIUS_CIRCLE, 0);
    lv_obj_set_style_bg_opa(o, LV_OPA_TRANSP, 0);
    lv_obj_set_style_pad_all(o, 0, 0);
    lv_obj_set_style_border_width(o, 1, 0); // the brand has no 2 px border
    lv_obj_set_style_border_color(o, lv_color_hex(color), 0);
    lv_obj_set_style_border_opa(o, LV_OPA_TRANSP, 0);
    return o;
}

static void level_tick(lv_timer_t *t)
{
    (void) t;
    // The voice brightens the light behind the star, the user's while
    // listening and Orion's own while speaking. Held off until the state
    // transition has landed so the two never fight.
    s_level += (s_level_target - s_level) * 0.35f;
    bool voiced = s_state == OS_LISTENING || s_state == OS_SPEAKING;
    if (!voiced || esp_timer_get_time() < s_settled_at) {
        return;
    }
    float v = LV_CLAMP(0.0f, s_level, 1.0f);
    s_now.glow_opa = (int16_t) (LOOK[s_state].glow_opa + v * 60.0f);
    apply();
}

void ui_orb_create(lv_obj_t *parent)
{
    s_box = lv_obj_create(parent);
    ui_no_touch(s_box);
    lv_obj_set_size(s_box, UI_W, UI_H);
    lv_obj_set_pos(s_box, 0, 0);
    lv_obj_set_style_bg_opa(s_box, LV_OPA_TRANSP, 0);
    lv_obj_set_style_border_width(s_box, 0, 0);
    lv_obj_set_style_pad_all(s_box, 0, 0);

    s_glow = lv_image_create(s_box);
    ui_no_touch(s_glow);
    lv_image_set_src(s_glow, &ui_img_glow_128);
    lv_obj_set_pos(s_glow, UI_ORB_CX - 64, UI_ORB_CY - 64);
    lv_obj_set_style_image_recolor(s_glow, ui_rgb(UI_GLOW_RGB), 0);
    lv_obj_set_style_image_recolor_opa(s_glow, LV_OPA_COVER, 0);
    lv_obj_set_style_image_opa(s_glow, LV_OPA_TRANSP, 0);

    s_halo = ring_obj(s_box, HALO_R, UI_TEXT_WHITE);
    s_ring = ring_obj(s_box, LOOK[OS_IDLE].ring_r, UI_ACCENT);

    s_core = lv_obj_create(s_box);
    ui_no_touch(s_core);
    lv_obj_set_style_radius(s_core, LV_RADIUS_CIRCLE, 0);
    lv_obj_set_style_border_width(s_core, 0, 0);
    lv_obj_set_style_pad_all(s_core, 0, 0);
    lv_obj_set_style_bg_opa(s_core, LV_OPA_TRANSP, 0);

    s_now = LOOK[OS_BOOT];
    apply();
    lv_timer_create(level_tick, 30, NULL);
}

static void start_loops(lv_timer_t *t)
{
    lv_timer_delete(t);
    const orb_look_t *l = &LOOK[s_state];
    switch (s_state) {
    case OS_IDLE:
        // A 2.5 s breath, the brand's slowest ambient timing. Only the light
        // moves; the mark standing in it holds still.
        ui_anim_loop(&s_now, set_glow_opa, l->glow_opa - 16, l->glow_opa + 24, UI_DUR_PULSE / 2);
        break;
    case OS_THINKING:
        ui_anim_loop(&s_now, set_glow_opa, l->glow_opa - 20, l->glow_opa + 20, UI_DUR_PULSE / 2);
        break;
    case OS_OFFLINE:
        ui_anim_loop(&s_now, set_ring_opa, 55, 95, UI_DUR_FADE);
        break;
    default:
        break;
    }
}

// Every state change eases the same seven numbers to their new values, so no
// transition is ever a cut.
static void ease_to(const orb_look_t *l, uint32_t ms)
{
    ui_anim_to(&s_now, set_ring_r, s_now.ring_r, l->ring_r, ms, 0, false, NULL);
    ui_anim_to(&s_now, set_ring_opa, s_now.ring_opa, l->ring_opa, ms, 0, false, NULL);
    ui_anim_to(&s_now, set_glow_opa, s_now.glow_opa, l->glow_opa, ms, 0, false, NULL);
    ui_anim_to(&s_now, set_core_r, s_now.core_r, l->core_r, ms, 0, false, NULL);
    ui_anim_to(&s_now, set_core_opa, s_now.core_opa, l->core_opa, ms, 0, false, NULL);
    ui_anim_to(&s_now, set_halo_opa, s_now.halo_opa, l->halo_opa, ms, 0, false, NULL);
    ui_anim_to(&s_now, set_tint, s_now.tint, l->tint, ms, 0, false, NULL);
}

static void shake(void)
{
    // One knock, then settle. Nothing in Orion bounces twice.
    lv_anim_t a;
    lv_anim_init(&a);
    lv_anim_set_var(&a, s_box);
    lv_anim_set_exec_cb(&a, set_shake);
    lv_anim_set_values(&a, -6, 6);
    lv_anim_set_duration(&a, 70);
    lv_anim_set_playback_duration(&a, 70);
    lv_anim_set_repeat_count(&a, 2);
    lv_anim_set_path_cb(&a, lv_anim_path_ease_in_out);
    lv_anim_start(&a);
    ui_anim_to(s_box, set_shake, -6, 0, UI_DUR_MED, 290, true, NULL);
}

void ui_orb_set_state(orion_state_t st)
{
    if (st >= OS_STATE_COUNT || st == s_state) {
        return;
    }
    s_state = st;
    ui_anim_stop(&s_now, NULL);
    ui_anim_stop(s_box, set_shake);
    lv_obj_set_style_translate_x(s_box, 0, 0);
    if (st == OS_LISTENING || st == OS_SPEAKING) {
        s_level = s_level_target = 0.0f;
    }

    uint32_t ms = (st == OS_WAKE) ? UI_DUR_FAST : UI_DUR_MED;
    s_settled_at = esp_timer_get_time() + ms * 1000;
    ease_to(&LOOK[st], ms);
    if (st == OS_ERROR) {
        shake();
    }
    lv_timer_create(start_loops, ms, NULL); // loops take over once it has landed
}

void ui_orb_set_level(float level)
{
    s_level_target = level;
}

void ui_orb_reveal_glow(uint32_t delay_ms)
{
    ui_anim_to(&s_now, set_glow_opa, 0, LOOK[OS_IDLE].glow_opa + 20, UI_DUR_FADE, delay_ms, false, NULL);
    ui_anim_to(&s_now, set_halo_opa, 0, LOOK[OS_IDLE].halo_opa, UI_DUR_REVEAL, delay_ms, true, NULL);
}
