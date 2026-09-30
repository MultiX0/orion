// The chunker cases from tools/cloud/chunker_test.py, run on the board by the
// cloud_selftest console command. Fed 1, 3 and 7 bytes at a time, which is
// harsher than the real stream: it splits Arabic characters down the middle.

#include "cloud_chunk.h"
#include "cloud_private.h"
#include "cloud_sse.h"

#include <string.h>

#include "esp_heap_caps.h"
#include "esp_log.h"

static const char *TAG = "chunk_test";

typedef struct {
    const char *text;
    const char *want[3];
} chunk_case_t;

static const chunk_case_t CASES[] = {
    {"عمان طبعاً.", {"عمان طبعاً."}},
    {"عاصمة فرنسا هي باريس، وهي مدينة جميلة كتير ومشهورة ببرج إيفل.",
     {"عاصمة فرنسا هي باريس،", "وهي مدينة جميلة كتير ومشهورة ببرج إيفل."}},
    {"[warm] أهلين، أنا أوريون وجاهز أساعدك. [playful] بس لا تسألني عن الطقس!",
     {"[warm] أهلين، أنا أوريون وجاهز أساعدك.", "[playful] بس لا تسألني عن الطقس!"}},
    {"[whispering] هاد سر كبير بيني وبينك، ما تحكي لحدا أبداً ولا حتى لأمك.",
     {"[whispering] هاد سر كبير بيني وبينك،",
      "[whispering] ما تحكي لحدا أبداً ولا حتى لأمك."}},
    {"[the calm, measured tone of a pro. really] كل شي تمام وماشي حسب الخطة.",
     {"[the calm, measured tone of a pro. really] كل شي تمام وماشي حسب الخطة."}},
    {"تمام، خلصت كل الشغل اللي طلبته مني اليوم. [laughing]",
     {"تمام، خلصت كل الشغل اللي طلبته مني اليوم. [laughing]"}},
    {"The file is 3.5 megabytes and it loads in about two seconds.",
     {"The file is 3.5 megabytes and it loads in about two seconds."}},
    {"The capital of France is Paris, and it is famous for the Eiffel Tower.",
     {"The capital of France is Paris,", "and it is famous for the Eiffel Tower."}},
    {"It will be sunny tomorrow in Irbid.<turn|>",
     {"It will be sunny tomorrow in Irbid."}},
    {"[chuckling] That is a classic excuse, but I believe you, and I think so too.",
     {"[chuckling] That is a classic excuse,", "but I believe you, and I think so too."}},
    {"Why did the man put his clock in the bank? [pause] He wanted to save time! [laugh]",
     {"Why did the man put his clock in the bank? [pause]", "He wanted to save time! [laugh]"}},
    {"سأل رجلٌ صديقه: لماذا وضعتَ ساعتك في البنك؟ [pause] قال: كي أوفّر الوقت! [laugh]",
     {"سأل رجلٌ صديقه: لماذا وضعتَ ساعتك في البنك؟ [pause]", "قال: كي أوفّر الوقت! [laugh]"}},
    {"The capital of France is Paris, [laughing nervously] or at least it was yesterday.",
     {"The capital of France is Paris,", "[laughing nervously] or at least it was yesterday."}},
    {"Honestly that is the best news [gasp] I have heard all week, and I mean it.",
     {"Honestly that is the best news [gasp] I have heard all week,", "and I mean it."}},
    {"[whispers sweetly] هذا سرّ صغير بيني وبينك، لا تخبر به أحداً أبداً ولا حتى أمك.",
     {"[whispers sweetly] هذا سرّ صغير بيني وبينك،",
      "[whispers sweetly] لا تخبر به أحداً أبداً ولا حتى أمك."}},
};

// Test buffers live in PSRAM: this runs on the console task, and a static
// array here would sit in internal RAM for the life of the program.
typedef struct {
    char piece[CLOUD_CHUNK_MAX];
    char pieces[4][CLOUD_CHUNK_MAX];
} test_bufs_t;

static int run_case(const chunk_case_t *tc, size_t step, char *storage, size_t cap,
                    test_bufs_t *b)
{
    cloud_chunker_t ck;
    chunker_init(&ck, storage, cap);
    char *piece = b->piece;
    const char *got[4] = {0};
    char (*pieces)[CLOUD_CHUNK_MAX] = b->pieces;
    int n = 0;

    const size_t len = strlen(tc->text);
    char part[8];
    for (size_t i = 0; i < len; i += step) {
        size_t take = (len - i) < step ? (len - i) : step;
        memcpy(part, tc->text + i, take);
        part[take] = '\0';
        chunker_feed(&ck, part);
        while (n < 4 && chunker_next(&ck, piece, CLOUD_CHUNK_MAX)) {
            strlcpy(pieces[n], piece, sizeof(pieces[n]));
            got[n] = pieces[n];
            n++;
        }
    }
    if (n < 4 && chunker_finish(&ck, piece, CLOUD_CHUNK_MAX)) {
        strlcpy(pieces[n], piece, sizeof(pieces[n]));
        got[n] = pieces[n];
        n++;
    }

    for (int i = 0; i < 3; i++) {
        const char *w = tc->want[i];
        const char *g = i < n ? got[i] : NULL;
        if ((w == NULL) != (g == NULL) || (w && strcmp(w, g) != 0)) {
            ESP_LOGE(TAG, "step %u piece %d\n  want %s\n  got  %s", (unsigned) step, i,
                     w ? w : "(none)", g ? g : "(none)");
            return 1;
        }
    }
    return n > 3 ? 1 : 0;
}

