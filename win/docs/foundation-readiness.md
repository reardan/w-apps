# Win foundation readiness

Win now has a runnable first browser milestone: a native W UI shell, bounded asynchronous local/HTTP loading, static HTML text layout, basic inline CSS, links, fragments, history, scrolling, reload, and stop. Run `./win/build run` from the repository root. Scripts, stylesheet cascade, images, forms, and tabs are not implemented yet.

Assessment updated after pulling both repositories' main branches. The W pin is now `f63d97aea815b3541ab78dd195ef8e1b17b4c30f`, incorporating [PR 640](https://github.com/reardan/w/pull/640) on top of [PR 639](https://github.com/reardan/w/pull/639). New foundations include retained JavaScript function invocation, HTML script escaped states, CSS URL tokens, canonical IPv6 hosts, and strict concatenated-gzip decoding. No tracked W source files were modified.

## Available now

| Foundation | Ready capability | Win integration needed |
| --- | --- | --- |
| [HTML](../../w/docs/projects/html.md) | Explicit-length parsing, owned static tree, spans, diagnostics, limits, raw/RCDATA content, initial recovery | Validate/repair UTF-8 input, map borrowed parser nodes into application document ownership; keep mutable DOM separate |
| [CSS](../../w/docs/projects/css.md) | Tokens, selector component groups, stylesheet/declaration trees, escapes, balanced blocks, recovery | Validate supported selectors and property values, match selectors, compute specificity/cascade/inheritance, and resolve values |
| [JavaScript](../../w/docs/projects/javascript.md) | Parser, lowerer, UTF-16 values, 64-bit subset interpreter, host callbacks, roots and cyclic collection, limits | One realm per document, DOM host bindings, script ordering, event/timer dispatch, error presentation |
| [Networking](../../w/docs/projects/browser_network.md) | Relative URLs/fragments, origin comparison, owned clients, total deadlines, cancellation, redirect approval, final URL, bounded decoding | Loader scheduler, local files, MIME/encoding decisions, redirect/credential policy, aggregate page budgets, stale-result handling |
| [Images](../../w/docs/projects/images.md) | Bounded PNG/baseline JPEG decoding; RGBA textures, alpha, scaling, clipping, ordered painting | Resource cache, intrinsic image sizing, decode-worker ownership transfer, unsupported-format placeholders |
| [W UI](../../w/graphics/ui/widgets.w) | Native widgets, fonts, text, window events, clipping, headless and native rendering | Browser controls and viewport; custom document layout and hit testing |
| [Accessibility boundary](../../w/docs/projects/browser_ui.md) | Bounded semantic snapshots and validated actions | Populate document/control semantics; native screen-reader bridges remain upstream work |

HTML and CSS are maintained handwritten W libraries with token/syntax specifications, not generated `.pg` consumers. Reuse these APIs directly. JavaScript uses the generated parser; build it with `./wbuild javascript_parser` inside W before compiling a consumer. The [upstream integration map](../../w/docs/projects/win_browser_foundations.md) describes ownership and build boundaries.

## Implemented application slice

The executable, build wrapper, fixtures, and tests now live under `win/`. The document owns W's static HTML tree and a separate list of laid-out text runs. It uses W fonts for measurement, W UI for controls and drawing, W CSS parsing for a small inline subset, and owned W HTTP clients in loader child processes. Navigation replaces or cancels the previous loader; the parent never applies an old loader's result.

The application has local and HTTP navigation, fragment scrolling, bounded history with scroll restoration, default HTML element styling, inline wrapping, link hit testing, a dynamic address editor, and readable errors. It has headless loading/layout and finite-frame native screenshot modes. See [run instructions and exact limitations](../README.md).

Next application steps are full selector/cascade/computed-style support, block/inline box layout, image resource integration, tabs, then mutable DOM and scripting. The current static-tree adapter does not yet implement a mutable DOM. It also does not execute page scripts or apply linked stylesheets.

## Resolve before event-driven scripting

These are embedding gaps identified by reading the public contract and implementation, rather than failed static-page prerequisites:

