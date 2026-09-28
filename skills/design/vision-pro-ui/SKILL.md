---
name: vision-pro-ui
description: Build web apps that look and behave like native Apple Vision Pro (visionOS) apps — floating glass windows over a room, ornaments, expanding vertical tab bars, gaze-style hover highlights, volumes and immersive spaces. Use when the user asks for 'Vision Pro style', 'visionOS UI', 'spatial computing UI' or 'make it feel like Vision Pro', in Lovable or any React + Tailwind app. Not for iPhone/Mac Liquid Glass or generic glassmorphism.
---

# /vision-pro-ui — web apps that pass as visionOS windows

The reference is **visionOS itself**, not iPhone or Mac glass. Picture a window
floating in a living room, a tab bar hovering beside it, controls lighting up
when you look at them, and the room still visible through everything.

One test for every decision: *would this look at home as a native visionOS app
window?* If it looks like an iOS screen or a Dribbble glassmorphism shot, it is
wrong. And because glass sits over an unpredictable background, **legibility is
a hard constraint** — beautiful glass nobody can read is a failed build.

## When to use this

- "Vision Pro style", "visionOS", "spatial UI", "make it float in a room".
- Lovable builds (ready prompts in `references/lovable-prompts.md`) or any
  React + Tailwind (+ shadcn) app.

## When NOT to use this

- iOS 26 / macOS Liquid Glass — different material (clear, refractive, light
  and dark modes). Don't mix the two vocabularies.
- Dense data tools, admin panels, anything read for hours: glass over a photo
  costs contrast and GPU. Say so and suggest a solid theme instead.
- The user wants generic frosted-card glassmorphism. That is an anti-pattern here.

## The look in one paragraph

Behind everything is **the room**: a softly blurred photo of a real interior or
landscape standing in for passthrough. In front floats a **window**: a large
rounded pane of neutral, slightly warm grey glass — tinted, not white frost.
Under it sit the **window controls**: a grabber pill with a close dot to its
left. Off its leading edge floats a **vertical tab bar** that widens to reveal
labels on hover. Primary actions live in an **ornament**, a glass capsule
overlapping the window's bottom edge. Text is white and set heavier than on
other platforms. Everything interactive **lights up on hover**, the way visionOS
highlights what your eyes rest on. No light mode, no opaque surfaces, almost no
brand colour.

## Vocabulary (use these names in code and prompts)

| visionOS | Web translation |
|---|---|
| **Environment** / passthrough | Full-viewport background layer: room photo, vista or ambient video |
| **Window** | `<Window>`, the main glass pane |
| **Window controls** | Grabber + close button floating just below the window |
| **Ornament** | `<Ornament>` capsule overlapping the window's bottom edge |
| **Tab bar** | `<TabBar>`, vertical pill on the leading edge, widens on hover/focus |
| **Hover effect** | Pointer-following glow + slight lift |
| **Volume** | Borderless 3D stage (`<model-viewer>` / React Three Fiber) over a floor shadow |
| **Full Space** | "Immersive mode": environment swaps to the app's scene, window recedes |
| **Home View** | Launcher of circular glass icons |

## Core principles

1. **Content first, chrome recedes.** User content is the most saturated,
   highest-contrast thing on screen.
2. **Glass needs something behind it.** Build the environment layer first; glass
   on a flat colour reads as grey plastic.
3. **Depth = layers, not borders.** Separate surfaces by blur, brightness and
   shadow. Dividers are white hairlines at 8–12%, never grey 1px borders.
4. **Light, not colour.** Brighter is closer; text opacity sets importance.
   Colour is reserved for state (selected, destructive, live).
5. **Legibility is non-negotiable.** Body text passes WCAG AA (4.5:1) measured
   over the *brightest* part of the environment. If it fails, thicken the glass
   or dim the room — never shrink the text.
6. **Everything floats** with generous margins. No edge-glued headers.
7. **Motion is physical.** Springs, subtle scale, depth lift. No linear slides.
8. **One appearance.** visionOS has no light/dark mode. Don't ship a theme toggle.
9. **Look, then pinch.** Every target has an obvious hover state before click,
   and is big enough to "look at": 56–60px on desktop, 44px minimum.

