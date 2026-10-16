# Web application execution

Win now connects a bounded WebAssembly interpreter, binary JavaScript values,
canvas WebGL rendering, module loading, and animation-frame scheduling. These
are subsets, not complete ECMAScript, WebAssembly, or WebGL conformance.

## Concrete target

The original `w/tools/web/index.html` now runs **unchanged** with the existing
`graphics/demo_web.w` wasm and web bridge. Native acceptance checks cover three
navigation cycles, 60 changing frames per cycle, 800×600 → 480×360 canvas resizing,
script/resource errors, post-navigation callback/task release, stable descriptors
and live W allocation counts, and triangle pixels in the actual browser window.
The [progress note](modern-browser-progress.md) records timing/memory measurements
and the remaining mobile, framework and isolation gates. This is not a claim of
full browser compatibility or performance parity.

From the repository root:

```sh
(cd w && ./bin/wv2 wasm graphics/demo_web.w -o bin/graphics_demo.wasm)
python3 -m http.server 8000
# In another terminal:
./win/build run --page 'http://localhost:8000/w/tools/web/index.html?module=/w/bin/graphics_demo.wasm'
```

`fixtures/wasm-demo.html` remains a separate three-frame Promise compatibility
fixture with a minimal WASI adapter. The unchanged mobile UI host requires an
explicit larger execution budget to render and does not yet pass input/workflow
acceptance. Its exact entry point and measured bottlenecks are in the progress note.

## Available layers

- Binary values: ArrayBuffer, Uint8Array, Float32Array, DataView, shared views,
  bounds checks, detachment, and one-shot UTF-8 TextEncoder/TextDecoder. Unsupported
  coercions and streaming codecs remain explicit failures. BigInt64 DataView
  methods and exact wasm i64 crossings use a distinct bounded BigInt primitive
  covering [-2^63, 2^64-1]; arbitrary-precision arithmetic is not implemented.
- Fetch: same-origin HTTP(S), bounded methods/string or binary request bodies,
  and single-use `text()`, `arrayBuffer()` and `json()`.
  Binary bodies may contain NUL and invalid UTF-8. `Response.json()` consumes the
  same body using forgiving UTF-8 decoding followed by strict bounded JSON parsing. Bodies are limited to 4 MiB
  each and 4 MiB retained per page; text decoding retains its 64 KiB/valid-UTF-8
  restriction. Native AbortSignal options and cancellation are supported. CORS, XHR, response
  headers, streams, and blob helpers remain unsupported.
- Static modules: bounded asynchronous same-origin source graph loading,
  relative resolution, named imports, cached evaluation, immutable const exports,
  and function exports with live bindings.
  Top-level await and async dependencies suspend through the browser event loop.
  This does not implement cycles, dynamic import, or live mutable exports. The current loader aborts its graph on a load failure.
- Animation: requestAnimationFrame/cancelAnimationFrame on Window and the global
  scope; up to 256 queued callbacks, one shared timestamp per visible paint,
  microtask checkpoints between callbacks, and deferred nested registration.
  Ordinary polling/headless dumps do not run animation callbacks; the opt-in
  interactive child advances them on explicit UI ticks. Navigation, tab closure,
  and Stop release queued callbacks.
- Host geometry: location/search and string-initialized URLSearchParams.get,
  native viewport dimensions and resize events, limited live computed padding
  and font size, bounding rectangles, and offset/client dimensions. These are
  the implemented properties, not complete browser DOM interfaces.
- WebAssembly: validated bounded interpreter, function imports/exports,
  defined linear memory/table/globals, and the instruction subset emitted by W's
  graphics demo. Unsupported types/proposals fail validation; this is not a JIT
  and does not accept arbitrary modern wasm binaries. JS i64 crossings and bounded BigInt arithmetic preserve exact integer bits;
  arbitrary-precision BigInt remains outside the subset. Streaming entry points buffer the response;
  they are not incremental compilers. They require an unconsumed native Fetch
  Response, successful status, and `application/wasm` with no MIME parameters;
  forged objects and overridden response methods cannot bypass validation.
  Modules are limited to 4 MiB and 1,048,576 decoded instructions, with a 4 MiB
  aggregate retained source budget (module and instance copies count), defined
  memories to 16 MiB, and total realm memory to 64 MiB with at most 16 machines.
- Canvas: `getContext('webgl2')` exposes the implemented native GL subset only
  with a graphics context. Headless calls return null. Each canvas owns a private
  GLX context and framebuffer, with opaque handles, upload/draw bounds checks,
  and readback/compositing into the page. Canvas dimensions participate in
  layout; changing the backing dimensions clears the surface. Limits include
  4096 pixels per dimension, 16 MiB pixels per canvas, 16 MiB uploaded storage,
  4096 handles, and eight canvases per realm. This Linux GLX implementation is
  not a complete WebGL2 implementation or a GPU-process sandbox.

Interactive isolation is separately available through `--isolated-interactive`.
It presents atomic DOM snapshots and bounded RGBA8 canvas surfaces from the
worker, with generation validation and acknowledgement backpressure. The unchanged
graphics host passes sustained rendering and resize in this mode. See
[isolated graphics](isolated-graphics.md) and [process isolation](script-isolation.md)
for the remaining input, shared-storage and OS-sandbox limitations.

## Verification

Focused tests cover binary memory ownership, wasm validation/traps and fuel,
fetch bytes and consumption, module cache/loading, animation ordering, and native
GL handles/buffer bounds/pixels. The actual browser rendering checks are:

```sh
xvfb-run -a python3 win/tests/canvas_rendering.py win/bin/win
python3 win/tests/wasm_graphics_integration.py win/bin/win
xvfb-run -a python3 win/tests/modern_graphics_integration.py win/bin/win
```

They require an X11/OpenGL display or Xvfb. The wasm test compiles the existing
W demo and serves only a loopback HTTP fixture. Passing these tests establishes
these paths, not compatibility with complete framework applications.

The pre-roadmap baseline validation run passed 1,210 W toolchain targets, all 23 browser W
test programs, eight Python integration suites, native GPU/canvas pixel checks,
and 12/12 pinned WPT reftests. Test262 records 41 passes and 12 explicitly
unsupported variants, with no unexpected failures. The toolchain run used
`env -u NO_COLOR ./wbuild tests` so its color-output fixture could control its
own environment.

Current implementation and validation evidence is recorded in
[modern-browser-progress.md](modern-browser-progress.md). Historical counts above
do not include subsequent slices.
