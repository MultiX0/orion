---
name: add-console-command
description: Add a command to the Orion board's serial console (esp_console on the USB port), so a feature can be driven and measured from tools/serial_capture.py or tools/cloud/console_session.py with nobody at the board. Use when adding a test, debug or control command to the firmware.
---

# Add a board console command

Every component exposes its own commands, and `firmware/main/orion_console.c` registers them all when the REPL starts. Commands are how the board is tested without a person, so give each one a result line a script can wait for.

## 1. Pick the home

| The command is about | Put it in |
|---|---|
| The assistant as a whole (state machine, turns, heap, saved volume) | `firmware/main/orion_console.c` |
| Power, button, backlight | `components/board/board_cmds.c` |
| Mic, speaker, WAV, DSP | `components/orion_audio/audio_cmds.c` or `audio_spk_cmds.c` (`spk ...`) |
| Wake word | `components/orion_wakeword/ww_cmds.c` (`ww ...`) |
| Camera | `components/orion_camera/camera_cmds.c` (`cam ...`) |
| Screen | `components/orion_ui/ui_cmds.c` (`ui ...`) |
| Cloud stages, settings | `components/orion_cloud/cloud_console.c`, `cloud_cfg_cmds.c` |
| Bluetooth setup | `components/orion_prov/prov_cmds.c` (`prov ...`) |

If the component already has a command with subcommands (`ww`, `cam`, `ui`, `spk`, `prov`), add a subcommand there instead of a new top-level name.

## 2. Write the handler

```c
// thing <n>: one line on why this command exists, if it is not obvious.
static int cmd_thing(int argc, char **argv)
{
    if (argc < 2) {
        printf("usage: thing <n>\n");
        return 1;
    }
    const int n = atoi(argv[1]);
    const esp_err_t err = orion_thing_do(n);
    printf("thing %d: %s\n", n, esp_err_to_name(err));
    return err == ESP_OK ? 0 : 1;
}
```

Rules:

- Print one final line that starts with the command's name and carries the result and any numbers (`cloud_test llm ok=1 ms=412 error=`). Scripts wait for that line. Return 0 on success, 1 on failure.
- Arguments arrive ASCII only: the console drops every byte above 0x7F. For UTF-8 text (Arabic), accept a `hex:<utf8 hex>` form the way `ask`, `talk` and `say` do. Keep command lines short; the USB receive buffer drops bytes from long lines.
- The console task has a small internal stack (4 KB). Anything that does TLS, HTTP, JSON, audio synthesis or deep calls runs on a helper task with a PSRAM stack and the handler waits for it. Inside `orion_cloud` use `cloud_run_big(job, arg)`; elsewhere copy its pattern (create with `xTaskCreatePinnedToCoreWithCaps(..., MALLOC_CAP_SPIRAM)`, park the task with `vTaskSuspend(NULL)` when done, delete it from the console task with `vTaskDeleteWithCaps`). A helper with a PSRAM stack must not read or write NVS, SPIFFS or partitions: read files and settings on the console task before starting it.
- NVS writes are fine on the console task itself, which has an internal stack.
- Never print a key or token. Print its length or that it is present.
- Do not reach into another component's internals. To act on the assistant, post an event (`sm_post(EV_WAKE, 0)`) or call a public header function. Screen changes go through `orion_ui.h`, which takes the LVGL lock; code inside `orion_ui` that touches `lv_*` from the console task takes `lvgl_port_lock(0)` itself.
- Big or long output (clips, screenshots) is framed with begin and end marker lines so a tool can pull it out of the log (`ORION_CLIP_BEGIN` and `ORION_CLIP_END`, `SHOT BEGIN` and `SHOT END`).

## 3. Register it

In the component's register function, add a row with help text in the form `"name <args>: what it does"`:

```c
{ .command = "thing", .help = "thing <n>: what it does", .func = cmd_thing },
```

For a component with no commands yet:

1. Declare `esp_err_t <component>_register_cmds(void);` in its public header.
2. Add `console` to `PRIV_REQUIRES` in the component's `CMakeLists.txt`.
3. Call it from `console_start()` in `firmware/main/orion_console.c`, next to the others.

If a script should wait for the command, add its result line to the `DONE` table in `tools/cloud/console_session.py`.

## 4. Build and try it

Build and flash the app partition (see the `flash-firmware` skill), then, with the user's go-ahead:

```
python tools/serial_capture.py --seconds 10 --no-reset --send "help" --send "thing 3" --out logs/thing.txt
python tools/cloud/console_session.py --out logs/thing.txt "vol 0" "thing 3" "heap"
```

Check the result line and that `heap` did not drop. Add the command to the console table in `AGENTS.md` if contributors will use it often.
