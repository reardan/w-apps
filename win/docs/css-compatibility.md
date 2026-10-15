# CSS and layout compatibility

Win now applies embedded and linked author stylesheets and inline declarations.
Stylesheet order follows document order even when external requests finish in a
different order. Each declaration competes by `!important`, selector specificity,
and source order; inline declarations outrank normal stylesheet declarations.
Specificity is compared as a tuple rather than a packed integer. Declarations
are validated before competing, so an invalid later value does not erase a valid
winner. Font-relative lengths resolve after the cascade selects the final font
size. Inherited text properties flow to descendants, and supported properties
accept `inherit`, `initial`, and `unset`. The implementation uses W's owned,
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
Coefficients and offsets are limited to magnitude 1,000,000,000.
`:nth-child(An+B of S)` and `:nth-last-child(An+B of S)` count only siblings
matching the selector list `S`, including the candidate itself; filters may use
supported complex selectors. Their specificity includes the most specific filter
branch, even if that branch does not match the candidate. The `of` clause is not
valid for `:nth-of-type()` or `:nth-last-of-type()`.

`:is()` and `:where()` use forgiving lists: invalid or unsupported branches are
discarded, contribute no specificity, and an empty surviving list matches nothing.
`:is()` uses the maximum surviving branch specificity; `:where()` contributes zero.
Ordinary selector lists, `:not()` arguments, and nth-child filters are strict:
one invalid branch rejects the entire list, including a whole stylesheet rule.

Pseudo-elements, interaction pseudo-classes such as `:hover`, namespaces and CSS nesting are not
implemented. `@media` supports screen/all and conjunctions of `min-width`
and `max-width` lengths in px/em/rem (media em/rem use the initial 18px size);
unsupported queries (including print) do not apply. Media queries
are re-evaluated on layout, including viewport resize.

## Properties

Supported properties are:

- `color`, `font-size`, `font-weight`, `font-style`, `text-decoration`,
  `white-space`, `text-align`, `line-height`, `display`, and `visibility`.
- `width`, `height`, `max-width`, `box-sizing`, `margin`, `padding`, and their
  four physical side longhands. Horizontal auto margins center or right-align
  constrained block boxes.
- Solid `background`/`background-color`, `border`, `border-width`, `border-style`, and
  `border-color` for block boxes.
- `gap`, `column-gap`, `flex-direction`, and `grid-template-columns` for the
  limited flex/grid layouts described below.

Lengths accept px, em, and rem values, including fractional and exponent numeric
syntax and case-insensitive units. Box geometry retains floating-point lengths;
font rasterization and some image/text placement still use integer metrics.
Width and max-width also accept percentages. Font-size percentages are
relative to the inherited font size. Line height accepts pixels, em/rem,
percentages, unitless inherited multipliers, normal, and inherit; values smaller
than the font metrics currently keep the natural line height. Used lengths are
bounded to a magnitude of 1,000,000 pixels; font rasterization uses bounded strike
sizes.
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
leave earlier valid declarations effective. Relative colors, other color spaces,
gradients, background images and custom properties are not implemented.
Functional colors apply to `color`, `background`, `background-color`,
`border-color`, and the `border` shorthand. Space-separated RGB/HSL forms accept
`none` for any channel (including alpha), rendered as zero; comma-separated forms
reject it. Missing-component preservation for interpolation and computed color
serialization is not implemented.

Uniform borders support `solid`, `none`, and `hidden` styles, pixel/em/rem widths
with fractional layout geometry, and `thin`/`medium`/`thick` (1/3/5 pixels).
Border painting currently uses whole-pixel widths.
Width and style cascade independently: a width alone does not enable painting.
The shorthand accepts supported components in any order and resets omitted
components to medium width, none style, and `currentColor`. Invalid or duplicate
components reject the whole declaration. Each component competes independently
with longhands and `!important`. Omitted border colors and explicit `currentColor`
in `border`/`border-color` follow the final computed text color. Per-side borders,
multiple longhand values and other line styles remain unsupported.

## Layout and painting

Block flow computes content width, padding, borders, margins and automatic
height. Text wraps, inherits typography and aligns left/center/right. Block
backgrounds and borders paint behind the content. Images preserve intrinsic
aspect ratio unless both dimensions are specified, accept HTML dimensions and
CSS width/height/max-width, and share line baseline placement with text. Forms
receive document boxes used by the browser's interactive widgets.

`display:flex` in row direction uses specified widths or intrinsic content sizes,
with the initial flex behavior (grow 0, shrink 1, basis auto). When items exceed the
available width, weighted shrinking freezes items at their supported content
minimums. Controls and decoded images contribute their own intrinsic dimensions;
failed or missing images use alt-text sizing. Descendant text measurement is approximate,
rather than a complete CSS min/max-content algorithm.
Percentage widths and max-widths resolve against the flex container once. Column
direction uses vertical rows; it does not implement the column flex sizing
algorithm.

Flex and grid generate anonymous items for non-whitespace text runs. Hidden
nodes and `display:none` children do not consume items or gaps; `visibility:hidden`
items retain geometry. `display:grid` creates equal tracks based on the number of
column tokens or `repeat(N, ...)`, wrapping later children into rows. Gap separates
rows/tracks. Declared flex factors, flex wrapping/alignment, proportional/fixed
grid track sizes, grid placement, and complete intrinsic sizing algorithms remain
unsupported.

Explicit block heights determine the box and following sibling position, while
visible overflowing content contributes to the page's scroll extent. This does
not implement clipping or scrolling through the CSS `overflow` property.

Inline backgrounds/borders, margin collapsing, floats, positioned layout,
transforms, animations, generated content, table layout, vertical writing and
full font-family selection remain unsupported. `visibility:hidden` preserves
layout geometry while suppressing painting and hit testing, and visible descendants
can restore painting. `inline-block` uses inline text flow,
not an independent formatting context. This is a substantial CSS implementation,
not browser-engine standards conformance.

The focused `win/tests/css_test.w` suite checks selector relationships, cascade
and inheritance, media resizing, box geometry and alignment, the supported flex/grid
layouts, and stylesheet order independent of request completion. The existing
browser regression suite also checks narrow viewport wrapping, oversized words,
preformatted text and clickable link geometry.

`win/tests/selectors_test.w` and `win/tests/colors_test.w` cover filtered sibling
counting, forgiving versus strict lists, specificity, missing color components,
border shorthand resets, malformed input, and cascade fallback.
`win/fixtures/standards.html` combines these features with page scripts and is
checked through actual browser loading in `win/tests/browser_test.w`.
The behavior targets the supported portions of
[Selectors Level 4](https://www.w3.org/TR/selectors-4/) and
[CSS Color Level 4](https://www.w3.org/TR/css-color-4/); these focused regressions
do not establish full conformance to either specification.

`win/tests/layout_test.w` covers anonymous text, hidden items, intrinsic
control/image sizes, flex shrinking, percentage max-width, and fixed-height visible
overflow. These cases qualify the supported foundation; full flex/grid and
independent inline-block formatting contexts remain deferred.
