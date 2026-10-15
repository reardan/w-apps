#!/usr/bin/env python3
"""Native browser smoke: unchanged W wasm binary + existing WebGL bridge.

The Promise-based fixture is intentionally distinct from tools/web/index.html;
passing this test does not establish support for that host's full JS surface.
"""
import functools
import http.server
import os
import pathlib
import shutil
import subprocess
import sys
import tempfile
import threading

ROOT = pathlib.Path(__file__).resolve().parents[2]
WIN = str(pathlib.Path(sys.argv[1]).resolve())
display = [] if os.environ.get('DISPLAY') else ['xvfb-run', '-a']
if display and not shutil.which(display[0]):
    raise SystemExit('X11/OpenGL or xvfb-run is required for the wasm graphics test')
subprocess.run([str(ROOT / 'w/bin/wv2'), 'wasm', 'graphics/demo_web.w', '-o', 'bin/graphics_demo.wasm'],
               cwd=ROOT / 'w', check=True)

class Handler(http.server.SimpleHTTPRequestHandler):
    def log_message(self, *_):
        pass

server = http.server.ThreadingHTTPServer(('127.0.0.1', 0), functools.partial(Handler, directory=str(ROOT)))
thread = threading.Thread(target=server.serve_forever, daemon=True)
thread.start()
try:
    with tempfile.TemporaryDirectory(prefix='win-wasm-') as directory:
        shot = pathlib.Path(directory) / 'frame.ppm'
        result = subprocess.run(display + [WIN, '--page',
            f'http://127.0.0.1:{server.server_port}/win/fixtures/wasm-demo.html',
            '--frames', '100', '--screenshot', str(shot)], capture_output=True, text=True, timeout=60)
        assert result.returncode == 0, (result.stdout, result.stderr)
        magic, dimensions, maximum, pixels = shot.read_bytes().split(b'\n', 3)
        assert magic == b'P6' and maximum == b'255', (magic, maximum)
        width, height = map(int, dimensions.split())
        assert len(pixels) == width * height * 3
        # Triangle interpolation yields thousands of saturated non-gray pixels;
        # UI chrome/text, a blank canvas, or merely clearing cannot pass this.
        colorful = 0
        for y in range(138, min(height, 618)):
            for x in range(12, min(width, 652)):
                offset = (y * width + x) * 3
                r, g, b = pixels[offset:offset + 3]
                if max(r, g, b) - min(r, g, b) > 45 and min(r, g, b) > 35:
                    colorful += 1
        if colorful <= 10000:
            artifact = ROOT / 'win/bin/wasm-failure.ppm'
            shutil.copyfile(shot, artifact)
            raise AssertionError(('wasm triangle missing', colorful, str(artifact), result.stdout, result.stderr))
finally:
    server.shutdown()
    server.server_close()
    thread.join()
print('native wasm + WebGL + animation-frame integration passed')
