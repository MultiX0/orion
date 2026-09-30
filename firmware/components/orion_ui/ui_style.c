// Brand styling shared by the panel and its cards: brand/components.md
// shrunk to a 240 px screen. Borders 1 px, accent never a fill.
#include "ui_internal.h"

#define CARD_PAD UI_SPACE_3

lv_obj_t *ui_mono_label(lv_obj_t *parent, uint32_t color, const char *text)
{
    lv_obj_t *l = lv_label_create(parent);
    ui_no_touch(l);
    lv_obj_set_style_text_font(l, &ui_font_mono_12, 0);
    lv_obj_set_style_text_color(l, lv_color_hex(color), 0);
    lv_obj_set_style_text_letter_space(l, 2, 0); // 0.15em, the brand's mono tic
    lv_label_set_text(l, text);
    return l;
}

lv_obj_t *ui_ar_label(lv_obj_t *parent, uint32_t color, const lv_font_t *font, const char *text)
{
    lv_obj_t *l = lv_label_create(parent);
    ui_no_touch(l);
    lv_obj_set_style_text_font(l, font, 0);
    lv_obj_set_style_text_color(l, lv_color_hex(color), 0);
    lv_obj_set_style_base_dir(l, LV_BASE_DIR_RTL, 0);
    lv_label_set_text(l, text);
    return l;
}

lv_obj_t *ui_card_new(lv_obj_t *parent, int32_t w, int32_t h)
{
    lv_obj_t *c = lv_obj_create(parent);
    ui_no_touch(c);
    lv_obj_set_size(c, w, h);
    lv_obj_set_style_bg_color(c, lv_color_hex(UI_BG_CARD), 0);
    lv_obj_set_style_bg_opa(c, LV_OPA_COVER, 0);
    lv_obj_set_style_border_width(c, 1, 0);
    lv_obj_set_style_border_color(c, lv_color_hex(UI_TEXT_WHITE), 0);
    lv_obj_set_style_border_opa(c, UI_OPA_BORDER_SUBTLE, 0);
    lv_obj_set_style_radius(c, UI_RADIUS_CARD, 0);
    lv_obj_set_style_pad_all(c, CARD_PAD, 0);
    lv_obj_remove_flag(c, LV_OBJ_FLAG_OVERFLOW_VISIBLE);
    return c;
}

// Ghost button from brand/components.md: transparent, 1 px subtle border,
// muted label. Compact size, 10 by 14.
lv_obj_t *ui_ghost_button(lv_obj_t *parent, const char *text, lv_event_cb_t cb)
{
    lv_obj_t *b = lv_obj_create(parent);
    lv_obj_set_size(b, 64, 24);
    lv_obj_set_style_bg_opa(b, LV_OPA_TRANSP, 0);
    lv_obj_set_style_border_width(b, 1, 0);
    lv_obj_set_style_border_color(b, lv_color_hex(UI_TEXT_WHITE), 0);
    lv_obj_set_style_border_opa(b, UI_OPA_BORDER_SUBTLE, 0);
    lv_obj_set_style_radius(b, UI_RADIUS_BTN, 0);
    lv_obj_set_style_pad_all(b, 0, 0);
    lv_obj_remove_flag(b, LV_OBJ_FLAG_SCROLLABLE);
    lv_obj_add_event_cb(b, cb, LV_EVENT_CLICKED, NULL);
    lv_obj_t *l = ui_ar_label(b, UI_TEXT_MUTED, &ui_font_text_16, text);
    lv_obj_center(l);
    return b;
}
