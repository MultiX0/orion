// Generated from brand/tokens.json by firmware/assets_src/ui/tools/build_tokens.py.
// Do not edit by hand, edit the tokens and rerun the script.
#pragma once

// Surfaces
#define UI_BG_PRIMARY        0x09090b
#define UI_BG_SECONDARY      0x0f0f12
#define UI_BG_CARD           0x111115
#define UI_BG_CARDELEVATED   0x16161c
#define UI_BG_HIGHLIGHT      0x1a2535

// Text
#define UI_TEXT_WHITE        0xf4f4f5
#define UI_TEXT_MUTED        0x71717a
#define UI_TEXT_FAINT        0x3f3f46
#define UI_TEXT_CYAN         0xa8ccd8
#define UI_TEXT_CYANSOFT     0x7cb8ce

// The one accent, used as low alpha light over the dark surface, never as paint.
#define UI_ACCENT              0xa8ccd8
#define UI_GLOW_RGB            160,210,230
#define UI_ACCENT_RGB          168,204,216

// Accent alphas as LVGL opacity (0..255)
#define UI_OPA_WASH           8
#define UI_OPA_AMBIENT        13
#define UI_OPA_FILL           26
#define UI_OPA_BORDER         51
#define UI_OPA_BORDERHOVER    102
#define UI_OPA_GLOW           128

// Borders are white at these alphas, 1 px, always.
#define UI_OPA_BORDER_SUBTLE   15
#define UI_OPA_BORDER_SOFT     26
#define UI_OPA_BORDER_CYAN     51

// Motion
#define UI_DUR_FAST           200
#define UI_DUR_HOVER          300
#define UI_DUR_MED            400
#define UI_DUR_KEYFRAME       700
#define UI_DUR_REVEAL         1400
#define UI_DUR_FADE           1800
#define UI_DUR_PULSE          2500
#define UI_STAGGER_MS          100
#define UI_EASE_BRAND          164, 1024, 307, 1024
#define UI_EASE_UI             225, 1024, 369, 1024

// Spacing ladder (px)
#define UI_SPACE_1             4
#define UI_SPACE_2             8
#define UI_SPACE_3             12
#define UI_SPACE_4             16
#define UI_SPACE_5             20
#define UI_SPACE_6             24
#define UI_SPACE_8             32
#define UI_SPACE_10            40
#define UI_SPACE_15            60
#define UI_SPACE_20            80
#define UI_SPACE_25            100
#define UI_SPACE_30            120

// Radii (px)
#define UI_RADIUS_XS           2
#define UI_RADIUS_SM           8
#define UI_RADIUS_BTN          10
#define UI_RADIUS_CARD         12
#define UI_RADIUS_LG           14

// Type sizes the brand fixes in pixels
#define UI_FONT_PX_CARDTITLE   24
#define UI_FONT_PX_BODY        15
#define UI_FONT_PX_UI          14
#define UI_FONT_PX_UISMALL     12
#define UI_FONT_PX_LABEL       10
#define UI_FONT_PX_MICRO       8
