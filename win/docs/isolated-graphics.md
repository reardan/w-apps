# Opt-in worker canvas presentation

`--isolated-interactive` now presents native WebGL canvas pixels produced by a
persistent child process. The parent parses a display-only HTML snapshot and
uploads validated RGBA bytes. It never evaluates the child page's JavaScript,
creates its Wasm instance, or receives native GL handles. The default execution
mode is unchanged. Process separation alone retains filesystem, network and
X server authority. An optional [offline Linux profile](offline-sandbox.md)
restricts local-content workers; sandboxed HTTP applications are not supported.

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
  misinterpreted. There is one request outstanding, a bounded native input queue described
  below, and a 30-second request deadline independent of JavaScript/Wasm fuel.
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

Zero-copy rendering, continuous high-refresh presentation and full M4 workflow
acceptance remain separate work. Legacy snapshot-targeted click/input/submit
requests retain their busy-refusal behavior; graphical input uses the bounded
ordered transport below. Non-WebGL canvas APIs and a missing GL display do not acquire new
rendering support. The renderer uses the existing bounded native WebGL subset;
this is not a claim of full browser conformance.

## Ordered native input

WINT kind 5/revision 2 carries a 36-byte prefix of little-endian int32 fields:
worker generation, document generation, viewport width/height, event count,
mouse x/y, modifiers and reserved zero. Each of at most 64 events has five int32
fields: kind, code, x, y and modifiers. Coordinates are relative to the document
viewport and bounded to ±65,536; dimensions are 1–4,096. Valid kinds are the
portable key, character, caret navigation, pointer button/cancel, wheel and
preedit records. Unknown kinds, invalid codes/scalars/modifiers, stale generation
or document IDs, and malformed lengths reject the whole batch before dispatch.

The parent retains at most eight batches while a request or frame ACK is pending.
Compatible text batches coalesce only up to 64 ordered records; redundant motion
snapshots coalesce. Overflow visibly stops the worker rather than losing a
release or text edit. Tab ownership changes discard unsent input and enqueue a
terminal cancellation. Keyboard input is routed to the focused document; browser
chrome consumes its own input locally.

Kind 102/revision 2 extends the canvas manifest with nine int32 metadata fields
before its strings: worker generation, document generation, focused node ID,
UTF-16 selection start/end/direction, vertical scroll, viewport width/height.
The worker uses the same native pointer/keyboard/forms pipeline as ordinary Win.
The parent disables local document editing and scrolling defaults, then applies
returned focus, selection and scroll to its inert presentation. Canvas handles
and executable realms remain private to the worker. Direct legacy transport consumers retain kind 100/101 snapshots and bounded
request APIs; browser-owned sessions use the History profile below.

`isolated_input_integration.py` covers actual button handlers, Unicode editing,
canceled beforeinput, selection, composition ordering and malformed/stale batches.
`interactive_input_test.w` covers queue coalescing, overflow and guard-allocator
cleanup. `isolated_mobile_acceptance.py` drives the unchanged mobile host through
pointer focus, Unicode input, Backspace and resize without a parent script realm.
Both native and isolated mobile acceptance run in `win/build test`. Complete
platform IME commit payloads remain unsupported. Parent-owned shared storage and
the framework workflow now pass their separate integration gates; see
[storage](isolated-storage.md) and [application evidence](modern-browser-progress.md).

Browser-owned interactive sessions additionally require kind 103/revision 3,
which extends the snapshot with bounded History metadata. Direct legacy consumers
retain kind 102/revision 2. History, focus and document identity publish together
with the completed frame set; see [isolated History](isolated-history.md) for
ordered Back/Forward, quotas and reload limitations.
