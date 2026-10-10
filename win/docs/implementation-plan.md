# Win browser implementation plan

Build Win as a native browser written in W. Reuse W's HTML/CSS libraries, generated JavaScript parser and interpreter, and `graphics.ui` for browser controls, text, and rendering. Implement Win's document model, CSS layout, and script bindings as separate, testable components.

The first release target is a small browser that renders local documents and selected HTTP/HTTPS pages, follows links, applies a documented CSS subset, and runs simple interactive JavaScript examples. Begin on Linux x64 with X11; expand platform support after the engine works. Full modern website compatibility is a longer-term goal.

All paths in code blocks are relative to the `w-apps` repository root unless stated otherwise. Proposed files and commands below are implementation work, not existing browser functionality.

## W foundations and gaps

Baseline: W at `731f0919522047bbb8d74d5b7779e3d02e81da7b`. The [readiness assessment](foundation-readiness.md) records the verified capabilities and remaining gaps. This revision is sufficient to start the native shell and static-page engine; keep reusable foundations in W and implement browser behavior here.

| Area | Existing W foundation | Win work |
| --- | --- | --- |
| HTML | [Owned tokenizer and static trees](../../w/docs/projects/html.md), spans, recovery, limits | Input normalization, document adapter, mutable DOM and fragment integration |
| CSS | [Stylesheet and declaration syntax](../../w/docs/projects/css.md), selector component groups | Selector validation/matching, cascade, computed styles |
| JavaScript | [Parser, AST, UTF-16 and subset interpreter](../../w/docs/projects/javascript.md) | DOM bindings, script order, callbacks, timers, compatibility policy |
| Grammar tooling | [Stateful ParserGenerator](../../w/docs/projects/parser_generator.md), ownership and limits | Reuse generated JavaScript parser; extend only for demonstrated gaps |
| Browser controls | [UI widgets](../../w/graphics/ui/widgets.w), [shell example](../../w/graphics/ui/demo_shell.w) | Address bar, navigation, tabs, status, inspector |
| Painting and images | [Renderer](../../w/graphics/ui/render.w), [PNG/JPEG and RGBA images](../../w/docs/projects/images.md) | Page display list, paint order, resource ownership, hit testing |
| Text | [Fonts](../../w/graphics/ui/font.w), [styled UTF-8 text](../../w/graphics/ui/text.w) | Inline formatting, wrapping, selection; later shaping and bidi |
| Network | [Owned HTTP clients and bounded decoding](../../w/docs/projects/browser_network.md) | Scheduling, aggregate page budgets, origin and redirect policy |
| URLs | [Reference resolution and fragments](../../w/libs/standard/web/urlparse.w) | Navigation semantics, local-file loader, broader normalization |
| Semantics | [Accessibility snapshots](../../w/docs/projects/browser_ui.md) | Populate controls/page trees; native bridges remain upstream |
| Toolchain | [Explicit import roots](../../w/docs/projects/compilation_model.md#71-resolution-order) | App build/test wrapper and generated dependency preparation |

HTML and CSS now have maintained handwritten W implementations and token/syntax specifications. They need no `.pg` generation. JavaScript uses W's generated parser. Do not create parallel parsers or an interpreter in Win for the support already supplied upstream.

## Architecture

```text
W window and events
        |
Win shell: address bar, navigation, tabs, inspector
        |
Navigation controller ---- Resource loader ---- W HTTP and TLS
        |                       |
        |                   source bytes
        v                       v
Document session <---- HTML tokenizer and tree builder
        |                       |
        |                      DOM <---- JavaScript host bindings
        |                       |                  ^
        |                 CSS cascade              |
        |                       |          JS parser and interpreter
        |                  layout boxes            |
        |                       |           event loop and timers
        +----------------> display list
                                |
                      W UI rendering adapter
```

The shell uses W widgets directly. The page viewport has its own retained DOM and layout tree, painted through W's rendering primitives. Do not equate an HTML element with a UI widget: CSS sizing, nesting, inline fragments, and paint order require a document engine. Reuse widget input behavior for early form controls through an adapter that respects the page's computed bounds and clipping.

Keep HTML parsing, CSS matching, layout, and JavaScript evaluation independent of a GL context. The same document engine must run in headless tests. A future wasm build can be a demonstration target, but must still exercise Win's engine.

### Ownership and execution

- A browser owns tabs. Each tab owns its navigation history and active document session. A session owns sources, DOM nodes, styles, layout, script realm, resource handles, and diagnostics.
- Use stable node IDs and document generations in script wrappers, hit records, and asynchronous responses. Navigation invalidates the old generation; late results cannot modify the replacement page.
- Parser documents own temporary tokens and parse trees. Lower them to typed browser structures with source spans and explicit lifetimes, following the explicit ownership contracts of W's HTML, CSS, and JavaScript APIs.
- DOM mutation marks style, layout, or paint dirty. Initially recompute a whole document when dirty; introduce smaller invalidation regions after profiling.
- The UI thread owns document mutation and painting. Use bounded task/worker scheduling for resource work, with explicit owned HTTP clients. Serialize each client; separate clients can run concurrently. Avoid the legacy global-cache path and do not run synchronous CPU/decoding work unbounded in a frame callback.
- Use bounded event queues, request deadlines, parser work limits, DOM/heap limits, and interpreter step budgets. Stop and close-tab must remain responsive during a stalled request or looping script.

## Web language front ends

### Shared parsing boundary

Consume W's public document APIs through thin Win adapters. HTML/CSS results own their source and borrowed nodes; convert them to typed browser structures where mutation or independent lifetimes are needed. JavaScript uses the existing parser, lowerer, and runtime. Keep source spans and diagnostics available to the inspector.

Build W's generated JavaScript parser in the dependency checkout before compiling script consumers. HTML/CSS require no generation step. Pin any additional imported fixtures and preserve their licenses; extend upstream grammars/libraries with deterministic tests rather than forking their implementations here.

### HTML

Call `html_parse_with_limits` after explicit input decoding/UTF-8 normalization. The existing static tree supplies implied document elements, attributes, text, a limited entity set, raw/RCDATA content, and initial malformed-markup recovery. Adapt it to Win's document model with stable node IDs. Retain unknown ordinary elements.

The initial renderer supports UTF-8 articles with headings, paragraphs, lists, links, preformatted text, and simple controls. Keep the supported parser boundary visible: full table recovery, formatting reconstruction, script escaped states, fragment contexts, encoding sniffing, and streaming resume remain upstream compatibility work. Implement `innerHTML` only after fragment parsing is specified and tested.

### CSS

Use `css_parse_stylesheet_n`, `css_parse_declarations_n`, and their token/component ranges. The syntax API does not validate full selectors or property values. Win validates the supported subset before matching or applying it, while retaining useful source diagnostics.

Implement selector matching, specificity, source order, inheritance, initial values, and computed values as separate steps. Keep a browser default stylesheet distinct from the shell theme. Account for inline declarations and `!important`; unsupported selector components must not accidentally broaden a rule.

Start with type, universal, class, ID, descendant, child, and grouped selectors. Add `:hover` and `:focus` when interaction lands. Support block/inline/none display, width, height, margin, padding, borders, colors, basic font properties, line height, text decoration, and normal/pre whitespace. Begin with `px`, `%` where containing dimensions are defined, `em`, and supported `auto` cases. Test margin collapse and anonymous inline boxes independently of UI widget layout.

### JavaScript

Use `libs.extras.javascript.runtime` on x64, with one instance per document. W already provides binary64 numbers, UTF-16 values, ordinary functions/closures, objects/arrays, control flow, completion results, host callbacks, and rooted cyclic collection. Preserve its ownership rules: collect between evaluations, root host-retained values, and release the instance on navigation.

The executable subset is narrower than parser acceptance. Use `let`/`const` and ordinary functions in initial fixtures. `var`, arrows, classes, modules, `this`, prototypes/accessors, standard built-ins, async/generators, templates, and regex execution are outside the current runtime contract. W rejects unsupported syntax before execution; do not silently emulate different semantics in Win.

Resolve the [embedding gaps](foundation-readiness.md#resolve-before-event-driven-scripting) before M6: a supported host-to-JavaScript callback entry point with fresh budget/completion setup, application context, and DOM property behavior. Budget exhaustion is a terminal abort, not a resumable execution slice. Host callbacks need their own bounded work/deadline policy.

Expose `console.log`, selected document lookup/creation APIs, `textContent`, attributes, append/remove operations, event listeners, and timers through that bridge. Add event capture/target/bubble phases and default actions for supported events. Begin with classic scripts at the end of `body`; parser suspension and classic external script ordering need a separate integration design because the existing HTML parser produces a completed static tree. Stage `async`, `defer`, modules, promises, `fetch`, `eval`, and `document.write` as later compatibility work.

## Initial product scope

| Area | First interactive milestone | Later expansion |
| --- | --- | --- |
| Navigation | One window, tabs, address bar, back/forward, reload/stop, link and fragment navigation | Session restore, downloads, bookmarks |
| Content | Headings, paragraphs, div/span, lists, links, preformatted text, style/link/script, basic controls | Tables, embedded documents, richer forms |
| Layout | Block flow, inline text wrapping, box model, viewport scrolling | Flexbox, grid, positioning, floats, nested scrolling |
| Text and images | Bundled fonts, supported UTF-8 glyphs, styled text; supported PNG/JPEG through W APIs | More image variants/formats, shaping, bidi, web fonts |
| Scripts | Documented interpreter subset and DOM event demos | Broader ECMAScript and web APIs |
| Resources | UTF-8 HTML/CSS/JS from explicit local files and HTTP/HTTPS; bounded identity/gzip/deflate | More encodings, streaming decompression, persistent cache, cookies |
| Platforms | Linux x64/X11 | macOS, Windows, then optional wasm demonstration |

Use W's PNG/baseline JPEG decoders and RGBA painting APIs. Supply placeholders with alt text and explicit dimensions for unsupported image variants. Decode off the UI path, then transfer owned pixels to the rendering thread for texture creation and release.

## Implementation milestones

### M0 Establish build and engine test boundaries

- Add the W entry point, build wrapper, generated-output directory, and headless test runner. Use explicit import roots for Win source and W.
- Bootstrap the pinned W compiler, prove a small native UI window and a headless render test, and compile an external consumer of W's HTML/CSS APIs and generated JavaScript parser.
- Define resource-loader and clock interfaces with deterministic fakes. Add fixture formats for DOM, styles, boxes, and diagnostics.

Exit: a fresh checkout can initialize the submodule, build a window, prepare generated dependencies, and run a headless fixture without modifying tracked W files.

### M1 Native browser shell and local documents

- Reuse W textbox, button, scroll, tab, and menu widgets for the shell.
- Implement tab/session ownership, explicit local-file loading, navigation generation IDs, loading/error views, and basic history.
- Initially paint source/plain text through the page viewport to prove resizing, scrolling, focus, and chrome/content event separation.

Exit: open two local files in separate tabs, switch and close tabs, navigate history, and resize without leaking sessions or losing address-bar input.

### M2 HTML to DOM to readable pages

- Adapt W's HTML static tree into Win document storage, preserving source spans and diagnostics; add UTF-8 validation and stable node identities.
- Add default element styling, block layout, inline fragments, text measurement/wrapping, paint commands, and hit testing.
- Add link activation, fragment targets, viewport scrolling, and relayout on resize.

Exit: a local article fixture containing headings, paragraphs, nested inline text, lists, entities, and links renders and navigates correctly. Malformed HTML fixtures produce stable expected DOM trees.

### M3 CSS styling and layout

- Consume W's CSS syntax trees, validate selectors/property values, and implement matching, cascade, and computed styles.
- Load inline and local linked stylesheets; preserve stylesheet order independently of completion order.
- Implement the scoped box model and text properties, dirty flags, and inspector views for matched rules and computed values.

Exit: styled article and form fixtures match expected computed styles, layout coordinates, and selected render probes at two viewport widths. One invalid declaration leaves neighboring valid declarations effective.

### M4 HTTP and HTTPS navigation

- Integrate W's URL resolution, fragments, final response URLs, owned clients, and content decoding. Add MIME/encoding decisions, aggregate page budgets, and scheduling for CSS, scripts, and images.
- Use W's redirect approval callback so each hop is policy-checked and the final URL becomes the document base. Resolve against `<base href>` when supported.
- Preserve certificate verification and configure checked total deadlines, byte caps, and cancellation. Add page-level request/concurrency limits and safe credential handling across redirects.
- Keep the UI responsive through worker messages; reject stale navigation completions. Defer cookies and disk cache; use a bounded memory cache only where its key and lifetime are defined.

Exit: a local test server serves a linked site over HTTP and HTTPS. Verify relative links, redirects, bad certificates, missing assets, oversized bodies, slow responses, and stop/reload races without freezing the shell.

### M5 Integrate the JavaScript runtime

- Generate W's parser dependency and instantiate its interpreter through a Win script adapter. Preserve source diagnostics, ownership, and the documented subset.
- Define realm lifecycle, host callback context, retained-function invocation, DOM property semantics, and terminal limit handling. Upstream reusable API improvements when needed.
- Add a small console/host fixture, script compatibility table, and tests for roots, document teardown, callback errors, and limits.

Exit: Win evaluates supported scripts and calls a host function. A retained closure can be dispatched with fresh execution state through a tested interface; unsupported constructs and limits produce explicit diagnostics.

M5 can begin after M0. Browser integration still depends on M2's DOM ownership and M3's invalidation behavior. W's standalone interpreter tests are existing dependency validation, not an unimplemented engine milestone.

### M6 Interactive pages

- Bind the JavaScript realm to its document through stable node handles. Add supported DOM APIs, event dispatch, timers, and classic script scheduling.
- Connect input changes and DOM mutations to style/layout invalidation; paint after bounded script/event work.
- Add console and resource diagnostics using W UI widgets. Cancel listeners, timers, and outstanding work when a document is replaced.

Exit: a counter and a small editable list run entirely from HTML/CSS/JavaScript loaded by Win. Clicks and keyboard input update the DOM and repaint. Tab focus, reload, stale callbacks, and detached-node access have deterministic tests.

### M7 Broader compatibility and release readiness

- Expand image variants, layout features, script semantics, accessibility bridges, and platform validation in independently tested increments; basic image decoding/painting already comes from W.
- Before enabling general untrusted scripted browsing, separate content execution from the shell with validated messages and OS-enforced restrictions. W's process API supplies lifecycle primitives; sandbox policy is additional work.
- Define same-origin and local-file boundaries from M4 onward. Initially block unsupported cross-origin subresources and web access to local files; later add tested CORS, cookie, storage, and mixed-content policies as their APIs land.
- Keep privileged browser controls outside content hit testing and clipping. An interpreter's step budget is not a substitute for process isolation or memory safety.

Exit: publish a precise compatibility matrix backed by fixtures, verify failure isolation and resource limits, and validate each advertised platform. Wider website support grows only as its features pass tests.

## Proposed repository layout

```text
win/
  docs/                     architecture, plan, compatibility notes
  main.w                    native executable entry point
  build                     build, generate, test, and run wrapper
  src/win/
    app/                    shell, tabs, navigation, history
    platform/               window, input, loader worker adapters
    net/                    URL resolution, resource loading, policy
    dom/                    nodes, documents, mutation, events
    html/                   W parser adapter and input normalization
    css/                    W syntax adapter, selectors, cascade
    layout/                 boxes, inline formatting, sizing
    paint/                  display list, W renderer adapter, hit tests
    js/                     W runtime adapter, realms, host context
    web/                    document bindings, event loop, timers
  tests/                    W unit and integration tests
  fixtures/                 page sources and expected engine results
  bin/                      ignored application binaries and test output
```

Keep browser code in this repository. Promote reusable grammar/runtime/UI improvements into W through separate changes, then advance the submodule pin. Do not copy W's standard library into Win or assume W's test discovery will cover the sibling `win/` tree.

Dependency preparation works now from the repository root:

```sh
git submodule update --init --recursive
(cd w && ./wbuild build javascript_parser)
```

After M0 creates `win/main.w` and `win/src`, use:

```sh
mkdir -p win/bin
w/bin/wv2 x64 --import-root win/src --import-root w win/main.w -o win/bin/win
w/bin/wv2 x64 check --json --import-root win/src --import-root w win/main.w
```

The wrapper must resolve paths from its own location and prepare generated W dependencies before compiling. W's build supplies font assets; its `javascript_parser` target supplies the parser module. W source uses tabs for indentation. Keep binaries/generated outputs ignored and own Win test discovery in this repository.

## Validation and progress tracking

Every milestone must ship an executable example and automated checks. Maintain a compatibility table with separate columns for parsed, executed or rendered, tested, and unsupported behavior; a green parser test alone does not establish working browser support.

- Parser tests cover valid input, recovery, malformed encodings, EOF, source locations, depth limits, and adversarial backtracking. Store expected DOM/AST structures, not just success flags.
- Style and layout tests assert computed values and box/fragment coordinates. Use pinned fonts, viewport sizes, and scale factors for deterministic results.
- Painting tests use W's headless renderer for geometry and clipping, plus a smaller native screenshot/pixel suite. Test text measurement and painting against the same font metrics.
- Network integration uses controlled local servers and explicit fixture trust stores. No ordinary unit test depends on a live public site.
- JavaScript tests exercise semantics, collection, limits, script order, and DOM lifetime. Adopt pinned subsets of language and web conformance tests with license notices and explicit expected failures as coverage expands.
- End-to-end tests drive address entry, navigation, focus, tabs, scrolling, and scripted updates. Track parse/style/layout/paint time, peak document memory, frame latency, and cancellation latency on fixed fixtures; set budgets after M2 establishes measurements.
- For Win changes, run its focused checks and headless suite plus relevant native smoke tests. For changes inside W, follow its own `AGENTS.md` checks and required regression suite before advancing the pin.

The first implementation slice is M0 followed by M1 and a small M2 article fixture. That establishes the native W application, parser integration, document ownership, and rendering path before the larger CSS and JavaScript work.
