# Root layout and overridable reader spacing

The initial containing block starts at `(0, 0)` and spans the layout width.
Win's existing reader spacing is represented by UA body margins, including an
implied body: `20px 28px 28px 28px`. Author declarations, inline styles and CSS
wide keywords override these defaults through the existing cascade. `html` is a
block with zero UA margins. No unconditional 28px/20px offset is applied outside
the CSS box tree, and scroll overflow adds the computed body bottom margin
instead of an unconditional trailing gap.

Solid root backgrounds cover at least the viewport. If the root background is
transparent, the first body child's solid background propagates instead. The
source box does not paint the propagated background a second time, preserving
translucent color. Computed styles remain unchanged. This follows the solid-color
portion of [CSS Backgrounds §2.11](https://www.w3.org/TR/css-backgrounds-3/#special-backgrounds);
background images and containment are outside the supported profile.

Validation:

- `root_layout_test.w`: implied-body defaults, explicit margins, author zero and
  initial resets, viewport units, root width, background propagation, alpha
  ownership and `display:none`.
- `root_layout_integration.py`: six full 800×600 pixel comparisons covering
  author zero margins, explicit margins, root/body propagation and single alpha
  compositing. Only the half-alpha case allows a one-channel rounding difference.
- Existing layout, CSS, CSS foundation, custom properties, calc/viewport, CSSOM
  and browser tests pass. The unchanged pinned WPT reftests remain 12 PASS,
  0 failures/errors/unsupported; no reference or host source changed.
- The unchanged mobile host renders with the explicit 200,000,000 execution
  budget, title `W mobile form`, and zero script/resource failures. Its root
  background covers the viewport and the external reader inset is gone.

This preserves Win's existing UA typography and generic block margins. In
particular the current generic `div` top margin is 10px, so the unchanged mobile
host's `#wrap` still has a 10px flow offset compared with Chromium's zero-margin
`div`. This is separate from body-margin override and remains visible in the
native/reference comparison. Percentage heights, fixed positioning, overflow
clipping, safe-area `env()` and background images are not implemented by this
change. The retained reader margins and generic block margins are Win defaults,
not a claim of matching Chromium's UA stylesheet.
