"""brand/tokens.json -> firmware/components/orion_ui/ui_tokens.h

Every color, alpha, duration and easing the screen uses comes out of this file,
so nothing on the device is a hand typed hex. Run from the repo root:

    python firmware/assets_src/ui/tools/build_tokens.py
"""
import json
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parents[4]
TOKENS = REPO / "brand" / "tokens.json"
OUT = REPO / "firmware" / "components" / "orion_ui" / "ui_tokens.h"


def hex_int(value):
    return int(value.lstrip("#"), 16)


def ms(value):
    return int(value.replace("ms", ""))


def px(value):
    return int(value.replace("px", ""))


def bezier(value):
    # "cubic-bezier(0.16, 1, 0.3, 1)" -> LVGL bezier3 params in 0..1024
    nums = value[value.index("(") + 1:value.index(")")].split(",")
    return ", ".join(str(round(float(n) * 1024)) for n in nums)


def alpha(value):
    return round(float(value) * 255)


def main():
    t = json.loads(TOKENS.read_text(encoding="utf-8"))
    c, f, m, s, r = t["color"], t["font"], t["motion"], t["space"], t["radius"]
    lines = [
        "// Generated from brand/tokens.json by firmware/assets_src/ui/tools/build_tokens.py.",
        "// Do not edit by hand, edit the tokens and rerun the script.",
        "#pragma once",
        "",
        "// Surfaces",
    ]
    for k, v in c["bg"].items():
        lines.append(f"#define UI_BG_{k.upper():<14} 0x{hex_int(v):06x}")
    lines += ["", "// Text"]
    for k, v in c["text"].items():
        lines.append(f"#define UI_TEXT_{k.upper():<12} 0x{hex_int(v):06x}")
    lines += [
        "",
        "// The one accent, used as low alpha light over the dark surface, never as paint.",
        f"#define UI_ACCENT              0x{hex_int(c['accent']['base']):06x}",
        f"#define UI_GLOW_RGB            {c['accent']['glowRgb'].replace(' ', '')}",
        f"#define UI_ACCENT_RGB          {c['accent']['rgb'].replace(' ', '')}",
        "",
        "// Accent alphas as LVGL opacity (0..255)",
    ]
    for k, v in c["accent"]["alphas"].items():
        lines.append(f"#define UI_OPA_{k.upper():<14} {alpha(v)}")
    lines += [
        "",
        "// Borders are white at these alphas, 1 px, always.",
        "#define UI_OPA_BORDER_SUBTLE   " + str(alpha(0.06)),
        "#define UI_OPA_BORDER_SOFT     " + str(alpha(0.10)),
        "#define UI_OPA_BORDER_CYAN     " + str(alpha(0.20)),
        "",
        "// Motion",
    ]
    for k, v in m["duration"].items():
        lines.append(f"#define UI_DUR_{k.upper():<14} {ms(v)}")
    lines.append(f"#define UI_STAGGER_MS          {ms(m['stagger'])}")
    lines.append(f"#define UI_EASE_BRAND          {bezier(m['ease']['brand'])}")
    lines.append(f"#define UI_EASE_UI             {bezier(m['ease']['ui'])}")
    lines += ["", "// Spacing ladder (px)"]
    for k, v in s.items():
        lines.append(f"#define UI_SPACE_{k:<13} {px(v)}")
    lines += ["", "// Radii (px)"]
    for k, v in r.items():
        if v.endswith("px"):
            lines.append(f"#define UI_RADIUS_{k.upper():<12} {px(v)}")
    lines += ["", "// Type sizes the brand fixes in pixels"]
    for k in ("cardTitle", "body", "ui", "uiSmall", "label", "micro"):
        lines.append(f"#define UI_FONT_PX_{k.upper():<11} {px(f['size'][k])}")
    lines.append("")
    OUT.write_text("\n".join(lines), encoding="utf-8", newline="\n")
    print(f"wrote {OUT.relative_to(REPO)} ({len(lines)} lines)")


if __name__ == "__main__":
    sys.exit(main())
