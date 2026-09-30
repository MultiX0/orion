# firmware/assets

Everything in this directory, and only this directory, is packed into the
`assets` SPIFFS partition (2 MB at 0x510000) by
`spiffs_create_partition_image` in `firmware/main/CMakeLists.txt`, and mounted
on the board at `/assets`.

So this is a runtime filesystem, not a source folder. Two rules follow.

**Runtime files only.** If the chip never opens it, it does not belong here.
Build time sources, fonts you convert to C arrays, and the scripts that convert
them live in `firmware/assets_src/`. A 400 KB .ttf that only the build reads
would otherwise eat a fifth of the partition for nothing.

**Watch the budget.** 2 MB total. The six earcons are about 236 KB. Check the
image size in the build output before adding anything large.

What lives where:

| path | what | made by |
|---|---|---|
| `earcons/` | the short sounds for wake, errors and offline | `tools/cloud/make_earcons.py` |
| `system_prompt.txt` | the assistant's instructions, sent every turn | edited by hand, see `docs/VOICE.md` |
| everything else | screen images and fonts | the scripts in `firmware/assets_src/ui/tools/` |
