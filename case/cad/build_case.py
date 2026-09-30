"""Build the Orion case from params.py with build123d (OpenCascade).

Writes, in the board frame (see params.py), for Blender:
  out/front_bezel.stl out/rear_shell.stl out/button_plunger.stl out/stand.stl
  out/fit_coupon.stl out/screen_frame.stl
  out/ref_display.stl out/ref_camera.stl out/ref_speaker.stl out/ref_antenna.stl out/ref_usb_plug.stl
Blender adds the branding, runs the checks and exports the print files.

Run: ../ref/.venv/Scripts/python.exe build_case.py
"""

import math
from pathlib import Path

from build123d import (Align, Axis, Box, Cone, Cylinder, Location, Plane, Polygon, Pos,
                       Rectangle, RectangleRounded, Rot, Circle, chamfer, export_stl,
                       extrude, fillet, offset, split, Keep, Solid, Compound)

from params import *

OUT = Path(__file__).parent / "out"
OUT.mkdir(exist_ok=True)
BIG = 400.0


def rrect_prism(x0, y0, x1, y1, z0, z1, r):
    """Rounded rectangle in x-y, extruded from z0 to z1."""
    r = min(r, (x1 - x0) / 2 - 0.01, (y1 - y0) / 2 - 0.01)
    return Pos((x0 + x1) / 2, (y0 + y1) / 2, z0) * extrude(RectangleRounded(x1 - x0, y1 - y0, r), z1 - z0)


def xz_prism(x0, z0, x1, z1, y0, y1, r):
    """Rounded rectangle in x-z, extruded along y from y0 to y1."""
    r = min(r, (x1 - x0) / 2 - 0.01, (z1 - z0) / 2 - 0.01)
    pl = Plane(origin=((x0 + x1) / 2, y0, (z0 + z1) / 2), x_dir=(1, 0, 0), z_dir=(0, 1, 0))
    return pl * extrude(RectangleRounded(x1 - x0, z1 - z0, r), y1 - y0)


def box(x0, y0, z0, x1, y1, z1):
    return Pos((x0 + x1) / 2, (y0 + y1) / 2, (z0 + z1) / 2) * Box(x1 - x0, y1 - y0, z1 - z0)


def cyl_z(x, y, z0, z1, d):
    return Pos(x, y, z0) * Cylinder(d / 2, z1 - z0, align=(Align.CENTER, Align.CENTER, Align.MIN))


def outer_body():
    b = rrect_prism(X_OUT[0], Y_SKIRT, X_OUT[1], Y_TOP_OUT, Z_BACK_OUT, Z_FRONT_OUT, R_PLAN)
    e = b.edges().filter_by_position(Axis.Z, Z_FRONT_OUT - .01, Z_FRONT_OUT + .01) + \
        b.edges().filter_by_position(Axis.Z, Z_BACK_OUT - .01, Z_BACK_OUT + .01)
    b = chamfer(e, EDGE_CH)
    zs = (Z_FRONT_OUT, Z_FRONT_OUT - EDGE_CH, Z_BACK_OUT, Z_BACK_OUT + EDGE_CH)
    new = [ed for ed in b.edges() if any(abs(ed.center().Z - z) < .01 for z in zs)]
    return fillet(new, EDGE_FIL)


def cavity():
    return rrect_prism(X_IN[0], Y_BOT_IN, X_IN[1], Y_CROWN_IN, Z_BACK_IN, Z_FRONT_IN, R_PLAN - WALL)


def cavity_outline(grow):
    face = Pos((X_IN[0] + X_IN[1]) / 2, (Y_BOT_IN + Y_CROWN_IN) / 2) * \
        RectangleRounded(X_IN[1] - X_IN[0], Y_CROWN_IN - Y_BOT_IN, R_PLAN - WALL)
    return offset(face, grow) if grow else face


