# Win browser

Win is an early native browser written in W. It opens local HTML files and HTTP pages in a W UI window, lays out readable text, and supports links, history, fragments, scrolling, resizing, reload, and stop. This is the first executable milestone, with a small inline CSS subset and scripts disabled.

## Run

Linux x64 with an X11/OpenGL display is the supported target. From the repository root:

```sh
git submodule update --init --recursive
./win/build run
./win/build run --page /absolute/path/to/document.html
./win/build run --page http://example.com/
```

The wrapper works from other working directories too. It bootstraps the pinned W compiler and required font assets, builds `win/bin/win`, and opens the included start page. Relative `--page` paths resolve from your working directory. The first compiler bootstrap downloads W's pinned seed.

Enter a full HTTP/HTTPS address or native file path in the address field. Ctrl+L selects the address; Enter or Go navigates. The mouse wheel and scrollbar move through the page. Back and Forward restore document history and scroll position. Stop terminates a pending loader without discarding the current page.

HTTPS is wired to W's verified TLS client but is not yet generally interoperable: live checks against `example.com` and `www.cloudflare.com` failed certificate verification. The captured example.com chain includes P-384 issuer keys, while W's current EC certificate verification supports P-256. See the [readiness assessment](docs/foundation-readiness.md#public-https-follow-up). Certificate verification remains enabled.

## Check and test

```sh
./win/build check
./win/build test
./win/build run --dump --page win/fixtures/article.html
./win/build run --frames 25 --screenshot /tmp/win.ppm
```

Tests require Python 3 for local HTTP fixtures, with no third-party packages or live public-site dependency. The W tests exercise document geometry, link hit testing, history, scroll restoration, keyboard submission, widget clicks, and cancellation. The HTTP suite covers redirects, concatenated gzip, malformed compression, size limits, content types, and a slow server while the UI continues drawing. `--dump` runs loading and layout headlessly. Screenshot capture uses the actual native GL window and writes PPM.

## Current boundaries

- Static text layout: headings, paragraphs, block containers, lists, bold/italic text, links, and line breaks. Preformatted text preserves spaces and line breaks, with four spaces per tab, and wraps to the viewport. Images show alt-text placeholders.
- Inline CSS only: `color` (hex and five named colors), `font-size` (8–72 integer pixels), bold `font-weight`, italic `font-style`, and `display:none`. This is not a full cascade; stylesheet elements and linked stylesheets are not applied.
- One window/document at a time. Tabs, forms, selection in page text, downloads, cookies, persistent cache, image resources, and JavaScript/DOM bindings remain future milestones.
- UTF-8 HTML only; unsupported UTF-8 is rejected. Each source is limited to 1 MiB, with additional parser limits and a 20,000-run display cap. HTTP loading has a 10-second total deadline and a 12-second parent watchdog.
- Linux loader processes isolate blocking I/O from the window. They are a responsiveness mechanism, not a content sandbox. Each navigation cancels the previous process, preventing old results from replacing the new page.

See the [implementation plan](docs/implementation-plan.md) and [foundation readiness](docs/foundation-readiness.md) for the next milestones.
