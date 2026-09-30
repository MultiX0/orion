# Orion — Component Recipes

Copy-paste patterns, lifted from the product. All of them assume
[`tokens.css`](tokens.css) is loaded.

---

## Buttons

### Primary

The only "filled" button in the system — and its fill is a 10% accent wash.

```css
.ctaPrimary {
  display: inline-flex;
  align-items: center;
  gap: 10px;
  padding: 12px 24px;
  background: rgba(168, 204, 216, 0.1);
  border: 1px solid rgba(168, 204, 216, 0.2);
  border-radius: 10px;
  font-family: var(--font-sans);
  font-size: 14px;
  font-weight: 500;
  color: var(--text-white);
  text-decoration: none;
  cursor: pointer;
  transition: all 300ms ease;
}
.ctaPrimary:hover {
  background: rgba(168, 204, 216, 0.18);
  border-color: rgba(168, 204, 216, 0.4);
  box-shadow: 0 0 24px rgba(168, 204, 216, 0.1);
  transform: translateY(-1px);
}
.ctaPrimary svg        { transition: transform 300ms ease; }
.ctaPrimary:hover svg  { transform: translateX(3px); }
```

### Secondary — a bare link with a sweeping underline

```css
.ctaSecondary {
  position: relative;
  padding: 0;
  background: none;
  border: none;
  font-family: var(--font-sans);
  font-size: 14px;
  font-weight: 400;
  color: var(--text-muted);
  text-decoration: none;
  cursor: pointer;
  transition: color 300ms ease;
}
.ctaSecondary::after {
  content: '';
  position: absolute;
  bottom: -2px;
  left: 0;
  width: 0;
  height: 1px;
  background: var(--text-cyan);
  transition: width 300ms ease;
}
.ctaSecondary:hover          { color: var(--text-white); }
.ctaSecondary:hover::after   { width: 100%; }
```

### Ghost / tertiary

`12px 20px`, `background: transparent`, `1px solid var(--border-subtle)`,
`border-radius: 10px`, `color: var(--text-muted)`; on hover the border goes to
`--border-soft` and the text to `--text-white`.

Button sizes: `12px 24px` (default) · `10px 14px` (compact) · `12px 16px` (field-adjacent).

---

## Card

```css
.card {
  background: var(--bg-card);
  border: 1px solid var(--border-subtle);
  border-radius: 12px;
  padding: 24px;
  transition: background var(--transition-med), border-color var(--transition-med);
}
.card:hover {
  background: var(--bg-card-elevated);
  border-color: var(--border-soft);
}
```

Composition inside a card, top to bottom:
mono label (`10px` / `0.15em` / `--text-faint`) → Playfair title (`24px` / 500 /
`--text-white`) → Source Serif body (`15px` / 1.65 / `--text-muted`), with `12–16px`
between each.

Large cards use `32px` padding and `14px` radius.

---

## Section header

```html
<span class="sectionLabel">// Core Pillars</span>
<h2 class="sectionTitle">What we believe</h2>
```

```css
.sectionLabel {
  font-family: var(--font-mono);
  font-size: 10px;
  letter-spacing: 0.15em;
  text-transform: uppercase;
  color: var(--text-faint);
}
.sectionTitle {
  font-family: var(--font-serif);
  font-size: clamp(28px, 3vw, 44px);
  font-weight: 500;
  line-height: 1.1;
  letter-spacing: -0.02em;
  color: var(--text-white);
}
.sectionTitle em {           /* the single italic emphasis */
  font-style: italic;
  color: var(--text-cyan);
}
```

Optionally followed by a fading hairline:
`height: 1px; background: linear-gradient(90deg, transparent, rgba(255,255,255,0.08), transparent);`

---

## Eyebrow with live dot

```html
<span class="eyebrow"><span class="eyebrowDot"></span>Est. 2026 · Brand Identity</span>
```

```css
.eyebrow {
  display: inline-flex;
  align-items: center;
  gap: 10px;
  font-family: var(--font-mono);
  font-size: 10px;
  letter-spacing: 0.18em;
  text-transform: uppercase;
  color: var(--text-cyan-soft);
}
.eyebrowDot {
  width: 6px;
  height: 6px;
  border-radius: 50%;
  background: var(--text-cyan);
  box-shadow: 0 0 8px rgba(168, 204, 216, 0.5);
  animation: dotPulse 2.5s ease-in-out infinite;
}
```

