// KEY1 on GPIO 17, polled every 10 ms from esp_timer. Three agreeing samples
// change the state, 700 ms held fires LONG once, a release before that is SHORT.
#include "board.h"

#include "board_pins.h"
#include "board_priv.h"
#include "driver/gpio.h"
#include "esp_check.h"
#include "esp_log.h"
#include "esp_timer.h"

static const char *TAG = "button";

#define POLL_MS      10
#define DEBOUNCE     3
#define LONG_MS      700

static esp_timer_handle_t s_timer;
static board_btn_cb_t s_cb;
static void *s_ctx;

static bool s_pressed;
static int s_stable;
static uint32_t s_held_ms;
static bool s_long_fired;

static void emit(board_btn_event_t ev)
{
    if (s_cb) {
        s_cb(ev, s_ctx);
    }
}

static void poll(void *arg)
{
    bool raw = gpio_get_level(BOARD_BUTTON) == BOARD_BUTTON_ACTIVE;

    if (raw == s_pressed) {
        s_stable = 0;
    } else if (++s_stable >= DEBOUNCE) {
        s_stable = 0;
        s_pressed = raw;
        if (raw) {
            s_held_ms = 0;
            s_long_fired = false;
        } else if (!s_long_fired) {
            emit(BOARD_BTN_SHORT);
        }
    }

    if (s_pressed && !s_long_fired) {
        s_held_ms += POLL_MS;
        if (s_held_ms >= LONG_MS) {
            s_long_fired = true;
            emit(BOARD_BTN_LONG);
        }
    }
}

esp_err_t board_button_init(void)
{
    gpio_config_t cfg = {
        .pin_bit_mask = 1ULL << BOARD_BUTTON,
        .mode = GPIO_MODE_INPUT,
        .pull_up_en = GPIO_PULLUP_ENABLE,
    };
    ESP_RETURN_ON_ERROR(gpio_config(&cfg), TAG, "gpio");

    esp_timer_create_args_t args = {
        .callback = poll,
        .name = "button",
        .dispatch_method = ESP_TIMER_TASK,
    };
    ESP_RETURN_ON_ERROR(esp_timer_create(&args, &s_timer), TAG, "timer");
    ESP_RETURN_ON_ERROR(esp_timer_start_periodic(s_timer, POLL_MS * 1000), TAG, "start");
    ESP_LOGI(TAG, "gpio %d, idle level %d", BOARD_BUTTON, gpio_get_level(BOARD_BUTTON));
    return ESP_OK;
}

esp_err_t board_button_register(board_btn_cb_t cb, void *ctx)
{
    s_cb = cb;
    s_ctx = ctx;
    return ESP_OK;
}
