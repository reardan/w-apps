# Browser implementation contracts

Execution baseline: application `82f06c3720d0522396e2c59c119a1a4cb2a2ec1d`,
W `79b5378f553db17303efdecc1506156891757260`. The native W engine and
unchanged M1–M4 applications remain regression gates. These contracts distinguish
existing guarantees from interfaces being implemented; none closes a ledger family.
The [machine-readable ledger](standards-ledger.json) owns outstanding requirements.

## Worktree and file ownership

All worktrees use independent physical `w/bin` and `win/bin` directories. Compilers
were copied, never hard-linked. No worker writes the coordinator checkout.

| Role | Worktree | Exclusive implementation paths |
| --- | --- | --- |
| Coordinator | `/home/w/git/W/w-apps` | `win/main.w`, `win/build`, `win/src/win/{script,browser,app}.w`, documentation, gitlink, registration, `win/tests/browser_measurements*.py`, `win/tests/standards_ledger*.py` |
| A | `/home/w/git/W/browser-workers/a` | `w/libs/extras/javascript/`, new object/global runtime tests under `w/tests/javascript/` |
| B → D → runtime assertion support | `/home/w/git/W/browser-workers/b` | Parser/DOM and cookie/network slices complete for integration; now `w/libs/extras/javascript/{runtime_regexp,regexp_syntax}.w`, new lookahead tests and the existing lookahead rejection expectation. A retains all other JS paths; cookie adapter provenance remains B-owned. |
| F | `/home/w/git/W/browser-workers/f` | `w/tools/test262_conformance.py`, `w/tools/test262_runtime_runner.w`, `w/tests/javascript/test262/{README.md,manifest.json,inventory.json}`, `w/tests/javascript/test262_runner_test.py`, `win/tests/wpt*` |

The coordinator temporarily owns E's `win/src/win/interactive_worker.w` and
`win/tests/interactive_worker_test.w` solely for the recorded exit/EOF race.
The coordinator also owns `history_state.w` and `history_test.w` for intrinsic
prototype integration: history retains its bounded data-tree policy and rejects
boxed values, arguments objects, mapped properties and serialization hooks.
B released HTML and DOM implementation ownership after app `8fb08cb`; the coordinator
now maintains those integrated files. The D transfer includes only cookie parsing,
state and separate HTTP Set-Cookie field transport, preserving existing security
denials. `document.w`, rendering, other network policy, graphics and platform modules are reserved
for their plan owners; they cannot be edited without an explicit transfer. A sends
Test262 family requests to F. B sends script-host hooks to the coordinator. W
commits land before dependent application changes. A separate agent reviews each
slice, including negative tests, before integration.

Initial acceptance: A ordinary descriptor/reflection and global binding semantics
with ownership/exception tests; B owned context-sensitive fragments and stable DOM
identity with unchanged upstream cases; F strict accounting and asynchronous native
execution without substituted upstream assertions. Full-family gaps remain open.
Every handoff records commit IDs, exact checks, failures, prerequisites and next
commands. Small local commits only; no push or publication.

## Parser suspension and document ownership (B / coordinator)

Existing HTML documents own nodes and attributes. Detached nodes retained by JS
wrappers remain document-owned until realm teardown; node identity must not change
on moves. A fragment parser returns an independently owned fragment document and
receives explicit context tag, namespace and scripting flag. It must not retain a
borrowed context pointer. Unsupported contexts must fail explicitly without
publishing a partially mutated live tree. Moving fragment children preflights all
hierarchy constraints before changing either parent.

A future resumable parser must retain decoder/tokenizer/insertion-mode state and
an explicit paused-script continuation. The host may resume only the same live
document generation. Stop/navigation cancels continuation before releasing nodes.
A synchronous full parse is not a substitute for parser-blocking execution.
`innerHTML` uses fragment parsing and inserts inert scripts; insertion must not
accidentally append scripts to the initial resource execution queue.

## JS host roots, global bindings and jobs (A / coordinator / F)

All host-retained callbacks, values and receiver identities must be runtime roots
or reachable through rooted wrappers. Foreign-runtime values are rejected before
mutation. Suspended frames preserve shared fuel and bounded retained state; host
reentry does not refill budgets. Native temporary ownership unwinds on exceptions,
cancellation and teardown before stacks/host contexts are freed.