---

## Metric / stat

```html
<div class="numberValue">1.4<em>B</em></div>
<div class="numberLabel">Knowledge Nodes Indexed</div>
```

```css
.numberValue {
  font-family: var(--font-serif);
  font-size: clamp(32px, 3.6vw, 58px);
  font-weight: 400;
  line-height: 1;
  letter-spacing: -0.02em;
  color: var(--text-white);
}
.numberValue em {
  font-style: italic;
  color: var(--text-cyan);
}
.numberLabel {
  margin-top: 10px;
  font-family: var(--font-mono);
  font-size: 9px;
  letter-spacing: 0.15em;
  text-transform: uppercase;
  color: var(--text-faint);
}
```

---

## Input / field

```css
.input {
  width: 100%;
  padding: 12px 16px;
  background: var(--bg-card);
  border: 1px solid var(--border-subtle);
  border-radius: 8px;
  font-family: var(--font-sans);
  font-size: 14px;
  color: var(--text-white);
  transition: border-color var(--transition-fast);
}
.input::placeholder { color: var(--text-faint); }
.input:focus {
  outline: none;
  border-color: var(--border-cyan);
  box-shadow: 0 0 0 1px rgba(160, 210, 230, 0.1);
}
```

---

## Nav

Fixed, `z-index: 50`, transparent at the top of the page and backdrop-blurred once
scrolled:

```css
.nav {
  position: fixed;
  inset: 0 0 auto 0;
  z-index: 50;
  display: flex;
  align-items: center;
  justify-content: space-between;
  padding: 0 40px;
  height: 64px;
}
.nav[data-scrolled='true'] {
  background: rgba(9, 9, 11, 0.72);
  backdrop-filter: blur(12px);
  border-bottom: 1px solid var(--border-subtle);
}
.navLink {
  font-family: var(--font-sans);
  font-size: 13px;
  letter-spacing: 0.02em;
  color: var(--text-muted);
  text-decoration: none;
  transition: color var(--transition-fast);
}
.navLink:hover,
.navLink[aria-current='page'] { color: var(--text-white); }
```

Brand lockup: mark at 28–32px + Playfair wordmark, `gap: 12px`.

---

## Footer

```css
.footer {
  position: relative;
  z-index: 5;
  background: var(--bg-primary);
  border-top: 1px solid var(--border-subtle);
  padding-top: 100px;
  overflow: hidden;            /* clips the giant ghosted wordmark */
}
.footerInner {
  position: relative;
  z-index: 2;
  max-width: 1400px;
  margin: 0 auto;
  padding: 0 40px;
}
.footerTopRow {
  display: flex;
  justify-content: space-between;
  align-items: flex-start;
  flex-wrap: wrap;
  gap: 80px;
  margin-bottom: 80px;
}
.footerBrandCol { flex: 1; min-width: 280px; max-width: 320px; }
```

The footer's signature: an oversized ghosted "Orion" in Playfair at `30vmin`,
`z-index: 0`, very low opacity, bleeding off the bottom edge.

---

## Image break

A full-bleed image section with an overlay scrim and a Playfair pull quote:

```css
.imageBreak         { position: relative; min-height: 80vh; }
.imageBreakOverlay  { position: absolute; inset: 0;
                      background: radial-gradient(circle at center, transparent, rgba(9,9,11,0.85)); }
.imageBreakQuoteText{ font-family: var(--font-serif); font-size: clamp(24px, 2.6vw, 40px);
                      font-weight: 400; line-height: 1.3; color: var(--text-white); max-width: 800px; }
.imageBreakAttrib   { font-family: var(--font-mono); font-size: 10px;
                      letter-spacing: 0.22em; text-transform: uppercase; color: var(--text-faint); }
```

---

## Marquee strip

Continuous `linear` scroll of short brand phrases separated by `✦`, mono uppercase
at `0.22em`, with `--bg-primary → transparent` gradient masks on both edges.
