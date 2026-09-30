// Private to orion_prov.
#pragma once

#include <stdint.h>
#include <sys/types.h>
#include "esp_err.h"

// The orion-pair endpoint: {"app_token","device_name"} in, {"device_id","ok"} out.
esp_err_t prov_pair_handler(uint32_t session_id, const uint8_t *inbuf, ssize_t inlen,
                            uint8_t **outbuf, ssize_t *outlen, void *priv);

// The orion-config endpoint: a partial config, whole or in parts.
esp_err_t prov_config_handler(uint32_t session_id, const uint8_t *inbuf, ssize_t inlen,
                              uint8_t **outbuf, ssize_t *outlen, void *priv);

// Console "prov stop" ends the wait from another task.
void prov_request_stop(void);

void prov_log_heap(const char *when);
