# Opt-in worker canvas presentation

`--isolated-interactive` now presents native WebGL canvas pixels produced by a
persistent child process. The parent parses a display-only HTML snapshot and
uploads validated RGBA bytes. It never evaluates the child page's JavaScript,
creates its Wasm instance, or receives native GL handles. The default execution
mode is unchanged. This is **process separation, not an OS sandbox**: the worker
retains its existing filesystem, network and X server authority.

The child opens an unmapped 1×1 X11 drawable and a GLX context. Canvas contexts and
FBOs remain private to the child; capture reads their RGBA buffers and flips rows
into top-left order. No worker window is mapped or focused. Without an available
X/GL display, non-canvas pages still return ordinary inert snapshots; native
canvas presentation requires a usable GLX display.

## Protocol and ownership

Legacy `WINT0001` kind 100 snapshots and legacy callers remain supported. A
positive `--worker-generation` selects the graphics profile:

- Kind 101 has the ordinary 24-byte WINT header, followed by script/resource
  failure counts, canvas count, canvas node IDs (all little-endian int32), then
  NUL-terminated UTF-8 address, title and HTML. At most eight unique canvas IDs
  are accepted, in the existing 8 MiB snapshot limit. Each ID must resolve to
  exactly one canvas in that same parsed snapshot.
- Each manifest entry is followed by a WFRM v1 record with the existing 48-byte
  header: version, pixel kind, generation, monotonically increasing sequence,
  RGBA8 format, dimensions, stride, payload length and zero reserved fields.
  This profile requires tight `width * 4` stride, dimensions 1–4096, and an
  aggregate pixel payload no larger than 16 MiB per snapshot. Header arithmetic
  and remaining aggregate capacity are checked before payload allocation.
- One frame is outstanding at a time. After taking ownership of a complete
  validated payload, the parent sends its matching WFRM ACK. The worker keeps
  the encoded payload until that ACK, and does not send another frame or
  snapshot beforehand. Wrong-generation, wrong-sequence or malformed ACKs end
  the connection. All frames must arrive before the parent publishes the new
  DOM and surface set; an incomplete reply cannot replace the displayed set.
- Parent polling reads at most 64 KiB and writes at most 64 KiB per call. Each
  read stops at the current record boundary, so coalesced records cannot be
  misinterpreted. There is one request outstanding, no growing request queue,
  and a 30-second request deadline independent of JavaScript/Wasm fuel.
- Graphics requests use WINT reserved/revision value 1, then a 12-byte prefix
  `{node_id, viewport_width, viewport_height}` followed by the existing UTF-8
  event value. Kinds 1–4 retain tick/click/input/submit semantics. Dimensions
  are applied before event dispatch and the next animation callback. A resize
  during an outstanding reply is sent with the next accepted request.
- Navigation creates a new process/socket and advances the browser's worker
  generation. Cancellation closes and reaps the old connection, including a
  partial frame; bytes from an old connection are never reused. Complete
  parent surfaces, pending surfaces, decoder buffers and encoded ACKs are
  released on worker teardown. GPU uploads occur on the parent's paint thread.

The 16 MiB limit bounds one reply's payload, not total process memory. The child
also owns its canvas buffers and one encoded frame; the parent may retain the
previous complete set while receiving a new set and uploading textures.

`--execution-budget` now forwards unchanged to interactive workers, retaining
its default 1,000,000 and finite maximum 200,000,000. The worker uses the same
shared JS/Wasm accounting and cancellation policy. Custom budgets for the
separate one-shot `--isolated-dump` mode remain explicitly rejected.

## Reproducible checks

`win/build test` includes the new guarded frame test and integration driver.
The focused real-graphics command is:

```sh
python3 win/tests/isolated_graphics_integration.py win/bin/win
```

It creates a dedicated Xvfb server when necessary, rebuilds the original
`graphics/demo_web.w` Wasm program, and serves the unchanged `tools/web/index.html`
and modules. It checks 36 parent-painted frames over three generations, resize
from 800×600 to 480×360, changing pixels, absence of a parent script/fetch realm,
real GL worker crash/reaping, partial-transfer cancellation, stable descriptor
counts, stale/future ACK rejection and no output before ACK. A separate native
window screenshot must contain the colored triangle. Outputs are under
`win/bin/isolated-graphics/`; the checked-in JSON records the measured run and
source hashes.

The recorded Linux/Xvfb run produced 36 painted frames and 36 changed hashes,
first presentation after 1827 ms, maximum parent poll 1 ms, maximum parent paint
4 ms, and 28,998 colorful pixels in the actual browser window. These are observed
sample timings, not scheduling guarantees. Descriptor count stayed constant
across all three stops; the absolute count includes the active GL driver's FDs.
The new transport regression runs with guard-page allocation and reports zero
retained W allocations, including failure and cancellation paths.

This slice does not implement a sandbox, zero-copy rendering, continuous
high-refresh presentation, or forwarding of native pointer/key streams. Existing
snapshot-targeted click/input/submit requests retain their busy refusal behavior.
Native input forwarding and broader M4 performance/interaction acceptance remain
separate work. Non-WebGL canvas APIs and a missing GL display do not acquire new
rendering support. The renderer uses the existing bounded native WebGL subset;
this is not a claim of full browser conformance.
