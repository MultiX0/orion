// Bluetooth Wi-Fi setup. A full screen view over everything else: which
// device to pick in the Orion app, the six digit code set large in Playfair,
// the brand's metric face, and one status line with the live dot. Arabic
// first, like every other screen.
#include "ui_internal.h"

#include <string.h>

#define DONE_HOLD_MS 2500

static lv_obj_t *s_view, *s_device, *s_code, *s_status, *s_dot;
static lv_timer_t *s_done_timer;
static bool s_shown;

// brand/voice.md: short, spoken, Levantine, no exclamation marks.
static const char *STATUS_TEXT[] = {
    [UI_SETUP_WAITING] = "بستنى التلفون عالبلوتوث",
    [UI_SETUP_CONNECTING] = "عم بتصل بالشبكة",
    [UI_SETUP_FAILED] = "ما زبط الاتصال",
    [UI_SETUP_DONE] = "تمام، صرت على الشبكة",
};

static lv_obj_t *line(lv_obj_t *parent, const lv_font_t *font, uint32_t color, int32_t y)
{
    lv_obj_t *l = ui_ar_label(parent, color, font, "");
    lv_obj_set_width(l, UI_W - 2 * UI_GUTTER);
    lv_obj_set_style_text_align(l, LV_TEXT_ALIGN_CENTER, 0);
    lv_label_set_long_mode(l, LV_LABEL_LONG_DOT);
    lv_obj_set_pos(l, UI_GUTTER, y);
    return l;
}

void ui_setup_create(lv_obj_t *parent)
{
    s_view = lv_obj_create(parent);
    lv_obj_set_size(s_view, UI_W, UI_H);
    lv_obj_set_pos(s_view, 0, 0);
    ui_flat(s_view);
    lv_obj_set_style_bg_color(s_view, lv_color_hex(UI_BG_PRIMARY), 0);
    lv_obj_set_style_bg_opa(s_view, LV_OPA_COVER, 0);
    lv_obj_remove_flag(s_view, LV_OBJ_FLAG_SCROLLABLE);
    // Clickable so a tap on the setup screen does not fall through and wake Orion.
    lv_obj_add_flag(s_view, LV_OBJ_FLAG_CLICKABLE | LV_OBJ_FLAG_HIDDEN);

    lv_obj_t *tag = ui_mono_label(s_view, UI_TEXT_FAINT, "// BLUETOOTH SETUP");
    lv_obj_align(tag, LV_ALIGN_TOP_MID, 0, UI_SPACE_4);

    // Bluetooth first: the board has no Wi-Fi yet, the phone is its only way
    // in, and a phone with Bluetooth off never sees it.
    lv_obj_t *title = line(s_view, &ui_font_text_16, UI_TEXT_WHITE, 30);
    lv_label_set_text(title, "شغّل البلوتوث على تلفونك");
    lv_obj_t *pick = line(s_view, &ui_font_text_16, UI_TEXT_MUTED, 56);
    lv_label_set_text(pick, "وافتح تطبيق أوريون واختار");

    s_device = ui_mono_label(s_view, UI_TEXT_CYAN, "");
    lv_obj_set_width(s_device, UI_W - 2 * UI_GUTTER);
    lv_obj_set_style_text_align(s_device, LV_TEXT_ALIGN_CENTER, 0);
    lv_label_set_long_mode(s_device, LV_LABEL_LONG_DOT);
    lv_obj_set_pos(s_device, UI_GUTTER, 90);

    // The code, the one thing the user must read from across a desk.
    s_code = lv_label_create(s_view);
    ui_no_touch(s_code);
    lv_obj_set_style_text_font(s_code, &ui_font_code_40, 0);
    lv_obj_set_style_text_color(s_code, lv_color_hex(UI_TEXT_WHITE), 0);
    lv_obj_set_style_text_letter_space(s_code, 4, 0);
    lv_obj_set_width(s_code, UI_W);
    lv_obj_set_style_text_align(s_code, LV_TEXT_ALIGN_CENTER, 0);
    lv_obj_set_pos(s_code, 0, 112);
    lv_obj_t *cap = ui_mono_label(s_view, UI_TEXT_FAINT, "// CODE");
    lv_obj_align(cap, LV_ALIGN_TOP_MID, 0, 154);

    // Eyebrow with live dot, brand/components.md, mirrored for Arabic: the dot
    // leads the line, so it sits on the right.
    // Two lines, so a failure can carry its reason in full. The box clips, so
    // even a reason longer than that stops at 240.
    s_status = line(s_view, &ui_font_text_16, UI_TEXT_MUTED, 176);
    lv_obj_set_size(s_status, UI_W - 2 * UI_GUTTER - UI_SPACE_4, 58);
    lv_label_set_long_mode(s_status, LV_LABEL_LONG_WRAP);
    lv_obj_set_style_text_line_space(s_status, -12, 0);
    lv_obj_set_style_text_align(s_status, LV_TEXT_ALIGN_RIGHT, 0);

    // The brand's live dot: 6 px, accent, pulsing on the 2.5 s cycle.
    s_dot = lv_obj_create(s_view);
    ui_no_touch(s_dot);
    ui_flat(s_dot);
    lv_obj_set_size(s_dot, 6, 6);
    lv_obj_set_style_radius(s_dot, LV_RADIUS_CIRCLE, 0);
    lv_obj_set_style_bg_color(s_dot, lv_color_hex(UI_TEXT_CYAN), 0);
    lv_obj_set_style_bg_opa(s_dot, LV_OPA_COVER, 0);
    lv_obj_set_pos(s_dot, UI_W - UI_GUTTER - 6, 190);
}