USB_CX = (USB_X[0] + USB_X[1]) / 2
USB_CZ = (USB_Z[0] + USB_Z[1]) / 2
OM_W, OM_H = USB_OVERMOLD[0] + 2 * CLR_PCB, USB_OVERMOLD[1] + 2 * CLR_PCB   # 12.6 x 7.6


def usb_channel():
    """Overmold channel straight up through the neck and the bottom wall, so the overmold face
    can reach 0.35 mm from the receptacle. A lip to hide the QWIIC edges would stop the plug short."""
    main = xz_prism(USB_CX - OM_W / 2, USB_CZ - OM_H / 2, USB_CX + OM_W / 2, USB_CZ + OM_H / 2,
                    Y_SKIRT - 1, Y_BOT_IN + 0.5, 2.0)
    entry = Plane(origin=(USB_CX, Y_SKIRT - 0.01, USB_CZ), x_dir=(1, 0, 0), z_dir=(0, 1, 0)) *         extrude(RectangleRounded(OM_W + 1.0, OM_H + 1.0, 2.5), 0.5, taper=45)
    return main + entry


def teardrop_x(y, z, d, x0, x1):
    """Horizontal hole along x with a 45 degree point toward +z, so it prints without support."""
    r = d / 2
    pl = Plane(origin=(x0, y, z), x_dir=(0, 1, 0), z_dir=(1, 0, 0))
    tip = r * math.sqrt(2)
    prof = Circle(r) + Polygon((-r * math.sqrt(.5), r * math.sqrt(.5)), (0, tip), (r * math.sqrt(.5), r * math.sqrt(.5)), (0, 0))
    return pl * extrude(prof, x1 - x0)


# ------------------------------------------------------------------ speaker, crown
SPK_CX = (X_IN[0] + X_IN[1]) / 2 - 0.2      # 14.0, centred on the case
SPK_CZ = -4.0
SPK_Y1 = Y_CROWN_IN - 0.5                   # face presses the 0.5 mm rim
SPK_Y0 = SPK_Y1 - SPK_T
SPK_BOX = (SPK_CX - SPK_L / 2, SPK_Y0, SPK_CZ - SPK_W / 2, SPK_CX + SPK_L / 2, SPK_Y1, SPK_CZ + SPK_W / 2)


def speaker_features():
    """Rear shell: rim, grille, posts with crush ribs, ledge and snap hooks."""
    x0, y0, z0, x1, y1, z1 = SPK_BOX
    ow, oh = SPK_OPEN[0] + 2.2, SPK_OPEN[1] + 2.2
    iw, ih = SPK_OPEN[0] + 0.6, SPK_OPEN[1] + 0.6
    rim = xz_prism(SPK_CX - ow / 2, SPK_CZ - oh / 2, SPK_CX + ow / 2, SPK_CZ + oh / 2, SPK_Y1, Y_CROWN_IN + .01, 1.0) - \
        xz_prism(SPK_CX - iw / 2, SPK_CZ - ih / 2, SPK_CX + iw / 2, SPK_CZ + ih / 2, SPK_Y1 - 1, Y_CROWN_IN + 1, 0.6)
    solid = rim
    c = 0.1
    for side in (-1, 1):
        xin = x0 - c if side < 0 else x1 + c
        xa, xb = (xin - 1.2, xin) if side < 0 else (xin, xin + 1.2)
        for ya, yb in ((y0 - 0.5, y0 + 1.5), (y1 - 1.5, Y_CROWN_IN + .01)):
            post = box(xa, ya, Z_BACK_IN - .01, xb, yb, z1 + 1.6)
            # 45 degree hook over the speaker's front edge, both faces at 45 so it prints unsupported
            hook = Plane(origin=(xin, (ya + yb) / 2, z1), x_dir=(-side, 0, 0), z_dir=(0, 1, 0)) *                 extrude(Polygon((0, 0), (0.8, -0.8), (0, -1.6), align=None), (yb - ya) / 2, both=True)
            rib = Pos(xin + side * 0.1, (ya + yb) / 2, Z_BACK_IN) *                 Cylinder(0.3, z1 - Z_BACK_IN - 1.0, align=(Align.CENTER, Align.CENTER, Align.MIN))
            solid = solid + post + hook + rib
    ledge = box(x0 + 1.5, y0 - 1.2 - c, Z_BACK_IN - .01, x1 - 1.5, y0 - c, SPK_CZ + 1.0)
    return solid + ledge


