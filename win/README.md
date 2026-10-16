# Win browser

Win is a native browser written in W. It opens local and HTTP/HTTPS documents with tabs, stylesheet cascade and box layout, PNG/JPEG images, editable forms, and bounded page JavaScript. Its CSS and JavaScript engines support documented subsets; full modern website compatibility remains future work.

## Run

Linux x64 with an X11/OpenGL display is the supported target. From the repository root:

```sh
git submodule update --init --recursive
./win/build run
./win/build run --page win/fixtures/interactive.html
./win/build run --page win/fixtures/standards.html
./win/build run --page http://example.com/
```

The wrapper works from other working directories, bootstraps the pinned W compiler/font assets, generates the JavaScript parser, and builds `win/bin/win`. Relative `--page` paths resolve from your working directory. The first compiler bootstrap downloads W's pinned seed.

Ctrl+L selects the address; Enter or Go navigates. Ctrl+T or **+** opens a tab, Ctrl+W closes it, and Ctrl+Tab/Ctrl+Shift+Tab switches tabs. Ctrl-clicking a link or following `target="_blank"` opens another tab. Each tab retains its own document, address editor, history, scroll state, resource queue, and JavaScript realm. Closing the last tab opens the home page.

Back/Forward restore history and scroll. Stop cancels pending document and resource workers. The mouse wheel and scrollbar move through the page. Tab/Shift+Tab navigate page controls; Enter submits a text field or activates a button, and Space activates buttons/choices.

HTTPS uses W's verified TLS client with the host CA bundle. The merged dependency includes P-384 certificate and handshake signature support, addressing the previously observed chain-verification gap. See [HTTPS compatibility](docs/foundation-readiness.md#https-compatibility) for the remaining transport boundaries.

## Features and compatibility

The [web application execution milestone](docs/web-app-compatibility.md) adds
bounded wasm execution, binary fetch and typed arrays, static modules, animation
frames, and native canvas WebGL rendering. The original W web host still needs
additional JavaScript/browser features; use the documented Promise-based demo
fixture for the implemented path.

- **CSS:** embedded and linked stylesheets, inline declarations, attribute and filtered structural selectors, forgiving `:is()`/`:where()` lists, specificity, `!important`, inheritance, media width queries, RGB/HSL colors with missing components, text styling, box dimensions, margins, padding, backgrounds, functional border colors, intrinsic row-flex sizing/shrinking, explicit row flex factors/basis, wrapped rows, column flow, main/cross-axis alignment, and equal-track grid layouts. [Exact CSS compatibility](docs/css-compatibility.md).
- **Images:** intrinsic/aspect-ratio layout, HTML/CSS sizing, scaling, clipping, alpha, and alt-text fallback. Decoding runs in resource processes; texture upload occurs on the rendering thread. W supports non-interlaced 8-bit PNG and baseline JPEG. Progressive JPEG, SVG, GIF, WebP, animation, and data URLs are unsupported.
- **Forms:** text/password fields, textareas, checkboxes, radio groups, single selects, submit/reset buttons, required fields, disabled/readonly controls, and URL-encoded GET/POST. Duplicate names and successful-control order are preserved. Submit and click handlers can cancel default actions. Single selects cycle through enabled options when activated. File uploads, multiple selects, multipart encoding, specialized date/number widgets, and full constraint validation are unsupported. Change events currently fire with each edit. History stores URLs; returning to or reloading a POST result fetches that URL with GET.
- **JavaScript:** ordered classic inline/external scripts, per-page interpreter state, DOM queries and mutations, styles/classes, capture/target/bubble events, once/passive listeners, canceled default actions, lifecycle events, synchronous DOM properties, inline CSSOM methods, bounded console storage, timers, Promise microtasks, origin-scoped memory storage, and same-origin GET fetch with response text. W's interpreter supports `let`/`const`/`var`, ordinary functions, synchronous arrows, and method/event receivers; it does not execute full ECMAScript. [Exact JavaScript compatibility](docs/javascript-compatibility.md).
- **Loading:** final-URL/base-relative resources, three concurrent subresource workers per page (plus up to three Fetch workers), MIME/UTF-8 checks, gzip/deflate, bounded decoding, deadlines, and cancellation. Cross-origin HTTP(S) stylesheets/scripts/images are allowed; HTTPS pages reject HTTP subresources and resource redirects cannot downgrade HTTPS. Web pages cannot load native files.

Cookies and explicitly fresh HTTP responses now have bounded in-memory state; see [network compatibility](docs/network-compatibility.md). DOM insertion and resource URL changes trigger bounded resource discovery, with stale loads canceled. Persistent cache/storage, downloads, session restoration, complete web APIs remain future work. Opt-in interactive isolation is available with documented snapshot limitations. Loader processes isolate blocking I/O and image decoding; interactive scripts execute with deterministic interpreter/DOM budgets inside the application process. `--isolated-dump` executes the entire page in a separate process with a watchdog and validated text output; see [headless process isolation](docs/script-isolation.md). This process boundary does not restrict the worker's OS authority.

## Check and test

```sh
./win/build check
./win/build test
./win/build standards
./win/build run --dump --page win/fixtures/interactive.html
./win/build run --isolated-dump --page win/fixtures/interactive.html
./win/build run --page win/fixtures/css.html --frames 40 --screenshot /tmp/win.ppm
# Optional native GL pixel regression (requires Xvfb, or omit xvfb-run on X11):
xvfb-run -a python3 win/tests/rendering.py win/bin/win /tmp/win-layout.ppm
```

`--dump` waits for initial resources and scripts, then emits the rendered text headlessly. Screenshots use the actual native GL window and write PPM. Tests need Python 3, no third-party packages, and no public-site access. `./win/build standards` additionally runs pinned Test262 variants through W and unmodified static WPT reftests through native GL; it requires X11/OpenGL or `xvfb-run`. Reports preserve unsupported cases separately from passes. See the [WPT adapter contract](tests/wpt/README.md) and [Test262 adapter contract](../w/tests/javascript/test262/README.md). The suite covers cascade/layout, image pixels/rendering, script ordering and events, form editing/GET/POST/redirects, tab isolation, navigation, cancellation, slow-server responsiveness, malformed content, and resource budgets.

The `standards.html` fixture demonstrates filtered sibling selectors, forgiving
selector lists, RGB/HSL border colors, DOM `matches()`/`closest()`, and a form event
trace with capture, target, bubble, and once listeners. Its loading, computed
colors/borders, DOM queries, and canceled form submissions are covered by the
browser integration suite. Focused regressions also cover strict selector-list
errors, specificity, border resets, and nested selector budgets. These are tested
compatibility increments; complete CSS and ECMAScript conformance remains future
work. The pinned W dependency includes the Test262 adapter and expands the bounded language/runtime foundation;
see the [integration status](docs/standards-implementation-status.md) for the
implemented scope and remaining work.

HTML is UTF-8 with a 1 MiB source/20,000-node limit. A page accepts at most 64 subresources, 16 MiB aggregate text resources, and 64 MiB decoded images. Each image allows 4 MiB input, 4096 pixels per dimension, and 16 MiB RGBA. HTTP workers have a 10-second total deadline and a 12-second parent watchdog. Tabs are limited to 32, histories to 128 entries, controls to 512, and encoded form data to 64 KiB. See the JavaScript compatibility document for interpreter and DOM limits.

The [implementation plan](docs/implementation-plan.md) records the architecture and longer-term milestones.
