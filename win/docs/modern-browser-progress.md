# Modern browser implementation progress

Implementation started 2026-10-15 from application
`75d4b4e4c7e081810e2dfc9e0d34b4051596e2ed` after pulling `origin/main`.
The original W gitlink is `d8aa1039087c5c940908531a9f4a58bbebfaf00a`.
The initial work used `codex/win-modern-browser-implementation`, with dependency
commits on W's `codex/modern-browser-integration`. Those branches are preserved;
the local main merge is recorded below. Remote publication has not occurred. The [roadmap](modern-browser-plan.md) also tracks remaining platform work;
this implementation is bounded app support, not full browser conformance.

## Mutable query parameters (2026-10-19)

This application-only increment starts from `cf0be72ea835971ead89a753f170670aa3b05786`
and retains W `79b5378f553db17303efdecc1506156891757260`. It replaces the
string/get-only URLSearchParams shim with native parameter lists: string, copy,
pair-array and plain-record construction; `size`, `get`, `getAll`, `has`,
`append`, `set`, `delete`, `sort`, `toString`, and `forEach`. Query-driven routing
and Fetch now work with duplicate filters, UTF-8 form encoding and live callbacks
in native, isolated dump, and isolated interactive execution.

Focused regressions cover duplicate ordering, optional value filters, malformed
UTF-8, embedded NUL, surrogate replacement, stable UTF-16 sorting, borrowed-method
receiver checks, conversion side effects, async callback retention/cancellation,
GC, failed-constructor cleanup, and atomic quota/fuel refusals. A separate native
ownership test passes with `W_DEBUG_ALLOC=1` and zero reported leaks. The larger
script test exhausted this host's VMA quota under the guard allocator; that run
is not passing memory-safety evidence. Its ordinary allocator run passes.

Nine portable semantic groups also pass in Chromium 145.0.7632.6. The comparison
caught the legacy null-constructor mismatch: null now becomes `"null"`, while
omitted/undefined initialization stays empty. Node 20's null and mutable-pair
constructor behavior differs, so Chromium is the recorded differential reference.
These are authored regressions, not new imported WPT cases or a conformance
percentage. The [JavaScript contract](javascript-compatibility.md) records exact
bounds and the remaining `URL`, Symbol, general iterable and iterator-object gaps.

Validation logs are under `win/bin/search-params-*.log`, with the reference page
in `win/bin/search-params-reference.html`. `search-params-validation.json` records
the tested working-tree source SHA-256 hashes against the baseline commits above;
the copied Test262/WPT reports preserve the selected gate results.

| Gate | Result |
| --- | --- |
| Full Win suite, Node 20.19.3 and dedicated Xvfb | Passed: 62 native test programs and all integrations/application/rendering acceptance |
| Query routing + Fetch workflow | Passed in native, isolated dump and isolated interactive modes |
| Focused native ownership under guard allocator | Passed, zero reported leaks |
| Chromium 145.0.7632.6 differential | Nine authored semantic groups passed |
| Selected Test262 gate | 110 PASS / 35 explicit UNSUPPORTED / zero FAIL or ERROR |
| Native WPT rendering | 20 PASS / zero FAIL, UNSUPPORTED or ERROR |

Reproduce the integrated gates with Node 20.19.3 on PATH:
`xvfb-run -a ./win/build test` and `xvfb-run -a ./win/build standards`.
The focused ownership command after building tests is
`W_DEBUG_ALLOC=1 win/bin/search_params_ownership_test`.
W sources and the dependency gitlink are unchanged; the W full suite was not
rerun for this application-only increment.

An initial full-suite run stopped at the existing interactive-worker crash test:
its process-exit/socket-EOF race reported disconnected status 4 instead of exited
status 3. Its focused rerun passed. The compiler dependency report confirms that
this transport test imports neither changed browser source; no assertion or
transport behavior was changed. The initial failure log is retained separately.

## Merge to main (2026-10-19)

Both repositories are now on local `main`. The app was fast-forwarded through
`d66f71d`, then updated to the merged W dependency in application implementation
`37765b5b77a46e34d4112f4a876b21f3849e3729`. W merge
`79b5378f553db17303efdecc1506156891757260` combines fetched upstream main
`8382c5f2` with browser feature head `b4b18edc`. Runtime/module documentation and
conflicts were reconciled while preserving upstream compiler/UI work and the
validated browser semantics. No remote push was performed.

The newer upstream compiler and UI were rebuilt and tested with Node 20.19.3:

| Gate | Merged-revision result |
| --- | --- |
| W full suite | 1,606 targets passed |
| Full Win suite | Passed, including native/isolated mobile, sandboxed HTTP, Preact/storage and exact rendering checks |
| Test262 | 110 PASS / 35 explicit UNSUPPORTED / zero FAIL or ERROR |
| Native WPT | 20 PASS / zero FAIL, UNSUPPORTED or ERROR |

Win and standards ran in a separate clean checkout of the exact application/W
commits while the W suite ran in the primary checkout; the primary browser
binary was rebuilt afterward. The mobile wasm was regenerated from upstream's
updated UI and host sources (SHA-256
`a2d52af44dc39e3f9c3d0538ee69561a9d4d8b91a6bbe90b43ce62c4f6462c1d`).
The earlier benchmark below remains evidence for its recorded source revisions,
not a new performance measurement of this merge.

Logs and copied acceptance reports are under `win/bin/merge-main/`:
`final-w.log`, `final-win.log`, `final-standards.log`, `final-build.log`,
`validation.json`, `broker-acceptance.json`, `mobile-native.json`,
`test262-report.json`, and `wpt-report.json`. Subsequent changes only record
validation; the implementation revisions above identify the tested sources.

## Browser gap expansion (2026-10-19)

The follow-up starts from application `4b3543f` and W
`3d1e5ce46d6e5dff5760fc6a533381680f93f49d`, on local branches
`codex/browser-gap-expansion` in both repositories. Parallel implementation and
cross-review added these bounded capabilities without changing the mobile host,
wasm application sources, or pinned Preact artifact:

- JavaScript: generic `every`, `forEach`, `map`, `filter`, `find`, `findIndex`,
  `findLast`, `findLastIndex`, `reduce`, and `reduceRight`, including live property
  lookup, sparse/mutated receivers, callback exceptions, shared budgets and
  async callback lifetime. Species and the remaining general language gaps are
  still outside this subset.
- CSS: inherited `pointer-events: auto/none`, native-control hit ownership,
  inline/computed CSSOM properties, and `row-reverse`/`column-reverse` main-axis
  placement. Reverse flow changes visual placement, preserving document order.
- Images: bounded GIF87a/GIF89a first-image decoding with LZW, palettes,
  interlacing, offsets and transparency. Animated GIFs display their first frame.
- Keyboard access: Tab/Shift-Tab in tabindex order, programmatic negative
  tabindex focus, hidden/disabled filtering, visible focus rings and cancelable
  Enter activation for links in native and isolated content. This does not add
  an accessibility tree, screen-reader integration, full IME, iframe/shadow
  focus navigation or radio-group roving focus.
- Isolation: explicit [same-origin HTTP brokerage](network-broker.md) through
  trusted parent-owned helpers while content retains its Landlock/seccomp
  restrictions. Bounds, origin checks before cache and every redirect, async
  cancellation, stalled-reader watchdogs and worker lifetime identity are tested.
  The original offline profile and opt-in default remain unchanged.
- Performance: wasm dispatch avoids repeated instruction/local container access
  and prioritizes common operations, preserving exact fuel and traps. Three
  alternating pairs with the unchanged mobile wasm measured median steady-frame
  CPU time of **78.6 ms → 58.3 ms (26% lower)**. Deterministic host stubs exclude
  browser/GL work; these are not end-to-end frame timings. The
  [raw measurements](browser-gap-performance.json) preserve fuel, memory digest
  and host-call counts alongside timing samples.

The pinned Test262 selection grows from 58 to 74 unmodified upstream files:
145 variants, **110 PASS / 35 explicit UNSUPPORTED / zero FAIL or ERROR**.
The added neighbors retain explicit unsupported classifications for array
literal elisions, sloppy mapped arguments and `delete`; no existing expected
PASS was relaxed. Native WPT continues to use the original 20 pinned reftests.

The final combined implementation is application
`72827e12e945f54b74d5782f3523dc37603a2922` with W
`b4b18edc5d0dfeee34f0e102099f89f20985c3f7`. Subsequent changes only record this
validation. All three commands below completed successfully with Node 20.19.3:

| Gate | Result |
| --- | --- |
| `(cd w && env -u NO_COLOR ./wbuild -j 4 tests)` | 1,240 targets passed |
| `xvfb-run -a ./win/build test` | Passed, including broker M2/M3 and existing offline kernel/GL checks |
| `xvfb-run -a ./win/build standards` | Test262 110 PASS / 35 explicit UNSUPPORTED; WPT 20 PASS; zero FAIL/ERROR |

