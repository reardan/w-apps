# Headless script process isolation

`win --isolated-dump --page PATH_OR_URL` loads and executes a page in a fresh
child executable and returns its rendered text. The parent does not parse the
page, construct a JavaScript realm, preflight scripts, or replay DOM mutations.
Inline and external scripts run through the ordinary browser loading pipeline
inside the child. The output has the same address/title/text format as `--dump`.
Unlike `--dump`, script or resource errors cause a nonzero exit even when a text
snapshot is available.

This is **process separation, not an OS sandbox**. The worker has the same user,
filesystem and network authority as the parent. It does not install seccomp,
namespaces, privilege separation or a memory quota. Interpreter and resource
limits still apply, but a native bug can consume memory or exercise the worker's
OS authority. The current implementation targets the browser's supported Linux
x64 environment; its parent-death lifecycle calls use Linux x64 syscall numbers.

Normal interactive browsing and `--dump` still execute scripts in process.
`--isolated-interactive` explicitly selects the persistent content worker
described below. The headless `--isolated-dump` response remains a completed
text snapshot, not a new executable document.

## Parent interface

Import `win.script_worker` and call:

```text
win_script_worker_start(executable, address, home, timeout_ms, max_bytes)
win_script_worker_poll(worker)  # 0 pending, 1 finished
win_script_worker_cancel(worker)
win_script_worker_free(worker)
```

Start returns an owned handle, including on configuration or spawn failure.
Polling drains at most 64 KiB without waiting for pipe readiness. The caller must
poll regularly to enforce the wall-clock deadline; it covers loading, execution,
serialization and response drain. `--isolated-dump` polls every 2 ms, defaults to
30 seconds, and accepts `--worker-timeout MS`. Valid deadlines are 1–120,000 ms.
Response limits are 24 bytes through 8 MiB, including the header.

`finished` and `status` describe the transport outcome:

| Status | Meaning |
| --- | --- |
| 1 | Complete validated response and successful child exit |
| 2 | Deadline expired |
| 3 | Child exited unsuccessfully or crashed |
| 4 | Invalid/truncated response or pipe failure |
| 5 | Received or declared response exceeds limit |
| 6 | Cancelled |
| 7 | Invalid limits or spawn failure |

`text` remains null until status 1 and is borrowed from the handle until free.
`script_failures` and `resource_failures` remain separate from transport success;
a successful worker response does not imply successful scripts. `error` is a
static diagnostic. Cancellation/free kills and reaps an unfinished direct child.
An already-finished handle can be polled or cancelled again safely.

## Protocol and process lifecycle

The private `--script-worker` mode emits one response on stdout:

| Bytes | Content |
| --- | --- |
| 0–7 | ASCII `WINSW001` |
| 8–11 | Little-endian int32 payload length |
| 12–15 | Little-endian int32 script failure count |
| 16–19 | Little-endian int32 resource failure count |
| 20–23 | Reserved int32, must be zero |
| 24 onward | UTF-8 rendered text, with no embedded NUL |

The parent bounds actual bytes before appending, rejects oversized declarations,
and requires an exact payload length, valid magic/version, valid counters,
reserved zero, valid UTF-8, EOF, and exit status zero. It never allocates using a
child-supplied length. Partial output, trailing bytes, a valid frame followed by
a crash, and a valid frame from a child that never exits are not published.
The child bounds serialization too; a document that cannot produce a bounded
snapshot exits unsuccessfully without publishing a partial frame.

Workers are spawned with fresh stdio and descriptor cleanup. The parent passes
its PID in `WIN_SCRIPT_WORKER_PARENT`; the child installs `PR_SET_PDEATHSIG` with
SIGKILL and verifies its actual parent PID before processing arguments. Before
loading, the worker replaces that environment value with its own PID. Exec'd
resource/document loaders perform the same check, so they die if the worker
crashes or is cancelled even though the existing loader gives them separate
process groups. Checking the expected parent after installing the signal closes
the startup race. This is lifecycle cleanup, not security authentication.

## Validation

`tests/script_worker_test.w` exercises fragmented headers, valid output,
malformed/truncated/extra bytes, invalid UTF-8, oversized declarations and actual
output, crashes, nonzero exit after valid output, timeout after valid output,
cancellation, repeated cleanup, direct-child reaping, and separately grouped
exec-descendant death/reaping using a test-only Linux subreaper.

