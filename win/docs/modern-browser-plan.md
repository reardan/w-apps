# Modern browser implementation plan

Status: planned, not implemented. Written 2026-10-15 after W #662 and w-apps #7 merged.
This document is the handoff for a fresh implementation session. It supersedes the
execution order in the older standards gap analysis, whose findings describe an
older baseline. The compatibility documents remain the source of truth for shipped
behavior. Do not interpret the roadmap as a support claim.

## Goal and acceptance milestones

Make Win capable of running our existing web applications unchanged, then expand
measured standards compatibility. Preserve the native W engine and reusable W
libraries; Win owns browser integration. Do not substitute another browser engine.

1. **M1 — original graphics host:** serve the repository locally and open
   `w/tools/web/index.html` unchanged. Compile the existing W graphics demo, load
   its existing bridge, and verify startup, sustained animation, resize, and clean
   navigation/teardown. No compatibility-only rewritten host or patched bridge.
2. **M2 — mobile UI host:** run the existing W mobile UI web demo unchanged with
   keyboard/pointer input, text editing, focus, scrolling, viewport resizing, and
   sustained rendering. Discover and record its exact entry point at the pinned W
   revision before assigning implementation. Compare representative screenshots
   and input-driven state transitions with a reference browser.
3. **M3 — application workflow:** a checked-in representative app must support
   module loading, routing/back/forward, form submission to a local API, persisted
   settings across browser restart, and responsive layouts. Include an unmodified
   production bundle from a pinned framework with its license and build recipe;
   select the smallest representative bundle during baseline work and record it.
4. **M4 — isolated application workflow:** M1–M3 also work through isolated page
   execution, including canvas presentation, responsive parent UI, crash recovery,
   and teardown. Only then consider making isolation the default.
5. **M5 — broader interoperability:** expand pinned Test262, WPT, wasm spec, and
   WebGL conformance coverage by feature family. No percentage of “modern browser
   support” may be inferred from local regression counts.

M1–M4 are sequential integration gates, not promises that all standards will be
complete. Work independent of an earlier gate can proceed in parallel. Every
remaining roadmap item below stays tracked if it is not needed for these apps.

## Baseline and restart procedure

