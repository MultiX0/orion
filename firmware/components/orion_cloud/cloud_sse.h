// OpenAI style server sent events, internal to orion_cloud. See cloud_sse.c.
#pragma once

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

typedef enum {
    SSE_NONE,       // nothing a caller needs: keep feeding
    SSE_TEXT,       // text holds the next piece of the reply
    SSE_TOOL,       // the model called a tool, name in tool_name
    SSE_DONE,       // [DONE]
    SSE_ERROR,      // the server sent an error frame
} sse_kind_t;

typedef struct {
    char *line;             // caller's storage, PSRAM
    size_t len;
    size_t cap;
    bool tool;
    char tool_name[24];
    char finish[16];        // finish_reason of the last frame that had one
} sse_t;

void sse_init(sse_t *s, char *line_buf, size_t cap);

// Consumes bytes from *data until a line yields something, advancing *data
// and *n. Call again with what is left until it returns SSE_NONE.
sse_kind_t sse_feed(sse_t *s, const char **data, size_t *n, char *text, size_t text_len);

// One complete line. Exposed for the self test.
sse_kind_t sse_parse_line(sse_t *s, const char *line, char *text, size_t text_len);

// Frames captured from DeepInfra, run on the chip by cloud_selftest. Returns failures.
int sse_selftest(void);