`tests/script_worker_integration.py` exercises real local and HTTP documents,
inline/external script mutations, equivalent normal/isolated text, script and
resource failure reporting, invalid deadlines, the wall-clock watchdog, and
real HTTP loader descendant death/reaping after watchdog expiry or abrupt
termination of the CLI parent.
Both are discovered by `win/build test`.


## Opt-in interactive content isolation

`win --isolated-interactive --page PATH_OR_URL` keeps each tab's browser,
JavaScript realm, event listeners, timers and document loading in a persistent
child executable. `--isolated-interactive --dump` also exercises this path
without a display. The default mode is unchanged: canvas/WebGL resource IPC
is not implemented, so isolated snapshots cannot display canvas output and
`getContext` is unavailable in the child. This mode is process separation with
the same OS authority, not a sandbox.

The parent renders an inert HTML snapshot and does not create a script realm
or execute scripts from it. Script elements are omitted; numeric
`data-win-node` attributes identify event targets in the current snapshot.
Clicks, input/change, form submission and periodic ticks travel to the child;
DOM changes return as a new snapshot. Links and form navigation execute in the
child. The parent maintains its tab/history controls and can cancel a stuck
worker. Closing a tab, stopping, reloading, navigating or freeing the app kills
and reaps the old child. The existing parent-death guard covers resource
loaders as well. Storage lives in each child and is not shared across isolated
tabs or retained when a child is replaced.

`win.interactive_worker` has no browser dependency:

```text
win_interactive_start(executable, address, home, timeout_ms, max_bytes)
win_interactive_poll(worker)  # -1 failure, 0 pending, 1 snapshot ready
win_interactive_request(worker, kind, node_id, value)  # 1 queued, 0 refused
win_interactive_free(worker)
```

Request kinds are 1 (tick), 2 (click), 3 (input value), and 4 (submit).
Only one request can be outstanding. The UI reports busy input instead of
building an unbounded event queue; users may need to retry input during a
request. Each accepted request invalidates the borrowed `html`, `address`,
and `title` pointers. A successful poll publishes them until the next accepted
request or free. There is a 30-second deadline per UI request, including the
initial load; transport callers may choose 1–120,000 ms. Polling must continue
to enforce it. Poll drains/sends at most 64 KiB per direction without waiting
for socket readiness. The socket is nonblocking, and sends suppress SIGPIPE
without changing the process signal dispositions. The wire and serialization
limits are at most 8 MiB; snapshot display retains the normal 1 MiB HTML
parser limit. Event values are limited to 64 KiB.

The private child mode is `--interactive-worker`. It uses a full-duplex socket
on fd 0; stdout is not the protocol. Each frame has a 24-byte header:
`WINT0001`, followed by little-endian int32 payload length, sequence number,
kind, and reserved zero. Initial snapshot sequence is zero; subsequent
responses must match the outstanding request's incrementing sequence. Reply
kind is 100. Its payload contains script/resource failure counts followed by
three NUL-terminated UTF-8 strings: address, title, and HTML. Request payloads
contain an int32 node ID followed by UTF-8 value bytes without NUL. Receivers
validate lengths before allocation, sequence, kind, reserved fields, counters,
UTF-8 and string boundaries. The child retains its realm between requests;
no evaluation replay or pointer transfer occurs. Unlike the one-shot dump,
a persistent reply does not imply that the child has exited; later death is
reported on the next poll.

The initial interactive implementation replaces the displayed DOM after a
mutation, so focus/selection preservation and complete native input-event
fidelity remain limited. It reloads display resources in the parent; it does
not transfer image, stylesheet, canvas or GPU objects. Ticks are requested at
roughly 100 ms intervals and can run timers/animation callbacks. These limits
are why isolation is explicitly selected rather than enabled by default.

`interactive_worker_test.w` covers actual fork/exec transport, fragmented
frames, sequence/type/reserved validation, oversized replies, bounded busy
refusal, timeout, crash, repeated requests, cancellation and direct-child
reaping. `interactive_browser_test.w` checks inert parent snapshots, per-tab
children, ticks, reload, stop and cleanup. `interactive_worker_integration.py`
checks real listener state across multiple clicks, input values and escaping,
navigation, malformed requests, and the parent headless snapshot path. When
X11 or `xvfb-run` is available, it also verifies that the native UI completes
24 frames and writes a screenshot while the child waits on a slow HTTP load.
