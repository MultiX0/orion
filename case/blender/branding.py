"""Brand marks: build them from the brand files, cut the inlay pockets, make the inlay bodies.

Run in Blender after import_parts.py:
    exec(open(r".../case/blender/branding.py").read())

Back, the brand lockup (brand/logo.md): the star from brand/assets/logo.svg (imported as a
curve, converted to a mesh) above the wordmark Ori-on, Playfair Display 500 with "on" in the
brand's Playfair italic. Front: the star on the crown above the screen, and the brand tagline
"// Seek the Undiscovered" very small at the bottom centre, all in Playfair italic, with the
"//" of the brand's section labels.

Playfair's hairlines are about 0.02 em, far under what FDM prints at these sizes, so every
outline is grown by a small even amount (BOOST_*) before it becomes an inlay. The star's tips
end where the arm is STAR_TIP_W wide.

Objects made, in collection BRAND:
  inlay_star_back, inlay_wordmark, inlay_star_front   0.8 mm, printed white and pressed in
  inlay_tagline                                        0.6 mm
  fill_*                                               the pocket shapes, for the multi-material 3MF
The pockets are cut into front_bezel and rear_shell with the Manifold boolean solver.
"""
import math
import os

import bmesh
import bpy
from mathutils import Matrix, Vector

ROOT = r"C:\Users\multix\Desktop\Dev\yt-projects\orion"
P = {}
exec(open(os.path.join(ROOT, "case", "cad", "params.py")).read(), P)
sc = bpy.context.scene


def coll(name):
    c = bpy.data.collections.get(name) or bpy.data.collections.new(name)
    if c.name not in [x.name for x in sc.collection.children]:
        sc.collection.children.link(c)
    return c


BRAND = coll("BRAND")
M_WHITE = bpy.data.materials.get("white_text_f4f4f5")


def clear(name):
    o = bpy.data.objects.get(name)
    if o:
        bpy.data.objects.remove(o, do_unlink=True)


def to_mesh_object(obj, name):
    """Curve or text object -> mesh object with flat filled faces, duplicates merged."""
    dg = bpy.context.evaluated_depsgraph_get()
    me = bpy.data.meshes.new_from_object(obj.evaluated_get(dg))
    clear(name)
    o = bpy.data.objects.new(name, me)
    BRAND.objects.link(o)
    o.matrix_world = obj.matrix_world.copy()
    bm = bmesh.new()
    bm.from_mesh(me)
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-5)
    bm.to_mesh(me)
    bm.free()
    return o


def apply_matrix(o, m):
    o.data.transform(m @ o.matrix_world)
    o.matrix_world = Matrix.Identity(4)


def bounds2d(o):
    xs = [v.co.x for v in o.data.vertices]
    ys = [v.co.y for v in o.data.vertices]
    return min(xs), max(xs), min(ys), max(ys)


STAR_SCALE = {}


def star_2d(size, name, off=0.0):
    """off is the curve outline offset in curve units (see grown())."""
    before = set(bpy.data.objects)
    bpy.ops.import_curve.svg(filepath=os.path.join(ROOT, "brand", "assets", "logo.svg"))
    new = [o for o in bpy.data.objects if o not in before]
    curve = new[0]
    curve.data.fill_mode = "BOTH"
    o = to_mesh_object(curve, name)
    for n in new:
        cd = n.data
        bpy.data.objects.remove(n, do_unlink=True)
        if cd and cd.users == 0:
            bpy.data.curves.remove(cd)
    apply_matrix(o, Matrix.Identity(4))
    x0, x1, y0, y1 = bounds2d(o)
    s = size / (x1 - x0) if not off else STAR_SCALE[size]
    STAR_SCALE[size] = s
    c = Vector(((x0 + x1) / 2, (y0 + y1) / 2, 0))
    o.data.transform(Matrix.Scale(s, 4) @ Matrix.Translation(-c))
    if off:
        offset_polygon(o, off)
    # end the four tips where the arm is STAR_TIP_W wide: w / (2 * 25.6 / 100.4) from the tip
    h = size / 2 - P["STAR_TIP_W"] / (2 * 25.6 / 100.4) + off
    bm = bmesh.new()
    bm.from_mesh(o.data)
    for co, no in (((h, 0, 0), (1, 0, 0)), ((-h, 0, 0), (-1, 0, 0)), ((0, h, 0), (0, 1, 0)), ((0, -h, 0), (0, -1, 0))):
        geom = bm.verts[:] + bm.edges[:] + bm.faces[:]
        bmesh.ops.bisect_plane(bm, geom=geom, plane_co=co, plane_no=no, clear_outer=True)
    bm.to_mesh(o.data)
    bm.free()
    fill_holes(o)
    return o


