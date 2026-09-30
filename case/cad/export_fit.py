"""Fit test prints, in print orientation, from the build123d output.

  fit_test/fit_coupon.stl    bezel slice (plunger hole, mic channel, boss 2) face down, the USB
                             neck block standing on its bottom, and a button plunger: one plate
  fit_test/screen_frame.stl  the bezel around the window, face down, to try on the real screen
"""
from pathlib import Path

import numpy as np
import trimesh

OUT = Path(__file__).parent / "out"
FIT = Path(__file__).parents[1] / "fit_test"
FIT.mkdir(exist_ok=True)


def drop(m, rot=None, at=(0, 0)):
    m = m.copy()
    if rot is not None:
        m.apply_transform(rot)
    lo, hi = m.bounds
    m.apply_translation((at[0] - (lo[0] + hi[0]) / 2, at[1] - (lo[1] + hi[1]) / 2, -lo[2]))
    return m


flip = trimesh.transformations.rotation_matrix(np.pi, (0, 1, 0))
stand_up = trimesh.transformations.rotation_matrix(np.pi / 2, (1, 0, 0))
bezel = drop(trimesh.load(OUT / "fit_coupon_bezel.stl"), flip, (0, 0))
neck = drop(trimesh.load(OUT / "fit_coupon_neck.stl"), stand_up, (28, 0))
plunger = drop(trimesh.load(OUT / "button_plunger.stl"), None, (0, 22))
coupon = trimesh.util.concatenate([bezel, neck, plunger])
coupon.export(FIT / "fit_coupon.stl")
frame = drop(trimesh.load(OUT / "screen_frame.stl"), flip)
frame.export(FIT / "screen_frame.stl")
for name, m in (("fit_coupon", coupon), ("screen_frame", frame)):
    print(name, "bodies", m.body_count, "size", (m.bounds[1] - m.bounds[0]).round(1), "volume", round(m.volume / 1000, 2), "cm3")
