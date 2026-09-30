#pragma once

#include "esp_err.h"

// Starts the REPL on USB-Serial-JTAG and registers every component's commands.
esp_err_t console_start(void);