def offset_polygon(o, d):
    """Mitred outward offset of a single flat outline by d mm (the star has one convex-concave loop)."""
    bm = bmesh.new()
    bm.from_mesh(o.data)
    bnd = [e for e in bm.edges if e.is_boundary]
    nxt = {}
    for e in bnd:
        a, b = e.verts
        nxt.setdefault(a, []).append(b)
        nxt.setdefault(b, []).append(a)
    start = bnd[0].verts[0]
    loop, prev, cur = [start], None, start
    while True:
        cand = [v for v in nxt[cur] if v is not prev]
        if not cand or cand[0] is start:
            break
        prev, cur = cur, cand[0]
        loop.append(cur)
    pts = [v.co.to_2d() for v in loop]
    # drop collinear points so every corner gets a proper mitre
    keep = []
    for i in range(len(pts)):
        a, b, c = pts[i - 1], pts[i], pts[(i + 1) % len(pts)]
        if abs((b - a).to_3d().cross((c - b).to_3d()).z) > 1e-6:
            keep.append(b)
    pts = keep
    if sum((pts[i - 1].x * pts[i].y - pts[i].x * pts[i - 1].y) for i in range(len(pts))) < 0:
        pts.reverse()
    n = len(pts)
    out = []
    for i in range(n):
        p0, p1, p2 = pts[i - 1], pts[i], pts[(i + 1) % n]
        e1 = (p1 - p0).normalized()
        e2 = (p2 - p1).normalized()
        n1 = Vector((e1.y, -e1.x))
        n2 = Vector((e2.y, -e2.x))
        m = (n1 + n2)
        m = m / (1 + n1.dot(n2))
        out.append(p1 + m * d)
    bm.free()
    me = o.data
    me.clear_geometry()
    me.from_pydata([(q.x, q.y, 0.0) for q in out], [], [list(range(n))])
    me.update()


def fill_holes(o):
    """Rebuild the outline as one n-gon per boundary loop so the face is clean after clipping."""
    bm = bmesh.new()
    bm.from_mesh(o.data)
    bmesh.ops.dissolve_limit(bm, angle_limit=0.0001, verts=bm.verts, edges=bm.edges)
    bm.to_mesh(o.data)
    bm.free()


FONT_DIR = os.path.join(ROOT, "case", "brand_build")


def font(name):
    return bpy.data.fonts.load(os.path.join(FONT_DIR, name), check_existing=True)


def em_per_size():
    """Blender's text size is not the font em. Measure it once on Playfair's O (-14..722 units)."""
    cu = bpy.data.curves.new("em_probe", type="FONT")
    cu.body = "O"
    cu.font = font("PlayfairDisplay-500.ttf")
    cu.size = 1.0
    t = bpy.data.objects.new("em_probe", cu)
    BRAND.objects.link(t)
    o = to_mesh_object(t, "em_probe_mesh")
    x0, x1, y0, y1 = bounds2d(o)
    bpy.data.objects.remove(o, do_unlink=True)
    bpy.data.objects.remove(t, do_unlink=True)
    bpy.data.curves.remove(cu)
    return (y1 - y0) / 0.736


TEXT_FIT = {}


