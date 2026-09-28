# Signature components

All sizes are desktop defaults. Class names refer to
`references/tokens-and-glass.md`.

## Environment

Pick one per app and keep it.

1. **Passthrough room (most native)** — a real, well-lit interior photo (living
   room, studio, office with a window). `filter: blur(12–20px) brightness(0.8)`,
   scaled 110% so blurred edges don't show. Most Vision Pro screenshots look
   like this.
2. **visionOS-style Environment** — a calm vista (alpine lake, desert at dusk,
   moonlit shore), same treatment, slow 60s Ken Burns drift (disabled under
   reduced motion).
3. **Ambient video** — muted looped footage, same treatment. Pause when the tab
   is hidden and under reduced motion; keep glass surfaces to ~4.

Avoid abstract gradient meshes. Always test UI over the **brightest** part of
the environment — that is where legibility breaks. `--env-dim` goes on a
separate overlay element, not a filter on the window.

## Window

- `glass`, max width ~1100px, centred, ≥48px from viewport edges, padding
  `--window-padding`.
- **Reserve room for the tab bar.** It sits 88px outside the leading edge
  (68px + 20px gap), so clamp the width:
  `max-width: min(1100px, 100vw - 2 * (48px + 88px))`. Otherwise it clips on
  1280px laptops.
- Title area: large bold title top-left, small glass capsule controls top-right.
  No divider under it.
- **Window controls (required, the most recognisable cue):** centred 14px below
  the window, a 64×6px white grabber pill at 45% opacity, with a 22px circular
  glass close button 10px to its left (hit area padded to 44px). Both brighten
  on hover. Close dismisses / navigates back; the grabber may drag the window.
- Optional: faint white quarter-circle resize arcs at the bottom corners on
  window hover.

## Vertical tab bar

- `glass glass-float`, 68px wide, 20px outside the window's leading edge,
  vertically centred. A **sibling** of the window (see SKILL.md).
- Icon-only at rest (Lucide, 22px, stroke 2).
- **The whole pill expands** — not a tooltip per icon. On `:hover` (inside
  `@media (hover: hover)`) **and** on `:focus-within`, it springs to ~220px and
  labels fade in. Animate `width` with the spring, or better a `clip-path`/
  `transform` reveal on an absolutely positioned label layer so the window
  doesn't reflow.
- Selected: `--fill-selected` circle behind the icon, `--text-primary`; others
  `--text-secondary`. Mark it with `aria-current="page"`.
- Below 768px: a horizontal floating capsule 16px above the bottom edge, labels
  hidden, `aria-label` on every item.

## Ornament

- `glass glass-float`, 56px tall, centred on the window's bottom edge,
  overlapping it by ~28px. A **sibling** of the window.
- 3–6 primary actions as icon buttons or icon+label capsules.
- `--shadow-float` so it clearly sits in front.
- Below 768px it stacks above the tab-bar capsule.

## Buttons

| Variant | Look | Use |
|---|---|---|
| Standard | capsule, `--fill-recessed`, white label 600 — carved into the glass. Hover: `--fill-hover` + glow + lift | default |
| Prominent | capsule, white at 90%, black label | one per view — visionOS's primary style |
| Accent | capsule filled `--accent` | brand-critical only |
| Icon | 44×44 visual circle, 60×60 hit area (padding or `::after`), `--fill-recessed`, glow | toolbars, ornament |

- Press: scale 0.97, 120ms.
- Targets 56–60px on desktop (visionOS asks for ~60pt because eyes are less
  precise than fingers), 44px absolute minimum, 8–16px between targets.

## Cards & lists

- Inside a window: `glass glass-thin` or **no glass at all** — the window's blur
  already does the work. Never regular glass on regular glass: nested
  backdrop filters only see the window, not the room, and read muddy.
- Radius `--radius-inner` (concentric with the window).
- List rows: 56px min height, `--hairline` separators inset from the leading
  edge, full-row hover glow. No blur per row.

## Segmented controls & toggles

- Segmented: recessed capsule track (`--fill-recessed`) with a `--fill-selected`
  capsule that springs between segments (`layoutId` in Motion). `role="tablist"`
  or radio group semantics.
- Toggle: iOS-shaped on a recessed track; "on" uses `--success` or white.
  Use `role="switch"` + `aria-checked`.

## Inputs

- Capsule fields, `--fill-recessed` (carved in, not raised), 48–52px tall,
  placeholder `--text-tertiary` (placeholders are exempt from AA, labels are not
  — always render a real label).
- Focus: 2px solid `--accent` (or `--focus-ring`) ring plus brightened fill.
  `--accent-soft` alone is too faint to meet the 3:1 focus-indicator contrast.

## Sheets, popovers, menus

- `glass glass-thick`.
- On open, the window behind scales to 0.97 and a scrim (`--env-dim`-style
  overlay) darkens it — the sheet comes *forward* while the parent pushes back.
  Dim with the scrim, not with `filter: brightness()` or `opacity` on the window
  (both turn it into a backdrop root).
- Spring in from 24px below. Trap focus, close on Escape, restore focus on close.

## Volume (3D content)

- For anything that is an object: products, devices, models.
- A borderless stage: the model (`@google/model-viewer` or React Three Fiber)
  floats above a soft elliptical floor shadow. **No window chrome and no glass
  background** — volumes don't have one in visionOS.
- Slow auto-rotate (off under reduced motion); drag to orbit. Window controls sit
  below the floor.

## Immersive mode (Full Space)

- An "Enter immersive" action in the ornament.
- On enter: the environment crossfades (800ms) to the app's own full-bleed scene,
  the window scales down and moves toward the bottom, other UI fades out. A small
  glass "Exit" capsule stays visible and focusable; Escape also exits.
- On exit: reverse the transition.

## Home View / launcher

- Grid of **circular** app icons (not rounded squares): a layered circle with a
  glass rim, subtle inner shadow and a foreground glyph. Labels white 13/600
  below.
- Hover: lift + scale 1.08 + strong glow. Honeycomb-offset rows feel most native.
- Use the app's own glyphs — never Apple's app icons.
