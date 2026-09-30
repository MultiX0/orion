// Boot: the mark surfaces out of the dark with the brand's scaleIn, the
// wordmark and tagline rise under it on the stagger ladder, then the mark
// folds into the orb. 1.7 s from black to the first state.
#include "ui_internal.h"

#include "esp_log.h"
#include "esp_timer.h"

#define BOOT_OUTRO_AT_MS 1300
#define MARK_SIZE        96

static lv_obj_t *s_mark;
static lv_obj_t *s_word;
static lv_obj_t *s_eyebrow;
static void (*s_done)(void);
static int64_t s_t0;

static void exec_scale(void *obj, int32_t v)
{
    lv_image_set_scale(obj, v);
}

static void exec_image_opa(void *obj, int32_t v)
{
    lv_obj_set_style_image_opa(obj, (lv_opa_t) v, 0);
}

static void finish(lv_anim_t *a)
{
    (void) a;
    lv_obj_delete(s_mark);
    lv_obj_delete(s_word);
    lv_obj_delete(s_eyebrow);
    s_mark = s_word = s_eyebrow = NULL;
    ESP_LOGI("orion_ui", "boot screen %d ms, handed over at uptime %d ms",
             (int) ((esp_timer_get_time() - s_t0) / 1000),
             (int) (esp_timer_get_time() / 1000));
    if (s_done) {
        s_done();
    }
}

static void outro(lv_timer_t *t)
{
    lv_timer_delete(t);
    ui_anim_to(s_mark, exec_scale, LV_SCALE_NONE, LV_SCALE_NONE / 2, UI_DUR_MED, 0, false, finish);
    ui_anim_to(s_mark, exec_image_opa, LV_OPA_COVER, LV_OPA_TRANSP, UI_DUR_MED, 0, false, NULL);
    ui_fade(s_word, LV_OPA_TRANSP, UI_DUR_MED, 0, NULL);
    ui_fade(s_eyebrow, LV_OPA_TRANSP, UI_DUR_MED, 0, NULL);
}

void ui_boot_play(lv_obj_t *parent, void (*done)(void))
{
    s_done = done;
    s_t0 = esp_timer_get_time();

    s_mark = lv_image_create(parent);
    ui_no_touch(s_mark);
    lv_image_set_src(s_mark, &ui_img_mark_96);
    lv_obj_set_pos(s_mark, UI_ORB_CX - MARK_SIZE / 2, UI_ORB_CY - MARK_SIZE / 2);
    lv_obj_set_style_image_recolor(s_mark, lv_color_hex(UI_TEXT_WHITE), 0);
    lv_obj_set_style_image_recolor_opa(s_mark, LV_OPA_COVER, 0);
    lv_obj_set_style_image_opa(s_mark, LV_OPA_TRANSP, 0);
    // scaleIn: 0.97 to 1 with a fade, 0.8 s
    lv_image_set_scale(s_mark, 248);
    ui_anim_to(s_mark, exec_scale, 248, LV_SCALE_NONE, 800, 0, false, NULL);
    ui_anim_to(s_mark, exec_image_opa, LV_OPA_TRANSP, LV_OPA_COVER, 800, 0, false, NULL);

    ui_orb_reveal_glow(150);

    s_word = lv_label_create(parent);
    ui_no_touch(s_word);
    lv_obj_set_style_text_font(s_word, &ui_font_wordmark_36, 0);
    lv_obj_set_style_text_color(s_word, lv_color_hex(UI_TEXT_WHITE), 0);
    lv_obj_set_style_text_letter_space(s_word, -1, 0); // display tracking, -0.025em
    lv_label_set_text(s_word, "Orion");
    lv_obj_set_width(s_word, UI_W);
    lv_obj_set_style_text_align(s_word, LV_TEXT_ALIGN_CENTER, 0);
    lv_obj_set_pos(s_word, 0, UI_ORB_CY + MARK_SIZE / 2 + UI_SPACE_3);
    ui_rise_in(s_word, 300);

    s_eyebrow = lv_label_create(parent);
    ui_no_touch(s_eyebrow);
    lv_obj_set_style_text_font(s_eyebrow, &ui_font_mono_12, 0);
    lv_obj_set_style_text_color(s_eyebrow, lv_color_hex(UI_TEXT_CYANSOFT), 0);
    lv_obj_set_style_text_letter_space(s_eyebrow, 2, 0);
    lv_label_set_text(s_eyebrow, "SEEK THE UNDISCOVERED");
    lv_obj_set_width(s_eyebrow, UI_W);
    lv_obj_set_style_text_align(s_eyebrow, LV_TEXT_ALIGN_CENTER, 0);
    lv_obj_set_pos(s_eyebrow, 0, UI_TEXT_Y + UI_SPACE_4);
    ui_rise_in(s_eyebrow, 500);

    lv_timer_create(outro, BOOT_OUTRO_AT_MS, NULL);
}