def text_2d(name, lines, em, italic_ranges, width=None, all_italic=False, off=0.0, key=None):
    """lines: list of strings; italic_ranges: (line, start, end) set in the italic font.
    Returns a flat mesh centred on the origin, 1 unit = 1 mm."""
    k = em_per_size()
    cu = bpy.data.curves.new(name + "_curve", type="FONT")
    cu.body = "\n".join(lines)
    cu.font = font("PlayfairDisplay-400-Italic.ttf" if all_italic else "PlayfairDisplay-500.ttf")
    cu.font_italic = font("PlayfairDisplay-400-Italic.ttf")
    cu.size = em / k
    cu.space_line = 1.05
    cu.align_x = "CENTER"
    cu.align_y = "CENTER"
    cu.fill_mode = "BOTH"
    # off is in mm on the final mesh; the text is later scaled by the width fit
    cu.offset = off / TEXT_FIT[key or name][0] if off else 0.0
    offs = [0]
    for ln in lines[:-1]:
        offs.append(offs[-1] + len(ln) + 1)
    for li, a, b in italic_ranges:
        for i in range(offs[li] + a, offs[li] + b):
            cu.body_format[i].use_italic = True
    clear(name + "_obj")
    t = bpy.data.objects.new(name + "_obj", cu)
    BRAND.objects.link(t)
    o = to_mesh_object(t, name + "_2d")
    apply_matrix(o, Matrix.Identity(4))
    x0, x1, y0, y1 = bounds2d(o)
    key = key or name
    if not off:
        TEXT_FIT[key] = (width / (x1 - x0) if width else 1.0, (x0 + x1) / 2, (y0 + y1) / 2)
    k2, cx, cy = TEXT_FIT[key]
    o.data.transform(Matrix.Scale(k2, 4) @ Matrix.Translation(Vector((-cx, -cy, 0))))
    t.hide_viewport = True
    t.hide_render = True
    return o


def outset(o, amount, name):
    clear(name)
    me = o.data.copy()
    n = bpy.data.objects.new(name, me)
    BRAND.objects.link(n)
    bm = bmesh.new()
    bm.from_mesh(me)
    if amount:
        bmesh.ops.inset_region(bm, faces=bm.faces[:], thickness=amount, use_outset=True, use_even_offset=True)
    bm.to_mesh(me)
    bm.free()
    return n


def extrude(o, depth):
    """Flat outline at z = 0 -> closed solid from z = 0 to z = -depth."""
    bm = bmesh.new()
    bm.from_mesh(o.data)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    for f in bm.faces:
        if f.normal.z < 0:
            f.normal_flip()
    ret = bmesh.ops.extrude_face_region(bm, geom=bm.faces[:])
    verts = [e for e in ret["geom"] if isinstance(e, bmesh.types.BMVert)]
    bmesh.ops.translate(bm, verts=verts, vec=(0, 0, -depth))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(o.data)
    bm.free()


def place(o, m):
    o.data.transform(m)
    o.data.update()


def cut(target_name, cutter):
    t = bpy.data.objects[target_name]
    mod = t.modifiers.new("brand_pocket", "BOOLEAN")
    mod.operation = "DIFFERENCE"
    mod.solver = "MANIFOLD"   # clean output; EXACT left sliver faces that self-intersect on the pocket rims
    mod.object = cutter
    bpy.context.view_layer.objects.active = t
    for s in bpy.context.selected_objects:
        s.select_set(False)
    t.select_set(True)
    before = len(t.data.polygons)
    bpy.ops.object.modifier_apply(modifier=mod.name)
    # tidy slivers left by the boolean, but only keep the tidy-up if the mesh stays manifold
    bm = bmesh.new()
    bm.from_mesh(t.data)
    bmesh.ops.dissolve_degenerate(bm, dist=0.0002, edges=bm.edges)
    if not any(not e.is_manifold for e in bm.edges):
        bm.to_mesh(t.data)
    bm.free()
    bm = bmesh.new()
    bm.from_mesh(t.data)
    bad = sum(1 for e in bm.edges if not e.is_manifold)
    n = len(bm.faces)
    bm.free()
    if n < before * 0.5 or bad:
        raise RuntimeError(f"pocket boolean on {target_name} failed: {n} faces (was {before}), {bad} non-manifold edges")


