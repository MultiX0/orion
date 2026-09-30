"""Convert LilyGO's T-CameraPlus-S3 V1.2 STEP into one STL per part, in millimetres.

Usage: .venv/Scripts/python.exe step_to_meshes.py src/board_v1.2.step meshes/

Writes meshes/<part>.stl and meshes/parts.json with each part's world bounding box.
Keeps the parts separate so Blender can measure the screen, lens, USB-C and buttons
one by one.
"""

import json
import re
import sys
from pathlib import Path

from OCP.BRepBndLib import BRepBndLib
from OCP.BRepMesh import BRepMesh_IncrementalMesh
from OCP.Bnd import Bnd_Box
from OCP.IFSelect import IFSelect_RetDone
from OCP.STEPCAFControl import STEPCAFControl_Reader
from OCP.StlAPI import StlAPI_Writer
from OCP.TCollection import TCollection_AsciiString, TCollection_ExtendedString
from OCP.TDF import TDF_Label
from OCP.collections import Sequence_TDF_Label as TDF_LabelSequence
from OCP.TDataStd import TDataStd_Name
from OCP.TDocStd import TDocStd_Document
from OCP.TopLoc import TopLoc_Location
from OCP.XCAFDoc import XCAFDoc_DocumentTool, XCAFDoc_ShapeTool


def label_name(label):
    attr = TDataStd_Name()
    if label.FindAttribute(TDataStd_Name.GetID_s(), attr):
        return TCollection_AsciiString(attr.Get()).ToCString()
    return "unnamed"


def walk(tool, label, loc, out, prefix=""):
    """Collect (name, shape) leaves with their accumulated placement applied."""
    name = label_name(label)
    if XCAFDoc_ShapeTool.IsReference_s(label):
        ref = TDF_Label()
        XCAFDoc_ShapeTool.GetReferredShape_s(label, ref)
        here = loc.Multiplied(XCAFDoc_ShapeTool.GetLocation_s(label))
        walk(tool, ref, here, out, prefix)
        return
    if XCAFDoc_ShapeTool.IsAssembly_s(label):
        kids = TDF_LabelSequence()
        XCAFDoc_ShapeTool.GetComponents_s(label, kids, False)
        for i in range(1, kids.Length() + 1):
            walk(tool, kids.Value(i), loc, out, prefix + name + "/")
        return
    shape = XCAFDoc_ShapeTool.GetShape_s(label)
    out.append((prefix + name, shape.Moved(loc)))


def main(step_path, out_dir):
    out_dir = Path(out_dir)
    out_dir.mkdir(parents=True, exist_ok=True)
    doc = TDocStd_Document(TCollection_ExtendedString("doc"))
    reader = STEPCAFControl_Reader()
    reader.SetNameMode(True)
    if reader.ReadFile(str(step_path)) != IFSelect_RetDone:
        sys.exit("could not read " + str(step_path))
    reader.Transfer(doc)
    tool = XCAFDoc_DocumentTool.ShapeTool_s(doc.Main())
    roots = TDF_LabelSequence()
    tool.GetFreeShapes(roots)
    leaves = []
    for i in range(1, roots.Length() + 1):
        walk(tool, roots.Value(i), TopLoc_Location(), leaves)

    parts = []
    used = {}
    for full, shape in leaves:
        short = full.split("/")[-1]
        if short in ("unnamed", "COMPOUND") and "/" in full:
            short = full.split("/")[-2] + "_" + short
        short = re.sub(r"^D5ws-", "", short)
        short = re.sub(r"[^A-Za-z0-9_.-]+", "_", short)[:60]
        used[short] = used.get(short, 0) + 1
        if used[short] > 1:
            short = f"{short}_{used[short]}"
        box = Bnd_Box()
        BRepBndLib.Add_s(shape, box)
        if box.IsVoid():
            continue
        lo, hi = box.CornerMin(), box.CornerMax()
        x0, y0, z0, x1, y1, z1 = lo.X(), lo.Y(), lo.Z(), hi.X(), hi.Y(), hi.Z()
        BRepMesh_IncrementalMesh(shape, 0.02, False, 0.3, True)
        writer = StlAPI_Writer()
        writer.ASCIIMode = False
        writer.Write(shape, str(out_dir / f"{short}.stl"))
        parts.append({"name": short, "path": full,
                      "min": [round(v, 4) for v in (x0, y0, z0)],
                      "max": [round(v, 4) for v in (x1, y1, z1)]})
        print(f"{short:60s} x {x0:8.3f}..{x1:8.3f}  y {y0:8.3f}..{y1:8.3f}  z {z0:7.3f}..{z1:7.3f}")
    (out_dir / "parts.json").write_text(json.dumps(parts, indent=1))
    print(len(parts), "parts written")


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2])
