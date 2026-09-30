"""Every dimension the Orion case is built from, with where it came from.

Board frame, millimetres: x across the board (0 = left edge seen from the screen side),
y along the board (0 = USB-C edge), z = 0 at the back (camera side) face of the PCB,
z grows toward the screen.

Source tags:
  STEP     measured from LilyGO's 3D_PCB_T-CameraPlus-S3_V1.2_202505091545.step
           (case/ref/measure_board.py, case/ref/measured.json)
  SILK     the display outline printed on the PCB top silkscreen, same STEP
  WIKI     wiki.lilygo.cc T-Camera Plus S3 page
  DS       a manufacturer datasheet, named on the line
    PROV     provisional: the STEP has no screen or camera model and no datasheet exists.
             Replace with the caliper check in SPEC.md and rebuild.
    DESIGN   a design choice
    SPEC     a requirement the case is built to, see SPEC.md
"""

# ---- board (STEP) ----
PCB_W = 27.974            # STEP, x 0.007 .. 27.981
PCB_L = 67.974            # STEP, y 0.016 .. 67.990
PCB_T = 1.141             # STEP
PCB_X0, PCB_Y0 = 0.007, 0.016
HOLES = [(2.044, 18.953), (25.944, 16.953), (2.044, 65.953), (25.944, 65.953)]  # STEP, all 2.0 mm
HOLE_D = 2.0              # STEP

IO17_CAP = (11.65, 12.907, 16.35, 17.593)   # STEP, square cap top, x0 y0 x1 y1
IO17_TOP_Z = 6.141        # STEP
MIC_PORT = (13.985, 24.224)                 # STEP, 1.3 mm recess in the MP34DT05 lid
MIC_LID = (12.526, 21.488, 15.445, 25.404)  # STEP, lid top face
MIC_TOP_Z = 2.142         # STEP
USB_X = (9.525, 18.475)   # STEP, receptacle shell
USB_Z = (1.181, 4.341)    # STEP, mouth
USB_FRONT_Y = -1.599      # STEP, shell face beyond the PCB edge
QWIIC_FRONT_Y = -1.651    # STEP, CN1 and CN2 overhang the edge a little more than USB-C
RST_ACT = (20.884, 22.590, -1.243, -0.537)  # STEP, side actuator y0 y1 z0 z1, x to 28.847
BOOT_ACT = (29.647, 31.353, -1.243, -0.537) # STEP
SIDE_BTN_X = 28.847       # STEP
AUDIO_CN4 = (0.188, 21.369, 3.398, 25.619, -4.60)  # STEP, x0 y0 x1 y1 zmin (back side)
IPEX_RF1 = (0.549, 54.095, 2.549, 56.095, -0.87)   # STEP
CAM_MOTOR_CN5 = (23.288, 45.227, 27.588, 52.527, -4.71)  # STEP
BACK_MIN_Z = -4.71        # STEP, deepest part on the back (CN5)

# ---- display module ----
# SILK: frame outline on the PCB top, x 0.06 .. 27.5, y 26.49 .. 57.69.
# WIKI: board is "60 x 32 x 12 mm"; 32 mm is wider than the PCB (28), so it is taken as
# the glass width (the glass overhangs both long edges in LilyGO's photos).
DISP_X = (-2.0, 30.0)     # WIKI width 32, centred on the PCB (PROV centring)
DISP_Y = (26.4, 57.8)     # SILK outer frame line, rounded out 0.1
DISP_R = 3.0              # PROV corner radius
DISP_Z0 = 3.0             # PROV, above the TF card top (STEP 2.992)
DISP_TOP_Z = 6.8          # PROV glass top
ACTIVE = 23.4             # DS GMT130-V1.0 1.3 inch 240x240 active area, square, PROV centred

# ---- camera (OV2640 on an IR-cut holder, back side) ----
LENS_XY = (13.1, 38.4)    # PROV
LENS_D = 15.0             # PROV outer barrel diameter
LENS_TIP_Z = -11.0        # PROV
HOLDER = (2.0, 27.0, 26.0, 54.0)  # PROV footprint x0 y0 x1 y1
HOLDER_TOP_Z = -8.0       # PROV
WIRE_CLEAR = 2.0          # DESIGN, room for the IR-cut wires that loop over the holder

# ---- speaker FUET FS2112NB0807-H7.0 ----
SPK_L, SPK_W, SPK_T = 20.8, 11.8, 7.0   # DS FUET spec for approval, +-0.2
SPK_OPEN = (15.0, 8.0)    # DS
# ---- antenna, FPC with IPEX ----
ANT_L, ANT_W = 30.0, 10.0  # PROV, no LilyGO spec; parametric pad
PAD_H = 0.5               # DESIGN, raised antenna pad; also backs the inlay pockets, 1.3 mm left behind them

