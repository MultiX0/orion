// Under the orb: a mono state label, then the transcript or the reply in
// Source Serif and Naskh. The text lives in a fixed 216 x 72 box and is
// clipped by it. Two lines fit. Longer text scrolls inside the box at about
// the pace it is being spoken, and stays at the end.
#include "ui_internal.h"

#include <stdint.h>
#include <string.h>

#define TEXT_W (UI_W - 2 * UI_GUTTER)

static lv_obj_t *s_label;
static lv_obj_t *s_box;
static lv_obj_t *s_text;
static lv_grad_dsc_t s_grad_top;
static lv_grad_dsc_t s_grad_bottom;

static char s_pending[512];
static bool s_pending_primary;
static char s_pending_label[24];

static void exec_y(void *obj, int32_t v)
{
    lv_obj_set_y(obj, v);
}

// The marquee edge mask from brand/colors.md: surface colour fading to nothing,
// so a scrolling line does not end on a hard cut.
static void edge_fade(lv_obj_t *parent, lv_grad_dsc_t *g, bool top)
{
    lv_obj_t *f = lv_obj_create(parent);
    ui_no_touch(f);
    ui_flat(f);
    lv_obj_set_size(f, TEXT_W, UI_SPACE_5);
    lv_obj_set_pos(f, UI_GUTTER, top ? UI_TEXT_Y : UI_TEXT_Y + UI_TEXT_H - UI_SPACE_5);

    g->dir = LV_GRAD_DIR_VER;
    g->stops_count = 2;
    g->stops[0].color = lv_color_hex(UI_BG_PRIMARY);
    g->stops[0].opa = top ? LV_OPA_COVER : LV_OPA_TRANSP;
    g->stops[0].frac = 0;
    g->stops[1].color = lv_color_hex(UI_BG_PRIMARY);
    g->stops[1].opa = top ? LV_OPA_TRANSP : LV_OPA_COVER;
    g->stops[1].frac = 255;
    lv_obj_set_style_bg_grad(f, g, 0);
    lv_obj_set_style_bg_opa(f, LV_OPA_COVER, 0);
}

void ui_text_create(lv_obj_t *parent)
{
    s_label = lv_label_create(parent);
    ui_no_touch(s_label);
    lv_obj_set_style_text_font(s_label, &ui_font_mono_12, 0);
    lv_obj_set_style_text_color(s_label, lv_color_hex(UI_TEXT_FAINT), 0);
    lv_obj_set_style_text_letter_space(s_label, 2, 0); // 0.15em at 12 px
    lv_label_set_text(s_label, "");
    lv_obj_set_width(s_label, TEXT_W);
    lv_obj_set_style_text_align(s_label, LV_TEXT_ALIGN_CENTER, 0);
    lv_obj_set_pos(s_label, UI_GUTTER, UI_LABEL_Y);

    s_box = lv_obj_create(parent);
    ui_no_touch(s_box);
    ui_flat(s_box);
    lv_obj_set_size(s_box, TEXT_W, UI_TEXT_H);
    lv_obj_set_pos(s_box, UI_GUTTER, UI_TEXT_Y);
    // Children are clipped to this box. Nothing the reply does can reach the
    // edge of the screen.
    lv_obj_remove_flag(s_box, LV_OBJ_FLAG_OVERFLOW_VISIBLE);

    s_text = lv_label_create(s_box);
    ui_no_touch(s_text);
    lv_obj_set_width(s_text, TEXT_W);
    lv_label_set_long_mode(s_text, LV_LABEL_LONG_WRAP);
    lv_obj_set_style_text_font(s_text, &ui_font_text_22, 0);
    lv_obj_set_style_text_color(s_text, lv_color_hex(UI_TEXT_WHITE), 0);
    // Naskh reports a 43 px line for 22 px type, which is its ascender and
    // descender reach, not its ink. Pulling the lines together fits two.
    lv_obj_set_style_text_line_space(s_text, -14, 0);
    lv_obj_set_style_base_dir(s_text, LV_BASE_DIR_AUTO, 0);
    lv_label_set_text(s_text, "");
    lv_obj_set_pos(s_text, 0, 0);

    edge_fade(parent, &s_grad_top, true);
    edge_fade(parent, &s_grad_bottom, false);
}

// First strong character decides which edge the block hangs from. Cheaper
// than pulling in LVGL's private bidi header, and it is all we need: LVGL
// still reorders the runs inside each line by itself.
bool ui_is_rtl(const char *s)
{
    for (const uint8_t *p = (const uint8_t *) s; *p; p++) {
        if (*p < 0x80) {
            if ((*p >= 'A' && *p <= 'Z') || (*p >= 'a' && *p <= 'z')) {
                return false;
            }
            continue;
        }
        uint32_t cp = 0;
        if ((*p & 0xE0) == 0xC0 && p[1]) {
            cp = ((uint32_t) (*p & 0x1F) << 6) | (p[1] & 0x3F);
        } else if ((*p & 0xF0) == 0xE0 && p[1] && p[2]) {
            cp = ((uint32_t) (*p & 0x0F) << 12) | ((uint32_t) (p[1] & 0x3F) << 6) | (p[2] & 0x3F);
        }
        // Hebrew, Arabic, Syriac, Thaana, and the Arabic presentation forms.
        if ((cp >= 0x0590 && cp <= 0x08FF) || (cp >= 0xFB1D && cp <= 0xFEFC)) {
            return true;
        }
    }
    return false;
}

