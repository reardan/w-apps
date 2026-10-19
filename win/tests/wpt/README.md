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

The manifest pins 20 unmodified HTML tests, their references, and the upstream
BSD license at WPT revision `6d4552a8b1057e42a180119d70273f563e53a264`. Every file
is SHA-256 verified before execution. Coverage is selected RGB/HSL/hex color
syntax, filtered nth-child matching/specificity, and CSS Variables inheritance,
invalid computed values, empty/whitespace fallback, and important cascade.
The eight added variable-reference cases (01–06, 13–14) and their shared green-text
reference retain their original CC0 notices; no upstream HTML/CSS is adapted. Reference links are read
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
to pass; all 20 have exact native reference matches. The expansion also exposed
and repaired an existing paragraph/div geometry mismatch through bounded
[adjacent block margin collapse](../../docs/margin-collapse.md). Exit codes are 0 for matching expectations, 1 for unexpected outcomes,
and 2 for invalid setup. The report never treats a timeout or harness error as
an expected rendering failure.

Contract tests run without a display and are included in `./win/build test`:

```sh
python3 win/tests/wpt_runner_test.py
```

`wpt_capture_test.py` runs under the standards command to check native ready-page captures and rejection of script failures, truncated output, and missing pages.

## Asynchronous script-host foundation

`wpt_driver.w` runs the real Win script host and polls its native timers and
microtask queues until a completion callback or a bounded deadline. The adapter
`wpt_testharness.py` loads the original hash-pinned upstream `testharness.js`,
registers `add_completion_callback`, and then evaluates unchanged `.any.js`
window scripts. It does not replace assertions or rewrite tests. The native
page lifecycle supplies load; upstream harness completion controls the result.
Build/run from the application repository root:

```sh
w/bin/wv2 x64 --strict --import-root win/src --import-root w \
  win/tests/wpt_driver.w -o win/bin/wpt_driver
python3 win/tests/wpt_testharness_test.py
python3 win/tests/wpt_testharness.py --json win/bin/wpt-testharness.json
```

The contract suite proves real timers, Promise checkpoints and suspended async
functions, failure propagation, missing/duplicate completion, fresh realms,
crashes, invalid output and malformed statuses. These are local driver tests,
not upstream WPT passes. The upstream `add_result_callback` additionally records
completed subtests even when a later harness error prevents completion. Observed
subtest passes never turn an incomplete file into PASS. The strict upstream
command currently exits 1: all
three original async files now initialize the original harness and bridge and
execute their test scripts. The microtask case currently stops on sloppy receiver
conversion; timer completion reaches the harness's negative-lookahead surrogate
sanitizer (line 4013), which remains unsupported. Earlier switch lowering,
globals, numeric keys, remainder, fromCharCode, indexOf and split blockers have
been implemented. Reports retain all three ERROR results;
there is no expected-failure success mode. Runtime and DOM dependencies remain
tracked with A/B/coordinator. The larger source limit is automation-only, for the
original 190+ KiB harness; ordinary browser execution limits remain unchanged.

This is an asynchronous native script-host execution path, not a complete
wptrunner product adapter. HTML/resources, server headers/substitutions,
multi-origin HTTP/TLS, variants, worker environments, testdriver/WebDriver,
dynamic reftest readiness and manifest-driven product execution remain mandatory
integration work. The three selected `.any.js` files also require worker
variants which this window seam does not execute. Those variants remain pending,
not passed or declared inapplicable.

`wpt-inventory.json` freezes the complete upstream archive and sorted per-file
hash index: 165,375 regular files, including 29,029 markup files referencing
`testharness.js` and 4,286 generated-test source files. These are file counts,
not applicable tests/variants. The unchanged upstream manifest generator now
expands the entire archive into version 9 manifest items: 32,080 testharness
source files produce 39,257 declared items; 28,227 reftest sources produce
28,601 items. Manual, support, crash, visual, print, accessibility, WebDriver
and vendored Test262 entries remain separate in the pinned summary. Declared
items are candidates, not executed tests or resolved product applicability.
Archive-to-manifest validation accounts for 16 archived symbolic-link paths
and six omitted `.coveragerc` config files; there are no manifest sources
outside the immutable archive.
Reproduce the complete archive/index and summary with:

```sh
python3 win/tests/wpt_inventory.py --output win/bin/upstream-inventory wpt
python3 win/tests/wpt_inventory.py --output win/bin/upstream-inventory test262
```

Then expand metadata from those hash-verified archives offline:

```sh
python3 win/tests/wpt_inventory.py --expand-existing --output win/bin/upstream-inventory wpt
python3 win/tests/wpt_inventory.py --expand-existing --output win/bin/upstream-inventory test262
```

WPT expansion requires Python 3.12+ for safe archive extraction and runs the
unchanged upstream manifest code with its pinned vendored dependencies. Test262
expansion runs its original metadata parser: 53,616 candidate files yield
102,994 declared strict/sloppy/raw/module variants, with zero parse diagnostics
or unexpanded files. Neither expansion is a conformance execution.

Only the explicit inventory download uses the network. Archive and index hashes
are pinned in the committed summaries. The GitHub recursive-tree API truncates
both suites and is not a valid complete-suite denominator.

## Complete asynchronous parent-family audit

`async-family-manifest.json` contains every item from the pinned official WPT
manifest under `html/webappapis/timers/` and
`html/webappapis/microtask-queuing/`: 20 test source files, 35 declared items,
and two separate support metadata files. All original source bytes are pinned.
The native script host admits all 12 window-script items. Fifteen worker
variants and eight HTML-document items remain mandatory UNSUPPORTED; they are
retained individually in the denominator, including cross-realm/resource cases.

```sh
python3 win/tests/wpt_family_audit_test.py
python3 win/tests/wpt_family_audit.py --json win/bin/wpt-family-audit.json
```

The audit has no favorable-file filter or expected-failure masking. It retains
all statuses and separately reports admitted-item counts. Its strict exit status
remains nonzero for any FAIL, ERROR or UNSUPPORTED. The four local contract tests
verify accounting, malformed environment admission and missing-driver behavior;
their synthetic executor results are not upstream WPT passes. Full Window,
HTML/resource loading, worker and multi-origin execution remain implementation
requirements beyond this script-host seam.
