"""Plot the silkscreen and part outlines from the converted meshes, top and bottom view."""
import json, sys
import numpy as np, trimesh
import matplotlib; matplotlib.use("Agg")
import matplotlib.pyplot as plt
from matplotlib.collections import PolyCollection
parts = json.load(open("meshes/parts.json"))
for side in ("top", "bottom"):
    fig, ax = plt.subplots(figsize=(9, 20), dpi=110)
    for p in parts:
        n = p["name"]
        top_part = p["max"][2] > 1.2
        if n in ("Board",):
            m = trimesh.load(f"meshes/{n}.stl")
            tri = m.triangles[:, :, :2]
            if side == "bottom": tri = tri * [-1, 1]
            ax.add_collection(PolyCollection(tri, facecolor="#1a3a1a", edgecolor="none"))
            continue
        want = ("TopSilk" if side == "top" else "BottomSilk")
        if n == want:
            m = trimesh.load(f"meshes/{n}.stl"); tri = m.triangles[:, :, :2]
            if side == "bottom": tri = tri * [-1, 1]
            ax.add_collection(PolyCollection(tri, facecolor="white", edgecolor="none"))
            continue
        if n.startswith(("Top", "Bot", "Bottom")): continue
        if (side == "top") != top_part: continue
        x0, y0 = p["min"][:2]; x1, y1 = p["max"][:2]
        if side == "bottom": x0, x1 = -x1, -x0
        big = (x1 - x0) * (y1 - y0) > 4
        ax.add_patch(plt.Rectangle((x0, y0), x1 - x0, y1 - y0, fill=False, ec="orange" if big else "#886600", lw=1 if big else 0.4))
        if big: ax.text((x0 + x1) / 2, (y0 + y1) / 2, n.split("-")[0], color="cyan", fontsize=8, ha="center")
    ax.set_xlim(-31, 31) if False else None
    ax.autoscale(); ax.set_aspect("equal"); ax.set_facecolor("#222")
    ax.grid(True, color="#444", lw=0.3); ax.set_xticks(np.arange(-30 if side=="bottom" else -2, 31, 2)); ax.set_yticks(np.arange(-2, 70, 2))
    ax.tick_params(labelsize=6)
    ax.set_title(f"{side} view (bottom view mirrored: x shown as -x)")
    fig.savefig(f"silk_{side}.png", bbox_inches="tight"); plt.close(fig)
print("ok")
