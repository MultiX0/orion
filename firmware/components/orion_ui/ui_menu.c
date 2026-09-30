// The menu: a 30 px hairline button in the top left corner, and the panel it
// opens. Three cards, right to left, Arabic titles, brand card recipe from
// brand/components.md shrunk to 240 px. Scrolls when the cards do not fit;
// nothing is ever cut off with no way to reach it.
#include "ui_internal.h"

#include <stdio.h>

#define PANEL_PAD   UI_SPACE_3
#define CARD_W      (UI_W - 2 * PANEL_PAD - UI_SPACE_2)  // room for the scrollbar
#define CARD_PAD    UI_SPACE_3
#define ROW_H       20
#define HEAD_H      34
#define AUTO_HIDE_MS 20000

static lv_obj_t *s_btn, *s_panel, *s_list;
static ui_tap_cb_t s_refresh_cb, s_wifi_cb, s_reset_cb;
static void *s_refresh_ctx, *s_wifi_ctx, *s_reset_ctx;
static lv_obj_t *s_reset_label;
static lv_timer_t *s_reset_armed;
static lv_obj_t *s_pc_state, *s_pc_name, *s_pc_ip;
static lv_obj_t *s_net_state, *s_net_ssid, *s_net_ip;
static lv_timer_t *s_hide_timer;
static bool s_visible;

// mono label, then an Arabic title, then rows. The brand's card composition.
static lv_obj_t *card_head(lv_obj_t *card, const char *tag, const char *title)
{
    lv_obj_t *l = ui_mono_label(card, UI_TEXT_FAINT, tag);
    lv_obj_align(l, LV_ALIGN_TOP_LEFT, 0, 0);
    lv_obj_t *t = ui_ar_label(card, UI_TEXT_WHITE, &ui_font_text_16, title);
    lv_obj_align(t, LV_ALIGN_TOP_RIGHT, 0, -6);
    return t;
}

static lv_obj_t *card_row(lv_obj_t *card, int idx, const char *name, lv_obj_t **value)
{
    int32_t y = HEAD_H + idx * ROW_H;
    lv_obj_t *n = ui_mono_label(card, UI_TEXT_FAINT, name);
    lv_obj_align(n, LV_ALIGN_TOP_LEFT, 0, y);
    *value = ui_ar_label(card, UI_TEXT_MUTED, &ui_font_text_16, "--");
    lv_obj_align(*value, LV_ALIGN_TOP_RIGHT, 0, y - 6);
    return n;
}

static void on_refresh(lv_event_t *e)
{
    (void) e;
    if (s_refresh_cb) {
        s_refresh_cb(s_refresh_ctx);
    }
}

// The menu gets out of the way first, so the setup view main opens next
// lands on a clean screen.
static void on_wifi(lv_event_t *e)
{
    (void) e;
    ui_menu_hide();
    if (s_wifi_cb) {
        s_wifi_cb(s_wifi_ctx);
    }
}

// Reset asks twice: the first tap arms it for 4 s and says so, the second
// runs it. Nothing this final should happen on a brushed screen.
static const char *RESET_TEXT = "امسح كل شي";
static const char *RESET_SURE = "متأكد؟ اضغط كمان";

static void reset_disarm(lv_timer_t *t)
{
    (void) t;
    s_reset_armed = NULL;  // one shot, LVGL deletes it after this call
    lv_label_set_text(s_reset_label, RESET_TEXT);
    lv_obj_set_style_text_color(s_reset_label, lv_color_hex(UI_TEXT_MUTED), 0);
}

static void on_reset(lv_event_t *e)
{
    (void) e;
    if (!s_reset_armed) {
        lv_label_set_text(s_reset_label, RESET_SURE);
        lv_obj_set_style_text_color(s_reset_label, lv_color_hex(UI_TEXT_WHITE), 0);
        s_reset_armed = lv_timer_create(reset_disarm, 4000, NULL);
        lv_timer_set_repeat_count(s_reset_armed, 1);
        return;
    }
    lv_timer_delete(s_reset_armed);
    s_reset_armed = NULL;
    lv_label_set_text(s_reset_label, RESET_TEXT);
    ui_menu_hide();
    if (s_reset_cb) {
        s_reset_cb(s_reset_ctx);
    }
}

