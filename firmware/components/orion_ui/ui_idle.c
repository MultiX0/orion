// The idle face. The mark from brand/assets sits still over the breathing
// glow, and one short Levantine line says how to wake Orion. The mark and the
// orb crossfade into each other on the brand curve, never cut. Under the line,
// two lights say which apps are here right now: the phone and the PC, each
// lit in the accent while it holds its link to the board, faint when not.
#include "ui_internal.h"

#define MARK 96
#define LINKS_Y (UI_HINT_Y + 52)
#define LINK_DOT 7

// brand/voice.md: short, spoken, no exclamation, no instruction manual tone.
// The name is the accent; everything else is body colour.
static const char *HINT_BEFORE = "قول ";
static const char *HINT_NAME = "أوريون";
static const char *HINT_AFTER = "، أو المس الشاشة";

// With the wake word off, only a tap starts a turn.
static const char *HINT_TAP = "المس الشاشة لتتكلم";

static lv_obj_t *s_mark;
static lv_obj_t *s_hint;
static lv_span_t *s_span_before, *s_span_name, *s_span_after;
static lv_obj_t *s_links;
static bool s_on;

// Right to left, the way the line above reads: the phone first, then the PC.
enum { LINK_PHONE = 0, LINK_PC, LINK_COUNT };
static const char *LINK_NAME[LINK_COUNT] = { "التلفون", "الكمبيوتر" };
static lv_obj_t *s_dot[LINK_COUNT];
static lv_obj_t *s_name[LINK_COUNT];
static bool s_lit[LINK_COUNT];

static void paint_link(int i)
{
    const bool on = s_lit[i];
    lv_obj_set_style_bg_color(s_dot[i], lv_color_hex(on ? UI_ACCENT : UI_TEXT_FAINT), 0);
    // The accent is light, never paint: a lit dot glows around itself.
    lv_obj_set_style_shadow_width(s_dot[i], on ? 10 : 0, 0);
    lv_obj_set_style_shadow_color(s_dot[i], lv_color_hex(UI_ACCENT), 0);
    lv_obj_set_style_shadow_opa(s_dot[i], on ? UI_OPA_GLOW : LV_OPA_TRANSP, 0);
    lv_obj_set_style_text_color(s_name[i], lv_color_hex(on ? UI_TEXT_CYAN : UI_TEXT_FAINT), 0);
}

static void links_create(lv_obj_t *parent)
{
    s_links = lv_obj_create(parent);
    ui_no_touch(s_links);
    ui_flat(s_links);
    lv_obj_set_size(s_links, UI_W - 2 * UI_GUTTER, 28);
    lv_obj_set_pos(s_links, UI_GUTTER, LINKS_Y);
    lv_obj_remove_flag(s_links, LV_OBJ_FLAG_SCROLLABLE);
    lv_obj_set_style_base_dir(s_links, LV_BASE_DIR_RTL, 0);
    lv_obj_set_flex_flow(s_links, LV_FLEX_FLOW_ROW);
    lv_obj_set_flex_align(s_links, LV_FLEX_ALIGN_CENTER, LV_FLEX_ALIGN_CENTER, LV_FLEX_ALIGN_CENTER);
    lv_obj_set_style_pad_column(s_links, UI_SPACE_5, 0);
    for (int i = 0; i < LINK_COUNT; i++) {
        lv_obj_t *item = lv_obj_create(s_links);
        ui_no_touch(item);
        ui_flat(item);
        lv_obj_set_size(item, LV_SIZE_CONTENT, LV_SIZE_CONTENT);
        lv_obj_set_style_base_dir(item, LV_BASE_DIR_RTL, 0);
        lv_obj_set_flex_flow(item, LV_FLEX_FLOW_ROW);
        lv_obj_set_flex_align(item, LV_FLEX_ALIGN_CENTER, LV_FLEX_ALIGN_CENTER, LV_FLEX_ALIGN_CENTER);
        lv_obj_set_style_pad_column(item, UI_SPACE_2, 0);
        lv_obj_set_style_pad_all(item, 4, 0);   // room for the glow
        lv_obj_remove_flag(item, LV_OBJ_FLAG_SCROLLABLE);

        s_dot[i] = lv_obj_create(item);
        ui_no_touch(s_dot[i]);
        ui_flat(s_dot[i]);
        lv_obj_set_size(s_dot[i], LINK_DOT, LINK_DOT);
        lv_obj_set_style_radius(s_dot[i], LV_RADIUS_CIRCLE, 0);
        lv_obj_set_style_bg_opa(s_dot[i], LV_OPA_COVER, 0);

        s_name[i] = ui_ar_label(item, UI_TEXT_FAINT, &ui_font_text_16, LINK_NAME[i]);
        paint_link(i);
    }
    lv_obj_set_style_opa(s_links, LV_OPA_TRANSP, 0);
    lv_obj_add_flag(s_links, LV_OBJ_FLAG_HIDDEN);
}

void ui_idle_set_wake_word(bool on)
{
    if (!s_hint) {
        return;
    }
    lv_span_set_text(s_span_before, on ? HINT_BEFORE : HINT_TAP);
    lv_span_set_text(s_span_name, on ? HINT_NAME : "");
    lv_span_set_text(s_span_after, on ? HINT_AFTER : "");
    lv_spangroup_refresh(s_hint);
}

