// The speaker pipeline, applied to every sample before the DMA. Three modes:
// raw is the volume alone; clean, the default, adds a steep high pass, 3 dB
// of trim and a look-ahead limiter at -6 dBFS; boost is the full loudness
// chain (high pass, mud cut, presence, treble shelf, make-up gain, limiter at
// -1 dBFS and a sustained power guard) for a strong supply. Everything is
// float until the limiter, so nothing clips inside the chain; the only place
// a sample can hit the rails is the int16 conversion at the end, and
// stats.clipped counts it. 32 kHz mono is little work for the S3.
#include "audio_priv.h"

#include <math.h>
#include <string.h>

// 3 ms of look-ahead at any rate, so the gain is down before a peak arrives.
// A fixed 32 samples is only 1 ms at 32 kHz, and peaks get over the ceiling.
#define LOOKAHEAD_MAX  160
#define LOOKAHEAD_MS   3
#define CEILING        0.891f    // -1 dBFS, the boost chain
// The amp runs off the 3.3 V rail at 9 dB of gain, so it clips its own
// output above about -4 dBFS in, and lower when the rail sags under load.
// Clean speech stays under -6 dBFS: the amp never clips, and never pulls
// the rail down with it.
#define CLEAN_CEILING  0.501f
#define HPF_HZ         300.0f    // bass is what pulls the supply down
#define PRESENCE_HZ    3000.0f
// In the room this speaker puts 2 to 4 kHz 11 dB above 300 Hz to 1 kHz,
// where the source has it 11 dB below. It is bright already, so the lift is
// off by default and adjustable (spk presence <db>).
#define PRESENCE_DB    0.0f      // a lift brings out sibilance and limiter grit
#define PRESENCE_Q     1.0f
// A high shelf over the top of the voice. Sibilance and the limiter's grit
// sit up there and can sound louder than the voice; a gentle cut smooths them.
#define TREBLE_HZ      5000.0f
#define TREBLE_DB      -6.0f
#define ATTACK_S       0.0005f
#define RELEASE_S      0.120f
// TTS arrives at about -9.4 dBFS rms, and dense speech leaves the limiter at
// -9.0 to -9.5 dBFS rms; a limited tone measures -4.2. An expressive voice
// can hold -6 dBFS for 2 s, so a short window with a -6 line would cut the
// speaker out mid sentence. A 4 s window and a line just under the limited
// tone keep speech clear of it while a stuck tone still trips it, after
// about 7 s. Tripped, it turns the sound down by at most 12 dB, never to
// silence.
#define GUARD_ON       0.562f    // -5 dBFS rms, sustained
#define GUARD_OFF      0.355f    // -9 dBFS, where the gain may creep back
#define GUARD_WINDOW_S 4.0f
#define GUARD_MIN_DB   -12.0f
#define GUARD_DROP_DBS 4.0f      // dB per second while tripped
#define GUARD_RISE_DBS 4.0f

typedef struct {
    float b0, b1, b2, a1, a2;
    float z1, z2;
} biquad_t;

// The boost chain (make-up gain, presence, mud cut, treble shelf, limiter,
// guard), only in boost mode. On a laptop's USB port it crackles and resets
// the board on dense phrases, so it is for a strong supply only.
static bool s_on = false;

// The default. The speaker (8 ohm, 0.7 W, resonance near 950 Hz) makes little
// sound below its resonance, yet most of a voice's electrical power sits
// there: it only heats the amp and draws the rail down. A 4th order
// high pass (two Butterworth stages) at 350 Hz takes it out with almost no
// audible change. The top is left alone: cutting it makes the voice sound
// like a radio.
#define CLEAN_HPF_HZ    350.0f
#define CLEAN_TRIM_DB   -3.0f
static audio_dsp_mode_t s_mode = AUDIO_DSP_CLEAN;
static float s_clean_hpf_hz = CLEAN_HPF_HZ;
static float s_clean_trim;
// Boost make-up gain in dB. At 12, a dense phrase at volume 100 pulls the
// USB supply down under the amp and resets the board; short of a reset the
// sag is heard as a crackle and a swallowed syllable. 8 and 9 are borderline:
// most dense phrases play, the odd one still resets. 5, with the gentler EQ
// below, keeps the limiter and the supply out of it.
static float s_makeup_db = 5.0f;
static float s_presence_db = PRESENCE_DB;
static float s_hpf_hz = HPF_HZ;
// A small box speaker blooms around 300 to 500 Hz and smears a soft voice.
// A peaking cut there, -4 dB by default (spk mud <db>).
#define MUD_HZ 400.0f
#define MUD_Q  1.0f
static float s_mud_db = -4.0f;
static float s_volume = 1.0f;
static uint32_t s_rate = 16000;

static float s_treble_db = TREBLE_DB;
static biquad_t s_hpf, s_presence, s_mud, s_treble;
static biquad_t s_clean_hpf, s_clean_hpf2;
static int s_look = 32;
static float s_ceiling = CEILING;
static float s_att, s_rel;
static float s_lim_gain = 1.0f;
static float s_ring[LOOKAHEAD_MAX];
static int s_ring_pos;
static float s_guard_db;
static float s_power_avg;
static float s_power_coef;

