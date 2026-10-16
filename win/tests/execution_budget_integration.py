#!/usr/bin/env python3
"""Explicit execution policy: default/override bounds and real Wasm exhaustion."""
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import threading

WIN = str(Path(sys.argv[1]).resolve())

def leb(value):
    output = bytearray()
    while value >= 128:
        output.append((value & 127) | 128)
        value >>= 7
    return bytes(output + bytes([value]))

def section(kind, contents):
    return bytes([kind]) + leb(len(contents)) + contents

# f() counts down from 200,000 and returns 7: >1m interpreted instructions,
# no per-iteration JS allocation, imports, network or timing dependence.
body = bytes.fromhex('01017f41c09a0c2100024003402000450d01200041016b21000c000b0b41070b')
WASM = (bytes.fromhex('0061736d01000000') + section(1, bytes.fromhex('016000017f'))
        + section(3, bytes.fromhex('0100')) + section(7, bytes.fromhex('0101660000'))
        + section(10, b'\x01' + leb(len(body)) + body))

class Handler(BaseHTTPRequestHandler):
    def log_message(self, *_):
        pass

    def do_GET(self):
        if self.path == '/loop.wasm':
            data, mime = WASM, 'application/wasm'
        else:
            data = b'''<title>PENDING</title><script type="module">
const p=await WebAssembly.instantiateStreaming(fetch('/loop.wasm'));
document.title=p.instance.exports.f()===7?'PASS':'BAD';
</script>'''
            mime = 'text/html'
        self.send_response(200)
        self.send_header('Content-Type', mime)
        self.send_header('Content-Length', str(len(data)))
        self.end_headers()
        self.wfile.write(data)

server = ThreadingHTTPServer(('127.0.0.1', 0), Handler)
thread = threading.Thread(target=server.serve_forever, daemon=True)
thread.start()
try:
    with tempfile.TemporaryDirectory(prefix='win-execution-') as directory:
        report = Path(directory) / 'report.json'
        command = [WIN, '--dump', '--report', str(report), '--page',
                   f'http://127.0.0.1:{server.server_port}/page']
        for budget, passes in ((None, False), ('1000000', False), ('5000000', True),
                               ('200000000', True), ('1', False)):
            result = subprocess.run(command + ([] if budget is None else ['--execution-budget', budget]),
                                    capture_output=True, text=True, timeout=30)
            assert result.returncode == 0, (budget, result.stdout, result.stderr)
            data = json.loads(report.read_text())
            if passes:
                assert data['title'] == 'PASS' and data['script_failures'] == 0, (budget, data)
            else:
                assert data['title'] != 'PASS' and data['script_failures'] > 0, (budget, data)
        for budget, passes in (('1000000', False), ('5000000', True)):
            result = subprocess.run(command + ['--isolated-interactive', '--execution-budget', budget],
                                    capture_output=True, text=True, timeout=30)
            assert result.returncode == 0, (budget, result.stdout, result.stderr)
            data = json.loads(report.read_text())
            assert (data['title'] == 'PASS' and data['script_failures'] == 0) == passes, data
        for invalid in ('0', '-1', '200000001', '99999999999999999999', '1x', '+2', '1.5', ''):
            result = subprocess.run([WIN, '--dump', '--execution-budget', invalid],
                                    capture_output=True, text=True, timeout=10)
            assert result.returncode != 0 and 'Execution budget must be' in result.stderr, (invalid, result)
        for mode in ('--isolated-dump',):
            result = subprocess.run([WIN, mode, '--execution-budget', '5000000'],
                                    capture_output=True, text=True, timeout=10)
            assert result.returncode != 0 and 'not yet forwarded' in result.stderr, result
finally:
    server.shutdown()
    server.server_close()
    thread.join()
print('execution budget: default fuel, explicit overrides, exhaustion and invalid policy rejection passed')
