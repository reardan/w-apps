# Modern browser implementation progress

Implementation started 2026-10-15 from application
`75d4b4e4c7e081810e2dfc9e0d34b4051596e2ed` after pulling `origin/main`.
The original W gitlink is `d8aa1039087c5c940908531a9f4a58bbebfaf00a`.
Work is on `codex/win-modern-browser-implementation`, with dependency commits on
W's `codex/modern-browser-integration`. These are local implementation branches;
publication/merge has not occurred. The [roadmap](modern-browser-plan.md) remains
an outstanding implementation program, not a support claim.

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
  integrated, with portable input, focus/selection metadata and bounded queues. Shared-state parity
  remains outstanding. The opt-in [offline Linux sandbox](offline-sandbox.md)
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
  `UnknownError`. Isolated execution explicitly refuses this option until a
  shared owner/service exists. No disk state is opened without the option.
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
  Raw pointer/key forwarding is integrated; shared storage is still underway.
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

## Remaining integration gates

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
that threshold in the edited 390×720 capture. This canvas comparison does not
establish full page CSS fidelity: fixed positioning remains unsupported. Native screenshots and source hashes
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
conditional evaluation have since landed. Native input now reaches API success,
HTTP 503 failure and abort with no late success. The next measured failure is
expression depth while navigating to the settings view; limits remain unchanged. Live HTML DOM tree APIs and
side-effect-free native property presence have also landed.
History push/replace/traversal and bounded JSON-tree state pass native and worker
HTTP tests. The complete native API/interaction/persistence scenario does not
pass yet. M4 still lacks shared-state/workflow parity and a sandboxed
HTTP resource broker. M5 remains measured feature-family
work; the current selected Test262 gate has 43 PASS/10 UNSUPPORTED variants.

The complete roadmap's remaining language, CSS/layout, networking, cookie/CORS,
cache, wasm/WebGL, worker, accessibility, media and platform items remain tracked
in the plan; none is considered implemented merely because a related local test
passes.

The actual M2 wasm is 1,703,097 bytes and decodes to 689,360 instructions. The
reusable wasm loader now accepts explicit source/instruction budgets; its default
1 MiB/524,288 limits remain. Win selects 4 MiB/1,048,576 and retains its aggregate
source/memory limits. Fetch accepts up to 4 MiB so the unmodified binary reaches
the loader; other resource classes keep their existing limits.

The current dependency checkpoint is `a9ba1c95`; focus, CSS root layout, DOM
tree APIs, native presence, ordered keyboard/composition, isolated input and
offline confinement are integrated. Terminal listener failure now preserves
already requested event cancellation (`92adfe2`). Feature-selected W tests and
focused Win tests pass; a new full exact-revision suite is still required after
the remaining runtime/DOM/input integrations.

The offline sandbox checkpoint `ce005ce` passes integrated kernel/TSYNC tests,
failed-readback zeroing and dedicated-Xvfb local GL/resource acceptance. The
parent paints 16,384 blue canvas pixels and 547,744 green CSS pixels; the two
intentional forbidden stylesheets fail, and the negative network listener sees
no connection. See its contract for retained authority and unsupported kernels.