void ui_menu_on_reset(ui_tap_cb_t cb, void *ctx)
{
    s_reset_cb = cb;
    s_reset_ctx = ctx;
}

void ui_menu_on_wifi_setup(ui_tap_cb_t cb, void *ctx)
{
    s_wifi_cb = cb;
    s_wifi_ctx = ctx;
}

void ui_menu_on_pc_refresh(ui_tap_cb_t cb, void *ctx)
{
    s_refresh_cb = cb;
    s_refresh_ctx = ctx;
}

static void touched(lv_event_t *e)
{
    (void) e;
    if (s_hide_timer) {
        lv_timer_reset(s_hide_timer);
    }
}

static void on_close(lv_event_t *e)
{
    (void) e;
    ui_menu_hide();
}

static void on_open(lv_event_t *e)
{
    (void) e;
    ui_menu_show();
}

// Three hairlines in a circle. A brand mark rather than an icon font glyph.
static void menu_button(lv_obj_t *parent)
{
    s_btn = lv_obj_create(parent);
    lv_obj_set_size(s_btn, UI_BTN_SIZE, UI_BTN_SIZE);
    lv_obj_set_pos(s_btn, UI_BTN_XY, UI_BTN_XY);
    lv_obj_set_style_radius(s_btn, LV_RADIUS_CIRCLE, 0);
    lv_obj_set_style_bg_color(s_btn, lv_color_hex(UI_BG_CARD), 0);
    lv_obj_set_style_bg_opa(s_btn, LV_OPA_COVER, 0);
    lv_obj_set_style_border_width(s_btn, 1, 0);
    lv_obj_set_style_border_color(s_btn, lv_color_hex(UI_TEXT_WHITE), 0);
    lv_obj_set_style_border_opa(s_btn, UI_OPA_BORDER_SOFT, 0);
    lv_obj_set_style_pad_all(s_btn, 0, 0);
    lv_obj_remove_flag(s_btn, LV_OBJ_FLAG_SCROLLABLE);
    lv_obj_add_flag(s_btn, LV_OBJ_FLAG_CLICKABLE);
    // Grows the touch target to the corner square, the drawing stays 30 px.
    lv_obj_set_ext_click_area(s_btn, UI_BTN_HIT - UI_BTN_XY - UI_BTN_SIZE);
    lv_obj_add_event_cb(s_btn, on_open, LV_EVENT_CLICKED, NULL);

    for (int i = 0; i < 3; i++) {
        lv_obj_t *bar = lv_obj_create(s_btn);
        ui_no_touch(bar);
        ui_flat(bar);
        lv_obj_set_size(bar, 12, 1);
        lv_obj_align(bar, LV_ALIGN_CENTER, 0, (i - 1) * 4);
        lv_obj_set_style_bg_color(bar, lv_color_hex(UI_TEXT_MUTED), 0);
        lv_obj_set_style_bg_opa(bar, LV_OPA_COVER, 0);
    }
}

