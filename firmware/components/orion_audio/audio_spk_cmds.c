// Console command: spk [stats|boost on|off|gain <db>|presence <db>|slots left|both]
// "stats" reports the last stream through the pipeline in dBFS, so two
// settings can be compared on the same clip.
#include "orion_audio.h"

#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "audio_priv.h"
#include "esp_check.h"
#include "esp_console.h"

static const char *TAG = "spk";

static float dbfs(double v)
{
    return v > 0 ? (float) (20.0 * log10(v)) : -99.0f;
}

static int stats(void)
{
    audio_dsp_stats_t s;
    audio_dsp_get_stats(&s);
    static const char *const modes[] = { "raw", "clean", "boost" };
    printf("spk mode %s, make-up %.1f dB, guard %.1f dB, volume %u, slots %s%s\n",
           modes[audio_dsp_mode()], audio_dsp_makeup_db(), audio_dsp_guard_db(),
           orion_audio_get_volume(), audio_spk_both_slots() ? "both" : "left",
           audio_spk_silent() ? ", silent" : "");
    if (s.samples == 0) {
        printf("spk stats: nothing played yet\n");
        return 0;
    }
    double in_rms = sqrt(s.in_sq / s.samples);
    double out_rms = sqrt(s.out_sq / s.samples);
    printf("spk last stream: %u samples (%u ms)\n", (unsigned) s.samples,
           (unsigned) (s.samples * 1000 / ORION_AUDIO_SAMPLE_RATE));
    printf("spk in   peak %6.1f dBFS  rms %6.1f dBFS\n", dbfs(s.in_peak), dbfs(in_rms));
    printf("spk out  peak %6.1f dBFS  rms %6.1f dBFS  gained %+.1f dB rms\n", dbfs(s.out_peak), dbfs(out_rms),
           dbfs(out_rms) - dbfs(in_rms));
    printf("spk limiter deepest %.1f dB, clipped samples %u, guard min %.1f dB, guard tripped %u ms\n",
           dbfs(s.min_lim_gain), (unsigned) s.clipped, s.min_guard_db,
           (unsigned) (s.guard_trips * 1000 / ORION_AUDIO_SAMPLE_RATE));
    return 0;
}

static int cmd_spk(int argc, char **argv)
{
    const char *sub = argc > 1 ? argv[1] : "stats";
    if (!strcmp(sub, "stats")) {
        return stats();
    }
    if (!strcmp(sub, "mode")) {
        if (argc > 2) {
            const char *m = argv[2];
            audio_dsp_set_mode(!strcmp(m, "raw") ? AUDIO_DSP_RAW
                               : !strcmp(m, "boost") ? AUDIO_DSP_BOOST : AUDIO_DSP_CLEAN);
        }
        static const char *const names[] = { "raw", "clean", "boost" };
        printf("spk mode %s\n", names[audio_dsp_mode()]);
        return 0;
    }
    if (!strcmp(sub, "silent")) {
        if (argc > 2) {
            audio_spk_set_silent(!strcmp(argv[2], "on") || !strcmp(argv[2], "1"));
        }
        printf("spk silent %s\n", audio_spk_silent() ? "on" : "off");
        return 0;
    }
    if (!strcmp(sub, "capture")) {
        const bool on = argc > 2 && (!strcmp(argv[2], "on") || !strcmp(argv[2], "1"));
        esp_err_t err = audio_spk_set_capture(on);
        printf("spk capture %s%s\n", on ? "on" : "off", err == ESP_OK ? "" : " (no memory)");
        return err == ESP_OK ? 0 : 1;
    }
    if (!strcmp(sub, "dump")) {
        audio_spk_dump();
        return 0;
    }
    if (!strcmp(sub, "boost")) {
        if (argc > 2) {
            audio_dsp_set_enabled(!strcmp(argv[2], "on") || !strcmp(argv[2], "1"));
        }
        printf("spk boost %s\n", audio_dsp_enabled() ? "on" : "off");
        return 0;
    }
    if (!strcmp(sub, "gain")) {
        if (argc > 2) {
            audio_dsp_set_makeup_db(strtof(argv[2], NULL));
        }
        printf("spk make-up gain %.1f dB\n", audio_dsp_makeup_db());
        return 0;
    }
    if (!strcmp(sub, "treble")) {
        if (argc > 2) {
            audio_dsp_set_treble_db(strtof(argv[2], NULL));
        }
        printf("spk treble %.1f dB above 5 kHz\n", audio_dsp_treble_db());
        return 0;
    }
    if (!strcmp(sub, "presence")) {
        if (argc > 2) {
            audio_dsp_set_presence_db(strtof(argv[2], NULL));
        }
        printf("spk presence %.1f dB at 3 kHz\n", audio_dsp_presence_db());
        return 0;
    }
    if (!strcmp(sub, "hpf")) {
        if (argc > 2) {
            audio_dsp_set_hpf_hz(strtof(argv[2], NULL));
        }
        printf("spk high pass %.0f Hz\n", audio_dsp_hpf_hz());
        return 0;
    }
    if (!strcmp(sub, "mud")) {
        if (argc > 2) {
            audio_dsp_set_mud_db(strtof(argv[2], NULL));
        }
        printf("spk mud cut %.1f dB at 400 Hz\n", audio_dsp_mud_db());
        return 0;
    }
    if (!strcmp(sub, "slots")) {
        if (argc > 2) {
            esp_err_t err = audio_spk_set_both_slots(!strcmp(argv[2], "both"));
            if (err != ESP_OK) {
                printf("spk slots: %s\n", esp_err_to_name(err));
                return 1;
            }
        }
        printf("spk slots %s\n", audio_spk_both_slots() ? "both" : "left");
        return 0;
    }
    printf("usage: spk [stats|mode raw|clean|boost|silent on|off|capture on|off|dump|boost on|off|"
           "gain <db>|presence <db>|treble <db>|hpf <hz>|mud <db>|slots left|both]\n");
    return 1;
}

esp_err_t audio_spk_register_cmd(void)
{
    const esp_console_cmd_t cmd = {
        .command = "spk",
        .help = "spk [stats|boost on|off|gain <db>|presence <db>|slots left|both]: loudness pipeline",
        .func = cmd_spk,
    };
    ESP_RETURN_ON_ERROR(esp_console_cmd_register(&cmd), TAG, "register spk");
    return ESP_OK;
}
