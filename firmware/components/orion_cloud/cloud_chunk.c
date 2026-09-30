// Cuts the streaming reply into pieces the TTS can start on before the model
// has finished. The rules, and the cases that prove them, are in
// tools/cloud/chunker.py and chunker_test.py; this is the same logic in C, and
// the cloud_selftest console command runs the same cases on the board.
//
// Why the rules are what they are:
//   - The first piece goes at the first clause of FIRST_MIN speakable
//     characters, because it decides when Orion starts talking.
//   - Later pieces wait for a full sentence of LATER_MIN: every join between
//     two TTS requests is a place a gap can happen, so there are few of them.
//   - Never cut inside a [tag], and a tag after a cut travels with the words
//     after it. A cut at a comma carries that sentence's tags into the next
//     piece, since a tag only colours the request it is in.
//   - A sound cue right after a sentence end, "you did it! [laugh]", stays
//     with that sentence. Sent forward it was lost at the end of a reply.
//     Cues are free text on Fish S2, so nothing here knows a fixed list.
//   - "." ends a sentence only when whitespace follows, so 3.5 stays whole.
//   - A model's own control token that leaks into the text, "<turn|>" from
//     Gemma, "<|im_end|>", is dropped: the voice read it out.

#include "cloud_chunk.h"

#include <ctype.h>
#include <string.h>

#define FIRST_MIN 15
#define LATER_MIN 40

// UTF-8 code point at s, and its length in bytes.
static uint32_t utf8_at(const char *s, size_t *len)
{
    const uint8_t *u = (const uint8_t *) s;
    if (u[0] < 0x80) { *len = 1; return u[0]; }
    if ((u[0] & 0xE0) == 0xC0 && u[1]) { *len = 2; return ((u[0] & 0x1F) << 6) | (u[1] & 0x3F); }
    if ((u[0] & 0xF0) == 0xE0 && u[1] && u[2]) {
        *len = 3;
        return ((u[0] & 0x0F) << 12) | ((u[1] & 0x3F) << 6) | (u[2] & 0x3F);
    }
    if ((u[0] & 0xF8) == 0xF0 && u[1] && u[2] && u[3]) {
        *len = 4;
        return ((u[0] & 0x07) << 18) | ((u[1] & 0x3F) << 12) | ((u[2] & 0x3F) << 6) | (u[3] & 0x3F);
    }
    *len = 1;
    return 0xFFFD;
}

static bool is_sentence_end(uint32_t cp)
{
    return cp == '.' || cp == '?' || cp == '!' || cp == '\n' || cp == 0x061F;
}

static bool is_clause_end(uint32_t cp)
{
    return cp == ',' || cp == ';' || cp == ':' || cp == 0x060C || cp == 0x061B;
}

// What a listener would hear. Arabic punctuation, harakat and tatweel are not
// letters; everything else outside ASCII in a reply is.
static bool is_speakable(uint32_t cp)
{
    if (cp < 0x80) {
        return isalnum((int) cp) != 0;
    }
    if (cp == 0x060C || cp == 0x061B || cp == 0x061F || cp == 0x06D4 || cp == 0x0640) {
        return false;
    }
    if ((cp >= 0x064B && cp <= 0x065F) || cp == 0x0670) {
        return false;
    }
    return cp != 0xFFFD;
}

// Speakable characters in s[0..n), not counting anything inside [tags].
static size_t speakable(const char *s, size_t n)
{
    size_t count = 0;
    int depth = 0;
    for (size_t i = 0; i < n;) {
        size_t len;
        uint32_t cp = utf8_at(s + i, &len);
        if (cp == '[') depth++;
        else if (cp == ']') depth = depth ? depth - 1 : 0;
        else if (!depth && is_speakable(cp)) count++;
        i += len;
    }
    return count;
}

void chunker_init(cloud_chunker_t *c, char *storage, size_t cap)
{
    c->buf = storage;
    c->cap = cap;
    c->len = 0;
    c->emitted = 0;
    c->carry[0] = '\0';
    if (cap) storage[0] = '\0';
}

