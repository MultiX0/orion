"""Export the print files from Blender, after print_check.py has made the print copies.

Run in Blender: exec(open(r".../case/blender/export_print.py").read())

  case/stl/<part>.stl   one file per part, in print orientation, on z = 0, millimetres
  case/orion_case.3mf   multi-material: each shell with its white inlays as parts of one
                        object (brand colours: case --bg-card #111115, inlays --text-white #F4F4F5)
"""
import os
import zipfile

import bpy
from mathutils import Matrix, Vector

ROOT = r"C:\Users\multix\Desktop\Dev\yt-projects\orion\case"
STL = os.path.join(ROOT, "stl")
os.makedirs(STL, exist_ok=True)

# print copy name -> published file name (the SPEC.md names where it gives one)
FILES = {
    "P_front_bezel": "front_bezel",
    "P_rear_shell": "rear_shell",
    "P_button_plunger": "button_plunger",
    "P_stand": "stand",
    "P_dock": "dock",
    "P_inlay_star_front": "inlay_star",
    "P_inlay_star_back": "inlay_star_back",
    "P_inlay_wordmark": "inlay_orion",
    "P_inlay_tagline": "inlay_tagline",
}
# 3MF groups: shell and the pocket fills that sit in it (fills are the pocket shape)
GROUPS = {
    "front_bezel": ["fill_star_front", "fill_tagline"],
    "rear_shell": ["fill_star_back", "fill_wordmark"],
    "button_plunger": [],
    "stand": [],
}


def tris(me, m=Matrix.Identity(4)):
    me.calc_loop_triangles()
    verts = [m @ v.co for v in me.vertices]
    return verts, [tuple(t.vertices) for t in me.loop_triangles]


def write_stl(path, verts, faces):
    import struct
    with open(path, "wb") as f:
        f.write(b"Orion case".ljust(80, b" "))
        f.write(struct.pack("<I", len(faces)))
        for a, b, c in faces:
            va, vb, vc = verts[a], verts[b], verts[c]
            n = (vb - va).cross(vc - va)
            n = n.normalized() if n.length else n
            f.write(struct.pack("<12fH", *n, *va, *vb, *vc, 0))


def print_matrix(src_name):
    """The transform print_check.py used for this part: orientation, then drop onto the bed."""
    src = bpy.data.objects[src_name]
    cp = bpy.data.objects["P_" + src_name]
    PC = {}
    exec(open(os.path.join(ROOT, "blender", "print_check.py")).read().split("\ndef coll")[0], PC)
    m = PC["PARTS"][src_name] @ src.matrix_world
    off = cp.data.vertices[0].co - (m @ src.data.vertices[0].co)
    return Matrix.Translation(off) @ m


def export_stls():
    out = []
    for cp, name in FILES.items():
        o = bpy.data.objects.get(cp)
        if not o:
            print("missing", cp)
            continue
        v, f = tris(o.data)
        write_stl(os.path.join(STL, name + ".stl"), v, f)
        out.append((name, len(f)))
    print("stl:", out)


def write_3mf(path):
    mats = [("case_bg_card", "#111115FF"), ("white_text", "#F4F4F5FF")]
    objects, items, oid = [], [], 2
    x_cursor = 0.0
    for part, fills in GROUPS.items():
        m = print_matrix(part)
        comps = []
        bodies = [(part, bpy.data.objects[part], 0)] + [(fn, bpy.data.objects[fn], 1) for fn in fills]
        allv = []
        for label, ob, mat in bodies:
            v, f = tris(ob.data, m)
            allv += v
            comps.append((oid, label, mat, v, f))
            oid += 1
        xs = [p.x for p in allv]
        shift = x_cursor - min(xs)
        x_cursor += (max(xs) - min(xs)) + 10.0
        group_id = oid
        oid += 1
        for cid, label, mat, v, f in comps:
            vx = "".join(f'<vertex x="{p.x + shift:.4f}" y="{p.y:.4f}" z="{p.z:.4f}"/>' for p in v)
            tx = "".join(f'<triangle v1="{a}" v2="{b}" v3="{c}"/>' for a, b, c in f)
            objects.append(f'<object id="{cid}" name="{label}" type="model" pid="1" pindex="{mat}">'
                           f'<mesh><vertices>{vx}</vertices><triangles>{tx}</triangles></mesh></object>')
        cx = "".join(f'<component objectid="{cid}"/>' for cid, *_ in comps)
        objects.append(f'<object id="{group_id}" name="{part}" type="model"><components>{cx}</components></object>')
        items.append(f'<item objectid="{group_id}"/>')
    base = "".join(f'<base name="{n}" displaycolor="{c}"/>' for n, c in mats)
    model = ('<?xml version="1.0" encoding="UTF-8"?>'
             '<model unit="millimeter" xml:lang="en-US" xmlns="http://schemas.microsoft.com/3dmanufacturing/core/2015/02">'
             '<metadata name="Title">Orion case</metadata>'
             f'<resources><basematerials id="1">{base}</basematerials>{"".join(objects)}</resources>'
             f'<build>{"".join(items)}</build></model>')
    ctypes = ('<?xml version="1.0" encoding="UTF-8"?>'
              '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
              '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>'
              '<Default Extension="model" ContentType="application/vnd.ms-package.3dmanufacturing-3dmodel+xml"/></Types>')
    rels = ('<?xml version="1.0" encoding="UTF-8"?>'
            '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
            '<Relationship Target="/3D/3dmodel.model" Id="rel0" '
            'Type="http://schemas.microsoft.com/3dmanufacturing/2013/01/3dmodel"/></Relationships>')
    with zipfile.ZipFile(path, "w", zipfile.ZIP_DEFLATED) as z:
        z.writestr("[Content_Types].xml", ctypes)
        z.writestr("_rels/.rels", rels)
        z.writestr("3D/3dmodel.model", model)
    print("3mf:", path, os.path.getsize(path) // 1024, "KB")


export_stls()
write_3mf(os.path.join(ROOT, "orion_case.3mf"))
