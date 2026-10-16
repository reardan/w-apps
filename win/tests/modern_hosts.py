#!/usr/bin/env python3
"""Record real unchanged-host startup failures; full M1/M2 gates remain stricter.

No script injection or bridge rewriting. A zero exit means all startup probes
pass, not that input, frame pacing, teardown or milestone parity is established.
"""
import argparse
import functools
import hashlib
import http.server
import json
import os
from pathlib import Path
import shutil
import subprocess
import threading

ROOT = Path(__file__).resolve().parents[2]

def run(args, **kw):
    return subprocess.run(args, text=True, capture_output=True, timeout=120, **kw)

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--browser', type=Path, default=ROOT / 'win/bin/win')
    parser.add_argument('--report', type=Path, default=ROOT / 'win/bin/modern-browser/hosts.json')
    parser.add_argument('--record', action='store_true', help='Record known failures without failing the command')
    parser.add_argument('--execution-budget', type=int, default=1000000,
                        help='Explicit synchronous task budget; higher values may stall the UI')
    opts = parser.parse_args()
    output = opts.report.resolve().parent
    output.mkdir(parents=True, exist_ok=True)
    compiler = ROOT / 'w/bin/wv2'
    probe = output / 'host-probe'
    for command in (
        [str(compiler), 'x64', 'check', '--json', '--import-root', str(ROOT / 'win/src'), '--import-root', str(ROOT / 'w'), str(ROOT / 'win/tests/modern_host_probe.w')],
        [str(compiler), 'x64', '--strict', '--import-root', str(ROOT / 'win/src'), '--import-root', str(ROOT / 'w'), str(ROOT / 'win/tests/modern_host_probe.w'), '-o', str(probe)],
        [str(compiler), 'wasm', 'graphics/demo_web.w', '-o', 'bin/graphics_demo.wasm'],
        ['./wbuild', 'graphics_ui_mobile_web'],
    ):
        result = run(command, cwd=ROOT / 'w')
        if result.returncode:
            raise RuntimeError((command, result.stdout, result.stderr))
    display = [] if os.environ.get('DISPLAY') else ['xvfb-run', '-a']
    if display and not shutil.which('xvfb-run'):
        raise RuntimeError('X11/OpenGL or xvfb-run is required')
    class Handler(http.server.SimpleHTTPRequestHandler):
        def log_message(self, *_):
            pass
    server = http.server.ThreadingHTTPServer(('127.0.0.1', 0), functools.partial(Handler, directory=str(ROOT)))
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    report = {'app_commit': run(['git', 'rev-parse', 'HEAD'], cwd=ROOT).stdout.strip(),
              'w_commit': run(['git', 'rev-parse', 'HEAD'], cwd=ROOT / 'w').stdout.strip(),
              'scope': 'startup probes only; not full milestone acceptance', 'hosts': {},
              'sources': {str(p.relative_to(ROOT)): hashlib.sha256(p.read_bytes()).hexdigest()
                          for p in sorted((ROOT / 'w/tools/web').glob('*')) if p.suffix in ('.mjs', '.html')}}
    try:
        for name, path in (
            ('compatibility', '/win/fixtures/wasm-demo.html'),
            ('M1', '/w/tools/web/index.html?module=/w/bin/graphics_demo.wasm'),
            ('M2', '/w/tools/web/index.html?module=/w/bin/graphics_ui_mobile.wasm'),
        ):
            url = f'http://127.0.0.1:{server.server_port}{path}'
            result = run(display + [str(probe), '--browser', str(opts.browser.resolve()), '--page', url,
                                    '--execution-budget', str(opts.execution_budget)])
            lines = [line for line in result.stdout.splitlines() if line.startswith('{')]
            if not lines:
                raise RuntimeError((name, result.returncode, result.stdout, result.stderr))
            data = json.loads(lines[-1])
            data['returncode'] = result.returncode
            data['startup_pass'] = (result.returncode == 0 and data['script_failures'] == 0 and
                                    data['resource_failures'] == 0 and data['canvas_nonblack_center'])
            report['hosts'][name] = data
            print(f"{name}: {'PASS' if data['startup_pass'] else 'FAIL'}: {data.get('script_error', data['status'])}")
        workflow = ROOT / 'win/fixtures/workflow/vendor/preact-10.27.2.module.js'
        report['sources'][str(workflow.relative_to(ROOT))] = hashlib.sha256(workflow.read_bytes()).hexdigest()
        workflow_report = output / 'M3-startup.json'
        result = run([str(opts.browser.resolve()), '--dump', '--report', str(workflow_report),
                      '--page', f'http://127.0.0.1:{server.server_port}/win/fixtures/workflow/index.html'])
        data = json.loads(workflow_report.read_text())
        data['returncode'] = result.returncode
        data['startup_pass'] = (result.returncode == 0 and data['script_failures'] == 0 and
                                data['resource_failures'] == 0 and data['title'] == 'Workflow: form' and
                                'Profile workflow' in result.stdout)
        report['hosts']['M3'] = data
        print(f"M3: {'PASS' if data['startup_pass'] else 'FAIL'}: {data.get('script_error', data['status'])}")
    finally:
        server.shutdown()
        server.server_close()
        thread.join()
    opts.report.write_text(json.dumps(report, indent=2) + '\n')
    print(f'Report: {opts.report}')
    return 0 if opts.record or all(h['startup_pass'] for h in report['hosts'].values()) else 1

if __name__ == '__main__':
    raise SystemExit(main())
