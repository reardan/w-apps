# Standards implementation status

The W dependency includes the bounded Promise/microtask runtime and standalone
module foundation from [W #657](https://github.com/reardan/w/pull/657), on top of
the merged [W #654](https://github.com/reardan/w/pull/654) Test262 foundation and
[W #652](https://github.com/reardan/w/pull/652) labelled JavaScript implementation.
The Git submodule pins merged commit
`343a124b22e1a39cd577e34e0b7ab13ee5191387`. This also includes the concurrent
[W #656](https://github.com/reardan/w/pull/656) wrapped-line bidi update.
All 27 W runtime PR checks passed before merge; the merged dependency is
validated again for browser integration.

Win's CSS, flexbox, native rendering, and WPT work remain in the application.
The earlier foundation and its validation are recorded below; the newer async,
network, storage and headless-isolation increment follows in its own section.
The broader [standards implementation plan](standards-gap-analysis.md) remains
open. These are bounded implementations, not full standards conformance.

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

## Next implementation increment

The browser now adds wrapped flex rows, column flow, cross-axis alignment and
stretch, with translated descendant geometry preserving links and anchors.
Column grow/shrink/basis and full grid sizing remain outside this increment.

W adds native `new Promise(executor)`, `Promise.resolve/reject`, `then/catch`, and
an explicitly drained, rooted FIFO microtask queue. A standalone
[module foundation](../../w/docs/projects/javascript_modules.md) parses, links
and evaluates acyclic static named imports and immutable exports with separate
strict environments, cached execution/failures and a host resolver. Browser
module graph loading is not yet connected. Win runs checkpoints at
script/event/timer boundaries and polls bounded timers in every live tab.
Origin-scoped memory storage survives navigation: local storage shares an app
owner, while session storage belongs to its tab. Same-origin GET `fetch` resolves
status-bearing response objects with single-use Promise-based `text()`; rejected
cross-origin redirects never make the foreign request.

Resource discovery now reconciles connected DOM mutations, cancels stale loads,
and preserves lifetime request/byte budgets. Dynamic classic scripts execute
once per node, including insertion after the initial load completes.
Cookies and explicitly fresh HTTP response cache entries live in bounded process
memory; their conservative supported policies are documented separately.

`--isolated-dump` moves complete headless page loading and execution into a fresh
child process. The parent validates bounded framed output and enforces a total
watchdog; cancellation also terminates loader descendants. Interactive tabs
retain their in-process interpreter. This is not an OS sandbox.

See the [CSS contract](css-compatibility.md), [JavaScript contract](javascript-compatibility.md),
[network contract](network-compatibility.md), and [process boundary](script-isolation.md).
The validation counts earlier in this file describe the preceding checkpoint.
Current increment validation:

- `env -u NO_COLOR ./wbuild -j 8 tests`: **1,205 targets passed** on current W main, including
  the module foundation, Promise runtime and compiler/toolchain regression gates.
- The pinned Test262 profile now reports **37 PASS, 16 UNSUPPORTED, 0 FAIL,
  0 ERROR**, with 28 execution passes and 164 assertions. Twelve adapter contract
  tests pass. Two short-circuit variants now execute successfully; explicit
  manifest capability requirements identify absent `eval`, `Number` and `isNaN`
  without downgrading unexpected ReferenceErrors or assertion failures.
- Focused native rendering checks pass after the layout additions.
- `./win/build test`: structured checks and strict compilation, all **14 W
  browser test programs**, all **five Python integration suites**, and eight
  display-free WPT adapter contract tests passed. The added suites cover Fetch
  allocation/settlement recovery, navigation/tab cancellation, origin boundaries,
  cookie/cache worker state, and isolated worker/descendant termination.
- `./win/build standards`: **12/12 pinned native WPT reftests passed**, with no
  failures, unsupported cases, harness errors or unexpected results. Capture
  readiness/error contracts and the Test262 profile above also passed.

## Remaining work

Complete flex/grid and inline formatting, column flex factors, reverse/wrapped
columns, baseline alignment and broader CSS remain deferred. CSSOM still lacks
computed-style and stylesheet rule APIs. Resource bases remain fixed after the
initial load, and parser-blocking/async/defer script scheduling is not modeled.

Complete ECMAScript and built-ins, generic thenable assimilation, async/await,
Promise combinators, browser module graph loading, XHR, full Fetch/CORS/streaming,
persistent storage/cache, storage events, complete cookie policies, native DOM
interfaces, accessibility, and interactive content-process isolation remain
future work. These increments are bounded implementations, not general modern
website compatibility or full standards conformance.
