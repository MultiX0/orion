# Orion — Brand Kit

A portable copy of the Orion visual identity, extracted from the Orion landing site
(`orion-landing`). Everything here is self-contained: fonts are vendored locally, the
logo is a plain SVG, and every design decision is written down as a token.

**Brand line:** *Orion — A New Interface to Knowledge* · Est. 2026
**Tagline:** *Seek the Undiscovered*

---

## What's in here

| Path | What it is |
| --- | --- |
| [`colors.md`](colors.md) | Palette, semantic roles, borders, glows, gradients |
| [`typography.md`](typography.md) | The four typefaces, the type scale, letter-spacing rules |
| [`spacing-layout.md`](spacing-layout.md) | Spacing scale, container widths, radii, breakpoints |
| [`logo.md`](logo.md) | The mark, its geometry, meaning, clear space and misuse |
| [`components.md`](components.md) | Buttons, cards, labels, inputs, nav, footer recipes |
| [`motion.md`](motion.md) | Easing curves, durations, scroll-reveal and keyframe patterns |
| [`voice.md`](voice.md) | Naming, tone, copy patterns, the manifesto |
| [`tokens.css`](tokens.css) | Every token as copy-paste CSS custom properties |
| [`tokens.json`](tokens.json) | The same tokens as JSON, for Tailwind / JS / Figma |
| [`fonts/`](fonts/) | Self-hosted `.woff2` files + ready-made `fonts.css` |
| [`assets/`](assets/) | `logo.svg`, `logo.ico`, brand imagery, social banner |

## Quick start (web)

```css
/* app/globals.css */
@import './brand/fonts/fonts.css';
@import './brand/tokens.css';

html {
  background: var(--bg-primary);
  color: var(--text-white);
  font-family: var(--font-body);
  font-size: 16px;
  -webkit-font-smoothing: antialiased;
  -moz-osx-font-smoothing: grayscale;
}
```

If you would rather stay on the CDN instead of the vendored files, the original
import is:

```css
@import url('https://fonts.googleapis.com/css2?family=Playfair+Display:ital,wght@0,400;0,500;0,600;0,700;1,400&family=Source+Serif+4:ital,opsz,wght@0,8..60,300;0,8..60,400;0,8..60,500;0,8..60,600;1,8..60,400&family=Inter:wght@300;400;500;600&family=DM+Mono:ital,wght@0,300;0,400;1,300&display=swap');
```

## The identity in one paragraph

Orion is an observatory, not a dashboard. The surface is near-black, the light is
cold and sparse, and the only color in the system is a single pale cyan that behaves
like starlight — used for accents, never for fills. Headlines are set in a high-contrast
display serif, body copy in a reading serif, interface chrome in a neutral sans, and
all machine-adjacent text (labels, metrics, coordinates) in a mono with wide tracking.
Motion is slow and eased, never bouncy. Nothing is loud; everything is deliberate.

## Licensing

- **Typefaces** — Playfair Display, Source Serif 4, Inter and DM Mono are all under the
  SIL Open Font License 1.1, so the vendored `.woff2` files may be redistributed with
  the product.
- **Logo, imagery and wordmark** — property of Orion. Not open licensed.
