"""Fit check inside Blender: case parts against REF_board and REF_modules.

Run in Blender: exec(open(r".../case/blender/fit_check.py").read())
For every case part and reference part that come near each other it reports:
  overlap  the volume of their boolean intersection (exact solver), in mm3
  gap      the smallest distance from the reference part's vertices to the case surface
Contacts that are part of the design (listed in PLANNED) are reported but not failures.
Writes case/blender/fit_report.txt.
"""
import bpy
import bmesh
from mathutils import Vector
from mathutils.bvhtree import BVHTree

REPORT = bpy.path.abspath(r"//") or ""
CASE = ["front_bezel", "rear_shell", "button_plunger"]
# (case part, reference part prefix): why the contact is intended
PLANNED = {
    ("front_bezel", "REF_Board"): "front bosses clamp the PCB top",
    ("rear_shell", "REF_Board"): "standoffs carry the PCB",
    ("front_bezel", "ref_display"): "bezel lip rests on the glass edge",
    ("front_bezel", "REF_MIC1"): "sealing ring sits on the mic lid",
    ("rear_shell", "ref_speaker"): "crush ribs grip the speaker, 0.1 mm",
    ("front_bezel", "ref_usb_plug"): "cable plug in its channel",
    ("rear_shell", "ref_usb_plug"): "cable plug in its channel",
}


def world_bm(o):
    bm = bmesh.new()
    bm.from_mesh(o.data)
    bm.transform(o.matrix_world)
    return bm


def bbox(o):
    pts = [o.matrix_world @ Vector(c) for c in o.bound_box]
    return Vector([min(p[i] for p in pts) for i in range(3)]), Vector([max(p[i] for p in pts) for i in range(3)])


def inter_volume(a, b):
    """Volume of a AND b using a temporary copy with an exact boolean modifier."""
    tmp = a.copy()
    tmp.data = a.data.copy()
    bpy.context.scene.collection.objects.link(tmp)
    m = tmp.modifiers.new("i", "BOOLEAN")
    m.operation = "INTERSECT"
    m.solver = "EXACT"
    m.object = b
    dg = bpy.context.evaluated_depsgraph_get()
    ev = tmp.evaluated_get(dg)
    me = ev.to_mesh()
    bm = bmesh.new()
    bm.from_mesh(me)
    vol = abs(bm.calc_volume(signed=True))
    bm.free()
    ev.to_mesh_clear()
    bpy.data.objects.remove(tmp, do_unlink=True)
    return vol


def run():
    # hidden objects are not evaluated, so make everything measured visible first
    for cn in ("REF_board", "REF_modules", "CASE"):
        for o in bpy.data.collections[cn].objects:
            if "Silk" not in o.name:
                o.hide_viewport = False
    dg = bpy.context.evaluated_depsgraph_get()
    refs = [o for o in bpy.data.collections["REF_board"].objects if "Silk" not in o.name and o.type == "MESH"]
    refs += [o for o in bpy.data.collections["REF_modules"].objects if o.type == "MESH"]
    lines, fails, gaps = [], [], []
    for cn in CASE:
        c = bpy.data.objects[cn]
        tree = BVHTree.FromObject(c, dg)
        cmin, cmax = bbox(c)
        for r in refs:
            rmin, rmax = bbox(r)
            if any(rmin[i] > cmax[i] + 1.5 or rmax[i] < cmin[i] - 1.5 for i in range(3)):
                continue
            rtree = BVHTree.FromObject(r, dg)
            touching = bool(tree.overlap(rtree))
            vol = inter_volume(c, r) if touching else 0.0
            # inside test for small parts swallowed whole: ray parity from the part centre
            centre = (rmin + rmax) / 2
            hits, origin = 0, centre.copy()
            for _ in range(50):
                loc, nrm, idx, d = tree.ray_cast(origin, Vector((0.0123, 0.0071, 1.0)))
                if loc is None:
                    break
                hits += 1
                origin = loc + Vector((0.0123, 0.0071, 1.0)).normalized() * 1e-4
            inside = hits % 2 == 1 and not touching
            gap = min((tree.find_nearest(r.matrix_world @ v.co, 5.0)[3] or 99) for v in r.data.vertices)
            planned = next((why for (a, b), why in PLANNED.items() if a == cn and r.name.startswith(b)), None)
            tag = "PLANNED" if planned else ("FAIL" if (vol > 1e-3 or inside) else "ok")
            if tag == "FAIL":
                fails.append((cn, r.name))
            if not planned and not touching and not inside:
                gaps.append((gap, cn, r.name))
            if touching or inside or gap < 0.5:
                lines.append(f"{tag:8s} {cn:15s} {r.name[:40]:40s} overlap {vol:8.3f} mm3  gap {gap:6.3f}  {planned or ''}")
    # stand and dock against the case body and the cable plugs
    for sn, others in (("stand", ("front_bezel", "rear_shell", "ref_usb_plug")),
                       ("dock", ("front_bezel", "rear_shell", "ref_dock_male"))):
        st = bpy.data.objects.get(sn)
        if not st:
            continue
        tree = BVHTree.FromObject(st, dg)
        for on in others:
            r = bpy.data.objects[on]
            rtree = BVHTree.FromObject(r, dg)
            touching = bool(tree.overlap(rtree))
            vol = inter_volume(st, r) if touching else 0.0
            gap = min((tree.find_nearest(r.matrix_world @ v.co, 5.0)[3] or 99) for v in r.data.vertices)
            planned = "plug held in its pocket" if on == "ref_dock_male" else ("body rests on the pocket floor" if on != "ref_usb_plug" else None)
            tag = "FAIL" if vol > 1e-3 else ("PLANNED" if planned and touching else "ok")
            if tag == "FAIL":
                fails.append((sn, on))
            lines.append(f"{tag:8s} {sn:15s} {on:40s} overlap {vol:8.3f} mm3  gap {gap:6.3f}  {planned or ''}")
    gaps.sort()
    lines.append("")
    lines.append("smallest clearances (unplanned pairs):")
    for g in gaps[:8]:
        lines.append(f"  {g[0]:6.3f} mm  {g[1]} vs {g[2]}")
    lines.append(f"FAILURES: {len(fails)}")
    text = "\n".join(lines)
    path = r"C:\Users\multix\Desktop\Dev\yt-projects\orion\case\blender\fit_report.txt"
    open(path, "w").write(text + "\n")
    print(text)


run()
