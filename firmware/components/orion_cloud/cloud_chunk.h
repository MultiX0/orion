// The reply chunker, internal to orion_cloud. See cloud_chunk.c for the rules.
#pragma once

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>
#include <stdio.h>

// Longest single piece handed to TTS. A reply is capped well below this by
// max_tokens, so in practice a piece is never truncated.
#define CLOUD_CHUNK_MAX 1024

typedef struct {
    char *buf;          // caller's storage, PSRAM; text not yet handed out
    size_t len;
    size_t cap;
    int emitted;        // pieces handed out so far
    char carry[96];     // tags carried across a cut in the middle of a sentence
} cloud_chunker_t;

void chunker_init(cloud_chunker_t *c, char *storage, size_t cap);

// Appends a delta from the stream.
void chunker_feed(cloud_chunker_t *c, const char *delta);

// True and a piece in out when one is ready. Call until it returns false.
bool chunker_next(cloud_chunker_t *c, char *out, size_t out_len);

// End of the stream: whatever is left, if a listener would hear anything.
bool chunker_finish(cloud_chunker_t *c, char *out, size_t out_len);

// Runs the same cases as tools/cloud/chunker_test.py. Returns failures.
int chunker_selftest(void);
