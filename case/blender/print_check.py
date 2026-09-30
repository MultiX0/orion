"""3D Print Toolbox checks on every printable part, in print orientation.

Run in Blender after import_parts.py and branding.py:
    exec(open(r".../case/blender/print_check.py").read())

Makes a PRINT collection with a copy of each part turned to its print orientation and
sitting on z = 0, then runs the toolbox (solid, intersections, degenerate, thickness 1.2 mm,
overhang 45 degrees). The toolbox counts faces lying on the bed as overhangs, so overhangs
are also counted again without the bed faces. Thin faces are grouped into clusters with their
board-frame location so each one can be traced to a feature.
Writes case/blender/print_report.txt.
"""
import math
import sys

import bmesh
import bpy
from mathutils import Matrix, Vector

TB = sys.modules["bl_ext.user_default.print3d_toolbox"]
sc = bpy.context.scene
T = math.radians(12.0)
C_DESK = -26.8

# board frame -> print orientation, before dropping onto z = 0
FLIP = Matrix.Rotation(math.pi, 4, "Y")               # front face down
STAND = Matrix.Rotation(math.pi / 2 - T, 4, "X")      # desk plane becomes z = const
NECK = Matrix.Rotation(math.pi / 2, 4, "X")           # bottom of the neck on the bed
PARTS = {
    "front_bezel": FLIP,
    "rear_shell": Matrix.Identity(4),
    "button_plunger": Matrix.Identity(4),
    "stand": STAND,
    "dock": STAND,
    "inlay_star_front": FLIP,
    "inlay_tagline": FLIP,
    "inlay_star_back": Matrix.Identity(4),
    "inlay_wordmark": Matrix.Identity(4),
}


def coll(name):
    c = bpy.data.collections.get(name) or bpy.data.collections.new(name)
    if c.name not in [x.name for x in sc.collection.children]:
        sc.collection.children.link(c)
    return c


def print_copy(name, m, pc):
    src = bpy.data.objects[name]
    cname = "P_" + name
    old = bpy.data.objects.get(cname)
    if old:
        bpy.data.objects.remove(old, do_unlink=True)
    me = src.data.copy()
    me.name = cname
    me.transform(m @ src.matrix_world)
    zmin = min(v.co.z for v in me.vertices)
    xs = [v.co.x for v in me.vertices]
    ys = [v.co.y for v in me.vertices]
    me.transform(Matrix.Translation(Vector((-(min(xs) + max(xs)) / 2, -(min(ys) + max(ys)) / 2, -zmin))))
    o = bpy.data.objects.new(cname, me)
    pc.objects.link(o)
    o.hide_viewport = True
    return o


def toolbox(o):
    area = next(a for a in bpy.context.screen.areas if a.type == "VIEW_3D")
    region = next(r for r in area.regions if r.type == "WINDOW")
    for s in bpy.context.selected_objects:
        s.select_set(False)
    bpy.context.view_layer.objects.active = o
    o.hide_viewport = False
    o.select_set(True)
    with bpy.context.temp_override(area=area, region=region, active_object=o, object=o, selected_objects=[o]):
        bpy.ops.mesh.print3d_check_all()
    o.hide_viewport = True
    return {it.name: (it.value, list(it.indices) if it.indices else []) for it in TB.report.get()}


def overhangs(o, angle=45.0):
    """Down-facing faces steeper than the limit, not counting faces on the bed."""
    lim = -math.cos(math.radians(angle))
    area, worst, n = 0.0, 0.0, 0
    for p in o.data.polygons:
        if p.normal.z < lim - 1e-4 and p.center.z > 0.05:
            n += 1
            area += p.area
    return n, area


def bridges(o):
    """Flat ceilings (faces pointing straight down, off the bed), grouped by connectivity.
    The span of a bridge is the shorter side of each group's footprint."""
    bm = bmesh.new()
    bm.from_mesh(o.data)
    bm.faces.ensure_lookup_table()
    down = {f.index for f in bm.faces if f.normal.z < -0.99 and f.calc_center_median().z > 0.05}
    seen, spans = set(), []
    for i in down:
        if i in seen:
            continue
        stack, grp = [i], []
        while stack:
            j = stack.pop()
            if j in seen:
                continue
            seen.add(j)
            grp.append(j)
            for e in bm.faces[j].edges:
                for f in e.link_faces:
                    if f.index in down and f.index not in seen:
                        stack.append(f.index)
        pts = [v.co for j in grp for v in bm.faces[j].verts]
        dx = max(p.x for p in pts) - min(p.x for p in pts)
        dy = max(p.y for p in pts) - min(p.y for p in pts)
        spans.append(min(dx, dy))
    bm.free()
    return sorted(spans, reverse=True)


def run():
    pc = coll("PRINT")
    sc.print3d_toolbox.thickness_min = 1.2
    sc.print3d_toolbox.angle_overhang = math.radians(45)
    lines = []
    for name, m in PARTS.items():
        if name not in bpy.data.objects:
            continue
        o = print_copy(name, m, pc)
        res = toolbox(o)
        n_oh, a_oh = overhangs(o)
        lines.append(f"== {name}  (print copy P_{name}, {len(o.data.polygons)} faces)")
        for k, (v, idx) in res.items():
            lines.append(f"   {k:22s} {v}")
        lines.append(f"   overhang>45 off bed    {n_oh} faces, {a_oh:.2f} mm2")
        br = bridges(o)
        lines.append(f"   flat ceilings          {len(br)}, widest span {br[0] if br else 0:.2f} mm (limit 10)")
        thin = res.get("Thin Faces", ("0", []))[1]
        if thin and not name.startswith("inlay_"):
            # locate clusters on the print copy, then map back to the board frame
            src = bpy.data.objects[name]
            me = o.data
            back = (m @ src.matrix_world)
            # offset used when dropping onto the bed
            v0 = src.data.vertices[0].co
            off = me.vertices[0].co - (back @ v0)
            to_board = back.inverted() @ Matrix.Translation(-off)
            groups = []
            for i in thin:
                p = to_board @ me.polygons[i].center
                for g in groups:
                    if (g[0] - p).length < 4.0:
                        g[1].append(p)
                        break
                else:
                    groups.append([p, [p]])
            for c, ps in groups:
                lo = Vector([min(q[i] for q in ps) for i in range(3)])
                hi = Vector([max(q[i] for q in ps) for i in range(3)])
                lines.append(f"   thin cluster {len(ps):4d} faces  board x {lo.x:6.1f}..{hi.x:6.1f} "
                             f"y {lo.y:6.1f}..{hi.y:6.1f} z {lo.z:6.1f}..{hi.z:6.1f}")
    text = "\n".join(lines)
    open(r"C:\Users\multix\Desktop\Dev\yt-projects\orion\case\blender\print_report.txt", "w").write(text + "\n")
    print(text)


run()
