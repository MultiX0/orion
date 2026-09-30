"""Type outlines for the inlays, from the brand's Playfair Display files.

  wordmark  "Ori" in Playfair Display 500 + "on" in Playfair Display italic (brand/logo.md)
  tagline   "// Seek the Undiscovered", all italic, very small (brand/voice.md)

Shaped with HarfBuzz (real kerning), outlined with fontTools, grown with shapely using round
joins. Blender's own text offset leaves spikes and overlapping faces at sharp corners, which
broke the exact boolean, so the solids come from here and blender/branding.py places them.
Writes cad/out/<mark>_inlay.stl, <mark>_fill.stl, <mark>_cutter.stl, centred on the origin,
face at z = 0, going to negative z.
"""
from pathlib import Path

import numpy as np
import trimesh
import uharfbuzz as hb
from fontTools.pens.basePen import BasePen
from fontTools.ttLib import TTFont
from shapely.affinity import scale, translate
from shapely.geometry import Polygon
from shapely.ops import unary_union

import params as P

FONTS = Path(__file__).parents[1] / "brand_build"
ROMAN = FONTS / "PlayfairDisplay-500.ttf"
ITALIC = FONTS / "PlayfairDisplay-400-Italic.ttf"
OUT = Path(__file__).parent / "out"


class FlatPen(BasePen):
    def __init__(self, gs):
        super().__init__(gs)
        self.contours, self.cur = [], []

    def _moveTo(self, p):
        self.cur = [p]

    def _lineTo(self, p):
        self.cur.append(p)

    def _curveToOne(self, p1, p2, p3):
        p0 = np.array(self.cur[-1])
        for t in np.linspace(0, 1, 18)[1:]:
            self.cur.append(tuple((1 - t) ** 3 * p0 + 3 * (1 - t) ** 2 * t * np.array(p1)
                                  + 3 * (1 - t) * t ** 2 * np.array(p2) + t ** 3 * np.array(p3)))

    def _qCurveToOne(self, p1, p2):
        p0 = np.array(self.cur[-1])
        for t in np.linspace(0, 1, 18)[1:]:
            self.cur.append(tuple((1 - t) ** 2 * p0 + 2 * (1 - t) * t * np.array(p1) + t ** 2 * np.array(p2)))

    def _closePath(self):
        if len(self.cur) > 2:
            self.contours.append(self.cur)
        self.cur = []


def outline(text, font_path, x_start=0.0):
    """Returns (shape, advance) in font units."""
    blob = hb.Blob.from_file_path(str(font_path))
    face = hb.Face(blob)
    font = hb.Font(face)
    buf = hb.Buffer()
    buf.add_str(text)
    buf.guess_segment_properties()
    hb.shape(font, buf, {"kern": True, "liga": False})
    tt = TTFont(str(font_path))
    gs = tt.getGlyphSet()
    order = tt.getGlyphOrder()
    x = x_start
    shapes = []
    for info, pos in zip(buf.glyph_infos, buf.glyph_positions):
        pen = FlatPen(gs)
        gs[order[info.codepoint]].draw(pen)
        g = None
        for c in pen.contours:
            p = Polygon(c).buffer(0)
            g = p if g is None else g.symmetric_difference(p)
        if g is not None:
            shapes.append(translate(g, x + pos.x_offset, pos.y_offset))
        x += pos.x_advance
    return unary_union(shapes), x


def solid(shape, z0, z1):
    parts = [shape] if shape.geom_type == "Polygon" else list(shape.geoms)
    meshes = [trimesh.creation.extrude_polygon(p, z1 - z0) for p in parts]
    m = trimesh.util.concatenate(meshes)
    m.merge_vertices()
    m.update_faces(m.nondegenerate_faces(height=1e-5))
    m.remove_unreferenced_vertices()
    trimesh.repair.fill_holes(m)
    m.apply_translation((0, 0, z0))
    return m


def tidy(g):
    """Drop points closer than 3 microns and repair, so the extruded solid has no slivers."""
    return g.simplify(0.003, preserve_topology=True).buffer(0)


def write(name, g, boost, clr, depth):
    inlay = tidy(g.buffer(boost, join_style="round", quad_segs=6))
    pocket = tidy(g.buffer(boost + clr, join_style="round", quad_segs=6))
    solid(inlay, -depth, 0).export(OUT / f"{name}_inlay.stl")
    solid(pocket, -depth, 0).export(OUT / f"{name}_fill.stl")
    solid(pocket, -depth, 0.05).export(OUT / f"{name}_cutter.stl")
    b = inlay.bounds
    thin = next((w / 100 for w in range(5, 200)
                 if (inlay.area - inlay.buffer(-w / 200).buffer(w / 200).area) / inlay.area > 0.02), None)
    print(f"{name}: {b[2] - b[0]:.2f} x {b[3] - b[1]:.2f} mm, thinnest stroke about {thin} mm")


def centred(g, k):
    g = scale(g, k, k, origin=(0, 0))
    x0, y0, x1, y1 = g.bounds
    return translate(g, -(x0 + x1) / 2, -(y0 + y1) / 2)


def main():
    # wordmark: em set by WORDMARK_EM, 1000 units per em
    ori, adv = outline("Ori", ROMAN)
    on, _ = outline("on", ITALIC, adv)
    write("wordmark", centred(unary_union([ori, on]), P.WORDMARK_EM / 1000), P.BOOST_WORDMARK, P.INLAY_CLR, P.INLAY_D)
    # tagline: fitted to TAGLINE_W
    g, _ = outline(P.TAGLINE, ITALIC)
    x0, y0, x1, y1 = g.bounds
    write("tagline", centred(g, P.TAGLINE_W / (x1 - x0)), P.BOOST_TAGLINE, P.TAGLINE_CLR, P.TAGLINE_D)


if __name__ == "__main__":
    main()