static audio_dsp_stats_t s_stats;

static float biquad_run(biquad_t *f, float x)
{
    // Transposed direct form II.
    float y = f->b0 * x + f->z1;
    f->z1 = f->b1 * x - f->a1 * y + f->z2;
    f->z2 = f->b2 * x - f->a2 * y;
    return y;
}

static void biquad_hpf(biquad_t *f, float hz, float q, float rate)
{
    float w0 = 2.0f * (float) M_PI * hz / rate;
    float c = cosf(w0), s = sinf(w0);
    float alpha = s / (2.0f * q);
    float a0 = 1.0f + alpha;
    f->b0 = (1.0f + c) / 2.0f / a0;
    f->b1 = -(1.0f + c) / a0;
    f->b2 = f->b0;
    f->a1 = -2.0f * c / a0;
    f->a2 = (1.0f - alpha) / a0;
    f->z1 = f->z2 = 0;
}

static void biquad_peak(biquad_t *f, float hz, float q, float db, float rate)
{
    float A = powf(10.0f, db / 40.0f);
    float w0 = 2.0f * (float) M_PI * hz / rate;
    float c = cosf(w0), s = sinf(w0);
    float alpha = s / (2.0f * q);
    float a0 = 1.0f + alpha / A;
    f->b0 = (1.0f + alpha * A) / a0;
    f->b1 = -2.0f * c / a0;
    f->b2 = (1.0f - alpha * A) / a0;
    f->a1 = -2.0f * c / a0;
    f->a2 = (1.0f - alpha / A) / a0;
    f->z1 = f->z2 = 0;
}

// RBJ high shelf, slope 1.
static void biquad_high_shelf(biquad_t *f, float hz, float db, float rate)
{
    float A = powf(10.0f, db / 40.0f);
    float w0 = 2.0f * (float) M_PI * hz / rate;
    float c = cosf(w0), s = sinf(w0);
    float alpha = s / 2.0f * sqrtf(2.0f);
    float sa = 2.0f * sqrtf(A) * alpha;
    float a0 = (A + 1.0f) - (A - 1.0f) * c + sa;
    f->b0 = A * ((A + 1.0f) + (A - 1.0f) * c + sa) / a0;
    f->b1 = -2.0f * A * ((A - 1.0f) + (A + 1.0f) * c) / a0;
    f->b2 = A * ((A + 1.0f) + (A - 1.0f) * c - sa) / a0;
    f->a1 = 2.0f * ((A - 1.0f) - (A + 1.0f) * c) / a0;
    f->a2 = ((A + 1.0f) - (A - 1.0f) * c - sa) / a0;
    f->z1 = f->z2 = 0;
}

void audio_dsp_begin(uint32_t rate, float volume)
{
    s_rate = rate;
    s_volume = volume;
    biquad_hpf(&s_hpf, s_hpf_hz, 0.7071f, (float) rate);
    biquad_peak(&s_mud, MUD_HZ, MUD_Q, s_mud_db, (float) rate);
    biquad_peak(&s_presence, PRESENCE_HZ, PRESENCE_Q, s_presence_db, (float) rate);
    // Above a third of the rate the shelf has nothing left to shape.
    const float treble_hz = TREBLE_HZ < rate / 3.0f ? TREBLE_HZ : rate / 3.0f;
    biquad_high_shelf(&s_treble, treble_hz, s_treble_db, (float) rate);
    biquad_hpf(&s_clean_hpf, s_clean_hpf_hz, 0.7071f, (float) rate);
    biquad_hpf(&s_clean_hpf2, s_clean_hpf_hz, 0.7071f, (float) rate);
    s_clean_trim = powf(10.0f, CLEAN_TRIM_DB / 20.0f);
    s_look = (int) (rate * LOOKAHEAD_MS / 1000);
    s_look = s_look < 16 ? 16 : (s_look > LOOKAHEAD_MAX ? LOOKAHEAD_MAX : s_look);
    s_ceiling = s_mode == AUDIO_DSP_CLEAN ? CLEAN_CEILING : CEILING;
    s_att = 1.0f - expf(-1.0f / (ATTACK_S * rate));
    s_rel = 1.0f - expf(-1.0f / (RELEASE_S * rate));
    s_power_coef = 1.0f / (GUARD_WINDOW_S * rate);
    s_lim_gain = 1.0f;
    memset(s_ring, 0, sizeof(s_ring));
    s_ring_pos = 0;
    // The guard carries across streams on purpose: a broken TTS loop is many
    // short plays. The power average and the stats start fresh.
    s_power_avg = 0;
    memset(&s_stats, 0, sizeof(s_stats));
    s_stats.min_lim_gain = 1.0f;
    s_stats.min_guard_db = s_guard_db;
}

