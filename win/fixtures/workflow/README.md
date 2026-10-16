# M3 acceptance application

This is the executable native and isolated application acceptance target.
Run `python3 win/tests/workflow_server.py` from the repository root and open the
printed URL. The page uses the unmodified production ES module distribution of
Preact 10.27.2 (MIT, license in `vendor/LICENSE`). It has no build-time dependency
on a package manager. `app.mjs` is the application source, not a framework shim.

Acceptance scenario:

1. Enter a name and save; require `Saved: <name>` and a JSON POST to `/api/profile`.
2. Submit `error`; require `Failed: HTTP 503`. Submit `slow`, cancel during the
   two-second response delay, and require `Cancelled` without a later success.
3. Navigate to Settings, select Green, then use browser Back/Forward; both URL
   and visible view must change. Reload and restart the browser with the same
   profile; Green must remain. A different origin must not see the setting.
4. Repeat at 800×600 and 360×640; controls must remain visible and clickable.
5. Repeat using isolated execution and parent-owned storage.

Requirements include Preact's DOM reflection/prototypes and mutation APIs,
module exports/live bindings, Promise finalization, Fetch POST/JSON/abort,
history and popstate, persistent localStorage, custom properties and grid/flex.
The ordinary startup probe does not establish this interaction scenario.

Reproduce the vendored distribution byte-for-byte:

```sh
curl -fL https://registry.npmjs.org/preact/-/preact-10.27.2.tgz -o /tmp/preact-10.27.2.tgz
printf '%s  %s\n' f1d9cb453deb8d922c2f21702d719d23d24aaa3cab1a89a3dd326d0d8f6b3c70 /tmp/preact-10.27.2.tgz | sha256sum -c -
tar -xOf /tmp/preact-10.27.2.tgz package/dist/preact.module.js > win/fixtures/workflow/vendor/preact-10.27.2.module.js
tar -xOf /tmp/preact-10.27.2.tgz package/LICENSE > win/fixtures/workflow/vendor/LICENSE
```

Upstream build recipe and sources are in the package's `package.json` and the
[10.27.2 tag](https://github.com/preactjs/preact/tree/10.27.2). The published
artifact is retained verbatim, including its source-map comment.

Native acceptance runs with `python3 win/tests/workflow_integration.py` after
`./win/build build`. It starts dedicated Xvfb displays, drives portable native
input records through the normal widget/DOM/framework path, repeats the complete
workflow at 800×600 and 360×640, and checks reload, fresh-process persistence and
origin separation. It neither injects JavaScript nor patches the app or framework.
Reports, source hashes and actual viewport captures go to
`win/bin/modern-browser/workflow/`. The GL screenshots are visual evidence;
functional assertions do not imply pixel parity or complete CSS support.

`workflow_reference.py` runs the corresponding reference scenario with pinned
Playwright 1.58 and Chromium 145.0.7632.6. Native input acceptance does not test
platform keyboard translation or a complete IME. The initial loading text remains
below the rendered root in both engines; it is part of this unchanged fixture's
Preact reconciliation behavior.