def speaker_grille():
    slots = None
    n, pitch = 7, 2.4          # 1.2 mm slots, 1.2 mm bars, 50 % open
    for i in range(n):
        x = SPK_CX + (i - (n - 1) / 2) * pitch
        s = Plane(origin=(x, Y_CROWN_IN - 1, SPK_CZ), x_dir=(1, 0, 0), z_dir=(0, 1, 0)) * \
            extrude(RectangleRounded(1.2, SPK_OPEN[1], 0.59), WALL + 2)
        slots = s if slots is None else slots + s
    return slots


# ------------------------------------------------------------------ bezel features
MIC_C = (MIC_PORT[0], MIC_PORT[1] - 0.17)   # tube centre, keeps the 0.8 ring on the lid
IO17_C = ((IO17_CAP[0] + IO17_CAP[2]) / 2, (IO17_CAP[1] + IO17_CAP[3]) / 2)
STEM = 5.6
FLANGE = 7.8
REST_GAP = 0.2
RECESS_Z = Z_FRONT_IN + 0.35
PLUNGER_TOP = Z_FRONT_OUT + 0.3


def window_cut():
    x0, x1 = DISP_X[0] + LIP, DISP_X[1] - LIP
    y0, y1 = DISP_Y[0] + LIP, DISP_Y[1] - LIP
    hole = rrect_prism(x0, y0, x1, y1, Z_FRONT_IN - 1, Z_FRONT_OUT + 1, DISP_R - LIP)
    # 45 degree chamfer: stack of steps approximated by a tapered extrude
    taper = Pos((x0 + x1) / 2, (y0 + y1) / 2, Z_FRONT_OUT - LIP) * \
        extrude(RectangleRounded(x1 - x0, y1 - y0, DISP_R - LIP), LIP + .01, taper=-45)
    return hole + taper


def plunger_cut():
    hole = rrect_prism(IO17_C[0] - (STEM + .6) / 2, IO17_C[1] - (STEM + .6) / 2,
                       IO17_C[0] + (STEM + .6) / 2, IO17_C[1] + (STEM + .6) / 2, Z_FRONT_IN - 1, Z_FRONT_OUT + 1, 1.1)
    rec = rrect_prism(IO17_C[0] - (FLANGE + .6) / 2, IO17_C[1] - (FLANGE + .6) / 2,
                      IO17_C[0] + (FLANGE + .6) / 2, IO17_C[1] + (FLANGE + .6) / 2, Z_FRONT_IN - 1, RECESS_Z, 1.3)
    return hole + rec


def plunger():
    z_bot = IO17_TOP_Z + REST_GAP
    flange = rrect_prism(IO17_C[0] - FLANGE / 2, IO17_C[1] - FLANGE / 2, IO17_C[0] + FLANGE / 2,
                         IO17_C[1] + FLANGE / 2, z_bot, RECESS_Z, 1.0)
    stem = rrect_prism(IO17_C[0] - STEM / 2, IO17_C[1] - STEM / 2, IO17_C[0] + STEM / 2,
                       IO17_C[1] + STEM / 2, z_bot, PLUNGER_TOP, 0.8)
    p = flange + stem
    top = p.edges().filter_by_position(Axis.Z, PLUNGER_TOP - .01, PLUNGER_TOP + .01)
    return fillet(top, 0.6)