void chunker_feed(cloud_chunker_t *c, const char *delta)
{
    size_t n = strlen(delta);
    if (c->len + n + 1 > c->cap) {
        n = c->cap - c->len - 1;     // a reply longer than the buffer is cut short
    }
    memcpy(c->buf + c->len, delta, n);
    c->len += n;
    c->buf[c->len] = '\0';
}

// A tag that is a sound, not a mood: [chuckling], [sigh]. It belongs where it
// was written. Carried into the next piece like a mood, the laugh is heard
// twice: "[chuckling] That is a classic excuse," then "[chuckling] but I
// believe you."
static bool is_sound_tag(const char *tag, size_t n)
{
    static const char *const sounds[] = {
        "laugh", "chuckl", "giggl", "sigh", "gasp", "breath", "inhale", "exhale",
        "cough", "throat", "pause", "break", "sob", "cry", "yawn", "groan", "pant",
        "snor", "sniff",
    };
    char low[48];
    if (n >= sizeof(low)) n = sizeof(low) - 1;
    for (size_t i = 0; i < n; i++) low[i] = (char) tolower((unsigned char) tag[i]);
    low[n] = '\0';
    for (size_t i = 0; i < sizeof(sounds) / sizeof(sounds[0]); i++) {
        if (strstr(low, sounds[i])) return true;
    }
    return false;
}

// Where a cut at a sentence end that finishes at `at` really goes: past a sound
// cue that follows it, so the laugh stays with what it laughs at. 0 while
// that cannot be told yet: nothing after the end so far, or a cue not closed.
#define CUE_MAX 48
static size_t past_sound_cue(const cloud_chunker_t *c, size_t at)
{
    size_t j = at;
    while (j < c->len && isspace((unsigned char) c->buf[j])) j++;
    if (j >= c->len) return 0;
    if (c->buf[j] != '[') return at;
    const char *end = memchr(c->buf + j, ']', c->len - j);
    if (!end) return (c->len - j) < CUE_MAX ? 0 : at;
    const size_t n = (size_t) (end - (c->buf + j)) + 1;
    return is_sound_tag(c->buf + j, n) ? j + n : at;
}

// Index just past the boundary to cut at, or 0 for "not yet".
static size_t cut_point(const cloud_chunker_t *c)
{
    const size_t want = c->emitted ? LATER_MIN : FIRST_MIN;
    int depth = 0;
    for (size_t i = 0; i < c->len;) {
        size_t len;
        uint32_t cp = utf8_at(c->buf + i, &len);
        if (cp == '[') depth++;
        else if (cp == ']') depth = depth ? depth - 1 : 0;
        const bool boundary = !depth &&
            (is_sentence_end(cp) || (!c->emitted && is_clause_end(cp)));
        if (boundary && cp == '.') {
            // The next character decides whether this is 3.5 or a full stop.
            if (i + 1 >= c->len || !isspace((unsigned char) c->buf[i + 1])) {
                i += len;
                continue;
            }
        }
        if (boundary && speakable(c->buf, i + len) >= want) {
            return is_sentence_end(cp) ? past_sound_cue(c, i + len) : i + len;
        }
        i += len;
    }
    return 0;
}

// The run of [tags] at the start of text, whitespace ignored, into out.
static void leading_tags(const char *text, char *out, size_t out_len)
{
    out[0] = '\0';
    const char *p = text;
    while (*p) {
        while (*p && isspace((unsigned char) *p)) p++;
        if (*p != '[') break;
        const char *end = strchr(p, ']');
        if (!end) break;
        size_t n = (size_t) (end - p + 1);
        size_t have = strlen(out);
        if (!is_sound_tag(p, n)) {
            if (have + n + 1 > out_len) break;
            memcpy(out + have, p, n);
            out[have + n] = '\0';
        }
        p = end + 1;
    }
}

// The last code point of s, ignoring trailing whitespace.
static uint32_t last_cp(const char *s)
{
    size_t n = strlen(s);
    while (n && isspace((unsigned char) s[n - 1])) n--;
    if (!n) return 0;
    size_t start = n - 1;
    // Step back over continuation bytes, 10xxxxxx, to the lead byte.
    while (start && ((unsigned char) s[start] & 0xC0) == 0x80) start--;
    size_t len;
    return utf8_at(s + start, &len);
}

