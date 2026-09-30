# Orion — Typography

Four typefaces, each with a job it never leaves. The mix is the identity: a display
serif for voice, a reading serif for substance, a neutral sans for interface, and a
mono for anything the machine says.

---

## 1. The families

| Token | Family | Fallbacks | Role |
| --- | --- | --- | --- |
| `--font-serif` | **Playfair Display** | `Georgia, serif` | Headlines, wordmark, numbers, pull quotes. High contrast, editorial. |
| `--font-body` | **Source Serif 4** | `Georgia, serif` | **The document default.** Body copy, long-form, article text. Set on `html`. |
| `--font-sans` | **Inter** | `system-ui, sans-serif` | Interface: nav, buttons, inputs, tabs, small UI labels. |
| `--font-mono` | **DM Mono** | `'Courier New', monospace` | Eyebrows, section labels, metrics, coordinates, code, timestamps. |

```css
--font-serif: 'Playfair Display', Georgia, serif;
--font-body:  'Source Serif 4', Georgia, serif;
--font-sans:  'Inter', system-ui, sans-serif;
--font-mono:  'DM Mono', 'Courier New', monospace;
```

**Weights shipped:** Playfair Display 400/500/600/700 + italic 400 · Source Serif 4
300/400/500/600 + italic 400 · Inter 300/400/500/600 · DM Mono 300/400 + italic 300.
Nothing heavier than 700 exists in the brand, and 700 is rare — 500 is the normal
headline weight.

Root: `font-size: 16px` on `html`, `font-family: var(--font-body)`, with
`-webkit-font-smoothing: antialiased` and `-moz-osx-font-smoothing: grayscale`.
The smoothing is not optional — serifs at these weights get muddy on dark without it.

## 2. The italic rule

Playfair italic is the brand's emphasis device. In headlines, **one word or phrase is
set in italic** while the rest stays roman:

> Seek the *Undiscovered*
> Ori*on*.
> Space has no limits. As *profoundly mysterious* and dense as a black hole…

In markup this is a literal `<em>` inside the heading. Use it once per headline, never
twice. Italic is never used for whole paragraphs.

## 3. The scale

Headline sizes are fluid; UI sizes are fixed pixels.

### Display & headlines — Playfair Display

| Role | Size | Weight | Line height | Tracking |
| --- | --- | --- | --- | --- |
| Monumental wordmark | `clamp(120px, 25vw, 360px)` | 400–500 | 0.9 | `-0.05em` |
| Ghost / background word | `30vmin` | 400 | 1 | `-0.04em` |
| Hero headline | `clamp(32px, 3.6vw, 58px)` | 500 | 1.08 | `-0.025em` |
| Section title (H2) | `clamp(28px, 3vw, 44px)` | 500 | 1.1 | `-0.02em` |
| Card title (H3) | `24px` / `30px` | 500 | 1.2 | `-0.02em` |
| Big number / metric | `32px` – `58px` | 400–500 | 1 | `-0.02em` |

The bigger the type, the tighter the tracking. Nothing above 40px is ever set at
default tracking.

### Body — Source Serif 4

| Role | Size | Weight | Line height | Color |
| --- | --- | --- | --- | --- |
| Lead paragraph | `clamp(14px, 1.1vw, 16px)` – `18px` | 400 | 1.6–1.7 | `--text-muted` |
| Body | `15px` – `16px` | 400 | 1.65 | `--text-muted` |
| Small body | `13px` – `14px` | 400 | 1.6 | `--text-muted` |
| Long-form article | `17px` – `18px` | 400 | 1.75 | `--text-muted` / `--text-white` |

Measure is capped at `600px` for body columns, `768px`–`800px` for articles.

### Interface — Inter

| Role | Size | Weight | Tracking |
| --- | --- | --- | --- |
| Button | `14px` | 500 | `0.02em` |
| Nav link | `13px` – `14px` | 400–500 | `0.02em` |
| Input / field | `14px` | 400 | normal |
| Small UI text | `12px` – `12.5px` | 400 | normal |

### Machine voice — DM Mono

Always **uppercase** and always widely tracked. This is the most recognizable
typographic tic in the brand.

| Role | Size | Weight | Tracking | Color |
| --- | --- | --- | --- | --- |
| Eyebrow above a headline | `10px` | 400 | `0.18em` | `--text-cyan-soft` |
| Section label (`// The Mark`) | `10px` – `11px` | 400 | `0.15em` | `--text-faint` |
| Metric caption | `9px` – `10px` | 400 | `0.15em` – `0.22em` | `--text-faint` |
| Micro-label / legend | `7px` – `8px` | 400 | `0.22em` – `0.28em` | `--text-faint` |
| Inline code, coordinates | `12px` – `13px` | 300–400 | normal | `--text-cyan-soft` |

The tracking ladder in use: `0.05em · 0.08em · 0.10em · 0.12em · 0.15em · 0.18em ·
0.22em · 0.28em`. Smaller text gets *more* tracking, not less.

### Negative tracking ladder (display only)

`-0.02em · -0.025em · -0.04em · -0.05em`

## 4. Recurring patterns

**Section label** — a mono comment marker. The `//` is part of the brand voice.

```css
.sectionLabel {
  font-family: var(--font-mono);
  font-size: 10px;
  letter-spacing: 0.15em;
  text-transform: uppercase;
  color: var(--text-faint);
}
```
```html
<span class="sectionLabel">// The Mark</span>
```

**Eyebrow with live dot** — mono, accent-colored, preceded by a pulsing 6px dot.

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
  margin-bottom: clamp(16px, 3vh, 32px);
}
```

**Index numbers** — `01`, `02`, `03` in mono, `--text-faint`, zero-padded, used to
enumerate pillars and steps.

**Metric** — Playfair for the value, with the unit as an italic `<em>`
(`1.4`*`B`*), and a mono uppercase caption beneath at `9px` / `0.15em`.

## 5. Don'ts

- Don't set body copy in Playfair. It's a display face; below 24px it loses its contrast.
- Don't set headlines in Inter. Inter never appears above 16px.
- Don't use mono in sentence case or lowercase for labels — mono labels are uppercase and tracked.
- Don't bold body text for emphasis; use `--text-white` against `--text-muted`, or Playfair italic.
- Don't mix more than three families in one component.
- Don't use `font-weight: 700` on dark for small text — it blooms. Cap small text at 500.
