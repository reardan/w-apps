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
There is no persistent isolated interactive realm, event RPC, or shared DOM.
The returned text is a completed snapshot, not a new executable document.

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