def mic_features():
    ring = cyl_z(*MIC_C, MIC_TOP_Z, 3.0, 2.9) - cyl_z(*MIC_C, MIC_TOP_Z - 1, 3.1, 1.3)
    tube = cyl_z(*MIC_C, 3.0, Z_FRONT_IN + .01, 4.2)
    return ring + tube


def mic_cut():
    bore = cyl_z(*MIC_C, 3.55, Z_FRONT_IN, 2.4)
    cone = Pos(*MIC_C, 3.0) * Cone(0.65, 1.2, 0.55, align=(Align.CENTER, Align.CENTER, Align.MIN))
    holes = None
    for a in (90, 210, 330):
        h = cyl_z(MIC_C[0] + 0.65 * math.cos(math.radians(a)), MIC_C[1] + 0.65 * math.sin(math.radians(a)),
                  Z_FRONT_IN - .5, Z_FRONT_OUT + 1, 0.9)
        holes = h if holes is None else holes + h
    return bore + cone + holes


def front_bosses():
    out = None
    for i, (x, y) in enumerate(HOLES):
        if i == 0:
            b = cyl_z(x, y, PCB_T, 2.6, FRONT_BOSS_D_LOW) + cyl_z(x, y, 2.6, Z_FRONT_IN + .01, FRONT_BOSS_D)
        else:
            b = cyl_z(x, y, PCB_T, Z_FRONT_IN + .01, FRONT_BOSS_D)
        out = b if out is None else out + b
    return out


def front_pilots():
    out = None
    for x, y in HOLES:
        h = cyl_z(x, y, PCB_T - 1, Z_FRONT_IN - 0.2, PILOT_D)
        out = h if out is None else out + h
    return out


ANT_C = (SPK_CX, (Y_CROWN_IN + DISP_Y[1]) / 2 + 6.0)


def antenna_pad():
    """Raised, flat pad on the crown's inner front face; it also thickens the wall behind the front star."""
    # runs into the side and top walls so no sliver gap is left between pad and wall
    pad = rrect_prism(X_IN[0] - 0.5, ANT_C[1] - (ANT_W + 2.0) / 2, X_IN[1] + 0.5, Y_CROWN_IN + 0.5,
                      Z_FRONT_IN - PAD_H, Z_FRONT_IN + .01, 0.5)
    # backs the front star's inlay pocket so 1.2 mm of wall stays behind it
    back = rrect_prism(X_IN[0] - 0.5, FRONT_STAR_C[1] - 7.5, X_IN[1] + 0.5, FRONT_STAR_C[1] + 7.5,
                       Z_FRONT_IN - PAD_H, Z_FRONT_IN + .01, 1.0)
    return pad + back


# ------------------------------------------------------------------ rear features
def rear_standoffs():
    out = None
    for i, (x, y) in enumerate(HOLES):
        s = cyl_z(x, y, Z_BACK_IN - .01, 0.0, BOSS_D[i])
        out = s if out is None else out + s
    return out


def rear_holes():
    out = None
    for x, y in HOLES:
        h = cyl_z(x, y, Z_BACK_OUT - 1, PCB_T + 1, SCREW_CLR_D) + cyl_z(x, y, Z_BACK_OUT - 1, Z_BACK_OUT + HEAD_H, HEAD_D)
        out = h if out is None else out + h
    return out


def camera_cut():
    d = LENS_D + 2 * 0.4
    hole = cyl_z(*LENS_XY, Z_BACK_OUT - 1, Z_BACK_IN + 1, d)
    cs = Pos(*LENS_XY, Z_BACK_OUT - .01) * Cone(d / 2 + 0.6, d / 2, 0.6 + .01, align=(Align.CENTER, Align.CENTER, Align.MIN))
    return hole + cs


def pinholes():
    out = None
    for act in (RST_ACT, BOOT_ACT):
        y, z = (act[0] + act[1]) / 2, (act[2] + act[3]) / 2
        h = teardrop_x(y, z, 1.5, X_IN[1] - 0.5, X_OUT[1] + 1)
        out = h if out is None else out + h
    return out


