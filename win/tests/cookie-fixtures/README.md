# Cookie date and age upstream data cases

`expires.html`, `max-age.html`, and `LICENSE.md` are unchanged copies from
web-platform-tests/wpt commit `6d4552a8b1057e42a180119d70273f563e53a264`:

- https://github.com/web-platform-tests/wpt/blob/6d4552a8b1057e42a180119d70273f563e53a264/cookies/attributes/expires.html
- https://github.com/web-platform-tests/wpt/blob/6d4552a8b1057e42a180119d70273f563e53a264/cookies/attributes/max-age.html
- License SHA256: `5fac07febb0e2a97fb0d7b0def149ec08b642e1ba4b9c345283ab1cbd2af6570`

`run.py` verifies source SHA256, executes unchanged inline scripts in Node to
collect upstream arguments, then runs each HTTP case through the native Win
cookie parser with a deterministic 2026-01-01 UTC clock. Node only enumerates
cases; it does not judge cookies. This is an upstream **data-case adapter**,
not a real WPT browser execution: networking, testharness.js, testdriver,
JavaScript cookie bindings, and browser event scheduling are not exercised.

Run from the app root after building `win/bin/cookie_dates_test`:

```
python3 win/tests/cookie-fixtures/run.py win/bin/cookie_dates_test --gate http --output win/bin/cookie-upstream.json
```

The denominator is all 33 upstream registrations: 21 HTTP and 12 DOM cases.
DOM cases remain `UNSUPPORTED` because `document.cookie` is not exposed.
Timeouts and driver crashes/missing executables remain individual report
entries, preserving the denominator. The default `--gate http` requires exactly
21 passing HTTP cases with the full 33-case inventory intact; HTTP FAIL/ERROR/
TIMEOUT fails that gate. `--gate all` requires all 33 cases to pass, so it returns
nonzero while the 12 DOM cases remain UNSUPPORTED. Both modes preserve all case
statuses and record their gate selection/result in the JSON report. Historical initial date/age commit `bd9711d` reported 20 PASS, 1 FAIL,
12 UNSUPPORTED; max-age case 9 required an empty-name cookie. The subsequent
empty-name identity slice reports 21 PASS and 12 UNSUPPORTED without fixture or
expectation changes. This closes the selected HTTP data cases only, not the full
upstream cookie family or browser execution.

The native deterministic test additionally checks past/future dates, malformed
Max-Age, both attribute orders, HttpOnly retention, exact absolute-expiry
snapshot roundtrip, deletion at the expiry boundary, bounded age overflow,
Secure overwrite and Domain denials, malformed records, and full-jar expiry.
Date parsing follows RFC 6265 section 5.1.1 and is reusable in W's cookie library.

SameSite, public-suffix/domain relaxation, partitioned state, complete cookie
pair grammar, browser cookie bindings, and full cookie-family execution remain
mandatory open. Existing conservative security checks remain enabled.

## Original HTTP fields and worker transport

The HTTP response keeps ordered original `Set-Cookie` fields separately from
its compatible comma-merged generic header map. Borrowed field strings remain
valid until response/stream teardown; the response frees its own copies.
Informational response fields are ignored. Win uses only original fields when
receiving response cookies, so `Expires=... GMT, baz=qux` cannot synthesize a
second cookie. The legacy merged-input helper remains for existing direct
callers but is not used by the loader.

Win accepts at most 32 original Set-Cookie fields across an entire redirect
chain, including malformed or oversized fields in that count. Fields after
that cap are discarded by the child; the parent also caps complete metadata
records at 32. Each accepted field remains limited to 2048 bytes and the loader
bounds the complete worker envelope separately from the decoded body. This is a bounded foundation policy,
not complete browser cookie capacity conformance. The native integration suite
covers the upstream comma ambiguity, multiple separate fields, discarded expired
cookies, HttpOnly retention, 33-field overflow, and cumulative redirect overflow.

Empty-name cookies have a distinct identity bit in the bounded jar. Cookie
request headers omit the empty name and separator; snapshots explicitly restore
an initial `=` so a value containing `=` cannot become a named cookie. Tests
cover replacement and deletion of the empty-name key, independent named cookies,
empty-pair rejection, named empty values, Secure/HttpOnly retention, conservative
prefix/domain checks, and native worker roundtrip. Complete cookie pair grammar
and the previously listed policy/binding gaps remain open.

The loader reserves `32 * (4096 + 2048 + 9) = 196896` bytes for COOKIE metadata,
plus 1024 bytes for other metadata and the separately bounded final URL/envelope.
The decoded body is independently limited to its resource-specific cap; metadata
allowance cannot become extra payload capacity. Sender and receiver enforce
per-field/address lengths and record count. Oversized, incomplete, or malformed
metadata prevents cookie-jar mutation, including worker ERROR exits. Integration
checks include a 1 MiB body with a long URL and 32 large cookie fields, the exact
maximum valid COOKIE metadata envelope, and rejected over-cap/malformed cases.
