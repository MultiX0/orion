"""(Re)import the parts written by case/cad/build_case.py into the open Blender scene.

Run in Blender: exec(open(r".../case/blender/import_parts.py").read())
Board frame, 1 unit = 1 mm. Case parts go to CASE, provisional modules to REF_modules.
"""
import os
import bpy

ROOT = r"C:\Users\multix\Desktop\Dev\yt-projects\orion\case"
OUT = os.path.join(ROOT, "cad", "out")
sc = bpy.context.scene


def coll(name):
    c = bpy.data.collections.get(name) or bpy.data.collections.new(name)
    if c.name not in [x.name for x in sc.collection.children]:
        sc.collection.children.link(c)
    return c


def srgb(h):
    c = [int(h[i:i + 2], 16) / 255 for i in (0, 2, 4)]
    return tuple(((x + 0.055) / 1.055) ** 2.4 if x > 0.04045 else x / 12.92 for x in c)


def mat(name, rgb, rough=0.45, metal=0.0):
    m = bpy.data.materials.get(name) or bpy.data.materials.new(name)
    m.use_nodes = True
    b = next(n for n in m.node_tree.nodes if n.type == "BSDF_PRINCIPLED")
    b.inputs["Base Color"].default_value = (*rgb, 1)
    b.inputs["Roughness"].default_value = rough
    b.inputs["Metallic"].default_value = metal
    m.diffuse_color = (*rgb, 1)
    return m


M_CASE = mat("case_bg_card_111115", srgb("111115"), 0.5)
M_REF = mat("ref_module_prov", (0.9, 0.35, 0.05), 0.6)


def imp(name, c, m, lock=False):
    old = bpy.data.objects.get(name)
    if old:
        bpy.data.objects.remove(old, do_unlink=True)
    bpy.ops.wm.stl_import(filepath=os.path.join(OUT, name + ".stl"))
    o = bpy.context.selected_objects[0]
    for u in o.users_collection:
        u.objects.unlink(o)
    c.objects.link(o)
    o.name = name
    o.data.name = name
    o.data.materials.clear()
    o.data.materials.append(m)
    o.hide_select = lock
    clean(o)
    return o


def clean(o, dist=0.0005):
    """Merge duplicate vertices and dissolve sliver faces left by STL tessellation."""
    import bmesh
    bm = bmesh.new()
    bm.from_mesh(o.data)
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=dist)
    bmesh.ops.dissolve_degenerate(bm, dist=dist, edges=bm.edges)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(o.data)
    bm.free()


case = coll("CASE")
refm = coll("REF_modules")
for n in ("front_bezel", "rear_shell", "button_plunger", "stand", "dock"):
    imp(n, case, M_CASE)
for n in ("ref_display", "ref_camera", "ref_speaker", "ref_antenna", "ref_usb_plug", "ref_dock_male"):
    imp(n, refm, M_REF, lock=True)
print("imported", [o.name for o in case.objects])