void ui_idle_set_links(bool pc, bool phone)
{
    const bool want[LINK_COUNT] = { [LINK_PHONE] = phone, [LINK_PC] = pc };
    for (int i = 0; i < LINK_COUNT; i++) {
        if (want[i] != s_lit[i]) {
            s_lit[i] = want[i];
            paint_link(i);
        }
    }
}

static lv_span_t *span(lv_obj_t *sg, const char *text, uint32_t color)
{
    lv_span_t *s = lv_spangroup_new_span(sg);
    lv_span_set_text(s, text);
    lv_style_set_text_color(lv_span_get_style(s), lv_color_hex(color));
    lv_style_set_text_font(lv_span_get_style(s), &ui_font_text_16);
    return s;
}

void ui_idle_create(lv_obj_t *parent)
{
    s_mark = lv_image_create(parent);
    ui_no_touch(s_mark);
    lv_image_set_src(s_mark, &ui_img_mark_96);
    lv_obj_set_pos(s_mark, UI_ORB_CX - MARK / 2, UI_ORB_CY - MARK / 2);
    // A8 asset, so the only colour it can ever be is this one. brand/logo.md:
    // white on dark, accent around it as glow, never inside it.
    lv_obj_set_style_image_recolor(s_mark, lv_color_hex(UI_TEXT_WHITE), 0);
    lv_obj_set_style_image_recolor_opa(s_mark, LV_OPA_COVER, 0);
    lv_obj_set_style_image_opa(s_mark, LV_OPA_TRANSP, 0);
    lv_obj_add_flag(s_mark, LV_OBJ_FLAG_HIDDEN);

    // A spangroup, not a label: one word has to carry the accent colour and
    // still join to its neighbours. Arabic words do not join across a space,
    // so the split is safe exactly here.
    s_hint = lv_spangroup_create(parent);
    ui_no_touch(s_hint);
    ui_flat(s_hint);
    lv_obj_set_size(s_hint, UI_W - 2 * UI_GUTTER, UI_HINT_H);
    lv_obj_set_pos(s_hint, UI_GUTTER, UI_HINT_Y);
    lv_obj_remove_flag(s_hint, LV_OBJ_FLAG_OVERFLOW_VISIBLE);
    lv_obj_set_style_base_dir(s_hint, LV_BASE_DIR_RTL, 0);
    lv_spangroup_set_align(s_hint, LV_TEXT_ALIGN_CENTER);
    lv_spangroup_set_mode(s_hint, LV_SPAN_MODE_BREAK);
    lv_spangroup_set_max_lines(s_hint, 2);
    s_span_before = span(s_hint, HINT_BEFORE, UI_TEXT_MUTED);
    s_span_name = span(s_hint, HINT_NAME, UI_TEXT_CYAN);
    s_span_after = span(s_hint, HINT_AFTER, UI_TEXT_MUTED);
    lv_obj_set_style_opa(s_hint, LV_OPA_TRANSP, 0);
    lv_obj_add_flag(s_hint, LV_OBJ_FLAG_HIDDEN);

    links_create(parent);
}

static void hidden(lv_anim_t *a)
{
    (void) a;
    if (!s_on) {
        lv_obj_add_flag(s_mark, LV_OBJ_FLAG_HIDDEN);
        lv_obj_add_flag(s_hint, LV_OBJ_FLAG_HIDDEN);
        lv_obj_add_flag(s_links, LV_OBJ_FLAG_HIDDEN);
    }
}

static void exec_image_opa(void *obj, int32_t v)
{
    lv_obj_set_style_image_opa(obj, (lv_opa_t) v, 0);
}

void ui_idle_show(bool on)
{
    if (on == s_on) {
        return;
    }
    s_on = on;
    lv_anim_delete(s_mark, exec_image_opa);
    if (on) {
        lv_obj_remove_flag(s_mark, LV_OBJ_FLAG_HIDDEN);
        lv_obj_remove_flag(s_hint, LV_OBJ_FLAG_HIDDEN);
        ui_anim_to(s_mark, exec_image_opa, lv_obj_get_style_image_opa(s_mark, 0),
                   LV_OPA_COVER, UI_DUR_MED, 0, true, NULL);
        ui_fade(s_hint, LV_OPA_COVER, UI_DUR_KEYFRAME, UI_STAGGER_MS * 2, NULL);
        lv_obj_remove_flag(s_links, LV_OBJ_FLAG_HIDDEN);
        ui_fade(s_links, LV_OPA_COVER, UI_DUR_KEYFRAME, UI_STAGGER_MS * 3, NULL);
        return;
    }
    ui_anim_to(s_mark, exec_image_opa, lv_obj_get_style_image_opa(s_mark, 0),
               LV_OPA_TRANSP, UI_DUR_MED, 0, true, NULL);
    ui_fade(s_hint, LV_OPA_TRANSP, UI_DUR_FAST, 0, hidden);
    ui_fade(s_links, LV_OPA_TRANSP, UI_DUR_FAST, 0, NULL);
}
