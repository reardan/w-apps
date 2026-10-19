# Browser completion and performance plan

Updated 2026-10-19. This is the execution plan for completing Win's native W
browser engine, expanding standards coverage, and meeting measured performance
targets. It replaces the earlier M1–M4 implementation sequence. Preserve the W
engine and reusable W libraries; Win owns browser integration.

The existing graphics host, mobile UI, Preact workflow and isolated application
milestones are regression gates. They do not establish complete web compatibility.
Remaining work runs through the parallel assignments below, with one coordinator
and three active subagents. This change is planning only; implementation and new
performance measurements remain to be done.

## Baseline and completion definition

Planning baseline: application `1a953f1429924322610515c9df72c5dd195f4cf7`, W gitlink
`79b5378f553db17303efdecc1506156891757260`. Both worktrees were clean during the
audit. Preserve the exact dependency revision when reproducing results.

| Area | Recorded evidence | Remaining boundary |
| --- | --- | --- |
| Application integration | M1–M4 paths, including unchanged mobile host and pinned Preact workflow | These exercise bounded app requirements |
| Regression suites | Latest progress records 62 native Win programs plus integrations; merged W revision records 1,606 targets | Historical reports; rerun on each implementation baseline |
| ECMAScript | 74 selected upstream files, 145 variants: 110 PASS, 35 UNSUPPORTED | Restricted native harness; async/module/full host harness unavailable |
| WPT | 20 pinned static CSS reftests pass | No executable testharness.js or general WPT product integration |
| Isolation | Opt-in interactive workers, Landlock/seccomp offline profile, same-origin HTTP broker | Default remains in process; general web policy and desktop/GPU boundary incomplete |
| Performance | Historical Wasm steady-frame CPU median 78.6 → 58.3 ms | Excludes browser/GL work; predates the merged mobile module; no current end-to-end speed gate |

Sources: [measured progress](modern-browser-progress.md),
[Test262 profile](../../w/tests/javascript/test262/README.md),
[WPT adapter](../tests/wpt/README.md), [sandbox](offline-sandbox.md),
[broker](network-broker.md), and [historical timings](browser-gap-performance.json).

“Fully standards compliant” needs a versioned target: HTML is a living standard
and CSS is a set of modules. Freeze specification snapshots, mandatory features,
platforms, and upstream suite revisions in phase 0. Start with Linux x64 as the
existing supported platform and explicitly inventory other platform work. Do not
remove a required feature from scope because it fails or is expensive. Optional
or platform-inapplicable exclusions need a specification-based reason; deferred
mandatory features remain completion blockers.

Completion requires all of the following:

1. Every mandatory feature in the standards inventory is implemented and reviewed
   against its specification algorithms, including error and lifecycle behavior.
2. Every applicable test in the pinned target suites runs; mandatory suites have
   zero FAIL, ERROR, timeout, untriaged skip or UNSUPPORTED results. An upstream
   test defect needs a linked disposition and replacement evidence, not a hidden
   exclusion. Publish executed/total counts and applicability decisions.
3. Native, isolated and sandboxed product configurations pass the application,
   input, accessibility, storage, network and security gates that apply to them.
4. Current binaries pass the performance and stability budgets below on the
   recorded reference machines.

Passing tests alone does not prove every normative requirement. Close gaps using
specification review, generated/adversarial tests and differential investigation.
Any interim release lists unresolved features and makes a narrower compatibility
claim. Standards updates become an ongoing maintenance queue after this target
is closed.

## Parallel execution and ownership

Use four total agents: coordinator plus three active subagents. Tracks are roles
scheduled across waves, not seven simultaneous agents. Each implementation agent
gets separate application/W worktrees, private build outputs, exact base SHAs,
exclusive files, interface contracts, tests and a bounded deliverable. Never share
mutable `bin/` output directories or concurrently edit a runtime monolith.

