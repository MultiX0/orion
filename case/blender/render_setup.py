"""Scene for the hero renders: assembly on the desk, world lighting, cameras, materials.

Run in Blender after import_parts.py and branding.py:
    exec(open(r".../case/blender/render_setup.py").read())
Then render with render(name, camera, samples, engine).
Everything is parented to the empty ASSEMBLY, which turns the board frame into the standing
pose: 12 degrees back, stand on the desk at z = 0.
"""
import math
import os

import bpy
from mathutils import Matrix, Vector

ROOT = r"C:\Users\multix\Desktop\Dev\yt-projects\orion"
sc = bpy.context.scene
T = math.radians(12.0)
C_DESK = -26.8


def srgb(h):
    c = [int(h[i:i + 2], 16) / 255 for i in (0, 2, 4)]
    return tuple(((x + 0.055) / 1.055) ** 2.4 if x > 0.04045 else x / 12.92 for x in c)


def coll(name):
    c = bpy.data.collections.get(name) or bpy.data.collections.new(name)
    if c.name not in [x.name for x in sc.collection.children]:
        sc.collection.children.link(c)
    return c


def principled(name, rgb, rough, metal=0.0, coat=0.0, emit=None, image=None, alpha=1.0, trans=0.0):
    m = bpy.data.materials.get(name) or bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    b = next(n for n in nt.nodes if n.type == "BSDF_PRINCIPLED")
    b.inputs["Base Color"].default_value = (*rgb, 1)
    b.inputs["Roughness"].default_value = rough
    b.inputs["Metallic"].default_value = metal
    for key in ("Coat Weight", "Clearcoat"):
        if key in b.inputs:
            b.inputs[key].default_value = coat
    if "Transmission Weight" in b.inputs:
        b.inputs["Transmission Weight"].default_value = trans
    if image:
        tex = next((n for n in nt.nodes if n.type == "TEX_IMAGE"), None) or nt.nodes.new("ShaderNodeTexImage")
        tex.image = bpy.data.images.load(image, check_existing=True)
        coord = next((n for n in nt.nodes if n.type == "TEX_COORD"), None) or nt.nodes.new("ShaderNodeTexCoord")
        mp = next((n for n in nt.nodes if n.type == "MAPPING"), None) or nt.nodes.new("ShaderNodeMapping")
        nt.links.new(coord.outputs["Generated"], mp.inputs["Vector"])
        nt.links.new(mp.outputs["Vector"], tex.inputs["Vector"])
        nt.links.new(tex.outputs["Color"], b.inputs["Emission Color"])
        b.inputs["Emission Strength"].default_value = emit or 1.0
        b.inputs["Base Color"].default_value = (0.0, 0.0, 0.0, 1)
    m.diffuse_color = (*rgb, 1)
    return m


def assign(names, m, prefix=False):
    for o in bpy.data.objects:
        if (o.name.startswith(names) if prefix else o.name in names) and o.type == "MESH":
            o.data.materials.clear()
            o.data.materials.append(m)


def materials():
    case = principled("case_bg_card_111115", srgb("111115"), 0.42, coat=0.15)
    white = principled("white_text_f4f4f5", srgb("f4f4f5"), 0.35)
    pcb = principled("r_pcb", srgb("0c0d0f"), 0.35, coat=0.4)
    comp = principled("r_component", srgb("2a2b30"), 0.4, metal=0.2)
    metal = principled("r_metal", (0.6, 0.6, 0.62), 0.25, metal=1.0)
    screen = principled("r_screen", srgb("09090b"), 0.05, coat=1.0,
                        image=os.path.join(ROOT, "case", "brand_build", "screen_idle.png"), emit=2.2)
    black = principled("r_black_plastic", srgb("0a0a0c"), 0.5)
    fpc = principled("r_fpc", srgb("1a1408"), 0.35, coat=0.5)
    assign(("front_bezel", "rear_shell", "button_plunger", "stand", "dock"), case)
    assign(("inlay_",), white, prefix=True)
    assign(("REF_Board",), pcb)
    for o in bpy.data.collections["REF_board"].objects:
        if o.name != "REF_Board":
            o.data.materials.clear()
            o.data.materials.append(metal if "USB" in o.name or "RF1" in o.name or "CARD1" in o.name else comp)
    assign(("ref_display",), screen)
    assign(("ref_camera", "ref_speaker", "ref_usb_plug", "ref_dock_male"), black)
    assign(("ref_antenna",), fpc)
    return case


