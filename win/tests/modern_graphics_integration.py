#!/usr/bin/env python3
"""Unchanged M1 host: animation, resize, repeated navigation and window paint."""
import functools
import hashlib
import http.server
import json
import os
from pathlib import Path
import subprocess
import sys
import threading

ROOT = Path(__file__).resolve().parents[2]
WIN = str(Path(sys.argv[1]).resolve())
OUTPUT = ROOT / 'win/bin/modern-browser'
OUTPUT.mkdir(parents=True, exist_ok=True)
display = [] if os.environ.get('DISPLAY') else ['xvfb-run', '-a']
compiler = str(ROOT / 'w/bin/wv2')
source = str(ROOT / 'win/tests/modern_graphics_probe.w')
imports = ['--import-root', str(ROOT / 'win/src'), '--import-root', str(ROOT / 'w')]
probe = str(OUTPUT / 'graphics-probe')
subprocess.run([compiler, 'x64', 'check', '--json', *imports, source], check=True)
subprocess.run([compiler, 'x64', '--strict', *imports, source, '-o', probe], check=True)
subprocess.run([compiler, 'wasm', 'graphics/demo_web.w', '-o', 'bin/graphics_demo.wasm'],
               cwd=ROOT / 'w', check=True)

class Handler(http.server.SimpleHTTPRequestHandler):
    def log_message(self, *_):
        pass

server = http.server.ThreadingHTTPServer(('127.0.0.1', 0),
    functools.partial(Handler, directory=str(ROOT)))
thread = threading.Thread(target=server.serve_forever, daemon=True)
thread.start()
try:
    url = f'http://127.0.0.1:{server.server_port}/w/tools/web/index.html?module=/w/bin/graphics_demo.wasm'
    result = subprocess.run(display + [probe, '--browser', WIN, '--page', url,
        '--blank', str(ROOT / 'win/fixtures/start.html')],
        capture_output=True, text=True, timeout=90)
    assert result.returncode == 0, (result.stdout, result.stderr)
    report = json.loads(next(line for line in reversed(result.stdout.splitlines()) if line.startswith('{')))
    assert report['status'] == 'PASS' and len(report['cycles']) == 3, report
    (OUTPUT / 'M1-cycles.json').write_text(json.dumps(report, indent=2) + '\n')
    shot = OUTPUT / 'M1.ppm'
    diagnostics_path = OUTPUT / 'M1-window.json'
    result = subprocess.run(display + [WIN, '--page', url, '--reftest',
        '--screenshot', str(shot), '--report', str(diagnostics_path)],
        capture_output=True, text=True, timeout=60)
    assert result.returncode == 0, (result.stdout, result.stderr)
    diagnostics = json.loads(diagnostics_path.read_text())
    assert diagnostics['script_failures'] == 0 and diagnostics['resource_failures'] == 0, diagnostics
    assert diagnostics['title'] == 'W graphics demo', diagnostics
    magic, dimensions, maximum, pixels = shot.read_bytes().split(b'\n', 3)
    width, height = map(int, dimensions.split())
    assert magic == b'P6' and maximum == b'255' and len(pixels) == width * height * 3
    colorful = sum(max(pixels[i:i+3]) - min(pixels[i:i+3]) > 45 and min(pixels[i:i+3]) > 35
                   for i in range(0, len(pixels), 3))
    assert colorful > 10000, ('Triangle missing from actual window paint', colorful, str(shot))
    report['window'] = {**diagnostics, 'colorful_pixels': colorful}
    report['source_sha256'] = {str(p.relative_to(ROOT)): hashlib.sha256(p.read_bytes()).hexdigest()
        for p in sorted((ROOT / 'w/tools/web').glob('*')) if p.suffix in ('.mjs', '.html')}
    report['w_commit'] = subprocess.check_output(['git', '-C', str(ROOT / 'w'), 'rev-parse', 'HEAD'], text=True).strip()
    (OUTPUT / 'M1.json').write_text(json.dumps(report, indent=2) + '\n')
finally:
    server.shutdown()
    server.server_close()
    thread.join()
print('unchanged M1 host: 3 navigation cycles, 180 animation callbacks, resize and native window paint passed')
