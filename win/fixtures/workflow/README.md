# M3 acceptance application

This is an executable target, **not a claim that Win supports this app yet**.
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
5. Repeat using isolated execution once M4's state/frame contracts are implemented.

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
