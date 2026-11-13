// Orion Hub, the client side (hub/README.md): finds hubs on the network with
// mDNS (_orionhub._tcp), pairs with one, and keeps its address current.
//
// The work runs on one worker task whose stack is in PSRAM; its NVS reads and
// writes run on the main task through orion_hub_serve(). The functions here
// only queue work and return at once. Changes are announced through
// orion_hub_on_change; the callback runs on the worker or on the caller of
// orion_hub_set_online(), and should only post an event.
#pragma once

#include <stdbool.h>
#include <stdint.h>

#include "esp_err.h"

typedef enum {
    HUB_NONE = 0,       // not paired, nothing found (yet)
    HUB_SCANNING,       // a scan is running
    HUB_FOUND,          // not paired, at least one hub answered
    HUB_PAIRING,        // asking the hub
    HUB_WAITING,        // the hub has an owner: waiting for approval, code set
    HUB_CONNECTED,      // paired, and the last health check passed
    HUB_OFFLINE,        // paired, but the hub does not answer
    HUB_FAILED,         // the last pairing failed, message set
} orion_hub_state_t;

#define ORION_HUB_MAX_FOUND 4

typedef struct {
    char name[48];
    char url[48];       // http://a.b.c.d:port
    char id[24];        // the hub's Orion Link id, "hub-..."; empty from an old hub
} orion_hub_found_t;

typedef struct {
    orion_hub_state_t state;
    char name[48];      // paired hub, or the one being paired
    char url[48];
    char code[8];       // HUB_WAITING: the 4 digits the hub owner sees
    char message[64];   // HUB_FAILED: why
    int found;
    orion_hub_found_t hubs[ORION_HUB_MAX_FOUND];
} orion_hub_status_t;

// Starts the worker and registers the `hub` console command. Call after the
// LAN API, which starts mDNS.
esp_err_t orion_hub_start(void);

// Waits up to ms, running the hub's NVS reads and writes meanwhile. Called by
// the main task, in place of its idle delay: those need an internal stack.
void orion_hub_serve(uint32_t ms);

void orion_hub_on_change(void (*cb)(void *ctx), void *ctx);
void orion_hub_status(orion_hub_status_t *out);
bool orion_hub_paired(void);
// The paired hub's Orion Link id, "" when not paired or paired before ids.
const char *orion_hub_id(void);

// Queue a scan, a pairing (a URL like http://192.168.1.5:8780, or "" for the
// first hub found), or forgetting the paired hub.
esp_err_t orion_hub_scan(void);
esp_err_t orion_hub_connect(const char *url);
esp_err_t orion_hub_forget(void);

// The paired hub's health, from the cloud's own check: called by whoever saw it
// change (the state machine on its heartbeat), so the status follows it.
void orion_hub_set_online(bool online);

const char *orion_hub_state_name(orion_hub_state_t s);