The application baseline is merged w-apps commit `08a6ed8` (PR #7). Its W gitlink
contains the tested runtime implementation from PR #662. Read the gitlink rather
than replacing it with the latest W main: subsequent W changes may change the
hosts, demos, or toolchain independently.

At the start of implementation:

1. Read this plan, repository instructions (including `w/AGENTS.md`), and
   `web-app-compatibility.md`, `javascript-compatibility.md`,
   `css-compatibility.md`, `network-compatibility.md`, and `script-isolation.md`.
2. Inspect status and preserve unrelated edits. Create an integration branch from
   the intended application baseline and initialize W at its gitlink. Record both
   full SHAs and tool versions in an implementation progress note.
3. Reproduce the existing Promise-host wasm fixture and capture actual failures
   from the unchanged original host and mobile demo. Turn the first failures into
   focused regression cases before changing runtime semantics.
4. Inventory scripts/imports and required browser APIs for both demos and the M3
   bundle. Record requirements, ownership, dependent work, and expected failures.
5. Record current test reports. Existing evidence is 1,210 W regression targets,
   41 PASS/12 UNSUPPORTED Test262 variants, 23 browser W test programs, eight Python
   integration suites, and 12 passing selected WPT reftests. These are historical
   counts, not required future totals or full-conformance claims.

Useful baseline commands, run from the application checkout:

```sh
git status --short
git rev-parse HEAD
git ls-tree HEAD w
git -C w rev-parse HEAD
./win/build test
xvfb-run -a python3 win/tests/wpt_reftests.py
python3 win/tests/wasm_graphics_integration.py win/bin/win
(cd w && env -u NO_COLOR ./wbuild tests)
```

## Parallel-subagent operating model

Use one coordinator plus up to four implementing subagents. If fewer slots are
available, queue the same tasks without overlapping file ownership. Each agent
gets a separate worktree and generated output directories, a precise base SHA,
exclusive paths, interface contracts, exit tests, and explicit exclusions. Never
share mutable `bin/` directories or ask agents to edit the same runtime monolith.

| Track | Exclusive implementation area | Responsibilities |
| --- | --- | --- |
| A: language/runtime | W `libs/extras/javascript/`, JS tests/docs | Language semantics, builtins, async execution, module linking; compiler/grammar edits only when justified and assigned |
| B: browser APIs | Win module/fetch/web-host bindings and new DOM/network modules; their tests | DOM, events, lifecycle, network, navigation, persistence |
| C: CSS/layout | Win style/document/layout modules, CSS tests; assigned W CSS modules if needed | Values, intrinsic sizing, flex/grid, positioning, painting/hit testing |
| D: graphics/isolation | W wasm library/tests; Win wasm/canvas/interactive-worker modules and tests | Wasm compatibility, WebGL/Canvas, frame transport, process lifecycle |

The coordinator exclusively owns shared integration files initially:
`win/src/win/script.w`, `browser.w`, `app.w`, `main.w`, build/test registration,
compatibility status, and the W gitlink. Track C owns `document.w`; DOM changes
requiring it must go through a coordinated patch or a later explicit ownership
transfer. Track B and D must agree transport interfaces before editing loaders or
worker protocols. Assign any additional touched file explicitly before work.

Agents should return commits, interface notes, executed checks, and known gaps.
Integrate W changes first into a common W integration branch, then test Win against
that exact SHA. Independent W worktrees must receive required runtime commits
before compiling dependent host code. Do not silently broaden scopes or let one
agent fix another agent's failures in its owned files.

## Wave 0 — contracts and executable targets

Coordinator owns the baseline inventory and M1–M3 acceptance fixtures. Agents
inspect their tracks in parallel and contribute minimal failing tests and interface
proposals. Read current primary specifications where behavior is uncertain.

Agree and document these contracts before dependent implementation:

- JS suspended-frame rooting, completion/error propagation, execution budget and
  cancellation; Promise jobs and host task/microtask checkpoint boundaries.
- Module record lifecycle: fetch, parse, link, evaluate, async dependencies,
  namespace/live bindings, cycles, failure caching and navigation cancellation.
- DOM identity/prototypes, property descriptors, event constructors and task queues.
- Fetch request/response ownership, header representation, byte streams, abort,
  redirects, credentials and origin checks; shared network/storage ownership.
- Layout invalidation, style dependencies, scroll/clip/transform coordinate spaces,
  and consistency between geometry, painting and hit testing.
- Frame IPC version, generation IDs, pixel format/stride, bounded sizes, ownership,
  acknowledgement/backpressure, resize and page teardown.

Exit: each milestone has a reproducible command, machine-readable assertions,
known failures, and an assigned owner. Avoid a long architectural rewrite before
one failing application path becomes executable.

## Wave 1 — unchanged original host (M1)

**A:** Implement the exact class/prototype/constructor semantics exercised by the
host, complete required BigInt arithmetic without precision-losing Number
conversion, async functions/await, and top-level await. Build reusable semantics,
not special cases keyed to demo source. Add correct Promise thenable assimilation
and required combinators/finalization. Root suspended frames and jobs across GC;
cover throw/rejection/finally and navigation cancellation. Extend module records
for live mutable exports, cycles, dynamic import and asynchronous evaluation in
reviewable increments; prioritize the dependency subset demonstrated by M1.

**B:** Connect async module evaluation to browser lifecycle and failure reporting;
add the host interfaces revealed by inventory, complete URL/URLSearchParams paths
needed by the host, and establish synthetic Event/dispatchEvent and abort signal
foundations. Keep module linking in W and network/task scheduling in Win.

**C:** Implement CSS custom properties with inheritance, fallback and cycle handling,
then `calc()`/required viewport units and column flex basis/grow/shrink. Add
reference geometry/rendering tests for nested resized containers. This track can
advance M2/M3 while M1 is blocked on language work.

**D:** Expand the wasm/WebGL subset only from specification-backed requirements and
actual demo failures; enforce streaming MIME rules and distinguish buffered from
incremental compilation. Audit memory growth/detachment, table/global/import
behavior, numerical traps and WebGL validation. Prototype bounded frame transport
without changing the default execution mode.

Exit: M1 passes using unchanged host/bridge, with continuous frame advancement,
resize correctness, and repeated navigation without leaked realms or contexts.
Capture first-frame latency, frame pacing, retained memory, and parent responsiveness
as baselines; do not assert performance parity with established engines.

## Wave 2 — DOM, input and layout (M2)

**A:** Fill language/builtin gaps demonstrated by mobile UI and the selected M3
bundle, including iterators, collections, accessors and coercion as needed. Track
full ECMAScript features separately from executable app subsets. Improve GC safe
points so long-running allocation-heavy code does not retain all garbage until a
callback returns. Preserve budgets and terminal host-limit behavior.

**B:** Implement fragment parsing/`innerHTML` through W's HTML implementation,
DOM interface prototypes and reflection, live collections, MutationObserver
microtask delivery, fuller events and listener ordering. Complete focus, keyboard,
pointer, text input/composition and dirty form value/checked state. Add history
navigation/popstate and URL updates with explicit same-document semantics.
Implement parser-blocking, async/defer and dynamically inserted script scheduling
with distinct DOMContentLoaded/load dependencies. Parser suspension requires a
resumable HTML parser upstream; assign that W work explicitly rather than trying
to emulate parser blocking with the existing post-parse queue. Cover changing base
URLs, resource cancellation and document-generation boundaries.

**C:** Implement proper grid track sizing/placement, intrinsic min/max-content
contributions, missing flex directions/wrapping/baselines, positioned boxes,
stacking order, clipping and scroll containers. Expand computed styles and
interaction selectors. Divide this work into feature PRs with screenshot and hit
location assertions, not one layout rewrite. Include text shaping/bidi/font
fallback and inline formatting issues revealed by the app.

**D:** Complete the graphics/input surface used by M2; add context loss/restoration
and resource cleanup tests. Transport canvas frames from isolated workers with
backpressure and stale-frame rejection; handle resize and input generation IDs.
Keep IPC work experimental until default and isolated modes produce equivalent
application behavior.

Exit: M2 passes the recorded interaction scenario and resize screenshots. No
runtime-specific edits to the demo. Broader layout items can continue into Wave 3
if they are not required for M2, but remain explicit outstanding tasks.

## Wave 3 — networked applications and persistence (M3)

**A:** Complete remaining selected framework semantics and expand Test262 by affected
feature families. Track generators, RegExp, Intl, Proxy/Reflect and broader standard
library coverage explicitly; choose implementation order from executable failures.

**B:** Implement Request/Response/Headers, HTTP methods and binary request bodies,
JSON/blob helpers, abort, redirect modes, credential policy and CORS/preflight.
Add XHR compatibility after the shared transport is correct. Cover two-origin
loopback scenarios including denied requests and redirects. Add WebSocket and
streaming bodies in separate increments when application requirements justify them.

Persist origin-scoped local storage and maintain tab-scoped session storage using
atomic versioned records and explicit quotas. Centralize state across workers.
Complete cookie HttpOnly/SameSite/expiry/domain policy before exposing
`document.cookie`; domain cookies require public-suffix handling. Add HTTP cache
revalidation, 304/Vary correctness, reload modes and persistence with credential
partitioning. Never use the current permissive subset as an implicit cross-origin
credential policy.

**C:** Finish required responsive layout/CSSOM work and add pseudo-elements,
backgrounds/gradients, transitions/transforms and broader media queries as separate
conformance slices. Keep geometry, clipping, painting and pointer targets aligned.

**D:** Expand wasm toward the core spec and required proposals, supported typed
arrays and WebGL conformance; add Canvas 2D as its own tested surface. Replace
hardcoded demo-sized limits with documented configurable budgets without removing
validation, fuel or aggregate memory bounds. Measure interpreter bottlenecks before
choosing optimization work; a JIT is not a prerequisite for this wave.

Exit: M3 runs its unmodified bundle, exercises API success/failure/abort paths,
routing, form interactions and restart persistence; origin-isolation and quota
negative tests pass. Record unsupported APIs instead of silently faking success.

## Wave 4 — isolated execution and wider platform (M4/M5)

Coordinator and D integrate isolation only after frame transport and worker state
ownership pass. B supplies consistent storage/network/navigation services; A
supplies interruptible execution and proper cancellation/root release; C verifies
snapshot or display-list fidelity for input, focus, scrolling and canvas.

Test worker crashes, hung scripts, malformed IPC, oversized frames, stale messages,
rapid navigation, multiple tabs and parent responsiveness. Add an actual Linux OS
sandbox with a documented syscall/filesystem/network authority boundary and negative
escape-surface tests; a child process alone is not a sandbox. Keep graphics-driver
access and any separate GPU process boundary explicit. Default isolation changes
require M1–M3 parity, not only a watchdog smoke test.

Then expand independently scoped tracks for workers/structured clone, IndexedDB,
service workers and offline cache, accessibility tree/native bridge, media/audio,
selection/clipboard, developer console/inspection and additional platform backends.
These are real remaining standards areas, not commitments to finish them in the
first implementation session. Each receives its own interfaces and acceptance
fixtures before assignment.

## Validation and delivery rules

- Read the applicable primary standards and pin imported test revisions/licenses:
  [ECMA-262](https://tc39.es/ecma262/), [HTML](https://html.spec.whatwg.org/),
  [DOM](https://dom.spec.whatwg.org/), [Fetch](https://fetch.spec.whatwg.org/),
  [CSS](https://www.w3.org/Style/CSS/current-work),
  [WebAssembly](https://webassembly.github.io/spec/), and
  [WebGL](https://registry.khronos.org/webgl/).
- Add focused semantic, negative and ownership tests. Run native rendering and
  interaction tests for visual changes; do not replace screenshot evidence with
  DOM text dumps. Reference browsers are differential tools, not the specification.
- Expand pinned [Test262](https://github.com/tc39/test262) and
  [WPT](https://web-platform-tests.org/) by feature. Distinguish unsupported cases,
  harness errors, unexpected failures and passes. Native adaptations must remain
  labelled separately from unmodified upstream tests.
- Follow W's structured compiler checks and manifest-driven test selection. Stage
  new W sources before tracked-source parser checks. Run its required full suite
  on the final integrated W revision; compiler changes require the additional
  compiler verification prescribed by repository instructions.
- Run the complete Win suite and affected native GPU/WPT/app acceptance tests
  against that exact dependency revision. Revalidate after substantive integration
  changes. Document unavailable environments and missing evidence honestly.
- Deliver small reviewable W and application commits/PRs per feature slice. Land
  W dependencies first, update the application gitlink deliberately, and verify the
  final merged dependency. The next implementation request determines publication
  and merge authorization; this planning request authorizes only the plan commit.
- Update compatibility documents and an implementation progress note at each
  integrated checkpoint. Record exact SHAs, checks, open failures, next runnable
  commands and ownership handoffs so another context can resume without guessing.

## First assignment after context reset

Start Wave 0 and launch four parallel inspection/test tasks using tracks A–D above.
The coordinator reproduces the original host failure and defines the shared
interfaces. Implement Wave 1 once those contracts are concrete, integrating the
smallest changes needed to reach M1 while the independent layout and IPC tracks
advance. Continue through later milestones under the next user's implementation
scope; never report this entire roadmap complete merely because the triangle runs.
