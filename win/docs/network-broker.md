# Opt-in same-origin HTTP resource broker

`--isolated-interactive --sandbox-root ABS_DIR --sandbox-origin ORIGIN` runs
HTTP(S) pages in the existing Linux Landlock/seccomp worker, with network
requests performed by the parent. Use an existing empty directory for the
worker's content root when the page needs no local files:

```sh
mkdir -p /tmp/win-empty-content
xvfb-run -a win/bin/win --isolated-interactive \
  --sandbox-root /tmp/win-empty-content \
  --sandbox-origin http://127.0.0.1:8000 \
  --page http://127.0.0.1:8000/index.html
```

The origin must be an HTTP(S) origin with no path beyond `/`, query, fragment,
or credentials. This is an explicit capability for that scheme/host/port, not a
wildcard or an Internet-wide grant. Omitting `--sandbox-origin` preserves the
existing **offline** profile, including rejection of HTTP resources. Unsupported
kernel requirements fail closed; neither mode retries without confinement.

The worker retains the same OS denial of Internet socket creation, `connect`,
process access, filesystem writes and executable creation as the
[offline profile](offline-sandbox.md). Startup environment sanitization,
`close_range`, TSYNC and retained graphics descriptor audit remain in force.
The selected content root still grants read access at the OS level. The broker
never serves local paths or `file:` resources, including those within that root;
parent snapshot CSS/image loaders enforce the same HTTP origin restriction
before cache lookup. An empty root minimizes the worker's local file authority.

## Transport and ownership

A second private connected AF_UNIX stream is mapped to worker descriptor 1,
previously `/dev/null`. Descriptor 0 remains the independent WINT input,
Storage/history and canvas transport. No Internet socket, file descriptor,
credential, origin override, executable path or parent environment is sent to
content. Each worker receives a fresh channel, which supplies its lifetime
identity; request IDs increase monotonically within that channel.

The WBRO0001 header has six fields: eight magic bytes, then payload length,
request ID, message kind and revision as four little-endian int32 values.
Revision is 1. Kinds are request (1), cancellation (2), response (3).
Requests contain six int32 values: enumerated resource kind (document, CSS,
script, image, Fetch), URL byte length, method length, Content-Type length,
Accept length, body length; those five byte strings follow without terminators.
Only the body may contain NUL or arbitrary binary bytes. Cancellation has no
payload. Responses contain error, HTTP status, wasm MIME marker, final URL
length, then final URL and binary resource bytes.

The parent independently validates framing, IDs, resource kind, lengths,
methods, headers and origin. Non-Fetch assets require GET; document form POST
is supported. GET/HEAD cannot carry bodies. Unsupported methods, malformed
frames, unknown kinds, future cancellation IDs and quota exhaustion fail
closed. Cancellation for an already-completed ID is harmless. A rejected URL
produces a resource failure without starting a helper. Every redirect is checked
against the configured origin before opening the next connection.

Network helpers are trusted parent-owned processes outside the content sandbox.
They use existing bounded HTTP/content decoding, TLS verification, MIME and
image limits. The parent owns cookies and caching, scopes cookies at every hop,
and passes only resource bytes/status to content. The parent also retains
Storage ownership: persistence outside the worker root uses the separate
existing Storage RPC, with its own parent-selected origin.

Requests remain asynchronous. The worker can continue timers and input while
Fetch is outstanding. AbortSignal, Stop, navigation, worker failure and teardown
cancel helper jobs; the parent kills and reaps helpers. Abort does not wait for
Promise settlement. No synchronous network operation runs in the UI process.

## Bounds and failure behavior

| Limit | Value |
| --- | --- |
| Active broker requests | 16 per worker |
| Request IDs | 4,096 per worker lifetime |
| Request plus cancellation messages | 8,192 per worker lifetime |
| Aggregate delivered resource bytes | 256 MiB per worker lifetime |
| URL / method / each supported header | 4,096 / 32 / 1,024 bytes |
| Request body | 64 KiB |
| HTML/CSS/script source | 1 MiB |
| Fetch response | 4 MiB |
| Decoded image RGBA | 16 MiB |
| One complete wire frame | 16,785,408 bytes |
| Queued outgoing wire data | 33,570,816 bytes |
| Each wire pump | at most 64 KiB read and 64 KiB written |
| Network helper watchdog | 12 seconds, including blocked-reader periods |
| Worker-side broker request deadline | 15 seconds |

Existing document resource counts, document/image aggregate limits and outer
interactive request deadlines still apply. Completed loads release their active
slot when the document/resource/Fetch consumer frees them; aborted loads release
it immediately. Parent wire output has backpressure: it retains one result
frame at a time and continues accepting cancellation and enforcing helper
watchdogs while the reader is stalled. Each poll performs bounded work; a parent
poll can also advance the finite set of loader jobs, each using its existing
64 KiB input budget. Invalid transport stops that worker instead of falling
back to unrestricted loading.

## Evidence and exclusions

`broker_test.w` covers malformed headers/lengths/IDs, resource kinds, local and
foreign URL requests sent directly to the parent protocol, and a real child
killed/reaped when a stalled reader blocks output past its watchdog.
`broker_integration.py` uses an actual confined worker and loopback server for
linked CSS/JS, Fetch, binary POST, streaming wasm, cross-origin redirect denial,
response limits, and timer-driven Abort. The abort test requires the slow helper
connection to close before the worker's subsequent successful request, rather
than accepting connection closure at final teardown.

`broker_acceptance.py` runs the unchanged M2 host/wasm and M3 Preact application
through existing isolated native-input drivers. Only driver setup receives the
sandbox root/origin. M2 covers pointer focus, queued Unicode input, Backspace,
selection, resize and canvas ACKs. M3 covers JSON POST, HTTP failure, Abort with
no late success, routing/history, theme, reload, and 800×600/360×640 viewports.
Separate runs verify parent-owned storage persistence, `localhost` versus
`127.0.0.1` separation and mode-0600 publication outside the worker root.
Reports/screenshots/probe binaries are under `win/bin/broker-validation`.

The offline kernel and GL integration tests still pass, including direct raw
network denial, environment/descriptor hygiene, fail-closed unsupported kernels,
TSYNC, shader rendering and teardown. Tests require Linux x86-64 Landlock ABI 8;
GL acceptance additionally requires Xvfb or an appropriate X server.

This profile does not implement cross-origin requests, CORS, cross-origin
navigation, arbitrary Fetch headers, cross-origin cookies, WebSocket, service
workers, a DNS/IP egress allowlist, or general HTTP browser security policy.
The chosen origin can resolve to whichever addresses DNS supplies. Cookie and
HTTP support retains the existing browser implementation's limits. Existing
X11/GPU authority and parent-side inert HTML/CSS/image parsing remain trusted
and are not isolated by this broker. This is bounded same-origin HTTP support,
not complete desktop isolation or general Internet browser parity.
