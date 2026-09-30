"""Viewport helper for checking the model: exec this, then call view(...)."""
import math
import bpy
from mathutils import Euler, Vector


def view(rot_deg, center=(14, 36, -2), dist=170, persp="PERSP", xray=False):
    for a in bpy.context.screen.areas:
        if a.type == "VIEW_3D":
            r = a.spaces[0].region_3d
            r.view_rotation = Euler([math.radians(v) for v in rot_deg]).to_quaternion()
            r.view_location = Vector(center)
            r.view_distance = dist
            r.view_perspective = persp
            sp = a.spaces[0]
            sp.shading.type = "SOLID"
            sp.shading.color_type = "MATERIAL"
            sp.shading.show_xray = xray
            sp.overlay.show_floor = False
            sp.overlay.show_axis_x = False
            sp.overlay.show_axis_y = False
            sp.overlay.show_cursor = False
            sp.overlay.show_object_origins = False


def show(names=None, hide=None):
    for o in bpy.data.objects:
        if names is not None:
            o.hide_viewport = not any(o.name.startswith(n) for n in names)
        if hide and any(o.name.startswith(n) for n in hide):
            o.hide_viewport = True