Window, self and globalThis designate the same Window object. Object-backed global
identifier lookup must honor lexical bindings and TDZ first, then ordinary
HasProperty/Get/Set with accessor receivers and exceptions. Declarations and
property deletion need explicit semantics; copying a fixed list of harness names
is forbidden. Modules retain separate lexical environments.

Microtasks run at existing script/event/timer checkpoints. WPT completion is an
explicit callback/message with strict schema, not title matching, a quiet timer
queue, or elapsed sleep. A supervisor deadline is ERROR/timeout, never PASS.
Repeated completion, assertion failure, process crash and malformed output remain
visible. Upstream harness code is immutable and hashed.

## Web IDL and native identity (A / B)

Bindings must specify receiver brands, conversion order, optional/undefined/null
handling and observable getters. Native property-presence tests must not invoke
getters or flush layout. Reflection must describe actual descriptors rather than
inventing successful descriptors for native properties. Prototype, enumerable,
configurable and writable flags are reviewed against Web IDL. Unsupported exotic
operations remain explicit until implemented; catchable language exceptions must
retain genuine engine identities. DOMException classes and live collection
semantics remain ledger blockers.

## Invalidation, geometry and accessibility (B / C / G)

DOM mutations increment the owning document's revision. Style, layout, paint,
hit testing and accessibility snapshots consume a matching revision and viewport.
Detached nodes cannot retain live layout pointers after invalidation. Coordinate
spaces (document, viewport, backing pixels) remain explicit; hit regions move with
painted content. C owns document layout structures. Semantic accessibility identity
uses stable node IDs, names/roles/states/relations and generation-qualified actions;
serialized isolated snapshots must not transfer native pointers.

## Origin/site/credentials and byte streams (D / E)

The existing same-origin broker restrictions remain enforced. A shared trusted
policy service must decide origin, top-level site, credential mode, redirects,
cache partition and capability admission before any external request. Opaque origins
never collapse into a shared empty bucket. Set-Cookie fields retain original boundaries and order through the HTTP client and
loader. The general merged-header API remains for existing callers; cookie parsing
never reconstructs field boundaries from commas. Borrowed fields live until response
teardown. Cookie metadata is bounded by the jar capacity and overall loader limits.
No `document.cookie` exposure before
HttpOnly/SameSite/PSL/partition rules are implemented and tested.

Native byte ownership is length-delimited and preserves NUL. Consumption is
single-use; cancellation invalidates pending completions and reaps helpers.
Future streams expose bounded queues/backpressure, explicit consumer cancellation
and error propagation. Buffered Fetch/wasm compilation is not called streaming.

## Generation-safe IPC and exit classification (E / coordinator)

Only complete validated generations publish DOM/history/focus/canvas state.
Stale messages and malformed lengths fail before allocation/publication. Existing
64 KiB per-direction poll limits, acknowledgments, quotas and confinement checks
remain. Reaping and socket closure are distinct kernel observations: EOF can arrive
before waitpid reports exit. A bounded nonblocking closing state must allow exit
observation without accepting a live disconnected peer indefinitely. The request
watchdog still bounds shutdown, and cancellation releases all resources.

## Evidence and measurement (F / coordinator)

Selected test counts, complete source inventories, applicable runnable tests,
variants and subtests are different denominators. Unknown counts remain null;
UNSUPPORTED and unexecuted mandatory tests remain completion blockers. Historical
reports never become fresh results through documentation edits.

`browser_measurements.py freeze` archives unchanged host/module/workflow artifacts,
source hashes, repository SHAs and environment. `verify` detects mutations. `run`
requires an idle preflight and records outside activity during the command under a
cross-worktree lock. Workers stop builders for timing windows. Process sampling
cannot prove absence of short-lived load, thermal throttling or GPU contention;
record these limits. Xvfb/software GL is separate from real-GPU evidence. Current
probes measure callback/readback times; those are not actual presentation latency.
Proposed budgets remain unqualified until the required raw sample counts and
presentation calibration exist.
