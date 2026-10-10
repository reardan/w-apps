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
presence and exact equality are supported. Pseudo-classes include `:root`,
`:first-child`, `:last-child`, `:link`, `:checked`, `:disabled`, `:not()`, `:is()`,
`:where()` and `:nth-child()` with integers, `odd`, or `even`.

Attribute substring operators, arbitrary `an+b` expressions, pseudo-elements,
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
Colors accept rgb()/rgba(), 3/4/6/8-digit hex, transparent, and the classic CSS palette (black,
white, gray/grey, silver, red, green, blue, yellow, orange, purple, navy, teal,
maroon, olive, lime, aqua/cyan, and fuchsia/magenta). HSL colors, gradients,
background images and custom properties are not implemented.

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
