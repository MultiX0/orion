"""Brand fonts -> LVGL fonts for the 240x240 screen.

Three fonts leave this script, each one a job from brand/typography.md:

  ui_font_text_22      Source Serif 4 (body copy) merged with Noto Naskh Arabic.
                       The transcript and the reply. Arabic needs the presentation
                       forms U+FE70..FEFF because LVGL shapes into those.
  ui_font_text_16      The same pair at 16 px. Idle hint, menu titles, card
                       values: everything Arabic that is not the hero line.
  ui_font_mono_12      DM Mono, the machine voice. Labels and the status card.
  ui_font_code_40      Playfair Display 500 digits only, the brand's "big number"
                       face, for the six digit pairing code on the setup screen.
  ui_font_wordmark_36  Playfair Display 500 for "Ori" and Playfair italic for "on",
                       one font, so a single label renders the Ori-on wordmark.

The brand ships woff2 subsets, so they are converted to ttf and the variable
ones are instanced first. Noto Naskh Arabic is vendored under fonts/src/ (OFL)
and downloaded there if missing. Run from the repo root:

    python firmware/assets_src/ui/tools/build_fonts.py

Needs: python fontTools + brotli, node (lv_font_conv runs through npx).
"""
import subprocess
import sys
import urllib.request
from pathlib import Path

from fontTools.ttLib import TTFont
from fontTools.varLib import instancer

REPO = Path(__file__).resolve().parents[4]
BRAND = REPO / "brand" / "fonts"
SRC = REPO / "firmware" / "assets_src" / "ui" / "fonts" / "src"
OUT = REPO / "firmware" / "assets_src" / "ui" / "fonts"
NOTO_URL = ("https://raw.githubusercontent.com/google/fonts/main/ofl/"
            "notonaskharabic/NotoNaskhArabic%5Bwght%5D.ttf")
LV_FONT_CONV = "lv_font_conv@1.5.3"

LATIN = "0x20-0x7E,0xA0-0xFF,0x2018-0x201F,0x2022,0x2026"
ARABIC = "0x600-0x6FF,0xFB50-0xFBFF,0xFE70-0xFEFF"


def to_ttf(src, dst, axes=None):
    if dst.exists():
        return dst
    font = TTFont(src)
    if axes and "fvar" in font:
        font = instancer.instantiateVariableFont(font, axes)
    font.flavor = None
    dst.parent.mkdir(parents=True, exist_ok=True)
    font.save(dst)
    print("  ttf", dst.name)
    return dst


def noto():
    vf = SRC / "NotoNaskhArabic[wght].ttf"
    if not vf.exists():
        SRC.mkdir(parents=True, exist_ok=True)
        print("  downloading Noto Naskh Arabic")
        urllib.request.urlretrieve(NOTO_URL, vf)
    return to_ttf(vf, SRC / "NotoNaskhArabic-Regular.ttf", {"wght": 400})


def conv(name, size, parts):
    args = ["npx", "--yes", LV_FONT_CONV, "--bpp", "4", "--size", str(size),
            "--format", "lvgl", "--no-compress", "--lv-include", "lvgl.h",
            "--lv-font-name", name, "-o", str(OUT / f"{name}.c")]
    for font, key, value in parts:
        args += ["--font", str(font), key, value]
    print("  lv_font_conv", name)
    subprocess.run(args, check=True, shell=(sys.platform == "win32"))


def main():
    print("fonts")
    serif = to_ttf(BRAND / "source-serif-4-variable-latin.woff2",
                   SRC / "SourceSerif4-Text.ttf", {"wght": 400, "opsz": 20})
    mono = to_ttf(BRAND / "dm-mono-400-latin.woff2", SRC / "DMMono-Regular.ttf")
    play = to_ttf(BRAND / "playfair-display-variable-latin.woff2",
                  SRC / "PlayfairDisplay-Medium.ttf", {"wght": 500})
    play_it = to_ttf(BRAND / "playfair-display-400-italic-latin.woff2",
                     SRC / "PlayfairDisplay-Italic.ttf")
    naskh = noto()

    conv("ui_font_text_22", 22, [(serif, "-r", LATIN), (naskh, "-r", ARABIC)])
    conv("ui_font_text_16", 16, [(serif, "-r", LATIN), (naskh, "-r", ARABIC)])
    conv("ui_font_mono_12", 12, [(mono, "-r", "0x20-0x7E,0xB7")])
    conv("ui_font_code_40", 40, [(play, "--symbols", "0123456789 ")])
    conv("ui_font_wordmark_36", 36, [(play, "--symbols", "Ori"),
                                      (play_it, "--symbols", "on")])
    for f in sorted(OUT.glob("ui_font_*.c")):
        print(f"  {f.name}: {f.stat().st_size // 1024} KB")


if __name__ == "__main__":
    main()
