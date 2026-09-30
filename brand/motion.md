# Orion — Motion

Motion in Orion is **slow, eased, and one-directional**. Things surface out of the dark;
they don't bounce, spin, or spring. If an animation draws attention to itself, it's wrong.

---

## 1. Easing

| Curve | Value | Use |
| --- | --- | --- |
| Brand ease-out | `cubic-bezier(0.16, 1, 0.3, 1)` | Scroll reveals, entrances. The signature curve — very fast start, long settle. |
| UI ease | `cubic-bezier(0.22, 1, 0.36, 1)` | Transitions on interactive elements, keyframe utilities. |
| Linear | `linear` | Marquees, continuous rotation, progress only. |
| `ease` / `ease-out` | — | Hover micro-transitions where a token isn't handy. |

```css
--transition-fast: 200ms cubic-bezier(0.22, 1, 0.36, 1);
--transition-med:  400ms cubic-bezier(0.22, 1, 0.36, 1);
```

## 2. Durations

| Duration | Use |
| --- | --- |
| `200ms` | Color / border / opacity on hover |
| `300ms` | Button hover, icon nudge, underline sweep |
| `400ms` | Panel and card transitions |
| `700 – 800ms` | Keyframe entrance utilities |
| `1.0 – 1.4s` | Scroll reveals (translate + fade) |
| `1.8s` | Pure opacity fades for large elements |
| `2.5s` | Indicator dot pulse (infinite) |

Stagger between siblings: **0.1 – 0.12s**. Hero elements use explicit delays of
`0.3 / 0.5 / 1.0 / 2.0s` to choreograph a slow, deliberate load.

## 3. Scroll reveal (Framer Motion)

The two patterns used everywhere:

```ts
// Rise + fade — for blocks, cards, headings
const reveal = (delay = 0) => ({
  initial:    { opacity: 0, y: 40 },
  whileInView:{ opacity: 1, y: 0 },
  viewport:   { once: true, margin: '-60px' },
  transition: { duration: 1.4, delay, ease: [0.16, 1, 0.3, 1] },
});

// Pure fade — for large images, ambient elements, labels
const fade = (delay = 0) => ({
  initial:    { opacity: 0 },
  whileInView:{ opacity: 1 },
  viewport:   { once: true, margin: '-60px' },
  transition: { duration: 1.8, delay, ease: 'easeOut' },
});
```

Line-by-line text reveals slide in horizontally instead:
`initial: { opacity: 0, x: -20 }` → `x: 0`, `duration: 1.0`, `delay: i * 0.1`.

`once: true` always — nothing re-animates on scroll-back.

## 4. CSS keyframes

```css
@keyframes fadeInUp {
  from { opacity: 0; transform: translateY(18px); }
  to   { opacity: 1; transform: translateY(0); }
}
@keyframes fadeIn  { from { opacity: 0; } to { opacity: 1; } }
@keyframes scaleIn {
  from { opacity: 0; transform: scale(0.97); }
  to   { opacity: 1; transform: scale(1); }
}
@keyframes dotPulse {
  0%, 100% { opacity: 1;   box-shadow: 0 0 8px  rgba(168, 204, 216, 0.5); }
  50%      { opacity: 0.5; box-shadow: 0 0 16px rgba(168, 204, 216, 0.8); }
}
```

Utility classes, with a staggered delay ladder of `0.1 / 0.2 / 0.35 / 0.5s`:

```css
.animate-fade-up          { animation: fadeInUp 0.7s var(--transition-med) both; }
.animate-fade-up-delay-1  { animation: fadeInUp 0.7s 0.10s cubic-bezier(0.22,1,0.36,1) both; }
.animate-fade-up-delay-2  { animation: fadeInUp 0.7s 0.20s cubic-bezier(0.22,1,0.36,1) both; }
.animate-fade-up-delay-3  { animation: fadeInUp 0.7s 0.35s cubic-bezier(0.22,1,0.36,1) both; }
.animate-fade-up-delay-4  { animation: fadeInUp 0.7s 0.50s cubic-bezier(0.22,1,0.36,1) both; }
.animate-scale-in         { animation: scaleIn 0.8s 0.15s cubic-bezier(0.22,1,0.36,1) both; }
```

## 5. Hover vocabulary

| Element | What moves |
| --- | --- |
| Primary button | Fill `0.10 → 0.18`, border `0.20 → 0.40`, `translateY(-1px)`, `box-shadow: 0 0 24px rgba(168,204,216,0.1)` |
| Button arrow icon | `translateX(3px)` |
| Text link | Underline sweeps `width: 0 → 100%` in accent, 300ms |
| Card | Border `--border-subtle → --border-soft`, background `--bg-card → --bg-card-elevated` |
| Nav link | `--text-muted → --text-white` |

Displacement is always ≤ 3px. Nothing scales up on hover.

## 6. Ambient motion

- **Indicator dot** — `dotPulse`, 2.5s, `ease-in-out`, infinite.
- **Marquee** — `linear`, infinite, edges masked with `linear-gradient(to right/left, var(--bg-primary), transparent)`.
- **Scroll hint** — a small dot fading in at `delay: 2s`, then drifting.
- **Canvas / manifold visuals** — continuous, very slow, no easing.

## 7. Accessibility

Respect the user's setting — Orion's long durations are exactly what motion
sensitivity flags.

```css
@media (prefers-reduced-motion: reduce) {
  *, *::before, *::after {
    animation-duration: 0.01ms !important;
    animation-iteration-count: 1 !important;
    transition-duration: 0.01ms !important;
    scroll-behavior: auto !important;
  }
}
```