# ---- branding (brand/logo.md, brand/typography.md, brand/voice.md) ----
# brand/voice.md: the name is written "Orion", never "ORION"; the wordmark is Playfair Display
# with the last syllable in italic (Ori-on). "Seek the Undiscovered" is the brand's own tagline.
WORDMARK_C = (14.0, 8.0)  # DESIGN, back, lower third, centred under the lens
WORDMARK_EM = 8.1         # DESIGN, caps 5.7 mm, word about 22 mm wide
STAR_C = (14.0, 19.0)     # DESIGN, back, above the wordmark: the brand lockup, stacked
STAR_S = 9.0              # DESIGN, tip to tip
STAR_TIP_W = 0.45         # DESIGN, tips end where the arm is one extrusion wide
FRONT_STAR_C = (14.0, 69.3)  # DESIGN, front crown, between window top and top edge
FRONT_STAR_S = 10.0       # DESIGN, clear space S/2 stays clear of the window and the top edge
TAGLINE = "// Seek the Undiscovered"  # brand/voice.md tagline, "//" from the brand section labels
TAGLINE_C = (14.0, -3.0)  # DESIGN, bottom centre of the front, just above the stand
TAGLINE_W = 24.0          # DESIGN, very small: about 1.7 mm capitals
TAGLINE_D = 0.6           # DESIGN, shallower pocket, 1.2 mm stays above the USB channel
TAGLINE_CLR = 0.0          # DESIGN, printed in place (3MF) or paint-filled: too fine for a pressed-in inlay
INLAY_D = 0.8             # SPEC
INLAY_CLR = 0.12          # DESIGN, pocket grows this much per side so a printed inlay presses in
BOOST_WORDMARK = 0.12     # DESIGN, outline grown per side: hairline 0.16 -> 0.40 mm
BOOST_TAGLINE = 0.08      # DESIGN, thinnest stroke about 0.21 mm: a 0.2 mm nozzle or paint fill, see SPEC.md

# ---- print and fit rules (SPEC) ----
WALL = 2.0
ROOF = 1.6
CLR_PCB = 0.3
CLR_PART = 0.3
CLR_GLASS = 0.2
LIP = 0.8                 # bezel lip over the glass edge
WINDOW_CH = 0.4           # DESIGN, 45 deg chamfer on the window edge, keeps the lip 1.2 mm thick

# ---- derived shell geometry ----
Z_SPLIT = PCB_T                               # DESIGN, parting plane at the PCB top face
Z_FRONT_IN = DISP_TOP_Z                       # lip underside touches the glass
Z_FRONT_OUT = Z_FRONT_IN + ROOF               # 8.4
Z_BACK_IN = HOLDER_TOP_Z - WIRE_CLEAR         # -10.0
Z_BACK_OUT = Z_BACK_IN - WALL                 # -12.0
X_IN = (DISP_X[0] - CLR_GLASS, DISP_X[1] + CLR_GLASS)   # -2.2 .. 30.2
X_OUT = (X_IN[0] - WALL, X_IN[1] + WALL)
Y_BOT_IN = QWIIC_FRONT_Y - CLR_PART           # -1.95
Y_BOT_OUT = Y_BOT_IN - WALL                   # -3.95
SKIRT = 8.0                                   # DESIGN, how deep the body sits in the stand
Y_SKIRT = Y_BOT_OUT - SKIRT                   # -11.95
Y_CROWN_IN = 82.0                             # DESIGN, room for the speaker and antenna
Y_TOP_OUT = Y_CROWN_IN + WALL                 # 84.0
R_PLAN = 6.0                                  # DESIGN, corner radius seen from the front
EDGE_CH = 2.0                                 # DESIGN, 45 deg chamfer on the bed side edges
EDGE_FIL = 1.0                                # DESIGN, softens both chamfer edges

# ---- screws: M2 x 16 pan head self-tapping, from the back ----
SCREW_L = 16.0
PILOT_D = 1.6
SCREW_CLR_D = 2.3
HEAD_D = 4.4              # counterbore, fits a 3.8 to 4.0 mm pan head
HEAD_H = 1.7              # counterbore depth: 1.6 mm head sits flush, the wall stays closed behind it
BOSS_D = {0: 4.2, 1: 4.2, 2: 5.0, 3: 4.4}     # rear standoffs, hole index -> OD, kept 0.3 off nearby parts
FRONT_BOSS_D = 5.0
FRONT_BOSS_D_LOW = 4.2    # below z 2.6 at hole 0, 0.32 mm clear of the CN4 pins

# ---- stand ----
TILT = 12.0               # DESIGN, degrees back from vertical
USB_OVERMOLD = (12.0, 7.0)  # SPEC
USB_OVERMOLD_LEN = 20.0   # DESIGN, typical straight cable overmold

# ---- dock: stand with a real USB-C male-to-female extension (10 cm) built in ----
DOCK_MALE_LEN = 20.0      # PROV, male overmold length, caliper check
DOCK_FEMALE_LEN = 20.0    # PROV, female overmold length, caliper check
DOCK_CLR = 0.15           # DESIGN, snug on the overmolds so they do not move when docking
DOCK_LIFT = 8.0           # DESIGN, dock is 8 mm taller than the stand: a 4 mm ledge under the plug and room for the cable to turn
