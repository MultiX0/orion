# Orion case

The 3D printed enclosure and desk stand for the LilyGO T-CameraPlus-S3 V1.2.

> **Heads up:** the measurements of the 3D case model are not fully accurate yet, and we are working on a fix. Print the fit test parts in [`fit_test/`](fit_test) first and check the fit before printing the whole case.

- Overview, printing, hardware and design decisions: [docs/CASE.md](../docs/CASE.md)
- Every dimension with its source, assembly and the caliper checklist: [SPEC.md](SPEC.md)

```
stl/            print files, one per part
orion_case.3mf  multi-material: shells with the white logo fills
fit_test/       print these first
cad/            build123d sources; params.py holds every dimension
blender/        fit check, print check, exports and renders
ref/            the board, converted from LilyGO's STEP, and its measurements
renders/        front, back and exploded views
```