def rear_pad():
    """Backs the lockup inlay pockets on the back wall so 1.3 mm stays behind them."""
    return rrect_prism(STAR_C[0] - 10.0, WORDMARK_C[1] - 5.5, STAR_C[0] + 10.0, STAR_C[1] + 5.0,
                       Z_BACK_IN - .01, Z_BACK_IN + PAD_H, 1.0)


# ------------------------------------------------------------------ stand
T = math.radians(TILT)
UP = (0.0, math.cos(T), math.sin(T))
C_DESK = -26.8   # DESIGN, puts the desk 16 mm below the plug column floor
STAND_TOP = 21.0 # DESIGN, height of the stand top above the desk
STAND_W, STAND_D = 46.0, 53.0
STAND_F = (-33.0, 20.0)   # world forward range of the footprint


def desk_plane(u=0.0, c_desk=None):
    o = tuple(v * ((C_DESK if c_desk is None else c_desk) + u) for v in UP)
    return Plane(origin=o, x_dir=(1, 0, 0), z_dir=UP)


def stand():
    # local y on the desk plane points backward, so forward f maps to local y = -f
    cx = (X_OUT[0] + X_OUT[1]) / 2
    cy = -(STAND_F[0] + STAND_F[1]) / 2
    s = desk_plane() * (Pos(cx, cy) * extrude(RectangleRounded(STAND_W, STAND_D, 10.0), STAND_TOP))
    top = [e for e in s.edges() if abs(desk_height(e.center()) - STAND_TOP) < .05]
    bot = [e for e in s.edges() if abs(desk_height(e.center())) < .05]
    s = fillet(top, 3.0)
    bot = [e for e in s.edges() if abs(desk_height(e.center())) < .05]
    s = chamfer(bot, 0.8)
    c = 0.3
    pocket = xz_prism(X_OUT[0] - c, Z_BACK_OUT - c, X_OUT[1] + c, Z_FRONT_OUT + c, Y_SKIRT, Y_SKIRT + 60, EDGE_CH + 0.5)
    # plug column, wide enough for the body facing either way
    zc_fwd = USB_CZ
    zc_rev = (Z_BACK_OUT + Z_FRONT_OUT) - USB_CZ
    col = xz_prism(USB_CX - OM_W / 2 - 1, min(zc_fwd, zc_rev) - OM_H / 2 - 1, USB_CX + OM_W / 2 + 1,
                   max(zc_fwd, zc_rev) + OM_H / 2 + 1, Y_SKIRT - 80, Y_SKIRT + 1, 3.0)
    groove = desk_plane(-1) * (Pos(cx, 40.0) * extrude(RectangleRounded(8.0, 80.0, 2.0), 7.0))
    feet = None
    for fx in (-1, 1):
        for fy in (-1, 1):
            f = desk_plane(-1) * (Pos(cx + fx * (STAND_W / 2 - 8.5), cy + fy * (STAND_D / 2 - 8.5)) * extrude(Circle(4.2), 2.0))
            feet = f if feet is None else feet + f
    return s - pocket - col - groove - feet


def tunnel(pl, x0, x1, y0, y1, wall_h):
    """Tunnel on plane pl (local z up), open at the bottom, walls wall_h tall, roof stepped at 45
    degrees in 0.25 mm steps (one layer each), so it prints upright without support."""
    w = x1 - x0
    body = pl * (Pos((x0 + x1) / 2, (y0 + y1) / 2, wall_h / 2 - 0.5) * Box(w, y1 - y0, wall_h + 1.0))
    roof = None
    n = int(w / 2 / 0.25) + 1
    for i in range(n):
        h = wall_h + i * 0.25
        ww = w - 2 * i * 0.25
        if ww <= 0.2:
            break
        b = pl * (Pos((x0 + x1) / 2, (y0 + y1) / 2, h + 0.125) * Box(ww, y1 - y0, 0.26))
        roof = b if roof is None else roof + b
    return body + roof