The full browser run includes 8 exact GIF worker comparisons, 4 GIF/PNG native
render comparisons, 6 reverse-flex/pointer-events render comparisons, and native
plus isolated focus-ring pixels. The real ABI-8 sandbox run passes unchanged
M2 input/resize and M3 success/failure/abort/history/theme/reload workflows,
including durable parent storage outside the empty content root and origin
separation. The broker's malformed-protocol, foreign/local URL, cancellation and
stalled-reader helper-reaping regressions also pass. The W suite includes normal
array cases plus all 11 guarded allocator groups and exact wasm fuel/trap checks.

Logs and machine-readable command results are under `win/bin/browser-gaps/`:
`final-w.log`, `final-win.log`, `final-standards.log`, and `validation.json`.
Broker screenshots and its acceptance report are under
`win/bin/broker-validation/`; WPT captures/report remain in `win/bin/wpt-results/`.
These generated artifacts are intentionally untracked. Build scripts now include
broker app acceptance and the new render comparisons; ABI-dependent broker
acceptance reports a skip on older kernels rather than relaxing the production
sandbox requirements. All tests ran without that skip on this host.

Full ECMAScript/CSS conformance, SVG/WebP/progressive JPEG/GIF animation,
audio/video, platform accessibility and IME, and general Internet/CORS/cookie/
cache behavior remain roadmap work. The broker retains the documented X11/GPU
and parent-parser authority; it is not complete desktop isolation.

## Original M1–M4 validated checkpoint

The initial M1–M4 application milestones pass under the documented bounds.
Isolation remains opt-in. M5 expands independently scoped upstream coverage;
the broader platform roadmap remains open.

| Gate | Final result |
| --- | --- |
| W full suite, Node 20.19.3 | 1,236 targets passed |
| Win full suite, dedicated Xvfb | Passed, including unchanged native/isolated apps |
| Pinned Test262 | 90 PASS, 23 explicit UNSUPPORTED, zero FAIL/ERROR |
| Pinned native WPT | 20 PASS, zero FAIL/UNSUPPORTED/ERROR |
| M3 native/isolated screenshots | Pixel-identical at both 800×600 and 360×640 |

Run `(cd w && env -u NO_COLOR ./wbuild -j 4 tests)`,
`xvfb-run -a ./win/build test`, and `xvfb-run -a ./win/build standards` with
Node 20.19.3 on PATH. Optional Chromium reference runs use the separately pinned
Playwright environment; ordinary acceptance needs no third-party Python packages.
All original `w/tools/web/` and `w/graphics/` sources remain unchanged from the
starting W gitlink. The production Preact artifact is unmodified.

Final M1 native measurements were 2.03–2.35 seconds to first frame, 9–10 ms maximum
frame callbacks, five descriptors after navigation and zero extra W blocks after
warm teardown. The isolated run painted 36 changing frames across three workers,
with resize/crash/partial-cancellation checks, 1.84-second first frame, 3 ms maximum
parent poll and 9 ms maximum paint. These are local samples, not latency guarantees.
The M2 200-million-step opt-in budget, platform input/IME gaps, visual differences,
and offline-only sandbox authority are detailed below.

## Reproducible application targets

- M1: `w/tools/web/index.html?module=/w/bin/graphics_demo.wasm`, served from the
  application repository root. Build with `(cd w && bin/wv2 wasm
  graphics/demo_web.w -o bin/graphics_demo.wasm)`.
- M2: the **same unchanged HTML host**, with
  `?module=/w/bin/graphics_ui_mobile.wasm`. Its exact source is
  `w/graphics/ui/mobile_demo_web.w`; build with
  `(cd w && ./wbuild graphics_ui_mobile_web)`. Do not use a guessed `ui/` entry.
- M3: [workflow fixture](../fixtures/workflow/README.md), using the unmodified
  production Preact 10.27.2 ES module and upstream MIT license. Its recipe pins
  the published tarball SHA-256. `python3 win/tests/workflow_server.py` serves the
  local API and app; the README defines success/failure/abort, routing, restart
  persistence, origin separation and responsive acceptance steps.
- M4: M1 now renders through isolated worker canvas frames. M2 raw input is
  integrated, with portable input, focus/selection metadata and bounded queues.
  Parent-owned local/session storage and the full isolated workflow pass, including
  [same-document History](isolated-history.md). The opt-in [offline Linux sandbox](offline-sandbox.md)
  passes local-content enforcement and GL tests; HTTP apps are outside that profile.

