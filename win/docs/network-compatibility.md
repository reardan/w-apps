# Browser network state and Fetch transport

The loader implements a bounded, memory-only cookie jar and explicit-freshness
HTTP cache for document and subresource loads. State belongs to the application
process, is shared across its tabs, and is lost when that process exits. Workers
receive cookie snapshots in their exec environment and return cookie updates in
their existing pipe. Credentials are not placed in argv or written to disk.
No initialization is required. Call `win_network_state_clear()` after stopping
loaders at final application shutdown or to reset isolated tests; do not call it
on ordinary tab/page destruction.

## Cookies

- At most 32 cookies, with a 2 KiB limit per received combined Set-Cookie header.
  Replacing a cookie uses its host, path and name; a full jar evicts entries in
  a bounded rotating order. Session cookies and Max-Age from 0 through 31,536,000
  seconds are supported. Zero/negative Max-Age deletes a matching cookie.
- Hosts are canonicalized by W's URL parser. Cookies are host-only, including
  when a Domain attribute exactly matches the response host (one leading dot is
  accepted). Parent-domain and foreign-domain attributes are rejected. Cookies
  do not extend to subdomains. Ports do not partition cookies.
- Default paths use the response URL's directory. Explicit paths must start
  with `/`; sending observes the path-segment boundary, so `/a` does not match
  `/ab`. Secure cookies are accepted only over HTTPS and sent only over HTTPS.
  An HTTP response cannot replace an existing Secure cookie with the same key.
- Cookie selection is recomputed at each redirect. Each hop's accepted cookies
  can affect its next hop. HTTPS-to-HTTP redirects are rejected. Complete cookie
  records from a valid worker error envelope are retained after a later network
  error; killed workers and malformed/truncated envelopes do not update state.
- Repeated Set-Cookie headers are split from the transport's combined header
  only at a comma followed by a cookie name and `=`. Commas inside individual
  cookies are rejected. Expires cookies, including normal HTTP-date forms,
  are unsupported and rejected; Max-Age/session cookies are the supported path.
- There is no public-suffix list, SameSite enforcement, top-level-site partition,
  or third-party-cookie policy. Matching host/path cookies can be sent on
  cross-origin subresource loads. SameSite attributes are currently ignored.
  HttpOnly is not tracked as a separate flag: **no cookie is exposed to page
  JavaScript**, and `document.cookie` is not implemented. A future script-cookie
  API must add HttpOnly preservation before exposing this jar. `__Secure-`
  requires Secure; `__Host-` cookies are conservatively rejected.
- Persistence, standard cookie creation-time/path ordering, full cookie-date
  parsing, prefix compatibility and full browser cookie conformance remain gaps.

## HTTP cache

The parent caches successful, already decoded and resource-validated payloads.
The cache has at most 16 entries and an 8 MiB aggregate limit; each stored payload
is at most 1 MiB, including decoded image bytes. Entries are keyed by the exact
fragment-free request URL and resource kind. Eviction is bounded and rotating;
exceeding the aggregate cap clears the cache.

Only status-200 GET responses with **zero redirects**, no request cookies, no
Set-Cookie, no Vary, and an explicit Cache-Control max-age of at most 86,400 seconds
are eligible. No-store, no-cache and private disable storage. Age and the
preferred HTTP Date form reduce freshness; invalid/obsolete Date forms disable
caching. Elapsed worker-load time is conservatively deducted too. No heuristic
freshness is used. Cookies added after storage cause credentialed lookups to
bypass the cache. Non-GET loader requests clear the cache.

A hit avoids starting a worker and retains status 200 and the original request
URL. Redirect responses and their final bodies are never stored under the
redirect's original URL. Non-2xx Fetch responses are never cached.

Ordinary reloads currently use this same fresh cache; there is no force-reload
bypass or request cache mode. Stale responses are fetched in full. Conditional
ETag/Last-Modified revalidation, 304 handling, Vary-keyed entries, persistence,
request Cache-Control options and a shared cache service are not implemented.

## Fetch transport interface

`win_load_start_fetch(executable, address, origin, method, body)` returns the
existing cancellable `win_load`. Poll with `win_load_poll()` and free with
`win_load_free()`. `load.status` contains the HTTP status, `load.address` the final
URL, and `load.source`/`load.length` the decoded body. HTTP 4xx/5xx are successful
transport responses; network/protocol failures set `load.error`.

This increment supports HTTP(S) GET only, with a 1 MiB decoded body limit, a
10-second worker deadline and a 12-second parent watchdog. The initial URL and
**every redirect** must match the supplied origin's scheme, host and effective
port. Foreign redirects are rejected before making the next request. MIME is
unrestricted; the JavaScript Fetch layer performs UTF-8 validation. No custom
request headers, cross-origin CORS, streaming, upload, or general XHR transport
contract is provided. No main-worker dispatch changes are required.

## Validation

`win/tests/network_test.w` checks cookie scope, Secure protection, deletion,
snapshot restoration, eviction bounds, cache partition/replacement and freshness.
`win/tests/network_integration.py` uses loopback servers and real exec workers to
check multi-header cookies, parent/worker persistence, redirect cookies, foreign
host credential stripping, blocked foreign Fetch redirects, 404 bodies/status,
cache hits, no-store and redirect cache exclusion. Both are picked up by
`./win/build test`; the Python integration compiles its own small worker probe.
