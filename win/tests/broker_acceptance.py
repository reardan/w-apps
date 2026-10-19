#!/usr/bin/env python3
"""Unchanged M2/M3 hosts and input drivers with opt-in OS sandbox + broker.

Only test-driver setup is extended: no application/host/framework source edits.
The optional wasm argument must be the existing graphics_ui_mobile.wasm build.
"""
import ctypes
import functools
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import threading
from http.server import ThreadingHTTPServer
from workflow_server import WorkflowHandler

ROOT = Path(__file__).resolve().parents[2]
WIN = Path(sys.argv[1]).resolve()
WASM = Path(sys.argv[2]).resolve() if len(sys.argv) > 2 else ROOT/'w/bin/graphics_ui_mobile.wasm'
OUT = ROOT/'win/bin/broker-validation'
OUT.mkdir(parents=True, exist_ok=True)
compiler = os.environ.get('WIN_TEST_COMPILER', str(ROOT/'w/bin/wv2'))
if ctypes.CDLL(None).syscall(444, 0, 0, 1) < 8:
    print('SKIP: Landlock ABI 8 is required for broker acceptance')
    raise SystemExit(0)
display = ['xvfb-run', '-a'] if shutil.which('xvfb-run') else []
if not display and not os.environ.get('DISPLAY'):
    raise SystemExit('Broker graphics acceptance requires X11/OpenGL or xvfb-run')
for name in ('isolated_mobile', 'isolated_workflow'):
    original = ROOT/f'win/tests/{name}_probe.w'
    generated = OUT/f'{name}_broker.w'
    source = original.read_text().replace('\targs_init(argc, argv)',
        '\targs_init(argc, argv)\n\twin_sandbox_root = args_value(c"sandbox-root")\n'
        '\twin_sandbox_origin = args_value(c"sandbox-origin")', 1)
    generated.write_text(source)
    subprocess.run([compiler, 'x64', '--strict', '--import-root', str(ROOT/'win/src'),
                    '--import-root', str(ROOT/'w'), str(generated), '-o', str(OUT/name)], check=True)
shutil.copyfile(WASM, OUT/'mobile.wasm')
class Handler(WorkflowHandler):
    def log_message(self, *_): pass
server = ThreadingHTTPServer(('127.0.0.1', 0), functools.partial(Handler, directory=str(ROOT)))
threading.Thread(target=server.serve_forever, daemon=True).start()
origin = f'http://127.0.0.1:{server.server_port}'
report = {'landlock_abi': ctypes.CDLL(None).syscall(444, 0, 0, 1),
          'wasm_sha256': hashlib.sha256(WASM.read_bytes()).hexdigest(), 'checks': []}
def run(arguments):
    result = subprocess.run([*display, *map(str, arguments)], capture_output=True,
                            text=True, timeout=240)
    if result.returncode:
        print(result.stdout, result.stderr)
        raise AssertionError((arguments, result.returncode))
    print(result.stdout.strip(), flush=True)
    return result
try:
    with tempfile.TemporaryDirectory(prefix='win-broker-acceptance-') as temporary:
        content = Path(temporary)/'content'
        content.mkdir()
        state = Path(temporary)/'storage'
        flags = ['--browser', WIN, '--sandbox-root', content, '--sandbox-origin', origin]
        run([OUT/'isolated_mobile', *flags, '--page', origin+'/w/tools/web/index.html?module=/win/bin/broker-validation/mobile.wasm'])
        report['checks'].append('M2 unchanged wasm/host: native input, focus, typing, resize, canvas ACKs')
        page = origin+'/win/fixtures/workflow/index.html'
        run([OUT/'isolated_workflow', *flags, '--storage', state, '--page', page,
             '--screenshot', OUT/'workflow-800x600.ppm', '--narrow-screenshot', OUT/'workflow-360x640.ppm'])
        report['checks'].append('M3 unchanged Preact: JSON POST, HTTP failure, Abort without late success, native input, history, theme, reload, two viewports')
        for host, expected in (('127.0.0.1', 'green'), ('localhost', 'blue')):
            own_origin = origin.replace('127.0.0.1', host)
            run([OUT/'isolated_workflow', '--browser', WIN, '--sandbox-root', content,
                 '--sandbox-origin', own_origin, '--storage', state,
                 '--page', own_origin+'/win/fixtures/workflow/index.html?view=settings', '--check-theme', expected])
        assert state.stat().st_mode & 0o777 == 0o600
        report['checks'].append('Parent-owned storage persistence, origin separation and 0600 publication outside worker root')
        report['status'] = 'PASS'
finally:
    server.shutdown()
    (OUT/'acceptance.json').write_text(json.dumps(report, indent=2)+'\n')
print(json.dumps(report))
