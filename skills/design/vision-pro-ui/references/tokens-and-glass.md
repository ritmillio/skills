# Tokens, glass recipe, type, motion, Tailwind, fallbacks

Everything here goes into `src/index.css` (or the app's global stylesheet) in
the order shown. Order matters: the fallback block must come after the glass
variants so it wins.

## Design tokens

```css
:root {
  /* Environment */
  --env-dim: rgba(0, 0, 0, 0.25);          /* overlay on the room photo */
  --env-blur: 16px;                        /* light — passthrough stays recognisable */

  /* Glass materials — neutral, slightly warm grey tint, NOT white frost.
     It darkens bright rooms and lifts dark ones. thin → thick = recessed → raised */
  --glass-thin:    rgba(128, 128, 128, 0.18);
  --glass-regular: rgba(110, 110, 112, 0.30);
  --glass-thick:   rgba(90, 90, 94, 0.42);
  --glass-dark:    rgba(30, 30, 32, 0.55);   /* for very bright environments */
  --glass-solid:   rgba(28, 28, 32, 0.94);   /* reduce-transparency fallback */

  /* Recessed fills — controls are carved INTO the window (darker), then lit on hover */
  --fill-recessed: rgba(0, 0, 0, 0.14);
  --fill-hover:    rgba(255, 255, 255, 0.12);
  --fill-selected: rgba(255, 255, 255, 0.24);

  --glass-blur-thin:  20px;
  --glass-blur:       32px;
  --glass-blur-thick: 48px;
  --glass-saturate:   180%;

  /* Edge light — the specular rim that makes glass read as glass */
  --edge-highlight: rgba(255, 255, 255, 0.35);
  --edge-lowlight:  rgba(255, 255, 255, 0.05);
  --hairline:       rgba(255, 255, 255, 0.10);

  /* Text vibrancy — hierarchy by opacity.
     Tertiary (50%) does NOT reach 4.5:1 on regular glass: use it only for
     large text (≥ 24px, or ≥ 19px bold) or non-essential metadata. */
  --text-primary:   rgba(255, 255, 255, 0.96);
  --text-secondary: rgba(255, 255, 255, 0.70);
  --text-tertiary:  rgba(255, 255, 255, 0.50);
  --text-disabled:  rgba(255, 255, 255, 0.30);

  /* Accents — use sparingly */
  --accent:      #0A84FF;
  --accent-soft: rgba(10, 132, 255, 0.25);   /* fills only — too faint for a focus ring */
  --success:     #30D158;
  --destructive: #FF453A;
  --focus-ring:  rgba(255, 255, 255, 0.92);  /* ≥ 3:1 against any glass */

  /* Radii — large and concentric: inner = outer − padding */
  --radius-window:   40px;
  --window-padding:  24px;
  --radius-inner:    calc(var(--radius-window) - var(--window-padding)); /* 16px */
  --radius-popover:  28px;
  --radius-control:  9999px;   /* capsules */

  /* Depth */
  --shadow-window:  0 30px 80px -20px rgba(0,0,0,0.45), 0 10px 30px -10px rgba(0,0,0,0.30);
  --shadow-float:   0 18px 40px -12px rgba(0,0,0,0.40);
  --shadow-popover: 0 40px 100px -20px rgba(0,0,0,0.55);

  /* Motion */
  --spring:   cubic-bezier(0.32, 0.72, 0, 1);
  --dur-fast: 180ms;
  --dur-base: 320ms;
  --dur-slow: 520ms;
}
```

**Concentric radii:** if you change `--window-padding`, `--radius-inner` follows.
Mismatched corners are the fastest tell of a fake glass UI.

## The glass recipe

One class family; no one-off `backdrop-filter`s in components. Variants are
modifiers, always combined with the base: `class="glass glass-thin"`. They only
swap custom properties, so the prefixed and unprefixed `backdrop-filter`, the
radius and the shadow all stay in sync (setting `backdrop-filter` directly in a
variant leaves Safari's `-webkit-` value behind).

```css
.glass {
  --glass-bg:     var(--glass-regular);
  --glass-blur-v: var(--glass-blur);
  --glass-radius: var(--radius-window);
  --glass-shadow: var(--shadow-window);

  position: relative;
  background: var(--glass-bg);
  -webkit-backdrop-filter: blur(var(--glass-blur-v)) saturate(var(--glass-saturate));
          backdrop-filter: blur(var(--glass-blur-v)) saturate(var(--glass-saturate));
  border-radius: var(--glass-radius);
  box-shadow:
    inset 0 1px 0 0 var(--edge-highlight),     /* top rim catches light */
    inset 0 -1px 0 0 var(--edge-lowlight),     /* bottom rim stays dark */
    var(--glass-shadow);
  isolation: isolate;
}

/* Gradient rim — brighter at top-left, fading around the edge */
.glass::before {
  content: "";
  position: absolute;
  inset: 0;
  border-radius: inherit;
  padding: 1px;
  background: linear-gradient(135deg,
    rgba(255,255,255,0.45) 0%, rgba(255,255,255,0.08) 40%,
    rgba(255,255,255,0.02) 60%, rgba(255,255,255,0.20) 100%);
  -webkit-mask: linear-gradient(#000 0 0) content-box, linear-gradient(#000 0 0);
  -webkit-mask-composite: xor;
          mask: linear-gradient(#000 0 0) content-box, linear-gradient(#000 0 0);
          mask-composite: exclude;
  pointer-events: none;
}

.glass-thin  { --glass-bg: var(--glass-thin);  --glass-blur-v: var(--glass-blur-thin);
               --glass-radius: var(--radius-inner); --glass-shadow: 0 0 #0000; }
.glass-thick { --glass-bg: var(--glass-thick); --glass-blur-v: var(--glass-blur-thick);
               --glass-radius: var(--radius-popover); --glass-shadow: var(--shadow-popover); }
.glass-dark  { --glass-bg: var(--glass-dark); }
.glass-float { --glass-radius: var(--radius-control); --glass-shadow: var(--shadow-float); } /* tab bar, ornament */
```

## Pointer glow (web stand-in for the gaze highlight)

Gradients can't be transitioned, so the glow lives on a `::after` layer that
fades in; the rim keeps `::before`.

```css
.glow { position: relative; }
.glow::after {
  content: "";
  position: absolute;
  inset: 0;
  border-radius: inherit;
  background: radial-gradient(180px circle at var(--x, 50%) var(--y, 50%),
    rgba(255,255,255,0.14), transparent 60%);
  opacity: 0;
  transition: opacity var(--dur-fast) var(--spring);
  pointer-events: none;
}
@media (hover: hover) {
  .glow:hover::after { opacity: 1; }
}

:focus-visible { outline: 2px solid var(--focus-ring); outline-offset: 3px; }
```

```ts
// hooks/usePointerGlow.ts — const ref = usePointerGlow<HTMLButtonElement>(); <button ref={ref} className="glow …">
import { useEffect, useRef } from "react";

export function usePointerGlow<T extends HTMLElement>() {
  const ref = useRef<T>(null);
  useEffect(() => {
    const el = ref.current;
    if (!el || !window.matchMedia("(hover: hover)").matches) return;
    let frame = 0;
    const onMove = (e: PointerEvent) => {
      cancelAnimationFrame(frame);
      frame = requestAnimationFrame(() => {
        const r = el.getBoundingClientRect();
        el.style.setProperty("--x", `${e.clientX - r.left}px`);
        el.style.setProperty("--y", `${e.clientY - r.top}px`);
      });
    };
    el.addEventListener("pointermove", onMove);
    return () => {
      el.removeEventListener("pointermove", onMove);
      cancelAnimationFrame(frame);
    };
  }, []);
  return ref;
}
```

## Typography

- **Stack:** `-apple-system, BlinkMacSystemFont, "SF Pro Text", "SF Pro Display", Inter, system-ui, sans-serif`.
  Apple devices render SF from the system; everywhere else gets Inter (Google
  Fonts, weights 400/500/600/700). Never self-host SF Pro files — Apple's
  licence doesn't allow web embedding.
- **Weights skew heavy — glass eats thin strokes.** Body 500, labels 600,
  titles 700. Nothing at 300 or lighter.

| Role | Size / line-height | Weight | Tracking |
|---|---|---|---|
| Large title | 44 / 52 | 700 | −0.02em |
| Title 1 | 32 / 40 | 700 | −0.015em |
| Title 2 | 24 / 32 | 600 | −0.01em |
| Headline | 19 / 26 | 600 | −0.005em |
| Body | 17 / 24 | 500 | 0 |
| Callout | 15 / 22 | 500 | 0 |
| Caption | 13 / 18 | 600 | 0.01em |

- **Colour:** white only, hierarchy via `--text-*`. No grey hex values.
- **Busy environments:** `text-shadow: 0 1px 2px rgba(0,0,0,0.25)` — only when a
  contrast check fails, and fix the glass first.

## Motion

Use Motion (`motion` package, `import { motion } from "motion/react"`), the
current name of Framer Motion; `framer-motion` imports still work in older
projects such as many Lovable templates.

```ts
export const spring = { type: "spring", stiffness: 260, damping: 30, mass: 0.9 };

// Window entrance: rise toward the viewer. Transform + opacity only — animating
// `filter: blur()` here makes the window a backdrop root mid-animation (child
// glass stops blurring the room) and costs a full repaint per frame.
export const windowIn = {
  initial: { opacity: 0, scale: 0.94, y: 24 },
  animate: { opacity: 1, scale: 1, y: 0, transition: spring },
};

// Hover lift for interactive glass
export const lift = { whileHover: { scale: 1.02, y: -2 }, whileTap: { scale: 0.97 } };
```

- Stagger children 40–60ms. Ornament and tab bar enter 120ms after the window.
- Wrap the app in `<MotionConfig reducedMotion="user">` so reduced-motion users
  get opacity fades (≤150ms) instead of springs and scale.
- Never animate `backdrop-filter` or `filter` values; `will-change: transform`
  only while an animation runs.

## Tailwind + shadcn

**Tailwind v3** (`tailwind.config.ts`):

```ts
extend: {
  borderRadius: { window: "var(--radius-window)", inner: "var(--radius-inner)", popover: "var(--radius-popover)" },
  backdropBlur: { "glass-thin": "var(--glass-blur-thin)", glass: "var(--glass-blur)", "glass-thick": "var(--glass-blur-thick)" },
  boxShadow: { window: "var(--shadow-window)", float: "var(--shadow-float)", popover: "var(--shadow-popover)" },
  colors: {
    glass: { thin: "var(--glass-thin)", DEFAULT: "var(--glass-regular)", thick: "var(--glass-thick)" },
    ink: { DEFAULT: "var(--text-primary)", 2: "var(--text-secondary)", 3: "var(--text-tertiary)" },
  },
  transitionTimingFunction: { spring: "var(--spring)" },
}
```

**Tailwind v4** (CSS-first, no config file) — map colours in `@theme inline`,
and reach the rest through variable shorthand (`rounded-(--radius-window)`,
`shadow-(--shadow-float)`) rather than redeclaring names that already live in
`:root`:

```css
@theme inline {
  --color-glass-thin: var(--glass-thin);
  --color-glass: var(--glass-regular);
  --color-glass-thick: var(--glass-thick);
  --color-ink: var(--text-primary);
  --color-ink-2: var(--text-secondary);
  --color-ink-3: var(--text-tertiary);
  --ease-spring: cubic-bezier(0.32, 0.72, 0, 1);
}
```

**shadcn:** check how its tokens are consumed before overriding them.
- Older (Tailwind v3) shadcn stores bare HSL channels (`--card: 0 0% 100%`) read
  as `hsl(var(--card))`. Setting `--card` to an `rgba()` token produces invalid
  CSS and the card goes transparent-white. Instead, change the component classes
  to `glass glass-thin` / `bg-glass`.
- Newer (Tailwind v4) shadcn stores full colours (`oklch(...)`), so
  `--card: var(--glass-regular)` works directly.
- Either way: `--background: transparent`, `--border` → `--hairline`,
  `--radius: 1.75rem`, and `Button` variants `glass`, `prominent`, `accent`, `icon`.

## Accessibility fallbacks

Place after the glass variants.

```css
@media (prefers-reduced-transparency: reduce) {
  .glass {
    --glass-bg: var(--glass-solid);
    -webkit-backdrop-filter: none;
            backdrop-filter: none;
  }
}

/* In-app "Reduce transparency" toggle adds .solid to <html> —
   the media query isn't supported in every browser yet. */
html.solid .glass {
  --glass-bg: var(--glass-solid);
  -webkit-backdrop-filter: none;
          backdrop-filter: none;
}

@supports not ((backdrop-filter: blur(1px)) or (-webkit-backdrop-filter: blur(1px))) {
  .glass { --glass-bg: rgba(28, 28, 32, 0.88); }
}
```

- Every control shows the `:focus-visible` ring — keyboard users get no glow.
- Hover-revealed UI (tab-bar labels, resize arcs) also appears on
  `:focus-within`, and never hides anything essential on touch screens.
- Icon-only buttons always get `aria-label`.
- Measure contrast against the environment, not against a black/white assumption.

## Performance

- Cap visible `backdrop-filter` surfaces at ~6–8 (≈4 over an ambient video,
  which forces every glass surface to re-blur each frame). Repeated items (list
  rows, grid cards) get a translucent fill, no blur.
- Environment images: WebP/AVIF, ≤300KB, ~1600px wide — the blur hides detail.
