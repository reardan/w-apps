#!/usr/bin/env python3
"""Native acceptance for the unchanged mobile host and Wasm application.

Uses the explicit 200M task budget required by this measured application;
production's default 1M limit is unchanged. No host rewriting or JS injection.
"""
import functools
import hashlib
import json
import http.server
import os
from pathlib import Path
import subprocess
import threading

ROOT = Path(__file__).resolve().parents[2]


def main():
    output = ROOT / 'win/bin/modern-browser/mobile-native'
    output.mkdir(parents=True, exist_ok=True)
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
        shots = {name: output / f'{name}.ppm' for name in ('edited', 'narrow', 'scrolled', 'parent-edited', 'parent-narrow')}
        result = subprocess.run(display + [str(probe), '--browser', str(browser), '--page', page,
            '--screenshot', str(shots['edited']), '--narrow-screenshot', str(shots['narrow']),
            '--scrolled-screenshot', str(shots['scrolled']),
            '--parent-screenshot', str(shots['parent-edited']),
            '--parent-narrow-screenshot', str(shots['parent-narrow'])], timeout=240, check=True)
        frames = {}
        sizes = {}
        for name, path in shots.items():
            magic, dimensions, maximum, pixels = path.read_bytes().split(b'\n', 3)
            width, height = map(int, dimensions.split())
            assert magic == b'P6' and maximum == b'255' and len(pixels) == width * height * 3
            frames[name] = pixels
            sizes[name] = [width, height]
        assert sizes['narrow'] == sizes['scrolled'] == sizes['parent-narrow'] == [360, 360], sizes
        assert sizes['edited'] == sizes['parent-edited'] == [390, 720], sizes
        changed = sum(frames['narrow'][i:i+3] != frames['scrolled'][i:i+3]
                      for i in range(0, len(frames['narrow']), 3))
        assert changed > 5000, ('inner wasm scroll did not change enough pixels', changed)
        sources = [*(ROOT / 'w/tools/web').glob('*.mjs'), ROOT / 'w/tools/web/index.html',
                   ROOT / 'w/graphics/ui/mobile_demo_web.w', ROOT / 'w/graphics/ui/mobile_demo_shared.w',
                   ROOT / 'w/bin/graphics_ui_mobile.wasm']
        report = {'status': 'PASS', 'execution_budget': 200000000,
                  'scope': 'portable native event seam, not platform key translation',
                  'checks': ['pointer focus', 'Unicode field editing', 'sink reset', 'Backspace',
                             'viewport resize', 'zero outer scroll', 'parent viewport captures',
                             'inner wheel scrolling', '30 sustained frames'],
                  'sizes': sizes, 'scroll_changed_pixels': changed,
                  'source_sha256': {str(p.relative_to(ROOT)): hashlib.sha256(p.read_bytes()).hexdigest()
                                    for p in sources},
                  'w_commit': subprocess.check_output(['git', '-C', str(ROOT / 'w'), 'rev-parse', 'HEAD'], text=True).strip()}
        (output / 'report.json').write_text(json.dumps(report, indent=2) + '\n')
        return result.returncode
    finally:
        server.shutdown()
        server.server_close()
        thread.join()


if __name__ == '__main__':
    raise SystemExit(main())