Run `python3 win/tests/modern_hosts.py` for machine-readable startup probes of
the unchanged graphics/mobile hosts and the Preact workflow. `--record` records failures without a
nonzero command exit. Reports go to `win/bin/modern-browser/`; a startup pass
alone does **not** establish sustained rendering, interaction, resize, teardown,
performance or full milestone acceptance. `--report FILE.json` on ordinary
Win graphical/dump runs records script/resource errors and the final title.

The original compatibility fixture's screenshot test only checked colorful
pixels. The new native probe caught a first-frame ReferenceError from missing
`String(frames)` after the triangle had already drawn. Primitive `String()` is
now available and the graphics integration also requires zero script/resource
failures and title `W wasm frame 3`. Original-host parsing initially failed with
`await outside async function (ES2020)` at the two top-level awaits. Module
loader errors now preserve the source identifier, line, column and diagnostic.

## Ownership and contracts

The coordinator owns integration, browser/app/main/build, dependency gitlink,
acceptance fixtures and status. Track A owns W JavaScript; B owns host DOM and
Fetch; C owns CSS/style/document/layout. D's initial streaming-validation slice
was performed by the coordinator while all three agent slots were occupied.
Each track uses a separate worktree and generated-output directory.

- Async execution: bounded suspended task records, GC-owned roots, completion
  and total-fuel state, Promise resume jobs and cancellation that unwinds native
  temporaries before releasing stacks. No synchronous wait implementation.
  Async module records expose an evaluation Promise and cached failure;
  browser lifecycle waits for settlement. Native HTTP integration covers a timer,
  awaited Fetch/text, dependency order, delayed DOM readiness and rejection with
  continued later scripts. There are at most 32 suspended tasks, 8 MiB of stacks,
  and 1,000,000 conservative retained root identities. Promise resolution
  assimilates thenables, and `finally` waits for cleanup before preserving the
  original result.
- DOM: stable wrappers survive detachment. Synthetic dispatch reuses the native
  listener algorithm with reentrant calls, preserved event identity, local
  listener exception reporting and an outermost microtask checkpoint. A bounded
  runtime callback-compilation API owns parsed inline handlers across GC.
- Storage: one explicit local owner per app, tab-local session owners. Optional
  `--storage FILE` opens a versioned bounded record under a lifetime advisory
  lock. Mutations use a mode-0600 temporary sibling, file sync, rename and
  directory sync. Failures before publication restore the previous in-memory
  contents; post-rename barrier failures preserve the new contents and report
  `UnknownError`. Isolated interactive execution now routes bounded synchronous storage operations
  to the parent owner. Durable writes run in a trusted helper while the parent
  polls; uncertain publication is reconciled from disk or poisons the store.
  See [isolated storage](isolated-storage.md) for identity, quota, recovery and
  cross-origin navigation restrictions. No disk state is opened without the option.
- Streaming wasm: only native same-origin Fetch responses are accepted; final
  HTTP status must be successful and Content-Type must be exactly
  `application/wasm` (ASCII case-insensitive, outer HTTP whitespace ignored,
  **no parameters**). Metadata survives cache hits, body consumption is native
  and single-use, and user-assigned response fields cannot bypass validation.
  Compilation remains buffered. Binary cache copies preserve embedded NULs.
- Layout: custom properties inherit computed token values, include fallback
  edges in cycle detection and preserve invalid-at-computed-value semantics.
  Flexible allocation is shared between row and column axes; final heights
  reach nested descendants before paint/hit geometry is produced. Reference
  renders compare native pixels with equivalent explicit CSS.
- Frame IPC: `WINT0001` retains the legacy HTML message and adds an atomic
  snapshot/canvas manifest. WFRM v1 transports bounded RGBA8 surfaces with
  generation/sequence validation and matching acknowledgments. Parent polling
  moves at most 64 KiB in either direction and presents completed generations
  without a parent script realm. Integrated acceptance passed 36 painted frames
  with 36 pixel changes, resize, three worker lifetimes, crash/reap, partial
  cancellation and descriptor cleanup. See [the protocol](isolated-graphics.md).
  Raw pointer/key forwarding and parent-owned shared storage are integrated.
  The offline sandbox is now integrated, retaining the documented desktop/GPU
  authority and rejecting network access.

## Initial evidence and toolchain

