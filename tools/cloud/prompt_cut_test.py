# The system prompt as the board sends it, for each text to speech provider.
# With Fish the <fish> section keeps its voice tag rules and loses its marker
# lines; with any other voice the section goes whole and a no brackets line is
# added. The same cut runs on the board (cloud_cut_fish_section, checked by the
# cloud_selftest console command). Offline, no keys.
#
#   python tools/cloud/prompt_cut_test.py

import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import cloud_api as c

TAG = re.compile(r"\[[^\]]{1,40}\]")


def main():
    raw = c.PROMPT_FILE.read_text(encoding="utf-8")
    fish = c.system_prompt(fish=True)
    other = c.system_prompt(fish=False)
    checks = [
        ("the file has one <fish> section", raw.count("<fish>\n") == 1 and raw.count("</fish>\n") == 1),
        ("fish: no marker lines", "<fish>" not in fish and "</fish>" not in fish),
        ("fish: voice tag rules kept", "Voice tags." in fish and "[laugh]" in fish),
        ("fish: no no-brackets line", "Never write anything in square brackets" not in fish),
        ("other: no tag rules and no cue", "Voice tags." not in other and not TAG.search(other)),
        ("other: no marker lines", "<fish>" not in other and "</fish>" not in other),
        ("other: asks for no brackets", other.endswith("reads everything aloud.")),
        ("other: the section leaves no blank line of its own", "code.\n\nLimits." in other),
        ("other: the rest of the prompt kept", "Length." in other and "Limits." in other),
        ("crlf file cut the same", c.for_tts(raw.replace("\n", "\r\n"), False).replace("\r\n", "\n").strip()
         == other),
    ]
    failed = [name for name, ok in checks if not ok]
    for name in failed:
        print("FAIL %s" % name)
    print("%d of %d passed, fish prompt %d bytes, other %d bytes" % (
        len(checks) - len(failed), len(checks), len(fish.encode()), len(other.encode())))
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