| Track | Exclusive area when assigned | Deliverable |
| --- | --- | --- |
| A Runtime | W `libs/extras/javascript/`, assigned JS parser/grammar and tests | ECMAScript semantics, jobs, modules, GC and execution speed |
| B Documents | W `libs/extras/html/`; Win DOM/events/forms/modules/web-host files and assigned tests | Parser, Web IDL bindings, lifecycle and browser APIs |
| C Rendering | W CSS modules; Win style/cascade/selectors/CSSOM/layout/document files | Layout, text, painting, hit testing and rendering speed |
| D Network | W HTTP/URL/TLS modules; Win fetch/loader/network/storage/broker files | Standards-correct policy, transport, cache and persistence |
| E Graphics and isolation | W Wasm; Win canvas/frame/worker/sandbox files | Graphics compliance, fast execution, confinement and recovery |
| F Conformance and measurement | Assigned W Test262 tooling; Win WPT, benchmark and CI tooling | Reproducible reports, complete harnesses and performance gates |
| G Platform and product | Assigned native input/accessibility/media/devtools/platform modules | Accessible and complete browser workflows |

Coordinator owns `win/main.w`, `win/build`, `win/src/win/{script,browser,app}.w`,
test registration, shared contracts, compatibility docs and the W gitlink.
Track C owns `document.w`; B submits an interface request or receives an explicit
ownership transfer before editing it. Track E owns worker transport; D requests
protocol changes through that owner. Name individual files before starting tasks
whose directories overlap, including W grammar and Test262 files.

Every assignment records: requirement/test IDs, prerequisites, owned paths,
explicit exclusions, proposed interface, reproduction command, acceptance tests,
performance impact and completion evidence. Return reviewable commits, checks,
remaining failures and a handoff. A different agent reviews correctness and
negative tests before integration. Integrate W dependencies first, update the
gitlink deliberately, then test Win against that exact W commit. Review work can
run in parallel; timing benchmarks run alone on their measurement machine.

## Phase 0 Establish the executable completion backlog

Run F, A and B audits in parallel while the coordinator reproduces the baseline,
inventories rendering/network/graphics/product requirements and assigns interfaces.
This planning audit seeds that work; it does not substitute for executable reports.

- Create a machine-readable feature ledger under `win/docs/`, linked to the
  compatibility documents. Each row has a spec snapshot/section, mandatory or
  optional status, implementation paths, dependency IDs, owner, upstream test
  family/counts, harness blockers, negative tests, performance fixture and status.
- Inventory the complete pinned suites before selecting shards. Reconcile every
  existing unsupported statement, old roadmap item and newly discovered feature
  into the ledger. Keep unexecuted tests in the denominator.
- Pin reference browser versions, test licenses/hashes, font/locale/timezone,
  OS/kernel/GPU/driver/CPU, build flags and corpus hashes. Archive reports with
  both repository SHAs. Fix the recorded worker-exit/socket-EOF race with a
  deterministic regression rather than accepting reruns as stability evidence.
- Define contracts for parser suspension and document ownership; JS host rooting,
  microtasks/cancellation; Web IDL descriptors; style invalidation and geometry;
  origin/site/credential policy; byte streams; and generation-safe IPC ownership.
- Capture cold/warm navigation, first presented frame, input-to-present latency,
  frame pacing, parent poll latency, RSS, allocations, FDs and cancellation for
  current unchanged M1–M3 fixtures in all supported execution profiles.

Exit: no unowned requirement families; reproducible baseline results and timing
traces; concrete failing cases and contracts for the first three assignments.
Estimate task sizes from these failures and measured throughput. The full program
needs multiple integration waves; no fixed delivery date is credible before this
inventory and the harness work.

## Phase 1 Build conformance infrastructure and core semantics

Active subagents: **F harness**, **A runtime**, **B parser and DOM**. Coordinator
integrates shared host hooks and makes the initial performance runner usable.

