// Shared between orion_net.c (driver and events) and net_state.c (what the
// rest of the firmware asks about). Nothing outside the component includes it.
#pragma once

#include <stdbool.h>
#include <stdint.h>

// Records the address and tells every listener.
void net_mark_up(const char *ip);
// No-op when already down, so a stop after a disconnect does not notify twice.
void net_mark_down(void);
bool net_ever_up(void);
// Increments and returns the count, for the three strikes diagnosis.
uint32_t net_count_disconnect(void);