static void build_panel(lv_obj_t *parent)
{
    s_panel = lv_obj_create(parent);
    lv_obj_set_size(s_panel, UI_W, UI_H);
    lv_obj_set_pos(s_panel, 0, 0);
    lv_obj_set_style_bg_color(s_panel, lv_color_hex(UI_BG_PRIMARY), 0);
    lv_obj_set_style_bg_opa(s_panel, LV_OPA_COVER, 0);
    lv_obj_set_style_border_width(s_panel, 0, 0);
    lv_obj_set_style_radius(s_panel, 0, 0);
    lv_obj_set_style_pad_all(s_panel, 0, 0);
    lv_obj_remove_flag(s_panel, LV_OBJ_FLAG_SCROLLABLE);
    lv_obj_add_flag(s_panel, LV_OBJ_FLAG_HIDDEN | LV_OBJ_FLAG_CLICKABLE);
    lv_obj_add_event_cb(s_panel, touched, LV_EVENT_PRESSED, NULL);

    lv_obj_t *title = ui_ar_label(s_panel, UI_TEXT_WHITE, &ui_font_text_16, "الإعدادات");
    lv_obj_align(title, LV_ALIGN_TOP_RIGHT, -PANEL_PAD, 6);

    // Close sits where the menu button was, so the corner reads as one toggle.
    lv_obj_t *close = lv_obj_create(s_panel);
    lv_obj_set_size(close, UI_BTN_SIZE, UI_BTN_SIZE);
    lv_obj_set_pos(close, UI_BTN_XY, UI_BTN_XY);
    lv_obj_set_style_radius(close, LV_RADIUS_CIRCLE, 0);
    lv_obj_set_style_bg_color(close, lv_color_hex(UI_BG_CARD), 0);
    lv_obj_set_style_bg_opa(close, LV_OPA_COVER, 0);
    lv_obj_set_style_border_width(close, 1, 0);
    lv_obj_set_style_border_color(close, lv_color_hex(UI_TEXT_WHITE), 0);
    lv_obj_set_style_border_opa(close, UI_OPA_BORDER_SOFT, 0);
    lv_obj_set_style_pad_all(close, 0, 0);
    lv_obj_remove_flag(close, LV_OBJ_FLAG_SCROLLABLE);
    // The list, created later, still wins below y 44.
    lv_obj_set_ext_click_area(close, UI_BTN_HIT - UI_BTN_XY - UI_BTN_SIZE);
    lv_obj_add_event_cb(close, on_close, LV_EVENT_CLICKED, NULL);
    lv_obj_t *x = ui_mono_label(close, UI_TEXT_MUTED, "X");
    lv_obj_center(x);

    s_list = lv_obj_create(s_panel);
    ui_flat(s_list);
    lv_obj_set_size(s_list, UI_W, UI_H - 44);
    lv_obj_set_pos(s_list, 0, 44);
    lv_obj_set_style_pad_all(s_list, PANEL_PAD, 0);
    lv_obj_set_style_pad_row(s_list, UI_SPACE_2, 0);
    lv_obj_set_flex_flow(s_list, LV_FLEX_FLOW_COLUMN);
    lv_obj_set_scroll_dir(s_list, LV_DIR_VER);
    lv_obj_set_scrollbar_mode(s_list, LV_SCROLLBAR_MODE_AUTO);
    lv_obj_add_event_cb(s_list, touched, LV_EVENT_PRESSED, NULL);

    lv_obj_t *pc = ui_card_new(s_list, CARD_W, HEAD_H + 3 * ROW_H + 30 + 2 * CARD_PAD);
    card_head(pc, "// PC", "الكمبيوتر");
    card_row(pc, 0, "STATE", &s_pc_state);
    card_row(pc, 1, "NAME", &s_pc_name);
    card_row(pc, 2, "IP", &s_pc_ip);
    lv_obj_t *refresh = ui_ghost_button(pc, "تحديث", on_refresh);
    lv_obj_align(refresh, LV_ALIGN_BOTTOM_RIGHT, 0, 0);

    lv_obj_t *net = ui_card_new(s_list, CARD_W, HEAD_H + 3 * ROW_H + 30 + 2 * CARD_PAD);
    card_head(net, "// NET", "الشبكة");
    card_row(net, 0, "STATE", &s_net_state);
    card_row(net, 1, "SSID", &s_net_ssid);
    card_row(net, 2, "IP", &s_net_ip);
    lv_obj_t *wifi = ui_ghost_button(net, "إعداد الواي فاي", on_wifi);
    lv_obj_set_width(wifi, 116);
    lv_obj_align(wifi, LV_ALIGN_BOTTOM_RIGHT, 0, 0);

    ui_cam_create(s_list, CARD_W, CARD_PAD);

    // Last, under everything: the way back when the app is gone and the
    // network with it. Wi-Fi setup above keeps the keys; this keeps nothing.
    lv_obj_t *reset = ui_card_new(s_list, CARD_W, HEAD_H + 56 + 34 + 2 * CARD_PAD);
    card_head(reset, "// RESET", "إعادة ضبط");
    lv_obj_t *what = ui_ar_label(reset, UI_TEXT_MUTED, &ui_font_text_16,
                                 "بيمسح الشبكة والمفاتيح والأجهزة، وبيرجع لأول إعداد");
    lv_obj_set_width(what, CARD_W - 2 * CARD_PAD);
    lv_label_set_long_mode(what, LV_LABEL_LONG_WRAP);
    lv_obj_set_style_text_align(what, LV_TEXT_ALIGN_RIGHT, 0);
    lv_obj_set_style_text_line_space(what, -10, 0);
    lv_obj_align(what, LV_ALIGN_TOP_RIGHT, 0, HEAD_H - 6);
    lv_obj_t *btn = ui_ghost_button(reset, RESET_TEXT, on_reset);
    // Taller than the other ghost buttons: Naskh runs deep below the line.
    lv_obj_set_size(btn, 128, 30);
    lv_obj_align(btn, LV_ALIGN_BOTTOM_RIGHT, 0, 0);
    s_reset_label = lv_obj_get_child(btn, 0);
}