## Layer model — and the one structural trap

| Layer | z | Notes |
|---|---|---|
| `environment` | 0 | Room photo/video, lightly blurred |
| `window` | 10 | Main glass pane |
| `content` | 20 | Cards/lists inside the window — thin glass or none |
| `tabbar`, `ornament` | 30 | Float at the window's edges |
| `popover` | 40 | Thickest glass, strongest shadow |
| `overlay` | 50 | Scrim; the window pushes back |

**Tab bar, ornament and window controls must be siblings of the window, not
children.** An element with `backdrop-filter` (or `filter`, `opacity < 1`,
`mask`) becomes a *backdrop root*: a glass child inside it only blurs the
window, not the room. An ornament nested in the window looks flat grey where it
hangs over the environment. Wrap all four in a positioned container instead:

```tsx
<div className="relative mx-auto max-w-[1100px]">   {/* scene anchor */}
  <Window />          {/* .glass */}
  <TabBar />          {/* absolute, right-full mr-5 */}
  <Ornament />        {/* absolute, bottom-0 translate-y-1/2 */}
  <WindowControls />  {/* absolute, top-full mt-3.5 */}
</div>
```

## Workflow

1. **Environment first.** Pick one recipe (`references/components.md` §Environment)
   and keep it for the whole app.
2. **Paste the tokens and glass recipe** from `references/tokens-and-glass.md`
   into `src/index.css`. Components reference variables, never raw values.
3. **Build the scene anchor** above: window, controls, tab bar, ornament.
4. **Build screens** from the component specs in `references/components.md`.
5. **Wire motion** (`references/tokens-and-glass.md` §Motion) — transform and
   opacity only.
6. **Add fallbacks**: reduced transparency (media query *and* in-app toggle),
   no-`backdrop-filter`, reduced motion.
7. **Run the QA checklist below** before calling it done. In Lovable, use the
   fix prompts in `references/lovable-prompts.md` for anything that fails.

## Anti-patterns

- Glass on flat white/black; bright white "frosted" glass.
- Purple-pink gradient-mesh environments (2021 glassmorphism, not Vision Pro).
- iPhone patterns on desktop: bottom tab bars, top nav bars, hamburgers,
  rounded-square app icons.
- A light/dark toggle. Missing window controls.
- A tooltip per tab icon instead of the whole bar expanding.
- Coloured or grey-hex text on glass; weights of 300 or lighter.
- Glass nested in glass of the same thickness, or glass ornaments nested inside
  the window (see the backdrop-root trap).
- Animating `filter`/`backdrop-filter` values.
- Accent colour on more than one action per view; emoji as icons.
- Apple logos, Apple app icons, or self-hosted SF Pro font files (Apple's font
  licence forbids web embedding — use the system stack).

## QA checklist

- [ ] Squint test: would this pass as a Vision Pro screenshot?
- [ ] Real room/vista with colour and detail behind every glass surface.
- [ ] Glass is tinted grey, not white frost.
- [ ] Window controls under every window; ornament overlaps the bottom edge.
- [ ] Tab bar, ornament and controls are window *siblings* and blur the room.
- [ ] Tab bar expands on hover **and** on keyboard focus.
- [ ] Controls look recessed at rest and light up on hover.
- [ ] Radii are concentric (inner = outer − padding).
- [ ] Body text ≥ 4.5:1 over the brightest area; focus rings ≥ 3:1.
- [ ] Hover glow, press scale and a visible focus ring on every control.
- [ ] Reduce-transparency (media query + toggle) and no-blur fallbacks work.
- [ ] Reduced-motion users get fades, not springs.
- [ ] Mobile: horizontal tab capsule, ornament stacked above it, no hover-only UI.
- [ ] ≤ 8 blurred surfaces on screen; scrolling stays smooth.

## Report format

When done, say which environment recipe was used, list any text pairing that
needed the dark-glass or dimmed-environment fallback, and name any QA item that
could not be verified (e.g. no Safari to test in).
