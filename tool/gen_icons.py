# Rebuilds every app icon and splash image from brand/assets/logo.png.
# Run from the repo root: python tool/gen_icons.py   (needs Pillow)
# python tool/gen_icons.py windows   rebuilds only the Windows .ico.
import os
import sys

from PIL import Image, ImageFilter

LOGO = "brand/assets/logo.png"
BG = (9, 9, 11)  # --bg-primary
GLOW = (168, 204, 216)  # --text-cyan


def star(size):
    """The white star, scaled to a square of the given size."""
    return Image.open(LOGO).convert("RGBA").resize((size, size), Image.LANCZOS)


def glow_behind(canvas, mark_size, strength):
    """A soft accent halo where the mark will sit. Light, never paint."""
    side = canvas.size[0]
    halo = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
    alpha = star(mark_size).split()[3].point(lambda v: int(v * strength))
    tint = Image.new("RGBA", (mark_size, mark_size), GLOW + (0,))
    tint.putalpha(alpha)
    halo.alpha_composite(tint, ((side - mark_size) // 2,) * 2)
    halo = halo.filter(ImageFilter.GaussianBlur(side * 0.06))
    canvas.alpha_composite(halo)


def icon(side, fill=0.56, background=True, glow=0.55):
    """Star centered on the brand black. fill is the star's share of the side."""
    canvas = Image.new("RGBA", (side, side), BG + (255,) if background else (0, 0, 0, 0))
    mark = max(8, int(side * fill))
    if glow > 0 and side >= 48:
        glow_behind(canvas, mark, glow)
    canvas.alpha_composite(star(mark), ((side - mark) // 2,) * 2)
    return canvas


WINDOWS_SIZES = [16, 24, 32, 48, 64, 128, 256]
WINDOWS_FILL = 0.88  # the star's share of the side, tip to tip


def windows_frame(side, fill=WINDOWS_FILL):
    """Only the star, on clear pixels. Drawn 8x larger and scaled down, so
    even the small sizes stay centred and soft edged."""
    big = side * 8
    logo = Image.open(LOGO).convert("RGBA")
    logo = logo.crop(logo.split()[3].point(lambda v: 255 if v > 8 else 0).getbbox())
    mark = round(big * fill)
    canvas = Image.new("RGBA", (big, big), (0, 0, 0, 0))
    canvas.alpha_composite(logo.resize((mark, mark), Image.LANCZOS), ((big - mark) // 2,) * 2)
    return canvas.resize((side, side), Image.LANCZOS)


def windows_icon():
    # Each size is drawn on its own rather than shrunk from the 256 frame.
    path = "windows/runner/resources/app_icon.ico"
    frames = [windows_frame(side) for side in WINDOWS_SIZES]
    os.makedirs(os.path.dirname(path), exist_ok=True)
    frames[-1].save(
        path,
        sizes=[(side, side) for side in WINDOWS_SIZES],
        append_images=frames[:-1],
    )
    print(path, WINDOWS_SIZES)


def save(image, path, rgb=False):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    (image.convert("RGB") if rgb else image).save(path)
    print(path, image.size)


def main():
    res = "android/app/src/main/res"
    legacy = {"mdpi": 48, "hdpi": 72, "xhdpi": 96, "xxhdpi": 144, "xxxhdpi": 192}
    for density, side in legacy.items():
        save(icon(side), f"{res}/mipmap-{density}/ic_launcher.png")
        # Adaptive foreground: 108dp canvas, the star stays inside the 66dp safe zone.
        fg = side * 108 // 48
        save(icon(fg, fill=0.42, background=False), f"{res}/mipmap-{density}/ic_launcher_foreground.png")
        # Splash: the mark in its glow for the launch background, glow-free for Android 12.
        save(icon(side * 4, fill=0.5, background=False), f"{res}/drawable-{density}/splash_mark.png")
        save(icon(side * 5, fill=0.4, background=False, glow=0), f"{res}/drawable-{density}/splash_icon.png")

    ios = "ios/Runner/Assets.xcassets/AppIcon.appiconset"
    for name, side in {
        "Icon-App-20x20@1x": 20, "Icon-App-20x20@2x": 40, "Icon-App-20x20@3x": 60,
        "Icon-App-29x29@1x": 29, "Icon-App-29x29@2x": 58, "Icon-App-29x29@3x": 87,
        "Icon-App-40x40@1x": 40, "Icon-App-40x40@2x": 80, "Icon-App-40x40@3x": 120,
        "Icon-App-60x60@2x": 120, "Icon-App-60x60@3x": 180,
        "Icon-App-76x76@1x": 76, "Icon-App-76x76@2x": 152,
        "Icon-App-83.5x83.5@2x": 167, "Icon-App-1024x1024@1x": 1024,
    }.items():
        save(icon(side), f"{ios}/{name}.png", rgb=True)
    launch = "ios/Runner/Assets.xcassets/LaunchImage.imageset"
    for name, side in {"LaunchImage": 96, "LaunchImage@2x": 192, "LaunchImage@3x": 288}.items():
        save(icon(side, fill=0.6, background=False), f"{launch}/{name}.png")

    windows_icon()
    icon(64, fill=0.7).save("brand/assets/logo.ico", sizes=[(32, 32)])
    save(icon(512), "assets/images/app_icon.png")
    save(Image.open(LOGO).convert("RGBA"), "assets/images/logo.png")

    svg = (
        '<svg width="256" height="256" viewBox="0 0 256 256" fill="none" xmlns="http://www.w3.org/2000/svg">\n'
        '<path d="M128 2L153.6 102.4L254 128L153.6 153.6L128 254L102.4 153.6L2 128L102.4 102.4Z" fill="white"/>\n'
        "</svg>\n"
    )
    for path in ("brand/assets/logo.svg", "assets/images/logo.svg"):
        with open(path, "w", encoding="utf-8", newline="\n") as f:
            f.write(svg)
        print(path)


if __name__ == "__main__":
    if sys.argv[1:] == ["windows"]:
        windows_icon()
    else:
        main()
