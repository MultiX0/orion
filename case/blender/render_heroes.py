"""Hero renders for the video: front three-quarter, back three-quarter, exploded view.

Run in Blender after render_setup.py:
    exec(open(r".../case/blender/render_heroes.py").read())
Uses the plain stand with a USB-C plug in the neck; the dock is hidden.
Writes case/renders/front.png, back.png, exploded.png.
"""
import bpy
from mathutils import Vector

RS = {}
exec(open(r"C:\Users\multix\Desktop\Dev\yt-projects\orion\case\blender\render_setup.py").read().split("\nmaterials()")[0], RS)
render, camera = RS["render"], RS["camera"]

# board-frame offsets for the exploded view (x, y, z in mm)
EXPLODE = {
    "front_bezel": (0, 0, 34), "button_plunger": (0, 0, 46), "inlay_star_front": (0, 0, 40),
    "inlay_tagline": (0, 0, 40), "ref_antenna": (0, 0, 24),
    "rear_shell": (0, 0, -38), "inlay_star_back": (0, 0, -46), "inlay_wordmark": (0, 0, -46),
    "ref_speaker": (0, 14, -18),
    "stand": (0, -46, 0), "ref_usb_plug": (0, -26, 0),
}


def visible(names, on=True):
    for n in names:
        o = bpy.data.objects.get(n)
        if o:
            o.hide_render = not on
            o.hide_viewport = not on


def explode(on):
    for n, d in EXPLODE.items():
        o = bpy.data.objects.get(n)
        if o:
            o.location = Vector(d) if on else Vector((0, 0, 0))


def hero(engine="CYCLES", samples=160, res=(1920, 1080), prefix=""):
    visible(["dock", "ref_dock_male", "ref_usb_plug"], False)
    visible(["stand"], True)
    # inside parts only show in the exploded view
    inside = [o.name for c in ("REF_board", "REF_modules") for o in bpy.data.collections[c].objects
              if "Silk" not in o.name and o.name not in ("ref_usb_plug", "ref_dock_male")]
    visible(inside, False)
    visible(["ref_display"], True)
    explode(False)
    camera("cam_front", (-170, -360, 170), (0, 4, 56), lens=58)
    camera("cam_back", (190, 350, 150), (0, 8, 54), lens=58)
    print(render(prefix + "front", "cam_front", samples=samples, engine=engine, res=res))
    print(render(prefix + "back", "cam_back", samples=samples, engine=engine, res=res))
    visible(inside, True)
    visible(["ref_usb_plug"], True)
    explode(True)
    camera("cam_exploded", (-520, -330, 300), (0, -6, 48), lens=78)
    print(render(prefix + "exploded", "cam_exploded", samples=samples, engine=engine, res=res))
    explode(False)