static void trim_copy(char *out, size_t out_len, const char *s, size_t n)
{
    while (n && isspace((unsigned char) *s)) { s++; n--; }
    while (n && isspace((unsigned char) s[n - 1])) n--;
    if (n >= out_len) n = out_len - 1;
    memcpy(out, s, n);
    out[n] = '\0';
}

// Removes <word> tokens (letters, _, | and / inside, up to 24) in place, and
// the space they leave at the end. A reply never has markup of its own.
// Korean, Chinese and Japanese letters the model sometimes slips into a reply
// ("어느" once in about 80 stories). The voice has nothing sensible to say for
// them, so they go, and a doubled space left behind goes with them.
static void drop_foreign(char *s)
{
    char *w = s;
    for (const char *r = s; *r;) {
        size_t len;
        const uint32_t cp = utf8_at(r, &len);
        const bool cjk = (cp >= 0x1100 && cp <= 0x11FF) || (cp >= 0x3000 && cp <= 0x9FFF) ||
                         (cp >= 0xAC00 && cp <= 0xD7AF) || (cp >= 0xF900 && cp <= 0xFAFF);
        if (!cjk) {
            memmove(w, r, len);
            w += len;
        }
        r += len;
    }
    *w = '\0';
    w = s;
    for (const char *r = s; *r; r++) {
        if (*r == ' ' && w > s && w[-1] == ' ') continue;
        *w++ = *r;
    }
    *w = '\0';
}

static void drop_model_tokens(char *s)
{
    char *w = s;
    for (const char *r = s; *r;) {
        if (*r == '<') {
            size_t k = 1;
            while (k <= 24 && (isalpha((unsigned char) r[k]) || r[k] == '_' ||
                               r[k] == '|' || r[k] == '/')) {
                k++;
            }
            if (k > 1 && r[k] == '>') {
                r += k + 1;
                continue;
            }
        }
        *w++ = *r++;
    }
    while (w > s && isspace((unsigned char) w[-1])) w--;
    *w = '\0';
}

// Builds the piece from buf[0..n) with the carry in front. False if it holds
// nothing a listener would hear.
static bool emit(cloud_chunker_t *c, size_t n, char *out, size_t out_len)
{
    // Written straight into out, carry first, so no second 1 KB copy sits on
    // the caller's stack. piece points at the part that came from the stream.
    size_t pre = 0;
    if (c->carry[0]) {
        pre = (size_t) snprintf(out, out_len, "%s ", c->carry);
        if (pre >= out_len) pre = out_len - 1;
    }
    char *piece = out + pre;
    trim_copy(piece, out_len - pre, c->buf, n);
    drop_model_tokens(piece);
    drop_foreign(piece);

    // Did the cut land mid sentence? Then that sentence's tone goes along.
    char carried[sizeof(c->carry)];
    strlcpy(carried, c->carry, sizeof(carried));
    c->carry[0] = '\0';
    if (is_clause_end(last_cp(piece))) {
        const char *start = piece;
        bool had_end = false;
        for (size_t i = 0; piece[i];) {
            size_t len;
            if (is_sentence_end(utf8_at(piece + i, &len))) {
                start = piece + i + len;
                had_end = true;
            }
            i += len;
        }
        leading_tags(start, c->carry, sizeof(c->carry));
        if (!c->carry[0] && !had_end) {
            strlcpy(c->carry, carried, sizeof(c->carry));
        }
    }

    memmove(c->buf, c->buf + n, c->len - n + 1);
    c->len -= n;

    if (speakable(out, strlen(out)) == 0) {
        return false;
    }
    c->emitted++;
    return true;
}

bool chunker_next(cloud_chunker_t *c, char *out, size_t out_len)
{
    size_t cut = cut_point(c);
    return cut && emit(c, cut, out, out_len);
}

bool chunker_finish(cloud_chunker_t *c, char *out, size_t out_len)
{
    if (speakable(c->buf, c->len) == 0) {
        c->len = 0;
        c->buf[0] = '\0';
        c->carry[0] = '\0';
        return false;
    }
    return emit(c, c->len, out, out_len);
}