def dock():
    """Stand with a USB-C male-to-female extension: male plug up into the board, female socket
    flush in the back. Faces the one way only: the plug sits under the port."""
    c_desk = C_DESK - DOCK_LIFT
    cx = (X_OUT[0] + X_OUT[1]) / 2
    cy = -(STAND_F[0] + STAND_F[1]) / 2
    top_h = STAND_TOP + DOCK_LIFT
    base = desk_plane(c_desk=c_desk) * (Pos(cx, cy) * extrude(RectangleRounded(STAND_W, STAND_D, 10.0), top_h))
    dh = lambda p: p.X * UP[0] + p.Y * UP[1] + p.Z * UP[2] - c_desk
    base = fillet([e for e in base.edges() if abs(dh(e.center()) - top_h) < .05], 3.0)
    base = chamfer([e for e in base.edges() if abs(dh(e.center())) < .05], 0.8)
    c = 0.3
    pocket = xz_prism(X_OUT[0] - c, Z_BACK_OUT - c, X_OUT[1] + c, Z_FRONT_OUT + c, Y_SKIRT, Y_SKIRT + 60, EDGE_CH + 0.5)
    # male overmold: its top face sits 0.35 mm under the receptacle, like a hand-held cable
    top = USB_FRONT_Y - 0.35
    bot = top - DOCK_MALE_LEN
    k = DOCK_CLR
    male = xz_prism(USB_CX - 6.0 - k, USB_CZ - 3.5 - k, USB_CX + 6.0 + k, USB_CZ + 3.5 + k, bot, Y_SKIRT + 1, 2.0)
    lead = xz_prism(USB_CX - 2.75, USB_CZ - 2.75, USB_CX + 2.75, USB_CZ + 2.75, bot - 30, bot + .01, 2.7)
    # under-floor channel from the plug to the back, and the female socket at the back
    pl = desk_plane(c_desk=c_desk)
    f_plug = USB_CZ * math.cos(T) - (bot) * math.sin(T)
    chan = tunnel(pl, cx - 4.0, cx + 4.0, -f_plug - 6.0, -STAND_F[0] - DOCK_FEMALE_LEN + 1, 5.0)
    fem = tunnel(pl, cx - 6.0 - k, cx + 6.0 + k, -STAND_F[0] - DOCK_FEMALE_LEN, -STAND_F[0] + 5, 7.0 + k)
    feet = None
    for fx in (-1, 1):
        for fy in (-1, 1):
            f = desk_plane(-1, c_desk) * (Pos(cx + fx * (STAND_W / 2 - 8.5), cy + fy * (STAND_D / 2 - 8.5)) * extrude(Circle(4.2), 2.0))
            feet = f if feet is None else feet + f
    return base - pocket - male - lead - chan - fem - feet


def desk_height(p):
    return p.X * UP[0] + p.Y * UP[1] + p.Z * UP[2] - C_DESK


