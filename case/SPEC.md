# Orion case

> **Heads up:** the measurements of the 3D case model are not fully accurate yet, and we are
> working on a fix. Print the fit test parts in `fit_test/` first and check the fit before
> printing the whole case.

A two-part printed enclosure for the LilyGO T-CameraPlus-S3 V1.2 board, with a desk stand, a
push-to-talk button, a sealed microphone channel, a sealed speaker pocket and a Wi-Fi antenna
pad. Everything here is generated from `cad/params.py`, so a changed measurement means one
edited number and a rebuild (see "Rebuilding" at the end).

## The honest note first

**The camera is on the opposite face from the screen.** With the screen facing you, the camera
looks away from you. It sees what is placed behind the device ("what do you see"), never your
face. The stand is symmetric, so the case also drops in the other way round: camera toward you,
screen away. The dock (optional) only works screen forward.

**Two sizes are estimates.** LilyGO's official STEP model has no screen and no camera in it (see
below). Their sizes are marked PROV in the table and must be checked with calipers and the fit
test prints before the full case is printed.

## Critical dimensions

Board frame used everywhere: x across the board (0 = left edge, screen facing you), y along it
(0 = the USB-C edge), z = 0 on the back (camera side) face of the PCB, z grows toward the screen.

| Feature | Value (mm) | Source |
| --- | --- | --- |
| PCB outline | 27.974 x 67.974, thickness 1.141 | STEP |
| Positioning holes | 4 x 2.0 at (2.044, 18.953), (25.944, 16.953), (2.044, 65.953), (25.944, 65.953) | STEP |
| Whole STEP assembly box | 30.00 x 69.64 x 10.85 | STEP |
| IO17 push-to-talk switch | 6 x 6 body, 4.7 x 4.7 cap centred (14.00, 15.25), cap top z 6.141 | STEP |
| Microphone MP34DT05-A | lid 2.92 x 3.92, top z 2.142, top port (1.3 recess) at (13.985, 24.224) | STEP, ST datasheet |
| USB-C receptacle | x 9.525 to 18.475, mouth z 1.181 to 4.341, face at y -1.599 | STEP |
| QWIIC CN1, CN2 | beside USB-C, overhang to y -1.651 | STEP |
| RST side button (SW2) | right edge, actuator y 20.88 to 22.59, z -1.24 to -0.54 | STEP, silkscreen "RST" |
| BOOT side button | right edge, actuator y 29.65 to 31.35, same z | STEP, silkscreen "BOOT" |
| Slide switch SW4 | left edge, y 7.9 to 15.7, back side | STEP; schematic: battery disconnect, not power |
| Audio socket CN4 (speaker) | x 0.19 to 3.40, y 21.37 to 25.62, back side to z -4.60 | STEP, silkscreen "Audio" |
| Wi-Fi IPEX RF1 | x 0.55 to 2.55, y 54.10 to 56.10, back side | STEP, silkscreen antenna icon |
| Camera motor CN5 (IR-cut) | x 23.29 to 27.59, y 45.23 to 52.53, back to z -4.71 | STEP, silkscreen "Camera motor" |
| Battery CN3 | x 10.25 to 17.76, y 0.95 to 6.20, back to z -3.55 | STEP, silkscreen "Battery" |
| TF card slot | x 13.39 to 28.64, y 33.02 to 49.02, under the screen | STEP |
| Display frame on the PCB | x 0.06 to 27.5, y 26.49 to 57.69, alignment holes 1.5 / 1.2 | STEP silkscreen |
| Screen glass | 32.0 x 31.4 (x -2.0 to 30.0, y 26.4 to 57.8), top at z 6.8, corner r 3 | PROV (width from the wiki's 32 mm, height from the silkscreen) |
| Active area | 23.4 x 23.4, assumed centred | datasheet of a typical 1.3 inch 240x240 panel, PROV |
| Camera lens | centre (13.1, 38.4), barrel 15.0, tip z -11.0; holder top z -8.0 | PROV |
| Speaker FUET FS2112NB0807-H7.0 | 20.8 x 11.8 x 7.0, front opening 15.0 x 8.0 | FUET datasheet (via LCSC) |
| FPC antenna | 30 x 10 | PROV, no LilyGO spec exists; pad is parametric |

### The wiki versus the STEP

The wiki says 60 x 32 x 12 mm. A third party measured about 30.00 x 69.67 x 10.87 from the STEP.
Measured here: the whole STEP assembly is 30.00 x 69.64 x 10.85 and the bare PCB 27.97 x 67.97.
So the third-party number is this same STEP, and the STEP holds only the PCB and its soldered parts
(the side buttons stick out to 30.00 across, the back connectors and IO17 switch make the 10.85).
The screen and the camera are missing from it. The wiki's 32 mm matches a screen that overhangs
the 28 mm board on both sides, as LilyGO's photos show, so it is used as the glass width. The
wiki's 60 mm fits nothing on V1.2 (the PCB is 68) and is not used. STEP numbers win everywhere
the STEP has the part.

## Clearances

| Where | Used |
| --- | --- |
| PCB edge to wall | 0.3 minimum (the walls sit 2.2 off the PCB sides because the screen is wider) |
| Connectors, moving parts | 0.3 to 0.4 |
| Screen glass to wall | 0.2 |
| Plunger above the IO17 cap at rest | 0.2 (travel before the click) |
| USB-C overmold channel | 12.6 x 7.6 (12 x 7 plus 0.3 per side), overmold face stops 0.35 short of the receptacle |
| Case in the stand pocket | 0.3 |
| Dock on the extension overmolds | 0.15 |

**Smallest clearance found** (Blender fit check, `blender/fit_report.txt`): 0.20 mm, the plunger
over the IO17 cap, which is the designed travel gap. Next: 0.30 mm, the walls against the QWIIC
connectors and the cable channels. No case part overlaps any board part. Planned contacts: the
bosses clamp the PCB, the lip rests on the glass, the mic ring sits on the mic lid, crush ribs grip
the speaker by 0.1.

## What goes where

- **Front:** the screen window (0.8 mm lip over the glass, glass flush against it), the IO17
  push-to-talk plunger, three 0.9 mm mic holes over a sealed channel whose 0.8 mm ring sits on the
  microphone lid. Small passives sit 0.27 mm from the mic body, so the ring seals on the lid
  around the port instead of on the PCB. The star is on the top, above the screen. "// Seek the
  Undiscovered" is very small at the bottom centre.
- **Back:** the camera opening (0.4 mm larger in radius than the barrel, 0.6 mm countersink; with
  the lens tip at the back face nothing enters a field of view up to about 150 degrees), the
  brand lockup (star over Ori*on*), four screw heads.
- **Top:** the speaker grille, seven 1.1 mm slots, 46 % open. The speaker fires up, from the
  opposite face and 50 mm from the microphone.
- **Right side:** 1.5 mm pinholes for RST and BOOT (teardrop shaped, print without support).
- **Bottom:** the USB-C channel through the neck that sits in the stand.
- **Inside:** the speaker in the top crown, face pressed on a 0.5 mm rim around its opening, held by
  two posts with crush ribs, a ledge and two snap hooks. The antenna on a flat raised pad on the
  inside of the front wall above the screen: beyond the end of the PCB ground plane, away from the
  screen and camera, no screws near it (nearest screw axis 5 mm).
- **Not given openings:** the QWIIC ports (only 0.48 mm of each housing edge shows inside the USB
  channel; a lip to hide them would stop a normal plug short of the receptacle), the battery socket,
  the slide switch (battery disconnect, does nothing without a battery), the TF slot (Orion's
  firmware never mounts the card; change a card by opening the case).

## Brand

- Case colour: `--bg-card` `#111115`, the nearest black the brand allows (no pure black). Logos:
  `--text-white` `#F4F4F5`.
- Mark: `brand/assets/logo.svg`. Front 10 mm, back 9 mm, tips end where the arm is 0.45 mm wide.
- Wordmark: Ori*on* in Playfair Display 500 with the italic syllable, as `brand/logo.md` defines
  it. `brand/voice.md` says the name is never written ORION, so the brief's capital ORION was not
  used.
- Tagline: "// Seek the Undiscovered", `brand/voice.md`, all in Playfair italic, with the `//` of
  the brand's section labels.
- Printability: Playfair's thinnest strokes are 0.02 em. At the sizes the case allows that is
  0.1 to 0.2 mm, so every outline is grown evenly: wordmark by 0.12 mm (thinnest stroke 0.41),
  tagline by 0.08 mm (thinnest 0.21). This is below the brief's 0.8 mm minimum stroke, a choice
  made for the real brand face over a heavy mono face. Print the white pieces in resin, or with a
  0.2 mm nozzle.

## Print settings

Material: PLA or PETG. **Never carbon fibre, metal-filled or conductive filament**: they detune the
Wi-Fi antenna inside the case. Nozzle 0.4, layers 0.2, walls 5 perimeters (2.0 mm), top and bottom
5 layers, infill 20 % for the shells, 40 % for the stand. No supports on any part.

| File | Colour | Orientation | Notes |
| --- | --- | --- | --- |
| `stl/front_bezel.stl` | black | front face down | the face is the first layer: clean bed |
| `stl/rear_shell.stl` | black | back face down | same |
| `stl/button_plunger.stl` | black | flange down | 0.12 layers if you like |
| `stl/stand.stl` | black | bottom down | 40 % infill for weight |
| `stl/dock.stl` | black | bottom down | optional, needs a 10 cm USB-C male-to-female extension |
| `stl/inlay_star.stl`, `inlay_star_back.stl`, `inlay_orion.stl` | white | flat | 0.8 thick, press in with super glue |
| `stl/inlay_tagline.stl` | white | flat | 0.6 thick, resin or 0.2 nozzle |
| `orion_case.3mf` | both | ready | multi-material: shells plus white fills in their pockets |
| `fit_test/fit_coupon.stl` | any | ready | print first |
| `fit_test/screen_frame.stl` | any | face down | print first, try on the real screen |

**White logos, single-nozzle printer:** print the inlay files separately in white (one filament
swap between jobs) and glue them in. A layer colour change does not work here: both branded faces
print face down on the bed. **Multi-colour printer:** use `orion_case.3mf`, give the parts named
`fill_...` the white filament.

Overhangs: no face steeper than 45 degrees except flat ceilings, and the widest flat ceiling is
8.5 mm (limit 10).

## Hardware

- 4 x M2 x 16 pan head self-tapping screws, head 3.8 to 4.0 mm. They go in from the back, through
  the rear standoffs and the PCB, and bite into 1.6 mm pilot holes in the front bosses (4.6 mm of
  thread). Heads sit 0.1 mm below the back face.
- 4 x rubber feet, 8 mm across, up to 1.5 mm thick, in the recesses under the stand.
- Optional: thin foam tape behind the speaker, super glue for the inlays.
- For the dock only: a USB-C male-to-female extension, 10 cm, overmolds about 12 x 7 x 20.

## Assembly order

1. Glue the white inlays into their pockets (skip if printed in place from the 3MF).
2. Rear shell: seat the speaker in the top pocket, grille side up against the rim, pressed under
   the two hooks. Its lead leaves on the left.
3. Front bezel: peel the antenna and stick it flat on the raised pad inside, above the window,
   coax end on the left.
4. With the board still out of the case: plug the antenna coax into the IPEX (back of the board,
   top left) and the speaker lead into the "Audio" socket (back, left).
5. Lay the board into the rear shell, back side down, onto the four standoffs. The speaker lead runs
   down the left side behind the board; the coax goes round the left edge of the board to the front,
   just above the top of the screen. Keep the coax bends at 3 mm radius or more; do not pinch the red
   and blue IR-cut wires on the camera holder.
6. Drop the button plunger into its hole in the bezel from the inside, flange inside.
7. Lower the bezel on: the screen sits in the window, the mic tube lands on the microphone.
8. Four screws from the back, snug only (self-tapping into plastic).
9. Stand: push the USB-C cable up through the hole from below, plug it into the case, lower the case
   into the stand. The cable leaves through the groove at the back.

## What I was unsure about

- **Screen glass size and height, camera lens position, diameter and height.** Not in the STEP, no
  datasheet found. Values are best estimates and PROV-tagged; the back depth of the whole case follows
  the camera height.
- **Antenna size.** LilyGO lists none. The pad is sized for 30 x 10.
- **The FS2112 variant.** The datasheet found is the 7.0 mm tall version; LilyGO's listing gives no
  height. The pocket is parametric.
- **The overmold length** of the user's cable (20 mm assumed): sets how deep the stand has to be.
- **Stroke width** of the brand type (above): at these sizes it needs resin or a 0.2 mm nozzle.

## Caliper check before the full print

Measure and send: PCB length and width; total thickness at the thickest point (usually the lens);
speaker length, width, thickness; antenna strip length and width. Because the STEP lacks them, also:
screen glass width, height and its top above the PCB; lens outer diameter and its centre from the
USB-C edge and the left edge. Print `fit_test/` first and report: USB-C cable plugs fully, screw
bites, button clicks, mic tube sits on the mic, screen frame fits the glass.

## Rebuilding

```
case/ref/.venv/Scripts/python.exe case/cad/build_case.py
case/ref/.venv/Scripts/python.exe case/cad/marks.py
case/ref/.venv/Scripts/python.exe case/cad/export_fit.py
```

Then in Blender, run in order: `blender/import_parts.py`, `branding.py`, `fit_check.py`,
`print_check.py`, `export_print.py`, and for images `render_setup.py` and `render_heroes.py`.

The STEP conversion is `ref/step_to_meshes.py` and the measurements are `ref/measure_board.py`. The
source STEP is not committed (68 MB); get it from
`github.com/Xinyuan-LilyGO/T-CameraPlus-S3/structure/3D_PCB_T-CameraPlus-S3_V1.2_202505091545.step`
(sha256 `b5ac2686...fbb9487`). The converted board is `ref/board_v1.2_parts.glb`, one node per part.