The initial full W suite passed **1,210 targets**; the initial full Win suite
passed all discovered native tests and Python integrations, including real
wasm/WebGL pixels. These are baseline regressions, not conformance percentages. An integrated
checkpoint with classes, BigInt, JSON, async/TLA and configurable wasm limits
passed all **1,216 W targets** plus the complete Win test suite. Later Promise,
RegExp, combinator, network and parseFloat slices passed an integrated
**1,222-target W suite**. An initial run under high concurrent load classified
the fuzz fixture's expected crash as a timeout; rerunning the complete suite
with `-j 4` passed. The latest Win integration run is tracked below.
Python is 3.12.3, system Node is 22.23.2, Git is 2.43.0, and the W bootstrap seed
is v0.3.0 as pinned in `w/SEEDS`. The explicit JavaScript compatibility gate uses
Node 20.19.3, downloaded separately with the official SHASUMS256 checksum.

The M3 reference scenario passed in Chromium **145.0.7632.6** through Playwright
**1.58.0**, including browser restart and a second origin. Reproduce with
`python win/tests/workflow_reference.py` in an environment containing that
Playwright release and Chromium. It writes two viewport screenshots and a JSON
report. This establishes the fixture's behavior in the reference engine only.
`modern_hosts_reference.py` also passes against the same reference version;
its M2 typed-input screenshot was visually inspected and displays `Ada` in the
Name field. The hidden textarea is a resettable sentinel sink, so its DOM value
is not used as a false assertion of the wasm UI's text state.

Focused tests accompany each implemented slice. Native custom-property and
column-flex reference renders passed, along with the existing 12 selected WPT
reftests. W debug allocator tests may exhaust the environment's 262,144 VMA cap;
a passwordless attempt to raise the cap was unavailable. Such runs are reported
as unavailable evidence, not passes or permission to weaken assertions. The
Win async lifecycle guard-allocator run exhausted that cap even with its pending
module teardown case isolated; the normal test passes. W's narrower suspended-
frame and thenable lifetime tests complete with zero reported leaks.

## Application acceptance and limits

M1's unchanged graphics path passes native startup, sustained frame changes,
resize and repeated navigation. `modern_graphics_integration.py` records exact
host source hashes, live W allocation deltas, open descriptors, RSS, first-frame
latency, maximum poll/callback durations and native window paint. This runs under
a dedicated Xvfb display to avoid interference from other desktop sessions.
The initial three-cycle run took 2.8–3.5 seconds to first frame under concurrent
build load, with 9–30 ms maximum frame callbacks and 1.4–1.6 second maximum polls.
These are measured baselines, not an assertion of responsive startup. A later
dedicated-Xvfb run on W `6b105463` passed all three 60-frame cycles, resize,
29,005 colored window pixels and stable five descriptors. Warm teardown retained
zero additional W blocks, with byte deltas −1,336/+80. Under concurrent unrelated
compiler/VM load, first frames took 11.8–14.3 seconds and maximum polls 5.3–6.5
seconds; a shared-display attempt timed out before 60 frames. These runs do not
isolate runtime performance from host contention. RSS alone
is not a leak detector: the production allocator and GL driver may retain pages.

M2 reaches startup, but its bundled font decoding and first glyph rasterization
consume far more than the default one-million-step execution budget. Isolated
profiling measured 100,437,402 shared instructions for `_start`, 121,537,963 for
the first frame, and 3,874,919 for subsequent frames. On this host, pinned-thread
CPU measurements are roughly 2.3 seconds, 2.6 seconds and 93 ms respectively.
`--execution-budget 200000000` is an explicit bounded experiment; the default
remains unchanged. Mouse pointer/capture and native focus/UTF-16 selection now have focused tests.
Integrated native input acceptance now passes pointer focus, KEY/CHAR and
CHAR-only Unicode edits (Nativeé🙂), rendered wasm-field changes, sink reset and
Backspace. Reproduce with `xvfb-run -a python3 win/tests/mobile_native_acceptance.py`.
The expanded scenario also passes resize from 390×720 to 360×360, wheel
scrolling inside wasm (61,082 changed canvas pixels without outer scrolling),
and 30 further frames. `mobile_native_reference.py` repeats this input/resize
sequence in Chromium 145.0.7632.6. Edited and narrow screenshots were visually
compared: field text and geometry match, including the application’s stretched
typography and right-edge field cropping. Pixel comparison found no channel
difference above 16 in either 360×360 capture; 151 of 280,800 pixels exceeded
that threshold in the edited 390×720 capture. Fixed positioning is now implemented and the same test also captures the actual
parent viewport, asserting zero outer scroll. Visually inspected parent captures
match the canvas origin and responsive size. They retain differences around text and rounded edges:
4,692/280,800 edited pixels and 1,952/129,600 narrow pixels exceed channel delta 16;
opacity and pointer-events remain unsupported. This is bounded app evidence,
not full CSS fidelity. Native screenshots and source hashes
are recorded under `win/bin/modern-browser/mobile-native/`.
The driver uses portable native event records, not synthetic JavaScript events;
platform key translation and complete IME behavior remain separate gaps. Author body margins now control the page origin
and root/body backgrounds cover the viewport; see [root layout](root-layout.md). No host or bridge is rewritten.