# ------------------------------------------------------------------ reference modules (provisional)
def ref_modules():
    disp = rrect_prism(DISP_X[0], DISP_Y[0], DISP_X[1], DISP_Y[1], DISP_Z0, DISP_TOP_Z, DISP_R)
    holder = box(HOLDER[0], HOLDER[1], HOLDER_TOP_Z, HOLDER[2], HOLDER[3], -2.2)
    lens = cyl_z(*LENS_XY, LENS_TIP_Z, HOLDER_TOP_Z + .01, LENS_D)
    spk = box(SPK_BOX[0], SPK_BOX[1], SPK_BOX[2], SPK_BOX[3], SPK_BOX[4], SPK_BOX[5])
    ant = rrect_prism(ANT_C[0] - ANT_L / 2, ANT_C[1] - ANT_W / 2, ANT_C[0] + ANT_L / 2, ANT_C[1] + ANT_W / 2,
                      Z_FRONT_IN - PAD_H - 0.15, Z_FRONT_IN - PAD_H, 1.0)
    plug = xz_prism(USB_CX - 6.0, USB_CZ - 3.5, USB_CX + 6.0, USB_CZ + 3.5, USB_FRONT_Y - USB_OVERMOLD_LEN - 0.35,
                    USB_FRONT_Y - 0.35, 2.0) + \
        xz_prism(USB_CX - 4.1, USB_CZ - 1.2, USB_CX + 4.1, USB_CZ + 1.2, USB_FRONT_Y - 0.36, USB_FRONT_Y + 6.2, 1.1)
    dm_top = USB_FRONT_Y - 0.35
    dock_male = xz_prism(USB_CX - 6.0, USB_CZ - 3.5, USB_CX + 6.0, USB_CZ + 3.5, dm_top - DOCK_MALE_LEN, dm_top, 2.0) +         xz_prism(USB_CX - 4.1, USB_CZ - 1.2, USB_CX + 4.1, USB_CZ + 1.2, dm_top - 0.01, USB_FRONT_Y + 6.2, 1.1)
    return {"ref_dock_male": dock_male, "ref_display": disp, "ref_camera": holder + lens, "ref_speaker": spk, "ref_antenna": ant, "ref_usb_plug": plug}


def main():
    # square the bottom front edge around the USB channel: the 45 degree edge chamfer would
    # otherwise meet the channel roof. Hidden inside the stand pocket.
    body = outer_body() + box(USB_CX - 9.0, Y_SKIRT, USB_CZ + 3.0, USB_CX + 9.0, Y_SKIRT + EDGE_CH + 1.0, Z_FRONT_OUT) - cavity()
    body = body - usb_channel()
    body = body - speaker_grille() - camera_cut() - rear_holes() - pinholes()

    rear = split(body, Plane.XY.offset(Z_SPLIT), keep=Keep.BOTTOM)
    front = split(body, Plane.XY.offset(Z_SPLIT), keep=Keep.TOP)

    rear = rear + rear_standoffs() + speaker_features() + rear_pad()
    rear = rear - rear_holes() - usb_channel() - pinholes()

    front = front + front_bosses() + mic_features() + antenna_pad()
    front = front - window_cut() - plunger_cut() - mic_cut() - front_pilots() - usb_channel()

    parts = {"front_bezel": front, "rear_shell": rear, "button_plunger": plunger(), "stand": stand(), "dock": dock()}
    parts.update(ref_modules())

    # fit coupon: bezel slice with plunger hole, mic tube and boss 2; the USB neck; the plunger
    whole = front + rear
    neck = whole & box(USB_CX - 9, Y_SKIRT - 1, USB_CZ - 6.5, USB_CX + 9, Y_BOT_IN + 0.3, USB_CZ + 6.5)
    slice_ = front & box(IO17_C[0] - 8, 9.0, Z_SPLIT, HOLES[1][0] + 3.2, 26.3, Z_FRONT_OUT + 1)
    parts["fit_coupon_neck"] = neck
    parts["fit_coupon_bezel"] = slice_
    parts["screen_frame"] = front & box(X_OUT[0] - 1, DISP_Y[0] - 0.4, DISP_Z0, X_OUT[1] + 1, DISP_Y[1] + 3.0, Z_FRONT_OUT + 1)

    for name, p in parts.items():
        ok = p.is_valid
        export_stl(p, str(OUT / f"{name}.stl"), tolerance=0.01, angular_tolerance=0.1)
        bb = p.bounding_box()
        print(f"{name:18s} valid={ok} vol={p.volume:9.1f} mm3  "
              f"x {bb.min.X:7.2f}..{bb.max.X:7.2f} y {bb.min.Y:7.2f}..{bb.max.Y:7.2f} z {bb.min.Z:7.2f}..{bb.max.Z:7.2f}")


if __name__ == "__main__":
    main()
