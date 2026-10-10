# Win foundation readiness

Win now integrates native tabs, bounded asynchronous document and resource loading, author stylesheet cascade, box layout, PNG/JPEG images, forms, and a mutable DOM with page JavaScript. Run `./win/build run --page win/fixtures/interactive.html` for the combined demo.

The W dependency pin remains `f63d97aea815b3541ab78dd195ef8e1b17b4c30f`. This application change does not modify W or its TLS implementation. W supplies HTML/CSS parsing, fonts/widgets/rendering, image codecs, HTTP/TLS, and the generated JavaScript parser/subset interpreter.

## Implemented integration

Each tab owns its document tree, display list, form editor states, stylesheet/resource queue, navigation history, and JavaScript runtime. Async worker results belong to their owning document; navigation, Stop, and tab closure cancel/reap pending workers. Image decoding happens in the worker, while GPU textures are created and released through W's renderer.

Author stylesheet order follows DOM order regardless of download completion. Scripts execute in DOM order after parsing, with one script per poll and deterministic execution/DOM budgets. DOM wrappers synchronize mutations at host calls and evaluation boundaries. Events invoke rooted callbacks through `js_runtime_invoke`; document replacement frees the realm and all listeners.

[CSS compatibility](css-compatibility.md) and [JavaScript compatibility](javascript-compatibility.md) specify the actual boundaries. These include simplified flex/grid, a partial CSS property/selector set, and W's language subset rather than full ECMAScript. HTML recovery/entities, image codec variants, IPv4 transport, text shaping, native accessibility, cookies/cache, and content-process isolation remain broader compatibility work. Form limitations are listed in the [README](../README.md).

## Public HTTPS follow-up

The application successfully loaded `http://example.com/` in a live check. `https://example.com/` and a direct W TLS probe against `www.cloudflare.com` failed certificate verification, while curl/OpenSSL verified example.com successfully in the same environment. An independent W X.509 probe of the captured chain reported `x509: signature verification failed`.

The captured chain includes P-384 intermediate/root public keys. W's current `x509_check_signature` supports RSA and EC P-256 issuer keys, so P-384 verification is a concrete upstream compatibility gap for this chain. The generic HTTP error currently loses the more specific X.509 reason. Add P-384 chain support, preserve detailed verification diagnostics, and qualify successful verified HTTPS against independent fixtures before advertising general HTTPS browsing. The browser keeps verification enabled and displays the failure.

The P-384 implementation is being handled separately. The earlier public-site observations above are historical evidence, not a re-test or claim of a TLS fix in this change.

## Validation

`./win/build test` performs structured checks and strict compilation for the application and every Win test, then exercises:

- CSS selectors, specificity, inheritance, ordering, media queries, box geometry, simplified flex/grid, line height, visibility, and text wrapping.
- Tab ownership, independent realms/history/editors/scroll, tab switching/closure, and pending-loader cleanup.
- Form serialization/validation/reset, keyboard editing, GET/POST transport, prevented submits, and redirect method/body behavior.
- Inline/external scripts, DOM mutation, style/class changes, event bubbling/cancellation, lifecycle, budgets, error recovery, and realm isolation.
- Local/HTTP resources, PNG/JPEG decoding, RGBA ownership/render commands, MIME/UTF-8 errors, redirects, compression, aggregate limits, slow responses, and cancellation.

Native finite-frame screenshot checks additionally exercise CSS backgrounds/borders/grid, tab chrome, form controls, and image texture upload through the GL window. Automated network fixtures use loopback servers; they do not depend on public sites. W's full suite is not required by these application-only edits and was not rerun.
