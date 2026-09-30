# Orion — Color

Orion is a **dark-only** system. There is no light theme, and one was never designed:
the brand reads as an observatory at night, and inverting it destroys the metaphor.
The palette is a near-black neutral ramp plus exactly one accent hue — a pale,
desaturated cyan that stands in for starlight.

---

## 1. Surfaces

| Token | Value | Use |
| --- | --- | --- |
| `--bg-primary` | `#09090b` | Page background. The default for `html` and `body`, every full-bleed section, and the footer. |
| `--bg-secondary` | `#0f0f12` | Alternating section bands, subtle separation from the page. |
| `--bg-card` | `#111115` | Default card / panel surface. |
| `--bg-card-elevated` | `#16161c` | Hovered cards, modals, dialogs, popovers, anything floating above a card. |
| `--bg-highlight` | `#1a2535` | Selected / active state. The only surface with a blue cast — use sparingly. |

The ramp is intentionally tight (`#09090b → #16161c`). Depth in Orion comes from
**borders and glow**, not from big jumps in surface lightness.

## 2. Text

| Token | Value | Use |
| --- | --- | --- |
| `--text-white` | `#f4f4f5` | Headlines and primary copy. Never pure `#fff` — it glares against `#09090b`. |
| `--text-muted` | `#71717a` | Body copy, descriptions, inactive nav links, secondary CTAs. |
| `--text-faint` | `#3f3f46` | Meta, timestamps, index numbers, decorative rules, disabled states. |
| `--text-cyan` | `#a8ccd8` | The accent. Eyebrows, live indicators, underlines, key emphasis. |
| `--text-cyan-soft` | `#7cb8ce` | Dimmer accent — mono labels, footnotes, gradient rules. |

**Contrast:** `--text-white` on `--bg-primary` is ~17:1. `--text-muted` on
`--bg-primary` is ~4.9:1 — fine for body text at 15px+, not for anything below 14px.
`--text-faint` is decorative only and fails AA; never put information there alone.

## 3. Borders

| Token | Value | Use |
| --- | --- | --- |
| `--border-subtle` | `rgba(255,255,255,0.06)` | Default. Cards, section dividers, footer top rule. |
| `--border-soft` | `rgba(255,255,255,0.10)` | Hover state of a subtle border; inputs on focus-within. |
| `--border-cyan` | `rgba(160,210,230,0.20)` | Accent border — primary buttons, active/selected state. |

Borders are always `1px`. There is no 2px border anywhere in the system.

## 4. The accent, expanded

The accent exists at two nominal hex values (`#a8ccd8`, `#7cb8ce`), but in practice it
is used as **low-alpha rgba over the dark surface**. Memorize these two triplets:

```
rgba(168, 204, 216, α)   /* from --text-cyan  #a8ccd8 */
rgba(160, 210, 230, α)   /* the "glow" cyan, slightly cooler  */
```

Working alphas, straight from the product:

| α | Where it's used |
| --- | --- |
| `0.02 – 0.03` | Atmospheric wash, grid lines over dark backgrounds |
| `0.05` | Ambient radial glow behind a section |
| `0.08 – 0.12` | Button fill, logo glow, hover wash |
| `0.18 – 0.20` | Accent border, button hover fill |
| `0.40` | Button hover border |
| `0.50 – 0.80` | Indicator dot `box-shadow` glow |

**Rule:** the accent is never a solid fill for a large area. It appears as a hairline,
a dot, a 10% wash, or a blur — like light, not like paint.

## 5. Atmosphere & gradients

These are the recurring background treatments. They are what makes a page feel like
Orion rather than a generic dark theme.

```css
/* Ambient corner haze — top-left of a hero */
background: radial-gradient(ellipse at center, rgba(30, 60, 100, 0.10) 0%, transparent 70%);

/* Warmer counter-haze — bottom-right, always fainter */
background: radial-gradient(ellipse at center, rgba(40, 80, 70, 0.06) 0%, transparent 70%);

/* Centered accent glow behind a logo or focal element */
background: radial-gradient(circle, rgba(160, 210, 230, 0.12) 0%, transparent 70%);

/* Section wash */
background: radial-gradient(ellipse at 20% 0%, rgba(168, 204, 216, 0.02) 0%, transparent 60%);

/* Hairline rule that fades at both ends — used under section headers */
background: linear-gradient(90deg, transparent, var(--text-cyan-soft), transparent);
background: linear-gradient(90deg, transparent, rgba(255,255,255,0.08), transparent);

/* Marquee / overflow edge masks */
background: linear-gradient(to right, var(--bg-primary), transparent);
background: linear-gradient(to left,  var(--bg-primary), transparent);

/* Cartographic dot grid */
background-image: radial-gradient(rgba(160, 210, 230, 0.10) 1px, transparent 1px);
background-size: 32px 32px;

/* Blueprint line grid */
background-image:
  linear-gradient(to right,  rgba(255,255,255,0.02) 1px, transparent 1px),
  linear-gradient(to bottom, rgba(255,255,255,0.02) 1px, transparent 1px);
background-size: 64px 64px;
```

### Film grain

Every hero carries a faint noise layer at `opacity: 0.4` over a `0.025`-opacity
turbulence texture. It kills banding in the radial gradients and gives the black
some tooth.

```css
.noiseOverlay {
  position: absolute;
  inset: 0;
  background-image: url("data:image/svg+xml,%3Csvg viewBox='0 0 256 256' xmlns='http://www.w3.org/2000/svg'%3E%3Cfilter id='noise'%3E%3CfeTurbulence type='fractalNoise' baseFrequency='0.9' numOctaves='4' stitchTiles='stitch'/%3E%3C/filter%3E%3Crect width='100%25' height='100%25' filter='url(%23noise)' opacity='0.025'/%3E%3C/svg%3E");
  background-repeat: repeat;
  background-size: 256px 256px;
  opacity: 0.4;
  pointer-events: none;
}
```

## 6. Glow / shadow

There are no conventional drop shadows in Orion — nothing casts a black shadow onto a
black page. "Elevation" is expressed as **emitted light**:

```css
box-shadow: 0 0 8px  rgba(168, 204, 216, 0.5);   /* small indicator dot */
box-shadow: 0 0 16px rgba(168, 204, 216, 0.8);   /* dot, pulsed peak */
box-shadow: 0 0 24px rgba(168, 204, 216, 0.1);   /* button hover halo */
```

## 7. Don'ts

- No pure `#000` and no pure `#ffffff`.
- No second accent hue. If something must be distinguished, use opacity or mono type, not a new color.
- No saturated status colors on brand surfaces. If a red/green is unavoidable in product UI, desaturate it toward the neutral ramp.
- No accent-filled buttons — the accent is a 10% wash with a 20% border, always.
- No gradients between two accent colors. Gradients go from accent to `transparent`.
