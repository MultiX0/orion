"""Build the whole Blender scene from scratch, save orion_case.blend and render the heroes.

Headless:
  "C:\\Program Files\\Blender Foundation\\Blender 5.2\\blender.exe" -b --factory-startup ^
      --python case/blender/build_scene.py -- [--no-render]

Needs case/cad/out (build_case.py, marks.py) and case/ref/meshes (step_to_meshes.py).
"""
import json
import os
import sys

import bpy

ROOT = r"C:\Users\multix\Desktop\Dev\yt-projects\orion\case"
B = os.path.join(ROOT, "blender")
args = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []

# empty scene, millimetres
bpy.ops.wm.read_factory_settings(use_empty=True)
import addon_utils
addon_utils.enable("io_curve_svg", default_set=True)
sc = bpy.context.scene
sc.unit_settings.system = "METRIC"
sc.unit_settings.scale_length = 0.001
sc.unit_settings.length_unit = "MILLIMETERS"
sc.tool_settings.snap_elements = {"INCREMENT"}

# REF_board: the converted STEP, one object per part, locked
col = bpy.data.collections.new("REF_board")
sc.collection.children.link(col)
MESH = os.path.join(ROOT, "ref", "meshes")
for p in json.load(open(os.path.join(MESH, "parts.json"))):
    f = os.path.join(MESH, p["name"] + ".stl")
    if not os.path.exists(f):
        continue
    bpy.ops.wm.stl_import(filepath=f)
    o = bpy.context.selected_objects[0]
    for u in o.users_collection:
        u.objects.unlink(o)
    col.objects.link(o)
    o.name = "REF_" + p["name"]
    o.hide_select = True
    if "Silk" in o.name:
        o.hide_viewport = o.hide_render = True

for step in ("import_parts.py", "branding.py"):
    exec(open(os.path.join(B, step)).read(), {"__name__": "__main__"})

# key dimensions as scene custom properties
P = {}
exec(open(os.path.join(ROOT, "cad", "params.py")).read(), P)
for k, v in P.items():
    if k.isupper() and isinstance(v, (int, float)):
        sc[f"orion_{k}"] = float(v)
    elif k.isupper() and isinstance(v, tuple) and all(isinstance(x, (int, float)) for x in v):
        sc[f"orion_{k}"] = [float(x) for x in v]

exec(open(os.path.join(B, "render_setup.py")).read(), {"__name__": "__main__"})

# Cycles on the GPU when there is one
try:
    cp = bpy.context.preferences.addons["cycles"].preferences
    for dev in ("OPTIX", "CUDA"):
        try:
            cp.compute_device_type = dev
            cp.get_devices()
            if any(d.type == dev for d in cp.devices):
                for d in cp.devices:
                    d.use = d.type == dev
                sc.cycles.device = "GPU"
                print("cycles device", dev)
                break
        except TypeError:
            continue
except KeyError:
    pass

bpy.ops.wm.save_as_mainfile(filepath=os.path.join(ROOT, "orion_case.blend"), compress=True)
print("saved orion_case.blend")

if "--no-render" not in args:
    G = {"__name__": "__main__"}
    exec(open(os.path.join(B, "render_heroes.py")).read(), G)
    G["hero"](engine="CYCLES", samples=int(os.environ.get("ORION_SAMPLES", "160")))
    bpy.ops.wm.save_as_mainfile(filepath=os.path.join(ROOT, "orion_case.blend"), compress=True)
print("done")
