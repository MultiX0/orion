# Turns a sentence into the console's hex form, for typed Arabic turns.
#
# esp_console's argv splitter drops every non-ASCII byte, so Arabic typed over
# serial arrives empty. `talk hex:<utf8 hex>` gets it through intact.
#
#   python tools/cloud/talk_hex.py "قديش الساعة بعمّان هلأ؟"
#   python tools/serial_capture.py --send "$(python tools/cloud/talk_hex.py 'شو عاصمة الأردن؟')"

import sys

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8")


def talk_cmd(text):
    return "talk hex:" + text.encode("utf-8").hex()


if __name__ == "__main__":
    print(talk_cmd(" ".join(sys.argv[1:])))
