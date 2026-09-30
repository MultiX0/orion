---
paths:
  - "tools/**"
---

# Board and cloud tooling rules

- One board, one port, one lock at `%USERPROFILE%\.orion\flash.lock`. Every script that flashes or reads the port takes it (`tools/serial_capture.py`'s `Lock`, `tools/flash.ps1`) and releases it in a `finally`. A lock is stale after 10 minutes or when its holder process is gone. A new script that touches the port imports `serial_capture` and uses its `Lock`.
- Nothing opens the port without an end: no `idf.py monitor` from scripts or agents. Captures run for a fixed time and write a file.
- `tools/idf.ps1` is the one place that activates ESP-IDF on Windows. Scripts target Windows PowerShell 5.1, clear the MSYS variables, and do not stop on native stderr.
- Python scripts start with a comment holding their exact command lines, use `argparse`, read keys from `.env` through `tools/cloud/cloud_api.py`, never print a key (length or last four only), and reconfigure stdout to UTF-8 when Arabic may be printed.
- Anything holding live keys (the NVS image in `provision.py`) is written outside the repo and deleted in a `finally`.
- Output goes to `logs/`, which is gitignored. No personal paths, names or network names in committed scripts or examples.
- A script that plays sound says so in its header, and is run only after telling whoever is in the room. Console sessions send `vol 0` first unless sound is the point.
- The console drops bytes above 0x7F and loses long lines: send UTF-8 as `hex:` and keep lines short.