static void exec_opa(void *obj, int32_t v)
{
    lv_obj_set_style_opa(obj, (lv_opa_t) v, 0);
}

// "482913" reads as 482 913, the way a person reads it aloud.
static void set_code(const char *code)
{
    char buf[16];
    char clean[16];
    ui_strip_tags(code, clean, sizeof(clean));
    size_t n = strlen(clean);
    if (n == 6) {
        memcpy(buf, clean, 3);
        buf[3] = ' ';
        memcpy(buf + 4, clean + 3, 3);
        buf[7] = '\0';
        lv_label_set_text(s_code, buf);
    } else {
        lv_label_set_text(s_code, clean);
    }
}

void ui_setup_show(const char *device_name, const char *code)
{
    char name[48];
    ui_strip_tags(device_name, name, sizeof(name));
    lv_label_set_text(s_device, name);
    set_code(code);
    ui_setup_status(UI_SETUP_WAITING, NULL);
    if (!s_shown) {
        s_shown = true;
        lv_obj_remove_flag(s_view, LV_OBJ_FLAG_HIDDEN);
        lv_obj_move_foreground(s_view);
        ui_rise_in(s_view, 0);
    }
}

static void hidden(lv_anim_t *a)
{
    (void) a;
    if (!s_shown) {
        lv_obj_add_flag(s_view, LV_OBJ_FLAG_HIDDEN);
    }
}

void ui_setup_hide(void)
{
    if (s_done_timer) {
        lv_timer_delete(s_done_timer);
        s_done_timer = NULL;
    }
    if (!s_shown) {
        return;
    }
    s_shown = false;
    lv_anim_delete(s_dot, exec_opa);
    ui_fade(s_view, LV_OPA_TRANSP, UI_DUR_MED, 0, hidden);
}

static void done_later(lv_timer_t *t)
{
    (void) t;
    s_done_timer = NULL; // one shot, LVGL deletes it after this call
    ui_setup_hide();
}

void ui_setup_status(int status, const char *detail)
{
    if (status < UI_SETUP_WAITING || status > UI_SETUP_DONE) {
        return;
    }
    static char text[160];
    char why[96] = "";
    ui_strip_tags(detail, why, sizeof(why));
    if (status == UI_SETUP_FAILED && why[0]) {
        lv_snprintf(text, sizeof(text), "%s: %s", STATUS_TEXT[status], why);
    } else {
        lv_strlcpy(text, STATUS_TEXT[status], sizeof(text));
    }
    lv_label_set_text(s_status, text);
    bool failed = status == UI_SETUP_FAILED;
    lv_obj_set_style_text_color(s_status, lv_color_hex(failed ? UI_TEXT_WHITE : UI_TEXT_MUTED), 0);

    // Waiting and connecting pulse; failed goes dim and still; done holds lit.
    lv_anim_delete(s_dot, exec_opa);
    bool busy = status == UI_SETUP_WAITING || status == UI_SETUP_CONNECTING;
    lv_obj_set_style_bg_color(s_dot, lv_color_hex(failed ? UI_TEXT_FAINT : UI_TEXT_CYAN), 0);
    lv_obj_set_style_opa(s_dot, LV_OPA_COVER, 0);
    if (busy) {
        ui_anim_loop(s_dot, exec_opa, LV_OPA_COVER, LV_OPA_50, UI_DUR_PULSE / 2);
    }
    if (status == UI_SETUP_DONE && s_done_timer == NULL) {
        s_done_timer = lv_timer_create(done_later, DONE_HOLD_MS, NULL);
        lv_timer_set_repeat_count(s_done_timer, 1);
    }
}

bool ui_setup_visible(void)
{
    return s_shown;
}
