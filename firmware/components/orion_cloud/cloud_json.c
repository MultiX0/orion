// Writes request bodies straight into one PSRAM buffer.
//
// cJSON builds a tree of small nodes first, and every node under 4 KB is placed
// in internal RAM, the resource this board runs out of. A chat request is a
// system prompt, six turns of history and possibly a 70 KB base64 photo, so the
// tree would be both large and in the wrong place. Our bodies are simple
// enough to write in order.

#include "cloud_json.h"

#include <stdio.h>
#include <string.h>

#include "esp_heap_caps.h"
#include "mbedtls/base64.h"

bool jw_init(jw_t *w, size_t cap)
{
    w->buf = heap_caps_malloc(cap, MALLOC_CAP_SPIRAM);
    w->cap = w->buf ? cap : 0;
    w->len = 0;
    w->overflow = !w->buf;
    if (w->buf) w->buf[0] = '\0';
    return w->buf != NULL;
}

void jw_free(jw_t *w)
{
    free(w->buf);
    w->buf = NULL;
    w->cap = w->len = 0;
}

static void put(jw_t *w, const char *s, size_t n)
{
    if (w->overflow || w->len + n + 1 > w->cap) {
        w->overflow = true;
        return;
    }
    memcpy(w->buf + w->len, s, n);
    w->len += n;
    w->buf[w->len] = '\0';
}

void jw_raw(jw_t *w, const char *s)
{
    put(w, s, strlen(s));
}

void jw_str(jw_t *w, const char *s)
{
    put(w, "\"", 1);
    const char *run = s;
    for (const char *p = s; *p; p++) {
        const unsigned char ch = (unsigned char) *p;
        const char *esc = NULL;
        char ubuf[8];
        switch (ch) {
        case '"':  esc = "\\\""; break;
        case '\\': esc = "\\\\"; break;
        case '\n': esc = "\\n"; break;
        case '\r': esc = "\\r"; break;
        case '\t': esc = "\\t"; break;
        default:
            if (ch < 0x20) {
                snprintf(ubuf, sizeof(ubuf), "\\u%04x", ch);
                esc = ubuf;
            }
        }
        if (esc) {
            put(w, run, (size_t) (p - run));
            jw_raw(w, esc);
            run = p + 1;
        }
    }
    put(w, run, strlen(run));
    put(w, "\"", 1);
}

void jw_kv_str(jw_t *w, const char *key, const char *value)
{
    jw_str(w, key);
    put(w, ":", 1);
    jw_str(w, value);
}

void jw_data_url_jpeg(jw_t *w, const uint8_t *jpeg, size_t len)
{
    jw_raw(w, "\"data:image/jpeg;base64,");
    if (w->overflow) return;
    size_t written = 0;
    if (mbedtls_base64_encode((unsigned char *) w->buf + w->len, w->cap - w->len - 1,
                              &written, jpeg, len) != 0) {
        w->overflow = true;
        return;
    }
    w->len += written;
    w->buf[w->len] = '\0';
    put(w, "\"", 1);
}

size_t jw_escaped_len(const char *s)
{
    size_t n = 2;
    for (; *s; s++) {
        const unsigned char ch = (unsigned char) *s;
        n += (ch == '"' || ch == '\\' || ch == '\n' || ch == '\r' || ch == '\t') ? 2
           : (ch < 0x20) ? 6 : 1;
    }
    return n;
}