**F:** Extend Test262 support for upstream includes/assertions, `assert.throws`,
`$DONE`, `$262`, realms, async/module execution, metadata and negative phases.
Replace restricted harness assumptions with the real upstream harness as language
support permits. Preserve the existing profile until the replacement is verified.
Build Win automation and a wptrunner product adapter: executable testharness.js,
completion callbacks, resources, multi-origin HTTP/TLS servers, async reftest
readiness, fonts, variants and server headers. Add testdriver/WebDriver actions
incrementally. Runtime or DOM requirements become explicit A/B blockers; do not
rewrite upstream tests or fake missing assertions. Validate the harness with
deliberate failures, crashes, timeouts and malformed reports.

**A:** Complete ordinary objects, property descriptors/accessors, Object reflection,
prototype chains, receiver/coercion semantics, deletion, sparse arrays and mapped
arguments. Add Symbols and iteration, full primitive conversions and constructors,
arbitrary-precision BigInt, classes, generators/async generators, Proxy/Reflect,
RegExp and Intl. Complete Promise/jobs and cyclic module linking/evaluation,
default/namespace exports and re-exports, dynamic import and failure caching.
Cover eval/Function, realms, weak references,
typed arrays/shared memory/Atomics and other mandatory target features through
separate ledger tasks. Preserve GC rooting across suspension and host reentry;
add safe points, allocation limits and cancellation without changing semantics.
Order the initial slices by harness blockers and complete feature-family tests.

**B:** Implement complete tokenizer states and HTML tree construction, insertion
modes, implied tags, foster parenting, adoption agency, templates, scripting-sensitive
noscript, foreign content, streaming encodings, quirks and context-sensitive
fragments in W. Add resumable parsing, parser-blocking scripts/document.write, async/defer
and module lifecycle scheduling in Win. Complete Web IDL conversions, native
interface prototypes, DOMException, node identity/reflection/live collections,
innerHTML and MutationObserver delivery. Then complete event propagation/options,
forms/validation, focus, history/navigation and document lifecycle. Define semantic
accessibility snapshots, names/states/actions and isolated snapshot ownership
alongside DOM identity so platform bridges consume the same stable tree; reuse
W's existing accessibility and text-shaping foundations.

Exit: the harness executes real synchronous/asynchronous JS tests and dynamic
reftests with strict outcome accounting; first complete runtime/parser/DOM families
pass; all previous expected passes and M1–M4 behavior remain intact. Unfinished
language/DOM families continue as named tasks in later waves.

## Phase 2 Complete layout and the network security model

Active subagents: **C rendering**, **D network**, **A or B remaining blockers**.
Coordinator maintains F gates; queue A/B tasks according to dependencies.

**C:** Complete cascade/origins/layers, selectors, CSS values and CSSOM; inline and
block formatting, floats/clear, independent formatting contexts and inline-block,
parent/empty margin collapse, tables, replaced-element/intrinsic sizing, logical
dimensions, fragmentation, flex
wrapping/alignment, and real grid track sizing/placement. Add positioned and sticky
boxes, containing blocks, stacking contexts, overflow/scroll containers, clipping,
transforms and consistent hit testing. Complete font selection/loading, shaping,
bidi, line breaking, writing modes and selection geometry. Extend pseudo-elements,
backgrounds/gradients, animations/transitions, media/container queries, responsive
images, SVG/MathML and print/paged rendering through separately tested slices.
The pinned CSS module inventory determines the remaining required properties.