def assembly():
    e = bpy.data.objects.get("ASSEMBLY")
    if not e:
        e = bpy.data.objects.new("ASSEMBLY", None)
        sc.collection.objects.link(e)
    e.matrix_world = Matrix.Translation(Vector((-14.0, 0.0, -C_DESK))) @ Matrix.Rotation(math.pi / 2 - T, 4, "X")
    for cn in ("REF_board", "REF_modules", "CASE", "BRAND"):
        for o in bpy.data.collections[cn].objects:
            if o.parent is not e:
                o.parent = e
                o.matrix_parent_inverse = Matrix.Identity(4)
    return e


def studio():
    """No backdrop, no light objects. Transparent film, lit only by an invisible world: bright
    from above, dark below, so the dark case still shows its edges."""
    for o in list(bpy.data.objects):
        if o.type == "LIGHT" or o.name == "backdrop":
            bpy.data.objects.remove(o, do_unlink=True)
    for coll_ in (bpy.data.lights, bpy.data.meshes):
        for d in list(coll_):
            if d.users == 0 and (coll_ is bpy.data.lights or d.name.startswith("backdrop")):
                coll_.remove(d)
    sc.render.film_transparent = True
    w = sc.world or bpy.data.worlds.new("World")
    sc.world = w
    w.use_nodes = True
    nt = w.node_tree
    for n in list(nt.nodes):
        if n.type not in ("BACKGROUND", "OUTPUT_WORLD"):
            nt.nodes.remove(n)
    bg = next(n for n in nt.nodes if n.type == "BACKGROUND")
    tc = nt.nodes.new("ShaderNodeTexCoord")
    sep = nt.nodes.new("ShaderNodeSeparateXYZ")
    ramp = nt.nodes.new("ShaderNodeValToRGB")
    nt.links.new(tc.outputs["Generated"], sep.inputs["Vector"])
    nt.links.new(sep.outputs["Z"], ramp.inputs["Fac"])
    nt.links.new(ramp.outputs["Color"], bg.inputs["Color"])
    ramp.color_ramp.elements[0].position = 0.35
    ramp.color_ramp.elements[0].color = (0.01, 0.01, 0.012, 1)
    ramp.color_ramp.elements[1].position = 0.9
    ramp.color_ramp.elements[1].color = (1.0, 1.0, 1.0, 1)
    bg.inputs["Strength"].default_value = 2.6


def camera(name, loc, target, lens=85):
    o = bpy.data.objects.get(name)
    if not o:
        o = bpy.data.objects.new(name, bpy.data.cameras.new(name))
        coll("STUDIO").objects.link(o)
    o.location = loc
    d = Vector(target) - Vector(loc)
    o.rotation_euler = d.to_track_quat("-Z", "Y").to_euler()
    o.data.lens = lens
    o.data.clip_start = 5
    o.data.clip_end = 5000
    o.data.dof.use_dof = True
    o.data.dof.focus_distance = d.length
    o.data.dof.aperture_fstop = 11
    return o


def cameras():
    camera("cam_front", (-190, -420, 190), (0, 0, 52))
    camera("cam_back", (230, 410, 175), (0, 0, 50))
    camera("cam_exploded", (-420, -330, 250), (0, 30, 60), lens=70)
    camera("cam_detail_front", (-60, -170, 125), (0, 0, 95), lens=100)
    camera("cam_detail_back", (70, 170, 70), (0, 10, 42), lens=100)


def render(name, cam, samples=64, engine=None, res=(1920, 1080)):
    sc.camera = bpy.data.objects[cam]
    if engine:
        try:
            sc.render.engine = engine
        except TypeError as e:
            print(e)
    if sc.render.engine == "CYCLES":
        sc.cycles.samples = samples
        sc.cycles.use_denoising = True
        try:
            sc.cycles.device = "GPU"
        except Exception:
            pass
    else:
        try:
            sc.eevee.taa_render_samples = samples
        except Exception:
            pass
    sc.render.resolution_x, sc.render.resolution_y = res
    sc.render.resolution_percentage = 100
    sc.render.image_settings.file_format = "PNG"
    sc.view_settings.view_transform = "AgX" if "AgX" in [i.identifier for i in sc.view_settings.bl_rna.properties["view_transform"].enum_items] else "Filmic"
    sc.view_settings.look = "None"
    path = os.path.join(ROOT, "case", "renders", name + ".png")
    os.makedirs(os.path.dirname(path), exist_ok=True)
    sc.render.filepath = path
    bpy.ops.render.render(write_still=True)
    return path


def hide_for_hero():
    for o in bpy.data.objects:
        if o.name.startswith(("REF_TopSilk", "REF_BottomSilk", "fill_", "cutter_", "P_", "ref_usb_plug")) or                 o.name.endswith(("_2d", "_obj")):
            o.hide_render = True
            o.hide_viewport = True


materials()
assembly()
studio()
cameras()
hide_for_hero()
print("studio ready")
