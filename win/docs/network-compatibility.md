# Browser network state and Fetch transport

Outstanding mandatory work is tracked in the [standards ledger](standards-ledger.json)
and [shared implementation contracts](browser-contracts.md). Selected passing tests
do not close the broader standards families.

The loader implements a bounded, memory-only cookie jar and explicit-freshness
HTTP cache for document and subresource loads. State belongs to the application
process, is shared across its tabs, and is lost when that process exits. Workers
receive cookie snapshots in their exec environment and return cookie updates in
their existing pipe. Credentials are not placed in argv or written to disk.
No initialization is required. Call `win_network_state_clear()` after stopping
loaders at final application shutdown or to reset isolated tests; do not call it
on ordinary tab/page destruction.

The explicit [sandboxed HTTP broker](network-broker.md) reuses this transport
in trusted parent-owned helpers. It restricts every resource and redirect to the
selected origin while content retains its direct network denial. The default
loader and offline sandbox behavior are unchanged.

## Cookies

- At most 32 cookies, with a 2 KiB limit per original Set-Cookie field.
  Replacement uses host, path and cookie name; empty-name cookies retain a separate
  identity bit so values containing `=` survive snapshot roundtrips. A full jar
  evicts entries in bounded rotating order. Empty pairs are rejected; named empty
  values and value-only cookies are supported. Session cookies and RFC 6265
  date-token Expires are supported. Valid Max-Age overrides Expires regardless of
  attribute order; malformed age/date attributes are ignored. Zero/negative age
  deletes a matching cookie. Positive age saturates at 999,999,999 seconds and
  absolute expiry is capped at year 9999.
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
- The HTTP client retains ordered original Set-Cookie fields separately from its
  compatible merged header API. The loader processes individual fields without
  splitting commas, so an Expires suffix such as `GMT, baz=qux` cannot create a
  second cookie. Commas remain rejected in the cookie pair and explicit Path.
  Only the first 32 original fields across the entire redirect chain are
  considered, counting malformed/oversized fields; later fields are discarded.
  Cookie fields and URLs are bounded to 2 KiB and 4 KiB respectively.
- Worker snapshots preserve HttpOnly and absolute expiry; restoration never
  renews Max-Age. The parent independently limits decoded body size and metadata:
  196,896 bytes for 32 maximum-sized COOKIE records plus 1,024 bytes for other
  metadata. Malformed/incomplete metadata or an oversized body prevents jar
  updates; complete bounded records from a valid ERROR envelope remain eligible.
- There is no public-suffix list, SameSite enforcement, top-level-site partition,
  or third-party-cookie policy. Matching host/path cookies can be sent on
  cross-origin subresource loads. SameSite attributes are currently ignored.
  HttpOnly is retained through storage and worker snapshots. **No cookie is exposed
  to page JavaScript**; `document.cookie` remains unavailable until the remaining
  cookie policy requirements are implemented. `__Secure-`
  requires Secure; `__Host-` cookies are conservatively rejected.
- Disk persistence, creation-time/path ordering, complete cookie-pair grammar,
  domain/PSL policy, SameSite, partitioning, prefix compatibility and full browser
  cookie conformance remain mandatory open.

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

`win_load_start_fetch_bytes(executable, address, origin, method, body, length,
content_type, accept)` returns the existing cancellable `win_load`. The older
`win_load_start_fetch` string wrapper remains available. Poll with
`win_load_poll()` and free with `win_load_free()`. `load.status` contains the HTTP
status, `load.address` the final URL, and `load.source`/`load.length` the decoded
body. HTTP 4xx/5xx fulfill; network/protocol failures set `load.error`.

Fetch accepts HTTP token methods up to 32 bytes, rejecting CONNECT/TRACE/TRACK.
GET/HEAD cannot carry a body. String bodies use UTF-8 USVString conversion;
BufferSource bodies are copied at admission, including view offsets and NUL
bytes. Request bodies are limited to 64 KiB. The explicit request-header subset
is a plain record of Content-Type and Accept, with at most 1024 ASCII bytes per
value; header accessors, duplicate case-insensitive names, other headers,
Request/Headers objects, streams, CORS and general XHR remain unavailable.

Workers receive one `WFET0001` frame through stdin: an 8-byte version, four
little-endian int32 lengths for method/Content-Type/Accept/body, then those byte
sequences and EOF. Lengths are checked before allocation; malformed/truncated or
trailing input fails before networking. A 5-second frame deadline bounds a stuck
sender. A socketpair mapped to child stdin/stdout lets the parent pump at most
64 KiB per poll with nonblocking writes and MSG_NOSIGNAL. Stop, signal abort and
teardown close the channel and reap the child, including partial uploads.

Responses retain the 4 MiB decoded limit, 10-second network deadline and
12-second parent watchdog. The initial URL and **every redirect** must match the
supplied origin. POST on 301/302 and non-HEAD on 303 switch to GET and remove body
headers; 307/308 preserve method/body. Foreign redirects fail before the next
request. Only GET uses the cache; custom-header Fetch requests bypass it.
No main-worker dispatch changes are required.

## Validation

`win/tests/network_test.w` checks cookie scope, Secure protection, deletion,
snapshot restoration, eviction bounds, cache partition/replacement and freshness.
`win/tests/network_integration.py` uses loopback servers and real exec workers to
check multi-header cookies, parent/worker persistence, redirect cookies, foreign
host credential stripping, blocked foreign Fetch redirects, 404 bodies/status,
cache hits, no-store and redirect cache exclusion. Both are picked up by
`./win/build test`; the Python integration compiles its own small worker probe.

The completion increment adds `cookie_dates_test.w` for date/age precedence,
HttpOnly, absolute snapshots, empty-name identity, expiry and security denials.
`network_integration.py` also tests original field boundaries, cumulative redirect
limits, a 1 MiB body with a long URL and 32 large fields, and hostile envelopes.
`cookie-fixtures/run.py` verifies unchanged pinned WPT expires.html/max-age.html
and runs a native data-case adapter at a fixed clock: 21 HTTP PASS / 12 DOM
UNSUPPORTED across all 33 registrations. This is not browser WPT execution.
The selected HTTP gate runs in `win/build test` and `standards`; the strict
`win/build cookie-upstream` gate remains nonzero while DOM cases are unsupported.