**D:** Establish one trusted origin/site and policy service for navigation, assets,
Fetch, cache and workers. Complete URL parsing and mutable URL/searchParams links,
Request/Response/Headers, byte streams/backpressure, Blob/File/FormData, abort,
redirect/credential modes, CORS/preflight and XHR. Implement cookie dates/domain/
public-suffix/HttpOnly/SameSite/prefix policy and partitioning before exposing
document.cookie. Complete cache revalidation/304/Vary/reload modes and persistent,
partitioned state. Add secure contexts, CSP, mixed content, referrer policy,
iframe sandboxing, MIME handling, integrity and cross-origin isolation rules.
Cover permissions and trustworthy origin checks before admitting new capabilities.
Audit current HTTP/TLS/URL behavior against the pinned standards; close protocol,
certificate, encoding/compression and connection-reuse gaps. Explicitly cover
WHATWG host/IDNA parsing, IPv6 transport, TLS 1.3 and its required algorithms,
native trust-store integration for each target OS, and HTTP/2 integration rather
than assuming existing W libraries are wired into Win. Add WebSocket,
EventSource and required HTTP versions as explicit tasks, with deterministic
loopback/TLS fixtures. Retain existing broker denial behavior while policy expands.

**A/B:** Finish runtime/DOM blockers and add iframe browsing contexts, postMessage,
structured clone, shadow DOM/custom elements, observers, selection/ranges and
editing. Rendering-dependent APIs wait for C's geometry contracts. Integrate the
initial semantic tree and Linux accessibility focus/actions alongside layout,
using assigned G work slices; full assistive-technology qualification follows in
phase 4.

Exit: complete selected layout and network families pass upstream and adversarial
tests; cross-origin credential leaks fail closed; visual geometry and pointer
targets agree. Responsive applications, forms and restart persistence work across
the recorded corpus without rewritten sources.

## Phase 3 Complete graphics and make isolation the product default

Active subagents: **E graphics/isolation**, **A runtime performance**, **C rendering
performance**. Coordinator integrates D policy and F performance gates.

**E:** Expand Wasm validation/execution to the pinned core version and mandatory
proposal set; complete imports, tables, references, memory growth, traps and
numerical behavior. Complete Canvas 2D and target WebGL versions/extensions with
upstream conformance tests, context loss and cleanup. Finish image decoding,
animation, color handling and required graphics APIs recorded in the ledger.
Preserve frame generation IDs, bounded buffers, acknowledgments and backpressure.

Extend the existing Linux confinement and broker rather than rebuilding them.
Specify the remaining network, filesystem, process, memory and graphics authority
boundaries; isolate display/GPU access where required, enforce aggregate quotas
and test compromised-content requests. General browsing must not grant content
raw X11 or parent authority. Exercise stale IPC, malformed frames, worker/GPU
crashes, hung scripts, rapid navigation, multiple tabs, restart and recovery.
Switch default execution only after the full app/policy/input/rendering/accessibility matrix
passes in confinement. Unsupported required sandbox facilities must produce an
explicit failure, with no silent unconfined retry.

**A/C:** Follow the measured optimization order below. Schedule E's Wasm runtime
optimizations under E ownership; A must not edit that runtime concurrently.
Use complete semantic families and app traces to validate each optimization.

Exit: unchanged applications meet the provisional speed budgets; the intended
shipping default is confined and passes its authority/recovery tests; graphics
families pass the pinned conformance suites. Remaining performance failures stay
release blockers even when correctness passes.

## Phase 4 Finish platform capabilities and browser workflows

Active subagents: **B/D web services**, **G accessibility/product**, **E/G media and
platform**. Transfer files explicitly and serialize overlapping G assignments.

Complete dedicated/shared workers, messaging/transfer, IndexedDB transactions,
storage quotas/eviction, service workers, Cache API and offline/update lifecycle.
Add Web Crypto and required secure-context/permission-gated APIs. Complete
audio/video playback, media loading/codecs, Web Audio, capture and real-time media
where required by the target. Inventory remaining APIs such as WebGPU, WebRTC,
filesystem and device capabilities explicitly; give each a milestone or justified
optional status instead of losing them in “future work.”

Build the semantic accessibility tree, accessible names/roles/states/relations,
native Linux accessibility bridge, screen-reader navigation and actions. Complete
keyboard controls, IME/composition, clipboard, selection, drag/drop, zoom and
high-contrast/reduced-motion behavior. Test actual native input and assistive
technology, beyond the current portable event seam. Add other OS backends only
with their own native rendering/input/accessibility/security evidence.

