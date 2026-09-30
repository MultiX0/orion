// The face of the product. main/ calls only include/orion_ui.h; everything
// else here is private. All LVGL work happens under the esp_lvgl_port lock.
#include "orion_ui.h"

#include "freertos/FreeRTOS.h"
#include "freertos/task.h"

#include "esp_check.h"
#include "esp_log.h"
#include "esp_lvgl_port.h"
#include "ui_internal.h"

static const char *TAG = "orion_ui";

// Machine voice: mono, uppercase, the brand's // comment marker. Idle has no
// label; the mark and the Arabic hint carry it instead.
static const char *STATE_LABEL[OS_STATE_COUNT] = {
    [OS_BOOT] = "",
    [OS_IDLE] = "",
    [OS_WAKE] = "// LISTENING",
    [OS_LISTENING] = "// LISTENING",
    [OS_THINKING] = "// THINKING",
    [OS_SPEAKING] = "// SPEAKING",
    [OS_ERROR] = "// ERROR",
    [OS_OFFLINE] = "// OFFLINE",
};

static lv_obj_t *s_screen;
static ui_tap_cb_t s_tap_cb;
static void *s_tap_ctx;
static orion_state_t s_state = OS_BOOT;
static bool s_booting = true;
static bool s_corner_press;

static void on_press(lv_event_t *e)
{
    lv_event_code_t code = lv_event_get_code(e);
    lv_point_t p = { -1, -1 };
    if (lv_indev_active()) {
        lv_indev_get_point(lv_indev_active(), &p);
    }
    if (code == LV_EVENT_PRESSED) {
        s_corner_press = p.x >= 0 && ui_in_btn_corner(&p);
        return;
    }
    if (code == LV_EVENT_LONG_PRESSED) {
        ui_menu_show();
        return;
    }
    // The menu corner never starts a listen, even for a finger that lands
    // there while the button is fading, or slides into it.
    if (s_corner_press || (p.x >= 0 && ui_in_btn_corner(&p))) {
        return;
    }
    if (ui_menu_visible() || ui_setup_visible()) {
        return;
    }
    if (s_tap_cb && !s_booting) {
        s_tap_cb(s_tap_ctx);
    }
}

static void build_screen(void)
{
    s_screen = lv_screen_active();
    lv_obj_set_style_bg_color(s_screen, lv_color_hex(UI_BG_PRIMARY), 0);
    lv_obj_set_style_bg_opa(s_screen, LV_OPA_COVER, 0);
    lv_obj_remove_flag(s_screen, LV_OBJ_FLAG_SCROLLABLE);
    lv_obj_set_style_pad_all(s_screen, 0, 0);

    // Bottom of the stack: the glass itself is the wake button. Everything
    // drawn after this sits on top of it and keeps its own touch behaviour.
    lv_obj_t *glass = lv_obj_create(s_screen);
    lv_obj_set_size(glass, UI_W, UI_H);
    lv_obj_set_pos(glass, 0, 0);
    ui_flat(glass);
    lv_obj_remove_flag(glass, LV_OBJ_FLAG_SCROLLABLE);
    lv_obj_add_flag(glass, LV_OBJ_FLAG_CLICKABLE);
    lv_obj_add_event_cb(glass, on_press, LV_EVENT_PRESSED, NULL);
    lv_obj_add_event_cb(glass, on_press, LV_EVENT_SHORT_CLICKED, NULL);
    lv_obj_add_event_cb(glass, on_press, LV_EVENT_LONG_PRESSED, NULL);

    ui_orb_create(s_screen);
    ui_star_create(s_screen);
    ui_idle_create(s_screen);
    ui_text_create(s_screen);
    ui_menu_create(s_screen);
    ui_setup_create(s_screen);
    ui_pair_create(s_screen);
}

static void boot_done(void)
{
    s_booting = false;
    ui_orb_set_state(OS_IDLE);
    ui_idle_show(true);
    ui_menu_button_show(true);
    s_state = OS_IDLE;
}

esp_err_t ui_init(void)
{
    lv_display_t *disp = NULL;
    lv_indev_t *indev = NULL;
    ESP_RETURN_ON_ERROR(ui_display_init(&disp, &indev), TAG, "display");

    lvgl_port_lock(0);
    build_screen();
    ui_menu_button_show(false);
    ui_boot_play(s_screen, boot_done);
    lvgl_port_unlock();

    // Let the first frame reach the panel before the light comes up, so the
    // user never sees the uninitialised framebuffer.
    vTaskDelay(pdMS_TO_TICKS(60));
    ui_display_on();
    ui_register_cmds();
    ESP_LOGI(TAG, "ready");
    return ESP_OK;
}