def grown(builder, name, amount):
    """Flat outline grown by `amount` mm per side. Builders take the growth in millimetres."""
    base = builder(name + "_g0", 0.0)
    if not amount:
        return base
    h0 = bounds2d(base)[3] - bounds2d(base)[2]
    o = builder(name + "_g", amount)
    got = ((bounds2d(o)[3] - bounds2d(o)[2]) - h0) / 2
    print(f"   {name}: grown {got:.3f} mm per side on the height (asked {amount})")
    bpy.data.objects.remove(base, do_unlink=True)
    return o


def make(key, builder, m, target, boost, depth=None):
    d, c = depth or P["INLAY_D"], P["INLAY_CLR"]
    flat = grown(builder, key + "_inlay_2d", boost)
    inlay = outset(flat, 0.0, f"inlay_{key}")
    extrude(inlay, d)
    place(inlay, m)
    pk = grown(builder, key + "_pocket_2d", boost + c)
    fill = outset(pk, 0.0, f"fill_{key}")
    extrude(fill, d)
    place(fill, m)
    cutter = outset(pk, 0.0, f"cutter_{key}")
    extrude(cutter, d + 0.05)
    place(cutter, m @ Matrix.Translation(Vector((0, 0, 0.05))))
    cut(target, cutter)
    for ob in (cutter, fill, flat, pk):
        ob.hide_viewport = True
        ob.hide_render = True
    for ob in (inlay, fill):
        ob.data.materials.clear()
        ob.data.materials.append(M_WHITE)
    xs = [v.co for v in inlay.data.vertices]
    lo = Vector([min(v[i] for v in xs) for i in range(3)])
    hi = Vector([max(v[i] for v in xs) for i in range(3)])
    print(key, "size", tuple(round(v, 2) for v in (hi - lo)), "centre", tuple(round(v, 2) for v in (lo + hi) / 2))


def stl_mark(mark, m, target):
    """Type marks come from case/cad/marks.py (HarfBuzz + shapely round joins): Blender's text
    offset leaves spikes and overlapping faces on sharp corners, which broke the exact boolean."""
    out = os.path.join(ROOT, "case", "cad", "out")
    made = {}
    for key in ("inlay", "fill", "cutter"):
        name = f"{key}_{mark}"
        clear(name)
        bpy.ops.wm.stl_import(filepath=os.path.join(out, f"{mark}_{key}.stl"))
        o = bpy.context.selected_objects[0]
        for u in o.users_collection:
            u.objects.unlink(o)
        BRAND.objects.link(o)
        o.name = name
        o.data.transform(m)
        o.data.materials.clear()
        o.data.materials.append(M_WHITE)
        made[key] = o
    cut(target, made["cutter"])
    for key in ("fill", "cutter"):
        made[key].hide_viewport = True
        made[key].hide_render = True


def build():
    for o in list(BRAND.objects):
        bpy.data.objects.remove(o, do_unlink=True)
    # the back face is z = Z_BACK_OUT with normal -z: flip about y so the marks read from behind
    back = Matrix.Rotation(math.radians(180), 4, "Y")
    zb, zf = P["Z_BACK_OUT"], P["Z_FRONT_OUT"]
    # back: the brand lockup, star over Ori-on
    make("star_back", lambda n, off: star_2d(P["STAR_S"], n, off),
         Matrix.Translation(Vector((P["STAR_C"][0], P["STAR_C"][1], zb))) @ back, "rear_shell", 0.0)
    # the Blender text object sets the wordmark; marks.py makes the printable solids from the same fonts
    ref = text_2d("wordmark_reference", ["Orion"], P["WORDMARK_EM"], [(0, 3, 5)], key="wordmark")
    ref.hide_viewport = ref.hide_render = True
    stl_mark("wordmark", Matrix.Translation(Vector((P["WORDMARK_C"][0], P["WORDMARK_C"][1], zb))) @ back, "rear_shell")
    # front: the star on the crown, the tagline very small at the bottom, all in italic
    make("star_front", lambda n, off: star_2d(P["FRONT_STAR_S"], n, off),
         Matrix.Translation(Vector((P["FRONT_STAR_C"][0], P["FRONT_STAR_C"][1], zf))), "front_bezel", 0.0)
    stl_mark("tagline", Matrix.Translation(Vector((P["TAGLINE_C"][0], P["TAGLINE_C"][1], zf))), "front_bezel")

build()
