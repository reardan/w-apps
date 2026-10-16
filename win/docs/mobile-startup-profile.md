# Unchanged mobile host: startup budget and interpreter cost

The M2 application completes under an explicit diagnostic budget of 200 million
shared JavaScript/Wasm instructions. The existing one-million default is too
small for its finite font initialization and rendering work. Raising that limit
alone would still block the calling browser thread for seconds during startup
and roughly 90–110 ms per subsequent frame. These measurements establish a
startup/rendering path, not input parity or responsiveness acceptance.

Measurements used app `443abd5`, W `3354e528`, Linux x64 on an Intel Core
i7-14700K, and Xvfb/OpenGL. All HTML/module files and the mobile Wasm binary were
unchanged and matched the coordinator checkout byte-for-byte. The Wasm SHA-256
was `1d32dc97bc5d26eba04fdfa37cee4f753e28feb3bb8ed6aa414906b764ee0d42`.
[Machine-readable evidence](mobile-startup-profile.json) includes every host
source hash, budget configuration, call cost, frame result, and paired timing.

## Budget measurements

The diagnostic probe varied the existing script entry/checkpoint budget and
Wasm export cap independently. No production limit was changed. Counts below
include Wasm instructions and JavaScript import work sharing the same fuel.

| JS cap | Wasm cap | `_start` consumed | Native `_start` wall time | Result |
| ---: | ---: | ---: | ---: | --- |
| 1 million | 1 million | 998,293 | 40 ms | Exhausted |
| 10 million | 1 million | 1,000,000 | 38 ms | Exhausted |
| 10 million | 10 million | 9,998,293 | 222 ms | Exhausted |
| 50 million | 50 million | 49,998,293 | 1,043 ms | Exhausted |
| 200 million | 200 million | 100,437,402 | 2,067 ms | Exit 0 |
| 500 million | 500 million | 100,437,402 | 2,304 ms | Exit 0 |
| 1 billion | 1 billion | 100,437,402 | 2,123 ms | Exit 0 |

The failing runs all reached the title `W mobile form` and exactly 35 host
imports. Successful startup used 42 imports and logged `_start returned (exit
0)`. Its internal throw status is the expected `proc_exit` unwind caught by the
unchanged WASI host, not an application failure. The identical completion counts
at three large caps rule out an unbounded startup loop. Raising only the JS cap
cannot help while the Wasm export independently clamps its budget to one million.

The first frame consumes **121,537,963** shared instructions. In the initial
completed runs it took 2,468–2,631 ms, produced a nonblack canvas, and arrived
7,227–7,510 ms after navigation. The largest individual browser poll took
2,249–2,549 ms. Later runs under concurrent compiler/VM tests were slower.
The native heap held 5,941 JavaScript values after the first frame, so this
failure was not a JavaScript heap-cap problem.

Frames 2–4 each consumed **3,874,919** instructions and took 92–106 ms in the
initial four-frame run. The first frame does substantial one-time work, but the
unchanged steady frame still exceeds the production cap almost fourfold.
Four frames rendered without script/resource failures; no input or resize
acceptance is claimed by this diagnostic.

## Where the work goes

Native instrumentation recorded per-function inclusive fuel and exclusive fuel
(after subtracting nested calls), then mapped indexes through the unchanged
Wasm name section. Instruction accounting itself was unchanged.

| Phase | Function | Cost | Fraction of phase |
| --- | --- | ---: | ---: |
| Startup | `base64_decode`, including `base64_decode_char` | 66,736,507 | 66.4% |
| Startup | `mem_copy$char` | 18,372,417 | 18.3% |
| Startup | `strlen` | 10,475,368 | 10.4% |
| Startup | `rle_decode` | 3,657,591 | 3.6% |
| First frame | `ttf_fill`, including its callees | 83,225,122 | 68.5% |
| First frame | `ui_font_rows_reserve`, including its callees | 10,492,659 | 8.6% |
| First frame | `ui_font_build_atlas`, including its callees | 12,908,839 | 10.6% |
| Steady frame | `ttf_kern_units`, including its callees | 1,765,681 | 45.6% |
| Steady frame | `ui_render_quad_sheared`, including its callees | 1,159,243 | 29.9% |

Startup decodes the bundled font data and baked atlas. The first frame
rasterizes initially used glyphs and grows/builds the atlas. Later frames reuse
those glyphs but continue kerning and geometry generation. Host imports consumed
only 15–22 ms during the initial successful startup runs and 5–40 ms for the
first frame: JavaScript/WebGL calls are not the dominant cost here.

Dynamic opcode counts explain why local interpreter tweaks have limited reach.
Global/local get/set, constants, and `i32.add` together account for about 80%
of guest operations. `i32.load`/`i32.store` account for about 11%. This follows
the W backend's virtual-register and explicit W-stack lowering. The cost is
not a single expensive JavaScript builtin.

## Local optimization experiment

An isolated x64-only candidate replaced the interpreter's 1/2/4/8-byte
little-endian load/store loops with native loads/stores **after the existing
bounds checks**. It retained original instruction fuel, trap checks, and host
import accounting. The existing 92 adversarial Wasm validation cases, including
truncation, host reentry, and shared start fuel, passed. This candidate was not
promoted to production.

Concurrent repository checks distorted wall times, so two alternating pairs
were pinned to CPU 0 and measured with `CLOCK_THREAD_CPUTIME_ID`. The medians
were:

| Phase | Baseline CPU time | Native load/store candidate |
| --- | ---: | ---: |
| Startup | 2,269.5 ms | 2,087 ms |
| First frame | 2,612 ms | 2,651 ms |
| Steady frames | 92.5 ms | 93.5 ms |

That is roughly an 8% startup reduction, with no repeatable rendering benefit.
The sample is small and CPU frequency/cache effects remain possible. It does
not justify treating the candidate as the M2 performance fix. Crucially, every
run still consumes the same guest fuel, so it cannot fix the one-million cap.
Larger improvements need work on generated instruction volume, validated
interpreter execution/dispatch, or execution isolation with interruptible work.
Replacing application/font functions by name would not be a general solution.

## Minimal experimental configuration

A single opt-in `--execution-budget N` is sufficient; keep the default at
**1,000,000** and reject values outside a finite **1–200,000,000** range. Store
it per browser/script instance and use it at independent module, checkpoint,
timer/event, and animation entries, and as the Wasm export cap. The same cap
must preserve the existing decreasing `rt.remaining`/`m.fuel` accounting across
imports and nested calls; it must never refill on host reentry.

A 200-million profile admits the measured startup and first frame with headroom
and enables explicit mobile rendering/input experiments. Keep wall-time
watchdogs, cancellation, isolation defaults, and resource caps independent and
unchanged. The heavier profile is not a promise of interactive responsiveness:
its synchronous task can still monopolize the caller for seconds. Worker frame
transport and cancellation responsiveness require their own acceptance gates.
