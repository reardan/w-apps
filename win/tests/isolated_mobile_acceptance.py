#!/usr/bin/env python3
"""Run unchanged M2 host through the real isolated parent input queue."""
import functools
import http.server
import os
from pathlib import Path
import subprocess
import threading
ROOT = Path(__file__).resolve().parents[2]
compiler = ROOT / 'w/bin/wv2'
imports = ['--import-root', str(ROOT / 'win/src'), '--import-root', str(ROOT / 'w')]
source = ROOT / 'win/tests/isolated_mobile_probe.w'
probe = ROOT / 'win/bin/isolated-mobile-probe'
subprocess.run([str(compiler), 'check', '--json', 'x64', *imports, str(source)], check=True)
subprocess.run([str(compiler), 'x64', '--strict', *imports, str(source), '-o', str(probe)], check=True)
subprocess.run([str(compiler), 'check', '--json', 'x64', *imports, str(ROOT / 'win/main.w')], check=True)
subprocess.run([str(compiler), 'x64', '--strict', *imports, str(ROOT / 'win/main.w'), '-o', str(ROOT / 'win/bin/win')], check=True)
subprocess.run(['./wbuild', 'graphics_ui_mobile_web'], cwd=ROOT / 'w', check=True)
class Handler(http.server.SimpleHTTPRequestHandler):
    def log_message(self, *_): pass
server = http.server.ThreadingHTTPServer(('127.0.0.1', 0), functools.partial(Handler, directory=str(ROOT)))
thread = threading.Thread(target=server.serve_forever, daemon=True)
thread.start()
try:
    prefix = [] if os.environ.get('DISPLAY') else ['xvfb-run', '-a']
    page = f'http://127.0.0.1:{server.server_port}/w/tools/web/index.html?module=/w/bin/graphics_ui_mobile.wasm'
    result = subprocess.run(prefix + [str(probe), '--browser', str(ROOT / 'win/bin/win'), '--page', page], timeout=240)
finally:
    server.shutdown()
    server.server_close()
    thread.join()
raise SystemExit(result.returncode)