M3's pinned Preact now lowers and links unchanged after bounded for-in, abstract
equality, property presence, mutable live exports, and Array constructor/isArray
support. Ordinary function construction, shared call/apply/bind, unmapped
arguments, generic array-like slice and Unicode String casing now pass focused
tests. The unchanged framework evaluates and creates virtual nodes; generic
Array.some, addition and bitwise numeric conversion, and iterative logical/comma/
conditional/binary evaluation and statement tails have since landed. The complete
native scenario now passes success, HTTP 503, abort without late success, theme,
routing/back/forward, restart persistence and origin separation under unchanged
execution limits. Live HTML DOM tree APIs and
side-effect-free native property presence have also landed.
History push/replace/traversal and bounded JSON-tree state pass native and worker
HTTP tests. Native controls now honor CSS theme colors; both viewport captures contain
10,973 exact green accent pixels. Native font metrics/control geometry remain
visibly different from Chromium. M4 passes the same workflow at both sizes,
including the same worker/realm, `Cancelled` result and `slow` name across live
Back/Forward. Native and isolated workflow screenshots are pixel-identical at
800×600 and 360×640. Retired-worker traversal reloads the URL without restoring
transient history state; a sandboxed HTTP resource broker remains outside the
offline sandbox profile. M5 remains measured feature-family
work; the current selected Test262 gate has 90 PASS/23 explicit UNSUPPORTED variants from 58 pinned files (zero failures/errors).
The pinned WPT corpus now adds eight unchanged CSS Variables cases: all 20 native
reftests pass with exact reference pixels. This run also exposed and fixed sibling
margin collapse; no prior expected PASS was weakened.

The complete roadmap's remaining language, CSS/layout, networking, cookie/CORS,
cache, wasm/WebGL, worker, accessibility, media and platform items remain tracked
in the plan; none is considered implemented merely because a related local test
passes.

The actual M2 wasm is 1,703,097 bytes and decodes to 689,360 instructions. The
reusable wasm loader now accepts explicit source/instruction budgets; its default
1 MiB/524,288 limits remain. Win selects 4 MiB/1,048,576 and retains its aggregate
source/memory limits. Fetch accepts up to 4 MiB so the unmodified binary reaches
the loader; other resource classes keep their existing limits.

The final W dependency is `3d1e5ce46d6e5dff5760fc6a533381680f93f49d`.
Its full `env -u NO_COLOR ./wbuild -j 4 tests` run with Node 20.19.3 passed
**1,236 targets** (log: `win/bin/modern-browser/final-w-exact.log`). The final
feature-selected run separately passed 57 targets including dependencies, with
no allocator warnings. Focus, CSS root/fixed layout, DOM tree APIs, native
presence, ordered keyboard/composition, isolated input, parent storage and
offline confinement are integrated. Terminal listener failure preserves already
requested event cancellation (`92adfe2`). The final full Win and standards suites
passed on application implementation `442d6a2eadcca00e599a8e63f5dd7650e6c88348`
and that exact W dependency; later changes only reconcile documentation.
Logs are `win/bin/modern-browser/final-win-exact.log` and
`win/bin/modern-browser/final-standards-exact.log`. The full run includes native
and isolated M1–M3, shared storage, ordered History/input, offline sandbox,
malformed messages, quotas, cancellation and crash/reap tests. An initial final
run exposed reload-before-first-history-entry; its central correction has a
normal/guarded regression and passes the complete rerun. The bounded History
quota guard run exceeded allocator bookkeeping capacity and remains unavailable;
normal quota tests and guarded wire/cancellation tests pass.

The offline sandbox checkpoint `ce005ce` passes integrated kernel/TSYNC tests,
failed-readback zeroing and dedicated-Xvfb local GL/resource acceptance. The
parent paints 16,384 blue canvas pixels and 547,744 green CSS pixels; the two
intentional forbidden stylesheets fail, and the negative network listener sees
no connection. See its contract for retained authority and unsupported kernels.
