# Web application execution

Win now connects a bounded WebAssembly interpreter, binary JavaScript values,
canvas WebGL rendering, module loading, and animation-frame scheduling. These
are subsets, not complete ECMAScript, WebAssembly, or WebGL conformance.

## Concrete target

`fixtures/wasm-demo.html` loads the unchanged wasm produced from
`w/graphics/demo_web.w` and imports the existing `w/tools/web/webgl_env.mjs`
bridge. Its startup uses Promises and a minimal WASI adapter. It is a separate
compatibility fixture: **the original `w/tools/web/index.html` is not supported
unchanged**. That host still requires top-level await, classes, BigInt arithmetic, and
additional browser interfaces. The mobile UI host is not an acceptance claim.

From the repository root:

```sh
(cd w && ./bin/wv2 wasm graphics/demo_web.w -o bin/graphics_demo.wasm)
python3 -m http.server 8000
# In another terminal:
./win/build run --page http://localhost:8000/win/fixtures/wasm-demo.html
```

The fixture draws three frames and stops. It is not a general WASI environment:
filesystem operations return errors, and its proc_exit handler records the exit
code at the end of W's generated startup wrapper.

## Available layers

- Binary values: ArrayBuffer, Uint8Array, Float32Array, DataView, shared views,
  bounds checks, detachment, and one-shot UTF-8 TextEncoder/TextDecoder. Unsupported
  coercions and streaming codecs remain explicit failures. BigInt64 DataView
  methods and exact wasm i64 crossings use a distinct bounded BigInt primitive
  covering [-2^63, 2^64-1]; arbitrary-precision arithmetic is not implemented.
- Fetch: same-origin HTTP(S) GET with single-use `text()` and `arrayBuffer()`.
  Binary bodies may contain NUL and invalid UTF-8. Bodies are limited to 1 MiB
  each and 4 MiB retained per page; text decoding retains its 64 KiB/valid-UTF-8
  restriction. Options, CORS, XHR, headers, streams, and JSON/blob helpers are
  not implemented.
- Static modules: bounded asynchronous same-origin source graph loading,
  relative resolution, named imports, cached evaluation, immutable const exports,
  and function exports with live bindings.
  This does not implement cycles, dynamic import, live mutable exports, or
  top-level await. The current loader aborts its graph on a load failure.
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
  and does not accept arbitrary modern wasm binaries. JS i64 crossings use a bounded BigInt representation; broader BigInt language
  operations remain outside the subset. Streaming entry points buffer the response;
  they are not incremental compilers and do not yet enforce response MIME. Modules are limited to 1 MiB, defined
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
Its DOM snapshots do not transport canvas surfaces; use the default interactive
path for wasm/WebGL. See [process isolation](script-isolation.md) for its current
input, storage, and lifecycle limitations.

## Verification

Focused tests cover binary memory ownership, wasm validation/traps and fuel,
fetch bytes and consumption, module cache/loading, animation ordering, and native
GL handles/buffer bounds/pixels. The actual browser rendering checks are:

```sh
xvfb-run -a python3 win/tests/canvas_rendering.py win/bin/win
python3 win/tests/wasm_graphics_integration.py win/bin/win
```

They require an X11/OpenGL display or Xvfb. The wasm test compiles the existing
W demo and serves only a loopback HTTP fixture. Passing these tests establishes
these paths, not compatibility with complete framework applications.

The completed validation run passed 1,210 W toolchain targets, all 23 browser W
test programs, eight Python integration suites, native GPU/canvas pixel checks,
and 12/12 pinned WPT reftests. Test262 records 41 passes and 12 explicitly
unsupported variants, with no unexpected failures. The toolchain run used
`env -u NO_COLOR ./wbuild tests` so its color-output fixture could control its
own environment.
