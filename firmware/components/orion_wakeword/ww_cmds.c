// Console command: ww [stats|start|stop|debug <0|1>|clip|cutoff <0..255>]
#include "orion_wakeword.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "esp_check.h"
#include "esp_console.h"
#include "esp_log.h"
#include "ww_priv.h"

static const char *TAG = "wakeword";

ww_model_t *ww_current_model(void);

static void on_wake(void *ctx)
{
    printf("WAKE_EVENT\n");
}

static int stats(void)
{
    orion_wakeword_stats_t s;
    orion_wakeword_get_stats(&s);
    ww_model_t *m = ww_current_model();
    printf("ww \"%s\" %s, cutoff %u, debug clips %s\n", orion_wakeword_phrase(),
           orion_wakeword_is_running() ? "running" : "stopped", m ? ww_model_cutoff(m) : 0,
           orion_wakeword_debug_clips() ? "on" : "off");
    printf("ww steps %u inferences %u detections %u (last avg %u max %u)\n", (unsigned) s.steps,
           (unsigned) s.inferences, (unsigned) s.detections, s.last_avg_prob, s.last_max_prob);
    printf("ww features %u us/step, invoke %u us avg %u us max, %u us per 10 ms step = %u.%u%% of a core\n",
           (unsigned) s.feature_us_avg, (unsigned) s.invoke_us_avg, (unsigned) s.invoke_us_max,
           (unsigned) orion_wakeword_step_us(), (unsigned) (orion_wakeword_step_us() / 100),
           (unsigned) (orion_wakeword_step_us() / 10 % 10));
    printf("ww arena %u used of %u\n", (unsigned) s.arena_used, (unsigned) s.arena_size);
    float load[2];
    orion_wakeword_cpu_load(1000, load);
    printf("ww cpu load over 1 s: core0 %d%% core1 %d%%\n", (int) (load[0] * 100), (int) (load[1] * 100));
    return 0;
}

static int cmd_ww(int argc, char **argv)
{
    const char *sub = argc > 1 ? argv[1] : "stats";
    if (!strcmp(sub, "stats")) {
        return stats();
    }
    if (!strcmp(sub, "start")) {
        esp_err_t err = orion_wakeword_start(on_wake, NULL);
        printf("ww start: %s\n", esp_err_to_name(err));
        return err == ESP_OK ? 0 : 1;
    }
    if (!strcmp(sub, "stop")) {
        orion_wakeword_stop();
        printf("ww stopped\n");
        return 0;
    }
    if (!strcmp(sub, "debug")) {
        if (argc > 2) {
            orion_wakeword_set_debug_clips(atoi(argv[2]) != 0);
        }
        printf("ww debug clips %s\n", orion_wakeword_debug_clips() ? "on" : "off");
        return 0;
    }
    if (!strcmp(sub, "clip")) {
        esp_err_t err = ww_clip_dump_now(argc > 2 ? argv[2] : "manual");
        printf("ww clip: %s\n", esp_err_to_name(err));
        return err == ESP_OK ? 0 : 1;
    }
    if (!strcmp(sub, "cutoff")) {
        ww_model_t *m = ww_current_model();
        if (argc > 2 && m) {
            ww_model_set_cutoff(m, (uint8_t) atoi(argv[2]));
        }
        printf("ww cutoff %u\n", m ? ww_model_cutoff(m) : 0);
        return 0;
    }
    printf("usage: ww [stats|start|stop|debug <0|1>|clip [name]|cutoff <0..255>]\n");
    return 1;
}

esp_err_t orion_wakeword_register_cmds(void)
{
    const esp_console_cmd_t cmd = {
        .command = "ww",
        .help = "ww [stats|start|stop|debug <0|1>|clip|cutoff <n>]: wake word pipeline",
        .func = cmd_ww,
    };
    ESP_RETURN_ON_ERROR(esp_console_cmd_register(&cmd), TAG, "register ww");
    return ESP_OK;
}
