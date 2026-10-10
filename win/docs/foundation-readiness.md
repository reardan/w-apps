# Win foundation readiness

W is sufficient to start Win's native shell and static-page engine. The next work belongs primarily in this application: document ownership, CSS selector matching and cascade, layout, page painting, input routing, and navigation. Simple scripted fixtures are feasible with the new interpreter, but a browser-quality DOM binding and event callback interface still need integration work.

Assessment date: 2026-10-09. Updated the submodule from `f999538e17d3d1ca3618db67070a6b2bb80b507a` to `731f0919522047bbb8d74d5b7779e3d02e81da7b`, upstream `main` at inspection time. The latter includes [PR 639](https://github.com/reardan/w/pull/639), implementing initial library milestones from [issue 637](https://github.com/reardan/w/issues/637). The W checkout has no tracked source modifications.

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

## Start with these application tasks

1. Add Win's build/run/test wrapper and x64 entry point using `--import-root` for the pinned W checkout. W's normal build generates required font assets; generate its JavaScript parser when scripting is enabled.
2. Build a W UI window with address input, back/reload controls, and a scrollable page viewport. Keep controls and content focus/hit testing separate.
3. Load explicit local UTF-8 HTML files, adapt the static tree into a Win document, and render a default-styled article with headings, paragraphs, links, and wrapped inline text.
4. Consume CSS syntax trees to implement a small selector/property subset, computed styles, block and inline layout, and invalidation on resize or mutation. Syntax parsing alone does not provide any of these behaviors.
5. Connect owned HTTP clients through bounded task/worker scheduling. Add relative navigation, stylesheet/image loading, stop/reload cancellation, and generation IDs that discard old document completions.
6. Bind the interpreter to the document and add a controlled counter/list fixture after documenting the host integration contract below.

No additional upstream foundation is a demonstrated blocker for steps 1–4. Keep the initial target Linux x64; the interpreter requires 64-bit numbers. Build an end-to-end article before expanding compatibility.

## Resolve before event-driven scripting

These are embedding gaps identified by reading the public contract and implementation, rather than failed static-page prerequisites:

- **Host-to-JavaScript invocation:** `js_runtime_eval` is the documented entry point. `js_runtime_call` exists as an internal-style helper, but relies on existing completion/budget/depth state and lacks the evaluation entry point's lifecycle setup. Define a supported call API for a retained function value with arguments, a fresh budget, rooted results, and reentrancy/error behavior before dispatching arbitrary listeners or timers. Re-evaluating generated source on every event would retain a new script AST each time, eventually hitting `max_scripts` (default 1000).
- **Host context and DOM properties:** bound callbacks receive the runtime as context; there is no documented per-binding application context. An application registry keyed by runtime can support an initial bridge. The runtime currently has plain own-data properties, without accessors, prototype chains, or `this`. Native `textContent`/attribute behavior therefore needs a deliberate host-object/property design or an explicitly restricted synchronization adapter. Merely constructing a `document` object does not supply DOM semantics.
- **Execution scheduling:** step exhaustion aborts evaluation with prior side effects visible; it cannot yield and resume. Keep scripts small and bounded, collect between callbacks, and report aborts. Resumable execution or separate content execution is follow-up work for longer scripts. Host callbacks must enforce their own deadlines.
- **Compatibility:** the interpreter rejects `var`, arrows, classes, modules, `new`, async/generators, template literals, regex execution, loose equality, and several numeric operators. Standard built-ins and ordinary prototype behavior are also absent. Use supported `let`/`const` and ordinary functions in early fixtures; do not equate broad parser acceptance with executable support.

Broader JavaScript compatibility remains [issue 492](https://github.com/reardan/w/issues/492). Promote reusable embedding improvements into W as small follow-ups when the first Win bridge makes the requirements concrete.

## Later compatibility work

- HTML has a small named-entity set and partial tree recovery; table foster parenting, adoption-agency recovery, fragment contexts, full script states, encodings, and streaming parsing remain incomplete. CSS syntax still requires full consumer-side selector/value validation.
- Network connections are IPv4 even though URL syntax accepts bracketed IPv6. URL handling lacks IDNA and full browser normalization; `file:` needs Win's separate loader. Explicit HTTP clients each allow one active stream and do not pool connections. Credentials must be handled deliberately across redirects.
- Content decoding buffers before decompression and accepts only the documented identity/gzip/deflate forms. Gzip concatenation/trailing-data semantics need further work for broader compatibility.
- Images exclude progressive JPEG and interlaced/packed/16-bit PNG, among other documented variants; provide placeholders on unsupported results. Color management, EXIF orientation, animation, SVG, and other formats are later work.
- Shaping, bidi, broader native Unicode input and IME remain [issue 459](https://github.com/reardan/w/issues/459). Native accessibility bridges remain [issue 465](https://github.com/reardan/w/issues/465); snapshots alone do not provide screen-reader support.
- Cookies, cache policy, origin enforcement, DOM/web APIs, and content isolation are browser work. General untrusted browsing requires a separately validated isolation design.

## Validation performed

The compiler bootstrap and self-host fixpoint passed locally. The following focused target groups passed on this Linux x64 environment:

```sh
cd w
./wbuild build
./wbuild verify html_64_test css_64_test javascript_runtime_test \
  javascript_text_64_test javascript_embed_example urlparse_64_test \
  http_browser_64_test content_decode_64_test png_64_test \
  graphics_image_jpeg_64_test graphics_ui_image_test \
  graphics_ui_image_smoke_test graphics_ui_accessibility_64_test
./wbuild graphics_ui_core_64_test graphics_ui_widgets_test \
  graphics_ui_render_test graphics_ui_text_font_test graphics_ui_smoke_test
```

Both native smoke probes executed successfully (`graphics ui image OK` and `graphics ui smoke OK`); they did not skip for lack of a display. HTTP tests exercised loopback cancellation, deadlines, redirects, TLS failure, and concurrent clients. JavaScript tests included runtime teardown/memory checks.

A temporary consumer outside both repositories passed structured compiler checking, compilation, and execution using only `--import-root /path/to/w`. It imported HTML, CSS, JavaScript runtime, HTTP content decoding, PNG/JPEG, UI rendering, and widgets together; executed parsing, relative URL resolution, a closure returning 42, and headless rectangle/image painting. This establishes basic cross-module integration, not a completed browser.

The complete W regression suite and Node compatibility oracle were not rerun locally for this submodule update. The upstream PR's reported checks were successful, including full-suite shards, JavaScript compatibility, and native/platform checks. The readiness recommendation rests on the local focused checks and the documented subset contracts.