void ui_menu_create(lv_obj_t *parent)
{
    menu_button(parent);
    build_panel(parent);
    ui_menu_set_pc(false, false, NULL, NULL);
    ui_menu_set_net(false, NULL, NULL, 0);
}

static void hidden(lv_anim_t *a)
{
    (void) a;
    lv_obj_add_flag(s_panel, LV_OBJ_FLAG_HIDDEN);
}

static void auto_hide(lv_timer_t *t)
{
    (void) t;
    ui_menu_hide();
}

void ui_menu_show(void)
{
    if (s_visible) {
        return;
    }
    s_visible = true;
    lv_obj_remove_flag(s_panel, LV_OBJ_FLAG_HIDDEN);
    lv_obj_move_foreground(s_panel);
    ui_rise_in(s_panel, 0);
    ui_menu_button_show(false);
    ui_cam_run(true);
    if (s_hide_timer == NULL) {
        s_hide_timer = lv_timer_create(auto_hide, AUTO_HIDE_MS, NULL);
    }
    lv_timer_reset(s_hide_timer);
    lv_timer_resume(s_hide_timer);
}

void ui_menu_hide(void)
{
    if (!s_visible) {
        return;
    }
    s_visible = false;
    ui_cam_run(false);
    if (s_hide_timer) {
        lv_timer_pause(s_hide_timer);
    }
    ui_fade(s_panel, LV_OPA_TRANSP, UI_DUR_FAST, 0, hidden);
    ui_menu_button_show(true);
}

void ui_menu_scroll(int32_t y)
{
    lv_obj_scroll_to_y(s_list, y, LV_ANIM_ON);
}

bool ui_menu_visible(void)
{
    return s_visible;
}

void ui_menu_button_show(bool on)
{
    ui_fade(s_btn, on ? LV_OPA_COVER : LV_OPA_TRANSP, UI_DUR_FAST, 0, NULL);
    if (on) {
        lv_obj_add_flag(s_btn, LV_OBJ_FLAG_CLICKABLE);
    } else {
        lv_obj_remove_flag(s_btn, LV_OBJ_FLAG_CLICKABLE);
    }
}

static void set_row(lv_obj_t *l, const char *text, uint32_t color)
{
    const char *v = (text && text[0]) ? text : "--";
    // An IP or a dBm figure is latin. Left to right, or the minus sign ends up
    // on the wrong side of the number.
    lv_obj_set_style_base_dir(l, ui_is_rtl(v) ? LV_BASE_DIR_RTL : LV_BASE_DIR_LTR, 0);
    lv_label_set_text(l, v);
    lv_obj_set_style_text_color(l, lv_color_hex(color), 0);
}

void ui_menu_set_pc(bool found, bool connected, const char *name, const char *ip)
{
    set_row(s_pc_state, connected ? "متصل" : (found ? "موجود" : "ما في جهاز"),
            connected ? UI_TEXT_CYAN : (found ? UI_TEXT_WHITE : UI_TEXT_FAINT));
    set_row(s_pc_name, name, UI_TEXT_MUTED);
    set_row(s_pc_ip, ip, UI_TEXT_MUTED);
}

void ui_menu_set_net(bool online, const char *ssid, const char *ip, int rssi)
{
    static char sig[24];
    if (online) {
        // Bars and the number: the brand shows the figure and its unit.
        int bars = rssi >= -55 ? 4 : rssi >= -67 ? 3 : rssi >= -78 ? 2 : 1;
        static const char *BAR[5] = { "", "|", "||", "|||", "||||" };
        snprintf(sig, sizeof(sig), "%s  %d dBm", BAR[bars], rssi);
    }
    set_row(s_net_state, online ? sig : "مافي إنترنت", online ? UI_TEXT_CYAN : UI_TEXT_FAINT);
    set_row(s_net_ssid, online ? ssid : NULL, UI_TEXT_MUTED);
    set_row(s_net_ip, online ? ip : NULL, UI_TEXT_MUTED);
}
