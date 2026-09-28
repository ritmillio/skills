# Lovable prompts

Paste the token block and glass recipe from `references/tokens-and-glass.md`
where the prompt says `[paste …]` — Lovable follows pasted CSS far more
faithfully than a description of it.

## Starter prompt (first message)

```
Build [APP NAME], a [one-line purpose], designed to look exactly like a native Apple Vision Pro (visionOS) app floating in a room.

Layers: a full-screen, lightly blurred photo of a real [living room / studio / lake at dusk] as the environment (standing in for passthrough). Over it, a centred scene container holding four SIBLINGS (none nested inside another): a floating window of neutral grey visionOS glass (40px radius, translucent tinted grey, bright top rim, deep soft shadow) with generous space around it; visionOS window controls centred just below the window (a white grabber pill with a small circular close button to its left); a vertical glass pill tab bar floating off the window's left edge that expands to reveal labels on hover and on keyboard focus; and a glass capsule ornament overlapping the window's bottom edge holding the primary actions.

Use these CSS variables as the single source of truth: [paste tokens]. Use the .glass class with .glass-thin / .glass-thick / .glass-float modifiers exactly as given: [paste glass recipe]. Controls inside the window are recessed (darker fill) and light up on hover with a pointer-following glow and slight lift, mimicking visionOS gaze highlighting. One prominent button per view: white capsule, black label. All text white, hierarchy via opacity (96/70/50%), font -apple-system with Inter fallback, weights 500+. Hit targets 56–60px. Spring animations with Motion (framer-motion), transform and opacity only.

Hard rules: no light mode, no opaque backgrounds, no grey hex text, no abstract gradient background, no glass nested in same-thickness glass, never animate filter or backdrop-filter, every body-text pairing passes WCAG AA over the brightest part of the background, visible white focus ring on every control, include reduce-transparency fallbacks (media query plus an in-app toggle).
```

## Follow-up prompts

- **Add a screen:** `Add a [screen] view inside the existing window. Reuse "glass glass-thin" cards and existing tokens only. Keep the tab bar and ornament in place; update the ornament actions to [actions].`
- **Add a 3D volume:** `Add a volume view for [object]: a 3D model with model-viewer floating above a soft elliptical floor shadow, no window background, slow auto-rotate (off for reduced motion), drag to orbit, window controls below.`
- **Add immersive mode:** `Add an "Enter immersive" ornament action: crossfade the environment to [scene] over 800ms, shrink the window toward the bottom, fade other UI, and show a small glass "Exit" capsule (also Escape) that reverses it.`
- **Add a sheet:** `Add a [name] sheet using "glass glass-thick". When open, scale the main window to 0.97 and darken it with a scrim overlay (not a filter). Spring in from 24px below, trap focus, close on Escape.`
- **Mobile pass:** `Make this responsive: below 768px, the window goes full-width with 12px margins, 28px radius and 12px padding; the tab bar becomes a horizontal floating capsule 16px above the bottom; the ornament sits above the tab bar. No hover-only behaviour on touch.`

## Fix prompts

- **Looks like grey plastic:** `The glass looks flat. Make sure the environment layer has real colour and detail behind the window, keep saturate() at 180%, and add the gradient rim ::before highlight.`
- **Ornament or tab bar looks flat grey over the background:** `The ornament and tab bar are nested inside the window, so their backdrop-filter only sees the window. Move them (and the window controls) out to be siblings of the window inside a relatively positioned scene container.`
- **Text hard to read:** `Text contrast fails over the bright parts of the background. Add the .glass-dark modifier to affected surfaces, increase --env-dim to 0.45, and keep body weight at 500. Don't reduce text size.`
- **Muddy nested panels:** `Remove backdrop-filter from cards inside the window; use a --glass-thin fill only so the window's blur does the work.`
- **Janky scrolling:** `Reduce simultaneous backdrop-filter elements to 8 or fewer. List items use a translucent fill without blur.`
- **Tab bar clipped on laptop screens:** `Clamp the window to max-width: min(1100px, 100vw - 272px) so the tab bar has room outside its leading edge.`
