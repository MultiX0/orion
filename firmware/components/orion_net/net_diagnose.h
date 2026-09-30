// Explaining a Wi-Fi failure in words instead of a number. Internal to
// orion_net; nothing outside the component includes this.
#pragma once

#include <stdint.h>

const char *reason_name(uint8_t reason);

// Scans and says whether the configured SSID is on the air at all. Called once,
// after a few failed attempts, when the station has never been connected.
void diagnose(void);