static void guard_update(float out)
{
    s_power_avg += (out * out - s_power_avg) * s_power_coef;
    if (s_power_avg > GUARD_ON * GUARD_ON) {
        s_guard_db -= GUARD_DROP_DBS / s_rate;
        if (s_guard_db < GUARD_MIN_DB) {
            s_guard_db = GUARD_MIN_DB;
        }
        s_stats.guard_trips++;
    } else if (s_power_avg < GUARD_OFF * GUARD_OFF && s_guard_db < 0) {
        s_guard_db += GUARD_RISE_DBS / s_rate;
        if (s_guard_db > 0) {
            s_guard_db = 0;
        }
    }
    if (s_guard_db < s_stats.min_guard_db) {
        s_stats.min_guard_db = s_guard_db;
    }
}

// Pushes one sample through the look-ahead limiter, returns the delayed one.
static float limit(float x)
{
    s_ring[s_ring_pos] = x;
    s_ring_pos = (s_ring_pos + 1) % s_look;
    float oldest = s_ring[s_ring_pos];

    float peak = 0;
    for (int i = 0; i < s_look; i++) {
        float a = fabsf(s_ring[i]);
        peak = a > peak ? a : peak;
    }
    float target = peak > s_ceiling ? s_ceiling / peak : 1.0f;
    s_lim_gain += (target - s_lim_gain) * (target < s_lim_gain ? s_att : s_rel);
    if (s_lim_gain < s_stats.min_lim_gain) {
        s_stats.min_lim_gain = s_lim_gain;
    }
    return oldest * s_lim_gain;
}

void audio_dsp_process(const int16_t *in, int16_t *out, size_t n)
{
    float makeup = powf(10.0f, (s_makeup_db + s_guard_db) / 20.0f);
    for (size_t i = 0; i < n; i++) {
        float x = in[i] / 32768.0f;
        float ax = fabsf(x);
        s_stats.in_peak = ax > s_stats.in_peak ? ax : s_stats.in_peak;
        s_stats.in_sq += x * x;

        float y = x * s_volume;
        if (s_mode == AUDIO_DSP_CLEAN) {
            y = biquad_run(&s_clean_hpf, y * s_clean_trim);
            y = biquad_run(&s_clean_hpf2, y);
            y = limit(y);
        } else if (s_on) {
            y = biquad_run(&s_hpf, y);
            y = biquad_run(&s_mud, y);
            y = biquad_run(&s_presence, y);
            y = biquad_run(&s_treble, y);
            y = limit(y * makeup);
            guard_update(y);
        }
        float ay = fabsf(y);
        s_stats.out_peak = ay > s_stats.out_peak ? ay : s_stats.out_peak;
        s_stats.out_sq += y * y;
        s_stats.samples++;

        int32_t v = (int32_t) lrintf(y * 32767.0f);
        if (v > 32767 || v < -32767) {
            s_stats.clipped++;
            v = v > 0 ? 32767 : -32767;
        }
        out[i] = (int16_t) v;
    }
}

size_t audio_dsp_latency(void)
{
    return s_mode == AUDIO_DSP_RAW ? 0 : (size_t) s_look;
}

// `spk boost on|off`: on is the boost mode, off is raw.
void audio_dsp_set_enabled(bool on)
{
    audio_dsp_set_mode(on ? AUDIO_DSP_BOOST : AUDIO_DSP_RAW);
}

bool audio_dsp_enabled(void)
{
    return s_mode == AUDIO_DSP_BOOST;
}

void audio_dsp_set_mode(audio_dsp_mode_t mode)
{
    s_mode = mode;
    s_on = mode == AUDIO_DSP_BOOST;
}

audio_dsp_mode_t audio_dsp_mode(void)
{
    return s_mode;
}

void audio_dsp_set_makeup_db(float db)
{
    s_makeup_db = db < 0 ? 0 : (db > 24 ? 24 : db);
}

float audio_dsp_makeup_db(void)
{
    return s_makeup_db;
}

void audio_dsp_set_presence_db(float db)
{
    s_presence_db = db < -6 ? -6 : (db > 6 ? 6 : db);
}

float audio_dsp_presence_db(void)
{
    return s_presence_db;
}

void audio_dsp_set_treble_db(float db)
{
    s_treble_db = db < -12 ? -12 : (db > 6 ? 6 : db);
}

float audio_dsp_treble_db(void)
{
    return s_treble_db;
}

float audio_dsp_guard_db(void)
{
    return s_guard_db;
}

void audio_dsp_get_stats(audio_dsp_stats_t *out)
{
    *out = s_stats;
}

void audio_dsp_set_hpf_hz(float hz)
{
    s_hpf_hz = hz < 60 ? 60 : (hz > 500 ? 500 : hz);
    s_clean_hpf_hz = s_hpf_hz;    // the clean mode's cut follows too
}

float audio_dsp_hpf_hz(void)
{
    return s_hpf_hz;
}

void audio_dsp_set_mud_db(float db)
{
    s_mud_db = db < -9 ? -9 : (db > 0 ? 0 : db);
}

float audio_dsp_mud_db(void)
{
    return s_mud_db;
}