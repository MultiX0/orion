// Reads the chat completion stream, OpenAI SSE, one "data: {...}" line per
// token.
//
// Deliberately not cJSON. A reply is fifty or more frames, and cJSON builds a
// tree of small nodes for each one: every node is under 4 KB, so every node goes
// to internal RAM, which is the thing this board runs out of. The frames have a
// fixed shape, checked against DeepInfra, so the few fields we need are found
// directly:
//
//   {"choices":[{"delta":{"content":"م","tool_calls":null},"finish_reason":null}]}
//   {"choices":[{"delta":{"tool_calls":[{"function":{"name":"look"}}]}}]}
//   {"choices":[],"usage":{...}}        the usage frame, skipped
//   [DONE]
//
// "content" is matched with its leading quote, so "reasoning_content" never
// matches it, and a quote inside the text arrives escaped as \" and cannot
// fake a key.

#include "cloud_sse.h"

#include <string.h>

#include "esp_log.h"

static const char *TAG = "cloud_sse";

void sse_init(sse_t *s, char *line_buf, size_t cap)
{
    memset(s, 0, sizeof(*s));
    s->line = line_buf;
    s->cap = cap;
}

static size_t put_utf8(char *out, uint32_t cp)
{
    if (cp < 0x80) { out[0] = (char) cp; return 1; }
    if (cp < 0x800) {
        out[0] = (char) (0xC0 | (cp >> 6));
        out[1] = (char) (0x80 | (cp & 0x3F));
        return 2;
    }
    if (cp < 0x10000) {
        out[0] = (char) (0xE0 | (cp >> 12));
        out[1] = (char) (0x80 | ((cp >> 6) & 0x3F));
        out[2] = (char) (0x80 | (cp & 0x3F));
        return 3;
    }
    out[0] = (char) (0xF0 | (cp >> 18));
    out[1] = (char) (0x80 | ((cp >> 12) & 0x3F));
    out[2] = (char) (0x80 | ((cp >> 6) & 0x3F));
    out[3] = (char) (0x80 | (cp & 0x3F));
    return 4;
}

static int hex4(const char *p, uint32_t *out)
{
    uint32_t v = 0;
    for (int i = 0; i < 4; i++) {
        char ch = p[i];
        v <<= 4;
        if (ch >= '0' && ch <= '9') v |= (uint32_t) (ch - '0');
        else if (ch >= 'a' && ch <= 'f') v |= (uint32_t) (ch - 'a' + 10);
        else if (ch >= 'A' && ch <= 'F') v |= (uint32_t) (ch - 'A' + 10);
        else return -1;
    }
    *out = v;
    return 0;
}

// p points just past an opening quote. Decodes the JSON string into out and
// returns true, or false if it is not terminated on this line.
static bool json_string(const char *p, char *out, size_t out_len)
{
    size_t w = 0;
    while (*p && *p != '"') {
        char ch = *p++;
        if (ch == '\\') {
            char e = *p++;
            uint32_t cp = 0;
            switch (e) {
            case 'n': ch = '\n'; break;
            case 't': ch = '\t'; break;
            case 'r': ch = '\r'; break;
            case 'b': ch = '\b'; break;
            case 'f': ch = '\f'; break;
            case 'u':
                if (hex4(p, &cp) != 0) return false;
                p += 4;
                // A surrogate pair is how JSON writes anything above U+FFFF.
                if (cp >= 0xD800 && cp <= 0xDBFF && p[0] == '\\' && p[1] == 'u') {
                    uint32_t lo;
                    if (hex4(p + 2, &lo) == 0 && lo >= 0xDC00 && lo <= 0xDFFF) {
                        cp = 0x10000 + ((cp - 0xD800) << 10) + (lo - 0xDC00);
                        p += 6;
                    }
                }
                if (w + 4 < out_len) w += put_utf8(out + w, cp);
                continue;
            case '\0': return false;
            default: ch = e; break;          // \" \\ \/
            }
        }
        if (w + 1 < out_len) out[w++] = ch;
    }
    out[w] = '\0';
    return *p == '"';
}

// The value after "key": as a string into out. False for null or missing.
static bool field(const char *json, const char *key, char *out, size_t out_len)
{
    const char *k = strstr(json, key);
    if (!k) return false;
    const char *v = k + strlen(key);
    while (*v == ' ') v++;
    if (*v != '"') return false;
    return json_string(v + 1, out, out_len);
}

sse_kind_t sse_parse_line(sse_t *s, const char *line, char *text, size_t text_len)
{
    text[0] = '\0';
    if (strncmp(line, "data:", 5) != 0) {
        return SSE_NONE;              // comments, "event:" lines, blank keep alives
    }
    const char *json = line + 5;
    while (*json == ' ') json++;

    if (strncmp(json, "[DONE]", 6) == 0) {
        return SSE_DONE;
    }
    if (strncmp(json, "{\"error\"", 8) == 0 || strstr(json, "\"object\":\"error\"")) {
        ESP_LOGE(TAG, "stream error: %.160s", json);
        return SSE_ERROR;
    }
    if (strstr(json, "\"choices\":[]")) {
        return SSE_NONE;              // the usage frame
    }

    char finish[16];
    if (field(json, "\"finish_reason\":", finish, sizeof(finish))) {
        strlcpy(s->finish, finish, sizeof(s->finish));
    }

    // A tool call can arrive with an empty content alongside it, so it is
    // checked first and wins.
    const char *calls = strstr(json, "\"tool_calls\":[");
    if (calls) {
        char name[24];
        if (field(calls, "\"name\":", name, sizeof(name))) {
            strlcpy(s->tool_name, name, sizeof(s->tool_name));
        }
        s->tool = true;
        return SSE_TOOL;
    }

    if (field(json, "\"content\":", text, text_len) && text[0]) {
        return SSE_TEXT;
    }
    return SSE_NONE;
}

sse_kind_t sse_feed(sse_t *s, const char **data, size_t *n, char *text, size_t text_len)
{
    while (*n) {
        char ch = **data;
        (*data)++;
        (*n)--;
        if (ch == '\r') {
            continue;
        }
        if (ch != '\n') {
            if (s->len + 1 < s->cap) {
                s->line[s->len++] = ch;
            }
            // A line longer than the buffer is the usage frame, which we do
            // not need; the rest of it is dropped rather than overflowing.
            continue;
        }
        s->line[s->len] = '\0';
        s->len = 0;
        sse_kind_t kind = sse_parse_line(s, s->line, text, text_len);
        if (kind != SSE_NONE) {
            return kind;
        }
    }
    return SSE_NONE;
}
