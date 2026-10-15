# Win foundation readiness

Win now integrates native tabs, bounded asynchronous document and resource loading, author stylesheet cascade, box layout, PNG/JPEG images, forms, and a mutable DOM with page JavaScript. Run `./win/build run --page win/fixtures/interactive.html` for the combined demo.

The W dependency is pinned to merged main `a5a54fd77eb049d7126db6ce7f1a68e823fa5aca`, containing [W #647](https://github.com/reardan/w/pull/647) and [W #650](https://github.com/reardan/w/pull/650). The application consumes those upstream changes without local W source edits. W supplies HTML/CSS parsing, fonts/widgets/rendering, image codecs, HTTP/TLS, and the generated JavaScript parser/subset interpreter.

## Implemented integration

Each tab owns its document tree, display list, form editor states, stylesheet/resource queue, navigation history, and JavaScript runtime. Async worker results belong to their owning document; navigation, Stop, and tab closure cancel/reap pending workers. Image decoding happens in the worker, while GPU textures are created and released through W's renderer.

Author stylesheet order follows DOM order regardless of download completion. Scripts execute in DOM order after parsing, with one script per poll and deterministic execution/DOM budgets. DOM property hooks apply mutations and reads synchronously; embedded stylesheet changes reconcile at host/evaluation boundaries. Window and Document are distinct event targets, and events invoke rooted callbacks with their current target as receiver. `DOMContentLoaded` follows the initial script queue and `load` follows the full initial resource queue; document replacement frees the realm and all listeners.

[CSS compatibility](css-compatibility.md) and [JavaScript compatibility](javascript-compatibility.md) specify the actual boundaries. These include intrinsic row-flex sizing and shrinking, equal-track grid layouts, a partial CSS property/selector set, and W's language subset rather than full ECMAScript. HTML tree construction/recovery beyond the supported insertion rules, image codec variants, IPv4 transport, text shaping, native accessibility, cookies/cache, and content-process isolation remain broader compatibility work. HTML character references now use W's complete pinned named-reference table and numeric repair rules, including context-sensitive legacy references; this does not complete HTML tree-building conformance. Form limitations are listed in the [README](../README.md).

## HTTPS compatibility

The previous public-site failure was traced to missing P-384 issuer signature
verification. The merged W dependency now supports P-384 X.509 signatures and
TLS `ecdsa_secp384r1_sha384` CertificateVerify, and preserves specific verification
errors in HTTP responses. Linux uses the host CA bundle; verification remains
enabled. The old failure is historical evidence, not a current unresolved P-384
gap.

[W's network contract](../../w/docs/projects/browser_network.md#https-trust-and-compatibility)
records upstream offline vector/chain/handshake tests and verified live Linux
connections. Those upstream results are separate from this repository's local
validation. This integration also successfully loaded `https://example.com/`
through Win's verified client on Linux x64 on October 15, 2026. TLS still
requires TLS 1.3, ChaCha20-Poly1305 and X25519; not every
certificate algorithm, extension, or chain-building strategy is implemented.

## Validation

`./win/build test` performs structured checks and strict compilation for the application and every Win test, then exercises:

- HTML character references reaching titles, rendered text, and link targets, including multi-codepoint names, legacy longest matching, numeric Windows-1252 repair, and attribute ambiguity rules in `win/tests/browser_test.w`.
- CSS selectors, specificity, inheritance, ordering, media queries, box geometry, intrinsic flex sizing/shrinking, equal-track grid, line height, visibility, and text wrapping.
- Tab ownership, independent realms/history/editors/scroll, tab switching/closure, and pending-loader cleanup.
- Form serialization/validation/reset, keyboard editing, GET/POST transport, prevented submits, and redirect method/body behavior.
- Inline/external scripts, synchronous DOM mutation, inline CSSOM/shorthand operations, stylesheet mutations, event receivers and Window propagation, separate lifecycle readiness, budgets, error recovery, and realm isolation.
- Local/HTTP resources, PNG/JPEG decoding, RGBA ownership/render commands, MIME/UTF-8 errors, redirects, compression, aggregate limits, slow responses, and cancellation.

The optional native GL pixel regression, `xvfb-run -a python3 win/tests/rendering.py win/bin/win /tmp/win-layout.ppm`, exercises percentage flex sizing/gaps, intrinsic control width, CSSOM shorthand margin mutation, fixed-height flow, and visible overflow using `win/fixtures/layout.html`. It also runs directly on an X11 display without `xvfb-run`. Other finite-frame screenshot checks can exercise tab chrome and image texture upload. Automated network fixtures use loopback servers; they do not depend on public sites. See [integration validation](standards-implementation-status.md#validation) for the results recorded for this dependency pin and application tree.