- **Host-to-JavaScript invocation is now available:** `js_runtime_invoke` sets up fresh completion/budget/depth state and calls a retained closure without parsing or retaining another script. Its focused invocation and memory tests passed locally at the new pin. Root host-retained callbacks/arguments across collection; Win still needs to wire this API into event/timer dispatch.
- **Host context and DOM properties:** bound callbacks receive the runtime as context; there is no documented per-binding application context. An application registry keyed by runtime can support an initial bridge. The runtime currently has plain own-data properties, without accessors, prototype chains, or `this`. Native `textContent`/attribute behavior therefore needs a deliberate host-object/property design or an explicitly restricted synchronization adapter. Merely constructing a `document` object does not supply DOM semantics.
- **Execution scheduling:** step exhaustion aborts evaluation with prior side effects visible; it cannot yield and resume. Keep scripts small and bounded, collect between callbacks, and report aborts. Resumable execution or separate content execution is follow-up work for longer scripts. Host callbacks must enforce their own deadlines.
- **Compatibility:** the interpreter rejects `var`, arrows, classes, modules, `new`, async/generators, template literals, regex execution, loose equality, and several numeric operators. Standard built-ins and ordinary prototype behavior are also absent. Use supported `let`/`const` and ordinary functions in early fixtures; do not equate broad parser acceptance with executable support.

Broader JavaScript compatibility remains [issue 492](https://github.com/reardan/w/issues/492). Promote reusable embedding improvements into W as small follow-ups when the first Win bridge makes the requirements concrete.

## Later compatibility work

- HTML has a small named-entity set and partial tree recovery; table foster parenting, adoption-agency recovery, fragment contexts, encodings, and streaming parsing remain incomplete. CSS syntax still requires full consumer-side selector/value validation.
- Network connections are IPv4 even though URL syntax accepts bracketed IPv6. Canonical IPv6 host handling is now supplied, but URL handling still lacks IDNA and full browser normalization; `file:` needs Win's separate loader. Explicit HTTP clients each allow one active stream and do not pool connections. Credentials must be handled deliberately across redirects.
- Content decoding buffers before decompression and accepts only the documented identity/gzip/deflate forms. Registered gzip/deflate now validate full input; concatenated gzip members share the expanded-byte budget. Streaming decompressed output remains future work.
- Images exclude progressive JPEG and interlaced/packed/16-bit PNG, among other documented variants; provide placeholders on unsupported results. Color management, EXIF orientation, animation, SVG, and other formats are later work.
- Shaping, bidi, broader native Unicode input and IME remain [issue 459](https://github.com/reardan/w/issues/459). Native accessibility bridges remain [issue 465](https://github.com/reardan/w/issues/465); snapshots alone do not provide screen-reader support.
- Cookies, cache policy, origin enforcement, DOM/web APIs, and content isolation are browser work. General untrusted browsing requires a separately validated isolation design.

## Public HTTPS follow-up

The application successfully loaded `http://example.com/` in a live check. `https://example.com/` and a direct W TLS probe against `www.cloudflare.com` failed certificate verification, while curl/OpenSSL verified example.com successfully in the same environment. An independent W X.509 probe of the captured chain reported `x509: signature verification failed`.

The captured chain includes P-384 intermediate/root public keys. W's current `x509_check_signature` supports RSA and EC P-256 issuer keys, so P-384 verification is a concrete upstream compatibility gap for this chain. The generic HTTP error currently loses the more specific X.509 reason. Add P-384 chain support, preserve detailed verification diagnostics, and qualify successful verified HTTPS against independent fixtures before advertising general HTTPS browsing. The browser keeps verification enabled and displays the failure.

## Validation performed

The updated W dependency passed `build`, `javascript_runtime_invoke_test` (including its memory mode), `html_64_test`, `css_64_test`, `urlparse_64_test`, and `content_decode_64_test`. The previous pin's foundation/UI checks remain historical evidence; they are not a claim that every upstream test was rerun at this pin.

`./win/build test` passes structured checks and strict compilation, then runs:

- W tests for HTML visibility, inline CSS, UTF-8 rejection, wrapping, oversized words, link hit testing, relative URLs, fragments, history/scroll restoration, failed and cancelled navigation, replacement requests, and headless painting.
- Synthetic W UI events for Back, content links, mouse-wheel scrolling, Ctrl+L selection, and Enter navigation.
- Local/HTTP integration with a loopback server for gzip members, redirects/final fragments, error statuses, invalid compression, unsupported MIME, input/expansion limits, and file paths with spaces.
- A deliberately stalled server while the UI renders thirty frames, followed by bounded Stop and child cleanup.

The W application tests also passed with `W_DEBUG_ALLOC=1`. A finite-frame native run rendered the start page and saved a screenshot; it was visually inspected. Public HTTP worked; the HTTPS failure is recorded above. Live website checks are manual and are not required by the automated suite.

The full upstream regression suite and Node compatibility oracle were not rerun for this application-only change. No W compiler or library sources were edited.
