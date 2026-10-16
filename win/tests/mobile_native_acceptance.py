#!/usr/bin/env python3
"""Native acceptance for the unchanged mobile host and Wasm application.

Uses the explicit 200M task budget required by this measured application;
production's default 1M limit is unchanged. No host rewriting or JS injection.
"""
import functools
import http.server
import os
from pathlib import Path
import subprocess
import threading

ROOT = Path(__file__).resolve().parents[2]


def main():
    compiler = ROOT / 'w/bin/wv2'
    imports = ['--import-root', str(ROOT / 'win/src'), '--import-root', str(ROOT / 'w')]
    probe = ROOT / 'win/bin/mobile-native-probe'
    browser = ROOT / 'win/bin/win'
    source = ROOT / 'win/tests/mobile_native_probe.w'
    subprocess.run([str(compiler), 'check', '--json', 'x64', *imports, str(source)], check=True)
    subprocess.run([str(compiler), 'x64', '--strict', *imports, str(source), '-o', str(probe)], check=True)
    subprocess.run([str(compiler), 'x64', '--strict', *imports, str(ROOT / 'win/main.w'), '-o', str(browser)], check=True)
    subprocess.run(['./wbuild', 'graphics_ui_mobile_web'], cwd=ROOT / 'w', check=True)

    class Handler(http.server.SimpleHTTPRequestHandler):
        def log_message(self, *_):
            pass

    server = http.server.ThreadingHTTPServer(('127.0.0.1', 0), functools.partial(Handler, directory=str(ROOT)))
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    display = [] if os.environ.get('DISPLAY') else ['xvfb-run', '-a']
    try:
        page = f'http://127.0.0.1:{server.server_port}/w/tools/web/index.html?module=/w/bin/graphics_ui_mobile.wasm'
        return subprocess.run(display + [str(probe), '--browser', str(browser), '--page', page], timeout=240).returncode
    finally:
        server.shutdown()
        server.server_close()
        thread.join()


if __name__ == '__main__':
    raise SystemExit(main())
