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
python3 win/tests/cookie-fixtures/run.py win/bin/cookie_dates_test --output win/bin/cookie-upstream.json
```

The denominator is all 33 upstream registrations: 21 HTTP and 12 DOM cases.
DOM cases remain `UNSUPPORTED` because `document.cookie` is not exposed.
Timeouts and driver crashes/missing executables remain individual report
entries, preserving the denominator. Exit status is nonzero for FAIL/ERROR/
TIMEOUT. A fresh run for the initial date/age slice reports 20 PASS, 1 FAIL,
12 UNSUPPORTED. The failure is max-age case 9: the native parser requires a
nonempty token name and `=`, while the upstream case expects nameless `test9`.
This gap is mandatory open, not an expected-pass exemption.

The native deterministic test additionally checks past/future dates, malformed
Max-Age, both attribute orders, HttpOnly retention, exact absolute-expiry
snapshot roundtrip, deletion at the expiry boundary, bounded age overflow,
Secure overwrite and Domain denials, malformed records, and full-jar expiry.
Date parsing follows RFC 6265 section 5.1.1 and is reusable in W's cookie library.

SameSite, public-suffix/domain relaxation, partitioned state, complete cookie
pair grammar, browser cookie bindings, and full cookie-family execution remain
mandatory open. Existing conservative security checks remain enabled.