// Punctuation that takes no space before it: . , ! ? ; : and Arabic ، ؛ ؟.
static bool is_stop(const char *p)
{
    if (*p && strchr(".,!?;:", *p)) {
        return true;
    }
    const uint8_t *u = (const uint8_t *) p;
    return u[0] == 0xD8 && (u[1] == 0x8C || u[1] == 0x9B || u[1] == 0x9F);
}

// Fish voice cues like [laugh], [laughing nervously] or [excited] steer the
// voice, they are not for reading, and they may sit anywhere in a sentence.
// Drop every [ ... ] span, fold the whitespace it leaves into single spaces,
// keep no space before a stop ("did it [laugh]." reads "did it."), and trim.
// An unclosed [ is kept as text.
void ui_strip_tags(const char *in, char *out, size_t n)
{
    size_t len = 0;
    bool space = false;
    for (const char *p = in ? in : ""; *p && len + 1 < n; p++) {
        if (space && is_stop(p)) {
            space = false;
        }
        if (*p == '[') {
            const char *end = strchr(p, ']');
            if (end) {
                p = end;
                space = len > 0;
                continue;
            }
        }
        if (*p == ' ' || *p == '\t' || *p == '\n' || *p == '\r') {
            space = len > 0;
            continue;
        }
        if (space && len + 2 < n) {
            out[len++] = ' ';
        }
        space = false;
        out[len++] = *p;
    }
    out[len] = '\0';
}

static uint32_t utf8_chars(const char *s)
{
    uint32_t n = 0;
    for (; *s; s++) {
        if (((uint8_t) *s & 0xC0) != 0x80) {
            n++;
        }
    }
    return n;
}

static void place(void)
{
    lv_obj_update_layout(s_text);
    int32_t h = lv_obj_get_height(s_text);
    if (h <= UI_TEXT_H) {
        // Short reply: sit it in the middle of the box instead of hanging
        // from the top with a hole underneath.
        lv_obj_set_y(s_text, (UI_TEXT_H - h) / 2);
        return;
    }
    lv_obj_set_y(s_text, 0);
    // Speech runs at roughly 70 ms a character; the scroll keeps that pace so
    // the visible lines follow what is being said. Clamped to 2 to 20 s.
    uint32_t ms = LV_CLAMP(2000u, utf8_chars(s_pending) * 70u, 20000u);
    lv_anim_t a;
    lv_anim_init(&a);
    lv_anim_set_var(&a, s_text);
    lv_anim_set_exec_cb(&a, exec_y);
    lv_anim_set_values(&a, 0, UI_TEXT_H - h);
    lv_anim_set_duration(&a, ms);
    lv_anim_set_delay(&a, UI_DUR_REVEAL);
    lv_anim_set_path_cb(&a, lv_anim_path_linear);
    lv_anim_start(&a);
}

static void swap_text(lv_anim_t *a)
{
    (void) a;
    lv_anim_delete(s_text, exec_y);
    lv_obj_set_y(s_text, 0);
    lv_obj_set_style_text_color(s_text, lv_color_hex(s_pending_primary ? UI_TEXT_WHITE : UI_TEXT_MUTED), 0);
    // Arabic hangs from the right, English from the left. LVGL reorders the
    // mixed runs inside the line; this only decides which edge the block sits on.
    bool rtl = ui_is_rtl(s_pending);
    lv_obj_set_style_text_align(s_text, rtl ? LV_TEXT_ALIGN_RIGHT : LV_TEXT_ALIGN_LEFT, 0);
    lv_label_set_text(s_text, s_pending);
    if (s_pending[0] == '\0') {
        return;
    }
    ui_rise_in(s_text, 0);
    place();
}

void ui_text_set(const char *text, bool primary)
{
    lv_strlcpy(s_pending, text ? text : "", sizeof(s_pending));
    s_pending_primary = primary;
    bool visible = lv_obj_get_style_opa(s_text, 0) > LV_OPA_MIN && lv_label_get_text(s_text)[0] != '\0';
    if (visible) {
        ui_fade(s_text, LV_OPA_TRANSP, UI_DUR_FAST, 0, swap_text);
    } else {
        swap_text(NULL);
    }
}

void ui_text_clear(void)
{
    ui_text_set("", false);
}

static void swap_label(lv_anim_t *a)
{
    (void) a;
    lv_label_set_text(s_label, s_pending_label);
    ui_fade(s_label, LV_OPA_COVER, UI_DUR_FAST, 0, NULL);
}

void ui_text_set_label(const char *text)
{
    lv_strlcpy(s_pending_label, text ? text : "", sizeof(s_pending_label));
    if (strcmp(lv_label_get_text(s_label), s_pending_label) == 0) {
        return;
    }
    ui_fade(s_label, LV_OPA_TRANSP, UI_DUR_FAST, 0, swap_label);
}
