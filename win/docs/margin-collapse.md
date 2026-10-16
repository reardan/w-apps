# Adjacent normal-block margin collapse

The expanded pinned WPT run exposed a geometry regression in the existing
`hex-001` and `rgb-001` cases. Two paragraph boxes forming the test square started
10px below the reference div. Removing nonstandard generic-container margins
had exposed missing sibling margin collapse; the RGB pixels themselves matched.

Adjacent in-flow block-level siblings now share the greatest positive margin
plus the most negative margin, following the supported sibling case in
[CSS 2.2 collapsing margins](https://www.w3.org/TR/CSS22/box.html#collapsing-margins).
Collapsed whitespace, comments, hidden/display-none elements, and out-of-flow
fixed elements do not separate the siblings. Inline text separates them. The
normal-flow child walker applies this calculation; flex/grid item layout keeps
its separate spacing rules. The boxes' own borders/padding remain inside their
border boxes and do not prevent their external sibling margins from adjoining.

Paragraph UA top/bottom margins are `1em` of their computed font size, consistent
with the [HTML rendering defaults](https://html.spec.whatwg.org/multipage/rendering.html#flow-content-3).
Author declarations, including explicit zero margins, retain their cascade
precedence. Generic containers retain zero default margins.

This is bounded sibling support, not complete margin collapsing. Parent/child
collapse, collapse through empty blocks, clearance/float interactions, and
transparent empty inline wrappers remain outside the implemented contract.
The change adds no retained allocations and keeps the existing page/node limits.

`margin_collapse_test.w` checks positive, mixed-sign and negative margins,
whitespace/hidden/fixed separators, borders/padding, flex/grid isolation, inline
text, computed-font paragraph defaults, and author overrides. Eleven existing
root/flex/CSS/layout/forms tests pass. The unchanged native WPT adapter reports
20 PASS, zero FAIL/UNSUPPORTED/ERROR, with exact pixels for all references.
