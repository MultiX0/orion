# Orion — Spacing, Layout & Shape

---

## 1. Spacing scale

A 4px base, used in practice as this ladder. The bolded values carry most of the
layout; treat the rest as adjustments.

`4 · 6 · 8 · 10 · 12 · **14** · **16** · 20 · **24** · 32 · **40** · 60 · **80** · 100 · 120`

| Step | Typical use |
| --- | --- |
| `4px` / `6px` | Icon-to-label gap, tight inline clusters |
| `8px` | Chip padding, small stack gap |
| `10px` / `12px` | Button icon gap, list item gap, form row gap |
| `16px` | **Default gap** between related elements |
| `20px` / `24px` | Card inner padding, gap between cards |
| `32px` | Large card padding, heading-to-body gap |
| `40px` | Column gap, page gutter on desktop |
| `60px` | Hero gutter, gap between major blocks |
| `80px` | Gap between footer columns, large section internals |
| `100px` / `120px` | Section vertical rhythm |

Most-used values in the codebase, in order: `16px`, `12px`, `8px`, `24px`, `20px`,
`40px`, `80px`.

### Section rhythm

```css
.section  { padding: 120px 20px; }              /* standard section */
.sectionInner { max-width: 1200px; margin: 0 auto; padding: 0 24px; }
```

Full-height sections use `height: 100dvh` (not `100vh` — mobile browser chrome).

## 2. Containers

| Width | Use |
| --- | --- |
| `1400px` | Footer and other wide, full-bleed-ish layouts |
| `1360px` | Hero inner |
| `1200px` | **Default content container** |
| `968px` | Narrow content sections |
| `800px` / `768px` | Article / long-form column |
| `640px` / `600px` | Body text measure, centered intros |
| `440px` | Dialogs, forms, newsletter card |
| `320px` | Footer brand column, small cards |

Gutters: `24px` on standard sections, `40px` on footer/wide layouts, `60px` on the
hero. Mobile drops all of these to `20px`.

## 3. Grids

```css
/* Hero — two equal columns, copy left / visual right */
display: grid;
grid-template-columns: 1fr 1fr;
gap: 64px;
align-items: center;

/* Feature / pillar rows */
gap: 60px;      /* between rows */
gap: 40px;      /* between columns */

/* Footer top row */
display: flex;
justify-content: space-between;
flex-wrap: wrap;
gap: 80px;
margin-bottom: 80px;
```

## 4. Breakpoints

| Max-width | Behavior |
| --- | --- |
| `968px` | Hero and 2-column grids collapse to one column; gutters shrink to `24px` |
| `768px` | Nav collapses; section padding drops to `80px 20px`; footer columns stack |
| `640px` | Single column everywhere; display type falls to the bottom of its `clamp()`; gutters `20px` |

Fluid type via `clamp()` handles most of the range, so there are few breakpoint-level
font-size overrides.

## 5. Radii

| Value | Use |
| --- | --- |
| `2px` | Tags, tiny chips, progress bars |
| `8px` | Inputs, small cards, dropdown panels |
| `10px` | **Buttons** |
| `12px` | **Default card** |
| `14px` | Large panels, dialogs |
| `50%` | Dots, avatars, the logo well |

There is no `border-radius: 0` hard-edge style and no fully-rounded pill buttons.

## 6. Borders & dividers

- Every border is `1px solid`.
- Default: `1px solid var(--border-subtle)`; hover: `var(--border-soft)`; accent/active: `var(--border-cyan)`.
- Section dividers are either a `1px` `--border-subtle` rule, or a gradient hairline that fades at both ends (see [colors.md](colors.md#5-atmosphere--gradients)).

## 7. Z-index ladder

| Layer | z-index |
| --- | --- |
| Atmosphere, noise, grid, ghost type | `0` |
| Content | `1` – `2` |
| Footer / sticky sections | `5` |
| Nav | `50` |
| Dialog / modal overlay | `100`+ |

## 8. Scrollbar

Thin and nearly invisible — part of the aesthetic, not an afterthought.

```css
html {
  scrollbar-width: thin;                                    /* Firefox */
  scrollbar-color: rgba(255,255,255,0.05) transparent;
  scroll-behavior: smooth;
}
::-webkit-scrollbar        { width: 3px; }
::-webkit-scrollbar-track  { background: transparent; }
::-webkit-scrollbar-thumb  { background: rgba(255,255,255,0.05); border-radius: 10px; }
::-webkit-scrollbar-thumb:hover { background: rgba(255,255,255,0.1); }
```

Also set `overflow-x: hidden` on `body` — several sections deliberately overflow
horizontally (marquees, ghost type).
