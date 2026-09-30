// Private to orion_ui. main/ sees only include/orion_ui.h.
#pragma once

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>
#include "esp_err.h"
#include "lvgl.h"
#include "orion_state.h"
#include "orion_ui.h"
#include "ui_tokens.h"

#define UI_W 240
#define UI_H 240

// The one layout. Every y on this screen comes from here, so nothing can
// drift off the bottom.
#define UI_ORB_CX    120
#define UI_ORB_CY    84
#define UI_GUTTER    UI_SPACE_3
#define UI_BTN_SIZE  30
#define UI_BTN_XY    10
// The drawn button is 3 mm across, far smaller than a fingertip. It answers
// to this whole corner square instead, and the glass ignores taps in it.
#define UI_BTN_HIT   72
#define UI_LABEL_Y   146
#define UI_TEXT_Y    164
#define UI_TEXT_H    72   // 164..236, two lines of 22 px Naskh exactly
#define UI_HINT_Y    152
#define UI_HINT_H    80

extern const lv_font_t ui_font_text_22;
extern const lv_font_t ui_font_text_16;
extern const lv_font_t ui_font_mono_12;
extern const lv_font_t ui_font_code_40;
extern const lv_font_t ui_font_wordmark_36;
extern const lv_image_dsc_t ui_img_mark_96;
extern const lv_image_dsc_t ui_img_glow_128;
extern const lv_image_dsc_t ui_img_star_56;
extern const uint8_t ui_img_test_frame[];
extern const size_t ui_img_test_frame_len;

// Display and touch. Returns the LVGL display; indev may be NULL if touch failed.
esp_err_t ui_display_init(lv_display_t **disp, lv_indev_t **indev);
void ui_display_on(void);
uint32_t ui_display_fps(void);
void ui_display_fake_touch(int16_t x, int16_t y, bool pressed);
void ui_display_touch_log(bool on);

// Animation helpers, brand curves and durations.
void ui_anim_to(void *var, lv_anim_exec_xcb_t exec, int32_t from, int32_t to,
                uint32_t ms, uint32_t delay, bool brand_ease, lv_anim_completed_cb_t done);
void ui_anim_loop(void *var, lv_anim_exec_xcb_t exec, int32_t a, int32_t b, uint32_t half_ms);
void ui_anim_spin(void *var, lv_anim_exec_xcb_t exec, int32_t a, int32_t b, uint32_t ms);
void ui_anim_stop(void *var, lv_anim_exec_xcb_t exec);
void ui_fade(lv_obj_t *obj, lv_opa_t to, uint32_t ms, uint32_t delay, lv_anim_completed_cb_t done);
void ui_rise_in(lv_obj_t *obj, uint32_t delay);

// The orb, which carries every state except idle.
void ui_orb_create(lv_obj_t *parent);
void ui_orb_set_state(orion_state_t state);
void ui_orb_set_level(float level);
void ui_orb_reveal_glow(uint32_t delay_ms);

// The star, which carries listening, thinking and speaking.
void ui_star_create(lv_obj_t *parent);
void ui_star_set_state(orion_state_t state);
void ui_star_set_level(float level);

// The idle face: the mark, still, over the breathing glow, plus the hint line.
void ui_idle_create(lv_obj_t *parent);
void ui_idle_show(bool on);
void ui_idle_set_links(bool pc, bool phone);
void ui_idle_set_wake_word(bool on);

// Text under the orb: state label plus transcript or reply.
void ui_text_create(lv_obj_t *parent);
void ui_text_set_label(const char *text);
void ui_text_set(const char *text, bool primary);
void ui_text_clear(void);
void ui_strip_tags(const char *in, char *out, size_t n);

// The menu: its top left button, the panel, and the three cards.
void ui_menu_create(lv_obj_t *parent);
void ui_menu_show(void);
void ui_menu_hide(void);
bool ui_menu_visible(void);
void ui_menu_button_show(bool on);
void ui_menu_set_net(bool online, const char *ssid, const char *ip, int rssi);
void ui_menu_set_pc(bool found, bool connected, const char *name, const char *ip);
void ui_menu_on_pc_refresh(ui_tap_cb_t cb, void *ctx);
void ui_menu_scroll(int32_t y);

// Setup view for Bluetooth Wi-Fi provisioning.
void ui_setup_create(lv_obj_t *parent);
void ui_setup_show(const char *device_name, const char *code);
void ui_setup_status(int status, const char *detail);
void ui_setup_hide(void);
bool ui_setup_visible(void);
void ui_menu_on_wifi_setup(ui_tap_cb_t cb, void *ctx);
void ui_menu_on_reset(ui_tap_cb_t cb, void *ctx);

// Pairing an app over the LAN, ui_pair.c.
void ui_pair_create(lv_obj_t *parent);
void ui_pair_show(const char *code, int seconds);
void ui_pair_hide(void);

// Camera card. It only asks for frames while it is on screen.
void ui_cam_create(lv_obj_t *parent, int32_t w, int32_t pad);
void ui_cam_run(bool on);
void ui_cam_self_test(void);
void ui_cam_set_source(ui_jpeg_get_t get, ui_jpeg_release_t release);
void ui_cam_set_preview(ui_rgb565_get_t get, ui_jpeg_release_t release);
int32_t ui_cam_height(void);

// Boot entrance. Calls done from the LVGL task when the mark has handed over.
void ui_boot_play(lv_obj_t *parent, void (*done)(void));

// Serial console commands, and the hook they use to fake a tap.
esp_err_t ui_register_cmds(void);
void ui_fire_tap(void);
void ui_menu_toggle(void);
void ui_boot_replay(void);

// Brand styling shared by the panel and its cards.
lv_obj_t *ui_card_new(lv_obj_t *parent, int32_t w, int32_t h);
lv_obj_t *ui_mono_label(lv_obj_t *parent, uint32_t color, const char *text);
lv_obj_t *ui_ar_label(lv_obj_t *parent, uint32_t color, const lv_font_t *font, const char *text);
bool ui_is_rtl(const char *text);
lv_obj_t *ui_ghost_button(lv_obj_t *parent, const char *text, lv_event_cb_t cb);

static inline lv_color_t ui_rgb(uint8_t r, uint8_t g, uint8_t b)
{
    return lv_color_make(r, g, b);
}

static inline void ui_no_touch(lv_obj_t *obj)
{
    lv_obj_remove_flag(obj, LV_OBJ_FLAG_CLICKABLE | LV_OBJ_FLAG_SCROLLABLE);
}

static inline bool ui_in_btn_corner(const lv_point_t *p)
{
    return p->x < UI_BTN_HIT && p->y < UI_BTN_HIT;
}

static inline void ui_flat(lv_obj_t *obj)
{
    lv_obj_set_style_bg_opa(obj, LV_OPA_TRANSP, 0);
    lv_obj_set_style_border_width(obj, 0, 0);
    lv_obj_set_style_pad_all(obj, 0, 0);
    lv_obj_set_style_radius(obj, 0, 0);
}
