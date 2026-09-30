// An app pairing over the LAN (POST /api/pair): the six digit code set large,
// the way Bluetooth setup shows its own, with the seconds it has left. The
// board is already on the network, so there is nothing else to say. It goes
// by itself when the time is up, or when the app gets it right.
#include "ui_internal.h"

#include <stdio.h>
#include <string.h>

static lv_obj_t *s_view, *s_code, *s_left;
static lv_timer_t *s_tick;
static int s_seconds;
static bool s_shown;

static lv_obj_t *line(lv_obj_t *parent, uint32_t color, int32_t y, const char *text)
{
    lv_obj_t *l = ui_ar_label(parent, color, &ui_font_text_16, text);
    lv_obj_set_width(l, UI_W - 2 * UI_GUTTER);
    lv_obj_set_style_text_align(l, LV_TEXT_ALIGN_CENTER, 0);
    lv_label_set_long_mode(l, LV_LABEL_LONG_DOT);
    lv_obj_set_pos(l, UI_GUTTER, y);
    return l;
}

void ui_pair_create(lv_obj_t *parent)
{
    s_view = lv_obj_create(parent);
    lv_obj_set_size(s_view, UI_W, UI_H);
    lv_obj_set_pos(s_view, 0, 0);
    ui_flat(s_view);
    lv_obj_set_style_bg_color(s_view, lv_color_hex(UI_BG_PRIMARY), 0);
    lv_obj_set_style_bg_opa(s_view, LV_OPA_COVER, 0);
    lv_obj_remove_flag(s_view, LV_OBJ_FLAG_SCROLLABLE);
    // Clickable so a tap here does not fall through and wake Orion.
    lv_obj_add_flag(s_view, LV_OBJ_FLAG_CLICKABLE | LV_OBJ_FLAG_HIDDEN);

    lv_obj_t *tag = ui_mono_label(s_view, UI_TEXT_FAINT, "// PAIR");
    lv_obj_align(tag, LV_ALIGN_TOP_MID, 0, UI_SPACE_4);

    line(s_view, UI_TEXT_WHITE, 36, "في جهاز بدو يتصل فيي");
    line(s_view, UI_TEXT_MUTED, 62, "اكتب هالرمز بتطبيق أوريون");

    s_code = lv_label_create(s_view);
    ui_no_touch(s_code);
    lv_obj_set_style_text_font(s_code, &ui_font_code_40, 0);
    lv_obj_set_style_text_color(s_code, lv_color_hex(UI_TEXT_WHITE), 0);
    lv_obj_set_style_text_letter_space(s_code, 4, 0);
    lv_obj_set_width(s_code, UI_W);
    lv_obj_set_style_text_align(s_code, LV_TEXT_ALIGN_CENTER, 0);
    lv_obj_set_pos(s_code, 0, 104);
    lv_obj_t *cap = ui_mono_label(s_view, UI_TEXT_FAINT, "// CODE");
    lv_obj_align(cap, LV_ALIGN_TOP_MID, 0, 146);

    s_left = line(s_view, UI_TEXT_MUTED, 180, "");
}

static void show_left(void)
{
    char text[48];
    lv_snprintf(text, sizeof(text), "باقي %d ثانية", s_seconds);
    lv_label_set_text(s_left, text);
}

static void hidden(lv_anim_t *a)
{
    (void) a;
    if (!s_shown) {
        lv_obj_add_flag(s_view, LV_OBJ_FLAG_HIDDEN);
    }
}

void ui_pair_hide(void)
{
    if (s_tick) {
        lv_timer_delete(s_tick);
        s_tick = NULL;
    }
    if (!s_shown) {
        return;
    }
    s_shown = false;
    ui_fade(s_view, LV_OPA_TRANSP, UI_DUR_MED, 0, hidden);
}

static void tick(lv_timer_t *t)
{
    (void) t;
    if (--s_seconds <= 0) {
        ui_pair_hide();
        return;
    }
    show_left();
}

// "482913" reads as 482 913, the way a person reads it aloud.
void ui_pair_show(const char *code, int seconds)
{
    char buf[8];
    if (strlen(code) == 6) {
        lv_snprintf(buf, sizeof(buf), "%.3s %.3s", code, code + 3);
    } else {
        lv_strlcpy(buf, code, sizeof(buf));
    }
    lv_label_set_text(s_code, buf);
    s_seconds = seconds > 0 ? seconds : 120;
    show_left();
    if (!s_tick) {
        s_tick = lv_timer_create(tick, 1000, NULL);
    }
    if (!s_shown) {
        s_shown = true;
        lv_obj_remove_flag(s_view, LV_OBJ_FLAG_HIDDEN);
        lv_obj_move_foreground(s_view);
        ui_rise_in(s_view, 0);
    }
}
