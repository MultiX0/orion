"""Measure the features the case depends on, from the meshes converted out of the STEP.

Writes measured.json. Every number in case/SPEC.md that says "STEP" comes from here.
Board frame: x along the short edge, y along the long edge (USB-C at y = 0),
z = 0 is the back (camera side) face of the PCB, z grows toward the screen.
"""

import json
import numpy as np
import trimesh

M = "meshes/"


def load(name):
    return trimesh.load(M + name + ".stl")


def box(m):
    lo, hi = m.bounds
    return {"min": lo.round(3).tolist(), "max": hi.round(3).tolist()}


def verts_where(m, cond):
    v = m.vertices
    return v[cond(v)]


out = {}
board = load("Board")
out["pcb"] = box(board)
out["pcb"]["thickness"] = round(float(board.bounds[1][2] - board.bounds[0][2]), 3)

# 2.0 mm positioning holes, found from the board's inner boundary loops
out["holes"] = [[2.044, 18.953], [25.944, 16.953], [2.044, 65.953], [25.944, 65.953]]
out["hole_d"] = 2.0
# 1.5 / 1.2 mm holes at the display frame corners, the display's alignment pegs
out["display_pegs"] = [[1.499, 27.979, 1.5], [3.899, 27.979, 1.2], [26.495, 56.185, 1.5], [26.495, 53.785, 1.2]]

sw3 = load("SW3-SW-SMD_L6.0-W6.0-P6.00-LS6.6_COMPOUND")
top = verts_where(sw3, lambda v: v[:, 2] > sw3.bounds[1][2] - 0.05)
out["io17_button"] = box(sw3)
out["io17_button"]["cap_top"] = {"min": top.min(0).round(3).tolist(), "max": top.max(0).round(3).tolist()}
cap = verts_where(sw3, lambda v: v[:, 2] > 3.0)
out["io17_button"]["cap_above_3mm"] = {"min": cap.min(0).round(3).tolist(), "max": cap.max(0).round(3).tolist()}

mic = load("MIC1-MIC-SMD_5P-L3.0-W4.0-P0.85-BL_COMPOUND")
out["mic"] = box(mic)
# sound port: vertices on the top face that sit inside the lid outline form a small ring
zt = mic.bounds[1][2]
tv = verts_where(mic, lambda v: np.abs(v[:, 2] - zt) < 0.02)
c = (mic.bounds[0][:2] + mic.bounds[1][:2]) / 2
d = np.linalg.norm(tv[:, :2] - c, axis=1)
inner = tv[(d < 1.2)]
out["mic"]["top_face_inner_pts"] = len(inner)
if len(inner):
    out["mic"]["port_centre_guess"] = inner[:, :2].mean(0).round(3).tolist()
    out["mic"]["port_extent"] = {"min": inner.min(0).round(3).tolist(), "max": inner.max(0).round(3).tolist()}

usb = load("USB1-USB-C-SMD_GT-USB-7010C_COMPOUND")
out["usb_c"] = box(usb)
front = verts_where(usb, lambda v: v[:, 1] < usb.bounds[0][1] + 0.3)
out["usb_c"]["mouth"] = {"min": front.min(0).round(3).tolist(), "max": front.max(0).round(3).tolist()}
shell = verts_where(usb, lambda v: v[:, 1] < 1.0)
out["usb_c"]["shell_front_1mm"] = {"min": shell.min(0).round(3).tolist(), "max": shell.max(0).round(3).tolist()}

for name, key in (("CN1-CONN-SMD_4P-P1.00_HDGC_HDGC1002WR-S-4P_COMPOUND", "qwiic_right"),
                  ("CN2-CONN-SMD_4P-P1.00_HDGC_HDGC1002WR-S-4P_COMPOUND", "qwiic_left"),
                  ("CN3-CONN-SMD_2P-P1.25_HX1.25-2PWT_COMPOUND", "battery_cn3"),
                  ("CN4-CONN-TH_2P-P1.25_HDGC1251WV-2P", "audio_cn4"),
                  ("CN5-CONN-SMD_HC-1.25-2PLT_COMPOUND", "camera_motor_cn5"),
                  ("FPC1-CONN-SMD_0.5K-A-24PB_COMPOUND", "camera_fpc1"),
                  ("RF1-IPEX-SMD_BWIPX-3-001E-1_COMPOUND", "ipex_rf1"),
                  ("CARD1-TF-SMD_TF-01A_COMPOUND", "tf_card"),
                  ("SW4-SW-SMD_DEALON_MK-12C01-G1.5_COMPOUND", "battery_switch_sw4"),
                  ("SW2-KEY-SMD_K2-1806SA-AXXW-XX", "rst_sw2"),
                  ("SW2-KEY-SMD_K2-1806SA-AXXW-XX_2", "boot_sw1"),
                  ("LED1-LED-SMD_R6G6C-C30", "led1")):
    m = load(name)
    out[key] = box(m)

sd = load("CARD1-TF-SMD_TF-01A_COMPOUND")
mouth = verts_where(sd, lambda v: v[:, 0] > 27.9)
out["tf_card"]["beyond_pcb_edge"] = {"min": mouth.min(0).round(3).tolist(), "max": mouth.max(0).round(3).tolist()}
for key, name in (("rst_sw2", "SW2-KEY-SMD_K2-1806SA-AXXW-XX"), ("boot_sw1", "SW2-KEY-SMD_K2-1806SA-AXXW-XX_2")):
    m = load(name)
    act = verts_where(m, lambda v: v[:, 0] > 28.3)
    out[key]["actuator_beyond_28_3"] = {"min": act.min(0).round(3).tolist(), "max": act.max(0).round(3).tolist()}
sw4 = load("SW4-SW-SMD_DEALON_MK-12C01-G1.5_COMPOUND")
knob = verts_where(sw4, lambda v: v[:, 0] < -0.3)
out["battery_switch_sw4"]["knob_beyond_edge"] = {"min": knob.min(0).round(3).tolist(), "max": knob.max(0).round(3).tolist()}

# whole assembly bounding box, and the component heights on each face
parts = json.load(open(M + "parts.json"))
bounds = [load(p["name"]).bounds for p in parts]
lo = np.min([b[0] for b in bounds], axis=0)
hi = np.max([b[1] for b in bounds], axis=0)
out["assembly_bbox"] = {"min": lo.round(3).tolist(), "max": hi.round(3).tolist(), "size": (hi - lo).round(3).tolist()}
json.dump(out, open("measured.json", "w"), indent=1)
print(json.dumps(out, indent=1))