void ui_set_state(orion_state_t state)
{
    if (state >= OS_STATE_COUNT || state == s_state) {
        return;
    }
    lvgl_port_lock(0);
    s_state = state;
    ui_idle_show(state == OS_IDLE);
    ui_orb_set_state(state);
    ui_star_set_state(state);
    ui_text_set_label(STATE_LABEL[state]);
    // A new turn starts on a clean line; the reply stays up through idle.
    if (state == OS_WAKE || state == OS_LISTENING) {
        ui_text_clear();
    }
    if (state == OS_IDLE) {
        ui_text_clear();
    }
    if (ui_menu_visible()) {
        ui_menu_hide();
    }
    lvgl_port_unlock();
}

// The mic while listening, Orion's own playback while speaking. Both
// consumers only store the float; the LVGL task reads it on its next tick.
void ui_set_level(float level)
{
    ui_orb_set_level(level);
    ui_star_set_level(level);
}

void ui_set_text(const char *text)
{
    // Every caller goes through here, so no emotion tag can reach the glass.
    static char clean[512];
    ui_strip_tags(text, clean, sizeof(clean));
    lvgl_port_lock(0);
    if (clean[0]) {
        ui_idle_show(false);
    }
    ui_text_set(clean, true);
    lvgl_port_unlock();
}

void ui_on_tap(ui_tap_cb_t cb, void *ctx)
{
    s_tap_cb = cb;
    s_tap_ctx = ctx;
}

void ui_set_net_info(bool online, const char *ssid, const char *ip, int rssi)
{
    lvgl_port_lock(0);
    ui_menu_set_net(online, ssid, ip, rssi);
    lvgl_port_unlock();
}

void ui_set_pc_info(bool found, bool connected, const char *name, const char *ip)
{
    lvgl_port_lock(0);
    ui_menu_set_pc(found, connected, name, ip);
    lvgl_port_unlock();
}

void ui_on_pc_refresh(ui_tap_cb_t cb, void *ctx)
{
    ui_menu_on_pc_refresh(cb, ctx);
}

void ui_show_setup(const char *device_name, const char *code)
{
    lvgl_port_lock(0);
    if (ui_menu_visible()) {
        ui_menu_hide();
    }
    ui_setup_show(device_name, code);
    lvgl_port_unlock();
}

void ui_set_setup_status(int status, const char *detail)
{
    lvgl_port_lock(0);
    ui_setup_status(status, detail);
    lvgl_port_unlock();
}

void ui_hide_setup(void)
{
    lvgl_port_lock(0);
    ui_setup_hide();
    lvgl_port_unlock();
}

void ui_on_wifi_setup(ui_tap_cb_t cb, void *ctx)
{
    ui_menu_on_wifi_setup(cb, ctx);
}

void ui_on_reset(ui_tap_cb_t cb, void *ctx)
{
    ui_menu_on_reset(cb, ctx);
}

void ui_set_links(bool pc, bool phone)
{
    lvgl_port_lock(0);
    ui_idle_set_links(pc, phone);
    lvgl_port_unlock();
}

void ui_set_wake_word(bool on)
{
    lvgl_port_lock(0);
    ui_idle_set_wake_word(on);
    lvgl_port_unlock();
}

void ui_show_pair_code(const char *code, int seconds)
{
    lvgl_port_lock(0);
    if (code && code[0]) {
        if (ui_menu_visible()) {
            ui_menu_hide();
        }
        ui_pair_show(code, seconds);
    } else {
        ui_pair_hide();
    }
    lvgl_port_unlock();
}

void ui_set_camera_source(ui_jpeg_get_t get, ui_jpeg_release_t release)
{
    ui_cam_set_source(get, release);
}

void ui_set_camera_preview(ui_rgb565_get_t get, ui_jpeg_release_t release)
{
    ui_cam_set_preview(get, release);
}

uint32_t ui_fps(void)
{
    return ui_display_fps();
}

void ui_menu_toggle(void)
{
    lvgl_port_lock(0);
    if (ui_menu_visible()) {
        ui_menu_hide();
    } else {
        ui_menu_show();
    }
    lvgl_port_unlock();
}

// Replays the entrance so it can be watched and timed without a reset.
void ui_boot_replay(void)
{
    lvgl_port_lock(0);
    s_booting = true;
    s_state = OS_BOOT;
    ui_idle_show(false);
    ui_orb_set_state(OS_BOOT);
    ui_menu_button_show(false);
    ui_boot_play(s_screen, boot_done);
    lvgl_port_unlock();
}

void ui_fire_tap(void)
{
    if (s_tap_cb) {
        s_tap_cb(s_tap_ctx);
    }
}