int chunker_selftest(void)
{
    const size_t cap = 2048;
    char *storage = heap_caps_malloc(cap, MALLOC_CAP_SPIRAM);
    test_bufs_t *b = heap_caps_malloc(sizeof(*b), MALLOC_CAP_SPIRAM);
    if (!storage || !b) {
        free(storage);
        free(b);
        return -1;
    }
    const size_t steps[] = {1, 3, 7};
    int failed = 0;
    int total = 0;
    for (size_t s = 0; s < 3; s++) {
        for (size_t i = 0; i < sizeof(CASES) / sizeof(CASES[0]); i++) {
            failed += run_case(&CASES[i], steps[s], storage, cap, b);
            total++;
        }
    }
    free(storage);
    free(b);
    ESP_LOGI(TAG, "chunker %d of %d passed", total - failed, total);
    return failed;
}

// Frames captured from DeepInfra, trimmed to the fields that matter.
int sse_selftest(void)
{
    static const struct { const char *line; sse_kind_t kind; const char *text; } cases[] = {
        {"data: {\"choices\":[{\"delta\":{\"role\":null,\"content\":\"\\u0645\\u0631\","
         "\"reasoning_content\":null,\"tool_calls\":null},\"finish_reason\":null}]}",
         SSE_TEXT, "مر"},
        {"data: {\"choices\":[{\"delta\":{\"content\":\"say \\\"hi\\\"\\n\"}}]}", SSE_TEXT,
         "say \"hi\"\n"},
        {"data: {\"choices\":[{\"delta\":{\"content\":\"\",\"tool_calls\":[{\"index\":0,"
         "\"function\":{\"arguments\":\"\",\"name\":\"look\"}}]}}]}", SSE_TOOL, ""},
        {"data: {\"choices\":[],\"usage\":{\"prompt_tokens\":80}}", SSE_NONE, ""},
        {"data: [DONE]", SSE_DONE, ""},
        {": keep-alive", SSE_NONE, ""},
    };
    int failed = 0;
    char text[64];
    for (size_t i = 0; i < sizeof(cases) / sizeof(cases[0]); i++) {
        sse_t s;
        char line[8];
        sse_init(&s, line, sizeof(line));
        const sse_kind_t k = sse_parse_line(&s, cases[i].line, text, sizeof(text));
        if (k != cases[i].kind || (k == SSE_TEXT && strcmp(text, cases[i].text) != 0) ||
            (k == SSE_TOOL && strcmp(s.tool_name, "look") != 0)) {
            ESP_LOGE(TAG, "sse case %u: kind %d text '%s'", (unsigned) i, k, text);
            failed++;
        }
    }
    ESP_LOGI(TAG, "sse %d of %u passed", (int) (sizeof(cases) / sizeof(cases[0])) - failed,
             (unsigned) (sizeof(cases) / sizeof(cases[0])));
    return failed;
}

// The <fish> section of the prompt: kept without its markers for Fish,
// dropped whole for any other voice, CRLF or LF.
int prompt_selftest(void)
{
    static const struct { const char *base; bool fish; const char *want; } cases[] = {
        {"Length.\n\n<fish>\nVoice tags. [laugh]\n</fish>\n\nLimits.", true,
         "Length.\n\nVoice tags. [laugh]\n\nLimits."},
        {"Length.\n\n<fish>\nVoice tags. [laugh]\n</fish>\n\nLimits.", false,
         "Length.\n\nLimits."},
        {"Length.\r\n\r\n<fish>\r\nVoice tags.\r\n</fish>\r\n\r\nLimits.", false,
         "Length.\r\n\r\nLimits."},
        {"No section here.", false, "No section here."},
    };
    int failed = 0;
    char out[96];
    for (size_t i = 0; i < sizeof(cases) / sizeof(cases[0]); i++) {
        cloud_cut_fish_section(cases[i].base, cases[i].fish, out);
        if (strcmp(out, cases[i].want) != 0) {
            ESP_LOGE(TAG, "prompt case %u: got '%s'", (unsigned) i, out);
            failed++;
        }
    }
    ESP_LOGI(TAG, "prompt %d of %u passed", (int) (sizeof(cases) / sizeof(cases[0])) - failed,
             (unsigned) (sizeof(cases) / sizeof(cases[0])));
    return failed;
}
