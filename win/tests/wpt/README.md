# Static WPT rendering corpus

Run the browser standards gate from the repository root:

```sh
./win/build standards
```

Or run just these reftests after building Win:

```sh
xvfb-run -a python3 win/tests/wpt_reftests.py
```

The runner uses Win's real native OpenGL renderer, serves the corpus from a local
HTTP server, and captures an 800×600 content viewport with `--reftest`. It waits
for the initial resource/script queue and two rendered frames. Browser chrome is
excluded; page layout and painting are shared with interactive browsing. Each
page runs in a new process. The output directory `win/bin/wpt-results/` contains
PPM screenshots and `report.json`, including pixel difference counts and upstream
provenance. Python 3.9+, X11/OpenGL (or Xvfb), and the built browser are required.
Normal runs need no internet access or third-party Python packages.

The manifest pins 12 unmodified HTML tests, their references, and the upstream
BSD license at WPT revision `6d4552a8b1057e42a180119d70273f563e53a264`. Every file
is SHA-256 verified before execution. Coverage is selected RGB/HSL/hex color
syntax and filtered nth-child matching/specificity. Reference links are read
from the original HTML. For multiple references, at least one `match` must match
exactly and all `mismatch` references must differ, following the
[WPT reftest rules](https://web-platform-tests.org/writing-tests/reftests.html).

This is a bounded static-reftest adapter, not a full wptrunner/WebDriver product
integration or a WPT pass-rate claim. It does not support testharness.js, scripts,
reftest-wait/TestRendered, fuzzy metadata, XHTML/XML, external assets, web fonts,
animations, variants, CSS escapes requiring resource inspection, server substitutions/response headers, or cross-origin/server fixtures. Such harness requirements
are reported as `UNSUPPORTED`, never as successful executions. Invalid pins,
missing references, renderer failures, truncated pages, timeouts, and malformed screenshots fail
setup or report `ERROR`. Unknown CSS language features are still rendered and
compared; they are not silently excluded from the pixel result.

The renderer retains Win's current initial canvas insets, font metrics, and
layout limitations. No scrollbar is drawn in this static capture mode. The
selected tests avoid scrollbar-dependent assertions. Passing a reference
comparison demonstrates that particular visual assertion in this configuration;
it does not prove the reference itself is standards-complete or qualify unrelated
layout or font behavior.

A reviewed expected `FAIL` can be recorded with a reason. It remains a failure in
the report's counts; a changed result, including an unexpected pass, fails the
gate until its expectation is reviewed. The current corpus expects every case
to pass. Exit codes are 0 for matching expectations, 1 for unexpected outcomes,
and 2 for invalid setup. The report never treats a timeout or harness error as
an expected rendering failure.

Contract tests run without a display and are included in `./win/build test`:

```sh
python3 win/tests/wpt_runner_test.py
```

`wpt_capture_test.py` runs under the standards command to check native ready-page captures and rejection of script failures, truncated output, and missing pages.
