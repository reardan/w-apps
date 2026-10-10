# CSS and layout compatibility

Win now applies embedded and linked author stylesheets and inline declarations.
Stylesheet order follows document order even when external requests finish in a
different order. Each declaration competes by `!important`, selector specificity,
and source order; inline declarations outrank normal stylesheet declarations.
Inherited text properties flow to descendants. The implementation uses W's owned,
bounded CSS tokenizer/parser; unsupported selectors and conditional at-rules are
ignored rather than matching every element.

## Selectors

Supported selectors are type, universal, ID, class, compound, comma-separated
lists, descendant, child, adjacent sibling and general sibling. Attribute
presence, exact equality, whitespace-word (`~=`), language-prefix (`|=`), prefix
(`^=`), suffix (`$=`), and substring (`*=`) matching are supported, with explicit
ASCII case-insensitive `i` and case-sensitive `s` flags. Without a flag, attribute
values use case-sensitive comparison; HTML's attribute-specific default case rules
are not modeled.

Pseudo-classes include `:root`, `:first-child`, `:last-child`, `:only-child`,
`:first-of-type`, `:last-of-type`, `:only-of-type`, `:link`, `:checked`, `:disabled`,
`:not()`, `:is()`, and `:where()`. `:nth-child()`, `:nth-last-child()`,
`:nth-of-type()`, and `:nth-last-of-type()` accept integer `an+b` expressions,
integers, `odd`, and `even`, including negative coefficients and offsets.
Coefficients and offsets are limited to magnitude 1,000,000,000. Unsupported or
malformed branches inside `:not()`, `:is()`, and `:where()` reject the containing
selector; forgiving selector-list recovery is not implemented.

Filtered `:nth-child(... of selector)` syntax, pseudo-elements,
interaction pseudo-classes such as `:hover`, namespaces and CSS nesting are not
implemented. `@media` supports screen/all and conjunctions of pixel `min-width`
and `max-width`; unsupported queries (including print) do not apply. Media queries
are re-evaluated on layout, including viewport resize.

## Properties

Supported properties are:

- `color`, `font-size`, `font-weight`, `font-style`, `text-decoration`,
  `white-space`, `text-align`, `line-height`, `display`, and `visibility`.
- `width`, `height`, `max-width`, `box-sizing`, `margin`, `padding`, and their
  four physical side longhands. Horizontal auto margins center or right-align
  constrained block boxes.
- Solid `background`/`background-color`, `border`, `border-width`, and
  `border-color` for block boxes.
- `gap`, `column-gap`, `flex-direction`, and `grid-template-columns` for the
  simplified column layouts described below.

Lengths accept pixel values and integer em/rem values, with rounding to whole
pixels. Width and max-width also accept percentages. Font-size percentages are
relative to the inherited font size. Line height accepts pixels, em/rem,
unitless inherited multipliers, normal, and inherit; values smaller than the font
metrics currently keep the natural line height. Font sizes are limited to 8–144 pixels.
Colors accept `rgb()`/`rgba()` and `hsl()`/`hsla()` in comma-separated and
space-separated forms, with slash alpha in space-separated forms. Hues accept
unitless degrees, `deg`, `grad`, `rad`, and `turn`, including wrapping negative
angles. Alpha accepts numbers and percentages. RGB and alpha channels are clamped
to their valid ranges. HSL saturation and lightness accept percentages, or numbers
in space-separated syntax, and are clamped to 0–100 before conversion. Color math
uses float32; out-of-gamut Color 4 mapping is not implemented. Colors also accept
3/4/6/8-digit hex, transparent, and the classic CSS palette (black,
white, gray/grey, silver, red, green, blue, yellow, orange, purple, navy, teal,
maroon, olive, lime, aqua/cyan, and fuchsia/magenta). Invalid color declarations
leave earlier valid declarations effective. Missing color components (`none`),
relative colors, other color spaces, gradients, background images and custom
properties are not implemented.
Functional colors apply to `color`, `background`, `background-color`, and
`border-color`; the `border` shorthand still accepts only named/hex colors.

## Layout and painting

Block flow computes content width, padding, borders, margins and automatic
height. Text wraps, inherits typography and aligns left/center/right. Block
backgrounds and borders paint behind the content. Images preserve intrinsic
aspect ratio unless both dimensions are specified, accept HTML dimensions and
CSS width/height/max-width, and share line baseline placement with text. Forms
receive document boxes used by the browser's interactive widgets.

`display:flex` lays element children into equally sized columns; column direction
uses ordinary vertical flow. `display:grid` creates equal tracks based on the
number of column tokens or `repeat(N, ...)`, wrapping later children into rows.
Gap separates rows/tracks. These are intentionally simplified layouts: flex
sizing, proportional/fixed grid track sizes, wrapping, item alignment, placement,
and min-content algorithms are not implemented. Non-element children of these
column containers do not generate anonymous items.

Inline backgrounds/borders, margin collapsing, floats, positioned layout,
transforms, animations, generated content, table layout, vertical writing and
full font-family selection remain unsupported. `visibility:hidden` preserves
layout geometry while suppressing painting and hit testing, and visible descendants
can restore painting. `inline-block` uses inline text flow,
not an independent formatting context. This is a substantial CSS implementation,
not browser-engine standards conformance.

The focused `win/tests/css_test.w` suite checks selector relationships, cascade
and inheritance, media resizing, box geometry and alignment, basic flex/grid
columns, and stylesheet order independent of request completion. The existing
browser regression suite also checks narrow viewport wrapping, oversized words,
preformatted text and clickable link geometry.

`win/tests/selectors_test.w` and `win/tests/colors_test.w` cover the expanded
selector and color syntax, including malformed input and cascade fallback.
`win/fixtures/standards.html` combines these features with page scripts and is
checked through actual browser loading in `win/tests/browser_test.w`.
The behavior targets the supported portions of
[Selectors Level 4](https://www.w3.org/TR/selectors-4/) and
[CSS Color Level 4](https://www.w3.org/TR/css-color-4/); these focused regressions
do not establish full conformance to either specification.
