# Orion — The Mark

> The mark is the single four-point star in `assets/logo.png` (also `assets/logo.svg`). The arcs and the two satellite stars described below are retired. Everything else here still holds: white on dark, the accent only as glow around it, clear space, minimum size.

Files: [`assets/logo.svg`](assets/logo.svg) (master, 240×240) · [`assets/logo.ico`](assets/logo.ico) (favicon)

---

## 1. What it is

A four-pointed navigational star — the kind travelers used to orient themselves across
featureless dark — with two arcs sweeping outward from its apex, each terminating in a
smaller star.

The main star is Orion itself: the root of discovery. The arcs are edges. The two
smaller stars are **nodes of knowledge** growing outward from that root — each one a
new hypothesis, a new domain, a new direction. They are not decoration; they are the
graph.

## 2. Geometry

The whole mark is drawn on a `240 × 240` canvas, centered on `(120, 120)`.

| Element | Spec |
| --- | --- |
| Primary star | 4-pointed, centered `(120,120)`, span `84 → 156` (72px), concave arms with control points at ±7.2 / ±28.8 from center |
| Arcs | Quadratic-ish curves from `(120, 84)` out to `(204, 132)` and `(36, 132)`; `stroke-width: 1.2`, `stroke-linecap: round` |
| Satellite stars | 4-pointed, 31.2px span, centered `(204, 147.6)` and `(36, 147.6)`, `fill-opacity: 0.6` |
| Fill | `white` — the mark is monochrome by definition |

```svg
<svg width="240" height="240" viewBox="0 0 240 240" fill="none" xmlns="http://www.w3.org/2000/svg">
  <path d="M120 84L127.2 112.8L156 120L127.2 127.2L120 156L112.8 127.2L84 120L112.8 112.8L120 84" fill="white"/>
  <path d="M120 84C180 84 204 108 204 132" stroke="white" stroke-width="1.2" stroke-linecap="round"/>
  <path d="M120 84C60 84 36 108 36 132" stroke="white" stroke-width="1.2" stroke-linecap="round"/>
  <path d="M204 132L207.6 144L216 147.6L207.6 151.2L204 163.2L200.4 151.2L192 147.6L200.4 144L204 132" fill="white" fill-opacity="0.6"/>
  <path d="M36 132L39.6 144L48 147.6L39.6 151.2L36 163.2L32.4 151.2L24 147.6L32.4 144L36 132" fill="white" fill-opacity="0.6"/>
</svg>
```

Note the internal hierarchy: the satellites sit at **60% opacity**, so the primary star
always reads first. Preserve that ratio if you recolor.

## 3. Color

The mark is **white on dark**. That is the canonical and only lockup.

- On `--bg-primary` / any brand surface: `fill: white` (or `currentColor` set to `--text-white`).
- Where the mark must appear on light (invoice, print, partner deck): solid `#09090b`, satellites still at 60% opacity.
- The accent cyan is **never** applied to the mark itself. Accent appears *around* it as glow, never inside it.

## 4. Sizes in use

| Context | Size |
| --- | --- |
| Favicon | 16 / 32 / 48 (`logo.ico`) |
| Nav | 28 – 32px |
| Footer / closing lockup | 56px |
| Brand showcase | 180px |
| Ghosted background mark | Up to 60vw at very low opacity |

Minimum legible size is **20px**. Below that the arcs and satellites disappear —
use the primary star alone.

## 5. Clear space

Keep clear space equal to **half the mark's height** on all sides
(at 240px, that's 120px). Nothing — type, rules, image edges — enters that zone.

## 6. The showcase treatment

When the mark is presented as a hero element, it sits in a well with a radial glow
and one or two concentric hairline rings:

```css
.logoGlow {
  position: absolute; inset: -40%;
  background: radial-gradient(circle, rgba(160, 210, 230, 0.12) 0%, transparent 70%);
  pointer-events: none;
}
.logoRing {
  position: absolute; inset: 0;
  border: 1px solid var(--border-subtle);
  border-radius: 50%;
}
```

## 7. Wordmark

Set in **Playfair Display**, with the final syllable in italic:

> Ori*on*.

At monumental sizes: `clamp(120px, 25vw, 360px)`, weight 400–500, `letter-spacing: -0.05em`,
`line-height: 0.9`. The period is part of the monumental treatment only — the inline
wordmark ("Orion") carries no period.

In nav and footer, the wordmark is paired with the mark at `gap: 12px`, vertically
centered.

## 8. Misuse

Don't:

- Recolor the mark to the accent cyan, or to any gradient.
- Add a stroke, bevel, shadow, or outer container shape (no rounded-square app-icon treatment on brand surfaces).
- Rotate it, skew it, or change the 60% satellite opacity.
- Redraw the arcs at a different weight — `1.2` at 240px is the ratio (0.5% of canvas).
- Set the wordmark in anything but Playfair Display.
- Place the mark on a busy photograph without a vignette or scrim beneath it.

## 9. Other brand imagery

| File | Use |
| --- | --- |
| `assets/brand-hero.png` | Hero background texture for brand pages |
| `assets/brand-blackhole.png` | Full-bleed image break; pairs with the "Orion Thesis" quote |
| `assets/banner.jpg` | 1200×630 social / OG card |

All imagery is dark, cosmic, low-saturation. Any new photography should be
desaturated and darkened until it can sit under `--text-white` type without a heavy
scrim.
