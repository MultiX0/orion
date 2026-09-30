#include "orion_state.h"

static const char *NAMES[OS_STATE_COUNT] = {
    "boot", "idle", "wake", "listening", "thinking", "speaking", "error", "offline",
};

const char *orion_state_name(orion_state_t state)
{
    if (state < 0 || state >= OS_STATE_COUNT) {
        return "unknown";
    }
    return NAMES[state];
}
