#!/usr/bin/env python3
"""Unchanged Preact workflow through isolated native input and worker-owned DOM.

The test driver injects portable gfx_event records at the application's native
input seam; it does not inject JavaScript or modify app/framework source. This
checks the widget/DOM/framework/API integration, not X11 key translation or IME.
"""
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import threading
from workflow_server import make_server

ROOT = Path(__file__).resolve().parents[2]
BROWSER = Path(sys.argv[1]).resolve() if len(sys.argv) > 1 else ROOT / 'win/bin/win'
OUTPUT = ROOT / 'win/bin/modern-browser/isolated-workflow'
OUTPUT.mkdir(parents=True, exist_ok=True)


def run(command, **kwargs):
    return subprocess.run([str(part) for part in command], check=True, text=True,
                          capture_output=True, timeout=120, **kwargs)


def main():
    compiler = ROOT / 'w/bin/wv2'
    source = ROOT / 'win/tests/isolated_workflow_probe.w'
    probe = OUTPUT / 'isolated-workflow-probe'
    imports = ['--import-root', ROOT / 'win/src', '--import-root', ROOT / 'w']
    run([compiler, 'check', '--json', 'x64', *imports, source])
    run([compiler, 'x64', '--strict', *imports, source, '-o', probe])
    # Keep screenshots and input independent of the shared desktop session.
    display = ['xvfb-run', '-a'] if shutil.which('xvfb-run') else []
    if not display and not os.environ.get('DISPLAY'):
        raise RuntimeError('X11/OpenGL or xvfb-run is required')
    server = make_server()
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    url = f'http://127.0.0.1:{server.server_port}/win/fixtures/workflow/index.html'
    report = {'app_commit': run(['git', 'rev-parse', 'HEAD'], cwd=ROOT).stdout.strip(),
              'w_commit': run(['git', 'rev-parse', 'HEAD'], cwd=ROOT / 'w').stdout.strip(),
              'sources': {str(p.relative_to(ROOT)): hashlib.sha256(p.read_bytes()).hexdigest()
                          for p in sorted((ROOT / 'win/fixtures/workflow').rglob('*')) if p.is_file()},
              'scope': 'isolated native input/DOM/framework/API pipeline; no parent JS realm or X11 key/IME claim',
              'checks': ['Worker-owned focus and UTF-16 selection', 'Native wheel scroll and queued input']}
    try:
        with tempfile.TemporaryDirectory(prefix='win-workflow-state-') as directory:
            storage = Path(directory) / 'storage'
            base = [*display, probe, '--browser', BROWSER, '--storage', storage]
            result = run([*base, '--page', url, '--screenshot', OUTPUT / 'workflow-800x600.ppm',
                          '--narrow-screenshot', OUTPUT / 'workflow-360x640.ppm'])
            assert '"status":"PASS"' in result.stdout, result.stdout
            report['checks'].extend(['JSON POST success', 'HTTP failure', 'Abort without late success',
                                     'Theme change', 'Routing/back/forward', 'Full workflow repeated at360x640',
                                     'Theme survives reload', 'Responsive native GL screenshots'])
            for origin, expected in ((url, 'green'), (url.replace('127.0.0.1', 'localhost'), 'blue')):
                result = run([*base, '--page', origin + '?view=settings', '--check-theme', expected])
                assert '"status":"PASS"' in result.stdout, result.stdout
            report['checks'].extend(['Persistence across process restart', 'Origin separation'])
            for viewport in ('800x600', '360x640'):
                shot = OUTPUT / f'workflow-{viewport}.ppm'
                magic, dimensions, maximum, pixels = shot.read_bytes().split(b'\n', 3)
                width, height = map(int, dimensions.split())
                assert (width, height) == tuple(map(int, viewport.split('x')))
                assert magic == b'P6' and maximum == b'255' and len(pixels) == width * height * 3
                assert len(set(pixels)) > 30, 'native screenshot is blank'
                accent_pixels = sum(pixels[i:i+3] == bytes((40, 99, 72)) for i in range(0, len(pixels), 3))
                assert accent_pixels > 1000, ('selected green theme is not painted', viewport, accent_pixels)
                report.setdefault('green_accent_pixels', {})[viewport] = accent_pixels
        report['status'] = 'PASS'
    except subprocess.CalledProcessError as error:
        report.update(status='FAIL', command=error.cmd, stdout=error.stdout, stderr=error.stderr)
        raise
    finally:
        server.shutdown()
        server.server_close()
        thread.join()
        (OUTPUT / 'workflow.json').write_text(json.dumps(report, indent=2) + '\n')
    print(json.dumps(report))


if __name__ == '__main__':
    main()