Finish browser chrome and user workflows: tab/window lifecycle, navigation and
error pages, downloads/file chooser, print, find, history/bookmarks/session restore,
site permissions and data clearing, settings, developer console/inspection/network
diagnostics, packaging and update/recovery behavior. Inventory current support
before assigning each feature; these product requirements are separate from
normative web-platform requirements.

Exit: every mandatory ledger family has implementation, tests and an owner-approved
closure; end-to-end workflows, accessibility, permissions and persistence pass.
Optional capabilities remain visible with their disposition and rationale.

## Performance targets and optimization order

These are proposed engineering acceptance budgets, not current measurements or
standards requirements. Phase 0 fixes the reference hardware, release build,
fixtures, viewport and network profiles. Review any budget revision explicitly;
do not relax budgets silently to make a result pass.

| Metric | Proposed gate on the reference machine |
| --- | --- |
| Unchanged mobile animation | At 60 Hz, p95 presented frame interval ≤one measured refresh period plus fixed measurement tolerance; <1% missed refresh deadlines |
| Input response | p95 input-to-present ≤50 ms; p99 ≤100 ms across typing, scrolling and tab switching |
| Parent event processing | p99 poll/work slice ≤8 ms; no observed UI stall >50 ms in scripted stress runs |
| Local fixture startup | p95 navigation-to-first-useful-present ≤1 s cold and ≤500 ms warm, including mobile |
| Stop/navigation cancellation | p95 visible response ≤100 ms; all old workers/resources reaped ≤1 s |
| Long-session resources | After warm-up and 100 navigation/tab cycles, no live-object/FD/child growth; settled RSS ≤5% above warm baseline with retained caches bounded |
| Change regression | No reproducible >5% median or >10% p95 latency/RSS regression on fixed workloads without reviewed justification |

Measure at least 30 independent samples per cold/warm navigation scenario,
at least 1,000 interactions per scenario for p99 qualification, and at least 1,000
presented frames for pacing. Define first useful presentation as visible required
content with working input, not a blank or partial frame. Calibrate presentation
timestamp tolerance in phase 0, record it before testing, and count missed deadlines
against measured vsync periods (about 16.7 ms at 60 Hz).
Repeat runs and report raw samples,
median/p95/p99 and uncertainty. Compare paired or alternating builds on an idle,
fixed machine; record throttling/power configuration and separate real GPU from
software rendering. Measure end-to-end timestamps through actual presentation,
not only callback duration. Cross-browser comparisons use identical artifacts,
machine, network and browser versions; no engine-specific source patches.

Prioritize by current profiles:

1. **Scheduling and cancellation:** keep parsing, networking, decoding and long
   JS/Wasm work off the UI path; provide safe points and bounded queues.
2. **Wasm/JS execution:** inspect dispatch, decoded instruction representation,
allocations, property lookup, calls and GC. Replace broad suspended-frame roots
with precise live roots and verify reclamation during long awaits. Measure predecoding, specialization
   and inline caches; evaluate baseline JIT/AOT only if interpreter improvements
   cannot meet budgets, with executable-memory policy and semantic tests included.
   Do not special-case fixture source or remove fuel/trap/security checks.
3. **Style/layout:** `document.w` currently rebuilds runs during full layout;
   style computation rescans rules and ancestor custom properties. Profile selector
   compilation/indexing, parsed-style caches, inherited-value sharing, explicit
   style/layout/paint invalidation and incremental subtree layout.
4. **Painting and transport:** profile retained display lists, damage tracking,
   viewport culling, glyph/image caches, composited scrolling, frame copies and IPC
   backpressure. Preserve coordinate-space and hit-test equivalence.
5. **Network/startup:** measure connection reuse, cache validation, concurrent loads,
   decoding and resource priority without weakening credential or origin checks.

