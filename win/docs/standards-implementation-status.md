# Standards implementation status

The browser consumes merged W main
`a5a54fd77eb049d7126db6ce7f1a68e823fa5aca`, which includes
[W #647](https://github.com/reardan/w/pull/647) and
[W #650](https://github.com/reardan/w/pull/650). The earlier paused draft
checkpoint is superseded by this integration. The broader
[standards implementation plan](standards-gap-analysis.md) remains open; this is
a bounded browser foundation, not general website or standards conformance.

## Implemented foundation

- CSS uses structured specificity/cascade keys and validates specified values
  before selecting winners. Fractional/exponent lengths and case-insensitive
  units are preserved, font-relative values resolve after the cascade, and
  supported properties implement inheritance/initial/unset behavior.
- W provides descriptor/prototype hooks, receiver-aware calls, synchronous host
  properties, typed runtime errors, completion handling, `var` environments,
  synchronous arrows, and `typeof`. Its parser and native execution ledger cover
  additional early errors and pinned cases; the ledger is not a complete Test262
  harness.
- Win reads and writes supported DOM properties synchronously and exposes
  specified inline style reads plus CSSStyleDeclaration methods. Shorthand
  mutation accounts for supported longhands, and stylesheet text/tree mutations
  reconcile active sheet order. Window and Document are distinct event targets;
  callbacks preserve receivers. DOMContentLoaded follows the initial scripts,
  while load waits for the initial resource queue.
- Layout generates anonymous text items, skips hidden items, and measures
  intrinsic text, controls, and images. Row flex uses initial sizing and weighted
  shrinking; percentage max-width resolves once against the container. Fixed
  block heights place following siblings correctly, while visible overflow
  contributes to page extent. Grid still uses equal tracks.
- W supplies the complete pinned HTML named-character-reference table and numeric
  repair rules. Browser regressions check decoded titles/text and preserved link
  attributes; complete HTML tree construction/recovery remains deferred.
- The dependency includes P-384 certificate/handshake verification. See
  [HTTPS compatibility](foundation-readiness.md#https-compatibility) for upstream
  evidence and remaining limits.

## Validation

Validated on Linux x64 on October 15, 2026 against the dependency pin above:

- `env -u NO_COLOR ./wbuild -j 8 tests` in `w/`: **1,190 targets passed**,
  including bootstrap verification and the native JavaScript conformance gate
  (26 PASS, one tracked XFAIL for labelled-statement lowering).
- `./win/build test`: structured checks and strict compilation passed for the
  application and **11 W test programs**; all programs and both Python HTTP
  integration suites passed. This includes HTML character-reference integration,
  synchronous DOM/CSSOM/lifecycle behavior, shorthand mutation geometry, and the
  new intrinsic sizing/flex/overflow regressions. The legacy inline-style test
  now checks CSSOM property values instead of obsolete serialization spacing.
- `xvfb-run -a python3 win/tests/rendering.py win/bin/win`: native GL pixel
  assertions passed for percentage flex sizing/gaps, intrinsic input width,
  shorthand margin mutation, fixed-height sibling flow, and visible overflow.
  The screenshot was also visually inspected. The percentage-width assertion
  failed against the prior browser binary (100px instead of 200px).
- A separate live `win/bin/win --dump --page https://example.com/` smoke check
  successfully loaded Example Domain with certificate verification enabled.
  Public-site access is not required by the automated suites.

These results qualify the documented foundation on Linux x64, not general
website compatibility or complete standards conformance. W has no local source
edits; only its application submodule pin changed.

## Remaining work

Full flex/grid sizing and alignment, independent inline-block formatting contexts,
complete intrinsic/inline layout, and broader CSS remain deferred. CSSOM exposes
only the documented properties and methods, with no computed-style or stylesheet
rule API. Resource discovery is static: DOM changes do not start external
stylesheet/script/image fetches or execute inserted scripts.

W's runtime remains a language subset. Complete ECMAScript environments and
built-ins, asynchronous scheduling, timers, promises, modules, fetch/XHR, browser
storage, native DOM interfaces, accessibility, cookies/cache, and content-process
isolation remain future work. See the [CSS contract](css-compatibility.md) and
[JavaScript contract](javascript-compatibility.md) for the supported surface.
