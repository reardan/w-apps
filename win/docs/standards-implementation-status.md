# Standards implementation status

The W submodule pins [W #654](https://github.com/reardan/w/pull/654) commit
`b56052296f8add56a14a672828282ac7722dbc2e`, stacked on
[W #652](https://github.com/reardan/w/pull/652) head
`968950d8c1055cff0f6d9a5ea2463b18a6362c66`. Both PRs were open when this
integration was published. This replaces the previous base
`a5a54fd77eb049d7126db6ce7f1a68e823fa5aca` and retains #652's labelled
JavaScript, opt-in paragraph bidi, and wasm accessibility work.

The duplicate local label implementation was removed in favor of #652's
implementation. W #654 adds the Test262 adapter, immutable error
identity used by runtime-negative checks, and additional combined regressions.
The native ledger preserves all 31 #652 cases and adds five additional cases under
distinct names; the separate Test262 corpus remains pinned and
tracked by the repository ignore rules.
Win's CSS, flexbox, native rendering, and WPT work remain in the application.
The broader [standards implementation plan](standards-gap-analysis.md) remains
open; this is a bounded browser foundation, not full standards conformance.

## Implemented foundation

- CSS uses structured specificity/cascade keys and validates specified values
  before selecting winners. Fractional/exponent lengths and case-insensitive
  units are preserved, font-relative values resolve after the cascade, and
  supported properties implement inheritance/initial/unset behavior.
- W provides descriptor/prototype hooks, receiver-aware calls, synchronous host
  properties, typed runtime errors, completion handling, `var` environments,
  synchronous arrows, and `typeof`. Its parser and native execution ledger cover
  additional early errors and pinned cases. The PR supplies labelled blocks/loops
  that lower, print, and execute with targeted break/continue and finally propagation. A
  separate bounded Test262 adapter executes unmodified upstream tests using
  documented native assertion overrides; unsupported harness/language features
  stay visible.
- Win reads and writes supported DOM properties synchronously and exposes
  specified inline style reads plus CSSStyleDeclaration methods. Shorthand
  mutation accounts for supported longhands, and stylesheet text/tree mutations
  reconcile active sheet order. Window and Document are distinct event targets;
  callbacks preserve receivers. DOMContentLoaded follows the initial scripts,
  while load waits for the initial resource queue.
- Layout generates anonymous text items, skips hidden items, and measures
  intrinsic text, controls, and images. Row flex now supports explicit
  grow/shrink/basis and shorthand values, original-base free-space distribution,
  min/max freezing, horizontal auto margins, and six justify-content values.
  Percentage max-width resolves once against the container. Fixed
  block heights place following siblings correctly, while visible overflow
  contributes to page extent. Grid still uses equal tracks.
- W supplies the complete pinned HTML named-character-reference table and numeric
  repair rules. Browser regressions check decoded titles/text and preserved link
  attributes; complete HTML tree construction/recovery remains deferred.
- The dependency includes P-384 certificate/handshake verification. See
  [HTTPS compatibility](foundation-readiness.md#https-compatibility) for upstream
  evidence and remaining limits.

## Validation

Validated on Linux x64 on October 15, 2026 with this implementation:

- `env -u NO_COLOR ./wbuild -j 8 tests tests_wasm javascript_compatibility`
  plus targets selected by `./bin/wtest changed a5a54fd7..` in `w/`:
  **1,219 targets passed** in the combined run. This includes native and wasm
  bootstrap verification, the PR's paragraph bidi and web accessibility tests,
  the additional labelled runtime tests, and the Test262 adapter.
  The native JavaScript ledger is now **36 PASS, 0 XFAIL**
  (25 execution cases and 11 syntax negatives).
- `./win/build test`: structured checks, strict compilation, all **11 W test
  programs**, and both Python HTTP integration suites passed. Display-free WPT
  adapter contract tests also pass.
- The existing `javascript_compatibility` gate passed with pinned Node v20.19.3,
  including nine W/Node runtime comparisons, both consumer examples, and 188
  upstream grammar adaptation checks.
- Native GL pixel checks passed for the previous layout cases and new explicit
  1:3 flex growth and space-between positioning. The capture contract verifies
  successful content capture and rejects script errors, truncated output, and
  missing pages.
- The **12 pinned upstream WPT reftests all pass**, with zero failures,
  unsupported cases, or harness errors in this selected static slice. The
  nth-child specificity fixture exposed a default text color difference;
  changing the initial light-canvas text color to black resolved it. The RGB
  percentage fixture also exposed half-byte raster rounding differences; native
  paint now deterministically rounds RGB to its 8-bit output precision.
- The bounded Test262 profile reports **35 PASS, 18 UNSUPPORTED, 0 FAIL,
  0 ERROR** across 53 variants of 28 upstream tests. There are 26 execution
  passes and 156 executed assertions. Eleven adapter contract tests pass;
  reviewed per-variant expectations reject regressions from pass to unsupported.
  `--require-all` intentionally exits nonzero while any variant is unsupported.

These results qualify the documented implementation slices, not general website
compatibility or complete standards conformance. The W submodule pin captures
the complete dependency implementation, including the adapter and regression
additions in W #654.

## Reproducible standards commands

`./win/build standards` builds Win, executes the selected upstream Test262
variants in W, runs the rendering adapter's contract tests, and compares pinned
unmodified WPT test/reference pages using the native GL renderer. An X11 display
or `xvfb-run` is required. Network access is unnecessary during test execution.

- [WPT static rendering contract](../tests/wpt/README.md): 12 pinned color and
  selector reftests, an 800×600 content viewport, exact pixel comparisons,
  captured evidence, and explicit unsupported/error handling.
- [Test262 runtime contract](../../w/tests/javascript/test262/README.md): 28
  upstream files, 53 metadata-selected variants, native boolean/SameValue
  assertions, phase/type-checked negatives, and separate unsupported results.
- WPT screenshots and JSON are saved under `win/bin/wpt-results/`. Test262
  writes its full report to `w/bin/test262-conformance.json`.

These are selected conformance slices. They do not execute the whole WPT or
Test262 suites, and passing the regression gates does not mean every web
standard is implemented.

## Remaining work

Full flex/grid sizing and alignment (including column flex, wrapping, and
cross-axis alignment), independent inline-block formatting contexts,
complete intrinsic/inline layout, and broader CSS remain deferred. CSSOM exposes
only the documented properties and methods, with no computed-style or stylesheet
rule API. Resource discovery is static: DOM changes do not start external
stylesheet/script/image fetches or execute inserted scripts.

W's runtime remains a language subset. Complete ECMAScript environments and
built-ins, asynchronous scheduling, timers, promises, modules, fetch/XHR, browser
storage, native DOM interfaces, accessibility, cookies/cache, and content-process
isolation remain future work. See the [CSS contract](css-compatibility.md) and
[JavaScript contract](javascript-compatibility.md) for the supported surface.