The code paths suggest opportunities; only paired measurements establish a speedup.
Keep the original app artifacts frozen for comparisons. Compiler/app output
improvements can be a separate experiment with a separately identified corpus.

## Phase 5 Release qualification and continued conformance

Active subagents: **F full-suite audit**, **D/E security and stability review**,
**G independent application/accessibility review**. Coordinator resolves gaps,
verifies exact artifacts and updates support claims.

- Run the complete pinned applicable Test262, WPT, Wasm and graphics suites in
  shards. Account for every test and subtest, including unsupported harness needs.
  Review specification requirements not represented by tests. Never infer global
  conformance from an unchanged curated pass count.
- Run parser/runtime/decoder/protocol fuzzing, malformed-input and resource-pressure
  tests, memory ownership checks, crash recovery and long-session stress. Investigate
  flakes rather than masking them with retries. Include real GPU/driver and native
  input/accessibility configurations required for the release.
- Gate CI on prior expected passes and relevant complete feature suites; schedule
  full suites and performance runs on suitable hosts. Store source/tool/spec/suite
  provenance, diagnostics, traces and visual artifacts. A skip on unavailable
  hardware is missing release evidence.
- Close every mandatory ledger item and every performance/security blocker. Publish
  exact support scope and results. Add a recurring spec/test update process and
  regression triage ownership; a versioned completion milestone does not end upkeep.

For implementation changes, run W's prescribed structured checks and focused
manifest-selected tests, followed by its full suite on the final integrated W
revision. Compiler changes also require the checks in `w/AGENTS.md`. For Win run
the full suite, standards gate and all new family/native acceptance gates. Existing
baseline commands from the application root are:

```sh
git status --short
git rev-parse HEAD
git ls-tree HEAD w
git -C w rev-parse HEAD
(cd w && env -u NO_COLOR ./wbuild -j 4 tests)
xvfb-run -a ./win/build test
xvfb-run -a ./win/build standards
```

Use the recorded compatible toolchain/environment, including Node for reference
workloads. These commands currently cover the bounded suites, not this future
completion gate. New harness/benchmark commands must be documented when added.
Keep implementation checkpoints in [progress](modern-browser-progress.md), with
next runnable tasks and exact evidence. This plan does not authorize publication
or change the existing shipped compatibility claims.

## First implementation assignments

1. **Coordinator:** record fresh SHAs/results, create the standards ledger and
   assign shared contracts/paths; preserve M1–M4 regressions and freeze corpora.
2. **Subagent F:** enumerate full upstream suite requirements, add report accounting
   and a minimal real async WPT execution path, identifying A/B blockers precisely.
3. **Subagent A:** implement the smallest complete object/reflection/harness-support
   slice needed by F, with full affected Test262 families and GC/exception tests.
4. **Subagent B:** establish HTML fragment/tree-construction and DOM identity
   contracts, implement the first complete parser/DOM slice with upstream cases.

The coordinator captures current performance while compilation/test loads are
idle. Integrate the first slices, run the gates, then assign C/D/E work using the
dependency order above. Do not restart already completed app milestones.

## Standards and test references

Freeze exact revisions during phase 0. The [HTML Living Standard](https://html.spec.whatwg.org/multipage/)
and [CSS Snapshot](https://www.w3.org/TR/css/) define the starting specification
inventory. Include their normative dependencies, plus DOM, Web IDL, URL, Encoding,
Fetch, Streams, Storage, ECMAScript/Intl, HTTP/TLS, accessibility and graphics
standards relevant to the target.

[WPT](https://web-platform-tests.org/) provides cross-browser tests;
[testharness.js](https://web-platform-tests.org/writing-tests/testharness.html)
and [wptrunner](https://web-platform-tests.org/tools/wptrunner/docs/internals.html)
provide the execution/reporting integration model.
[Test262](https://github.com/tc39/test262) covers ECMAScript and Intl conformance;
its maintainers explicitly note that coverage is not complete. Use normative
specifications to resolve behavior, with reference engines as differential evidence.
