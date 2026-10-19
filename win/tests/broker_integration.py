#!/usr/bin/env python3
"""Real Landlock/seccomp worker plus parent broker, loopback only."""
import ctypes
import http.server
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import threading
import time

WIN = str(Path(sys.argv[1]).resolve())
ROOT = Path(__file__).resolve().parents[2]
# Deliberately independent output; never replaces the application's binary.
OUT = ROOT / 'win/bin/broker-validation'
OUT.mkdir(parents=True, exist_ok=True)
compiler = os.environ.get('WIN_TEST_COMPILER', str(ROOT / 'w/bin/wv2'))
subprocess.run([compiler, 'x64', '--strict', '--import-root', str(ROOT/'win/src'),
                '--import-root', str(ROOT/'w'), str(ROOT/'win/tests/broker_harness.w'),
                '-o', str(OUT/'harness')], check=True)
if ctypes.CDLL(None).syscall(444, 0, 0, 1) < 8:
    print('SKIP broker kernel test: Landlock ABI8 unavailable')
    raise SystemExit(0)

hits = []
slow_closed = threading.Event()
class Server(http.server.BaseHTTPRequestHandler):
    def log_message(self, *_): pass
    def do_POST(self):
        length = int(self.headers.get("Content-Length", "0"))
        body = self.rfile.read(length)
        assert self.path == "/echo" and body == b"\x00\xff" + b"\x00"*65534
        result = b"BROKER-PASS"
        self.send_response(200)
        self.send_header("Content-Type", "text/plain")
        self.send_header("Content-Length", str(len(result)))
        self.end_headers()
        self.wfile.write(result)
    def do_GET(self):
        hits.append(self.path)
        if self.path == '/redirect-cross':
            self.send_response(302)
            self.send_header('Location', f'http://localhost:{self.server.server_port}/forbidden')
            self.end_headers()
            return
        if self.path == '/slow':
            self.connection.settimeout(5)
            if self.connection.recv(1) == b'': slow_closed.set()
            return
        if self.path == '/style.css':
            body, mime = b'body { color: green; }', 'text/css'
        elif self.path == '/app.js':
            body, mime = b'document.title="BROKER-PASS";', 'text/javascript'
        elif self.path == '/data':
            if '/slow' in hits:
                assert slow_closed.wait(1), 'Abort did not cancel the helper before the next request'
            body, mime = b'BROKER-PASS', 'text/plain'
        elif self.path == '/oversize-data':
            body, mime = b'x' * 4194305, 'application/octet-stream'
        elif self.path == '/module.wasm':
            body, mime = bytes.fromhex('0061736d01000000'), 'application/wasm'
        else:
            scripts = {
                '/linked': '<link rel="stylesheet" href="/style.css"><script src="/app.js"></script>',
                '/tab-header': '<script>fetch("/data",{headers:{Accept:"text/plain;\\tq=0.9"}}).then(function(r){return r.text();}).then(function(t){document.title=t;});</script>',
                '/binary': '<script>var b=new Uint8Array(65536);b[1]=255;fetch("/echo",{method:"POST",body:b}).then(function(r){return r.text();}).then(function(t){document.title=t;});</script>',
                '/oversize': '<script>fetch("/oversize-data").catch(function(){document.title="BROKER-PASS";});</script>',
                '/fetch': '<script>fetch("/data").then(function(r){return r.text();}).then(function(t){document.title=t;});</script>',
                '/wasm': '<script>WebAssembly.instantiateStreaming(fetch("/module.wasm")).then(function(){document.title="BROKER-PASS";});</script>',
                '/cross': '<script>fetch("/redirect-cross").catch(function(){document.title="BROKER-PASS";});</script>',
                '/abort': '<script>var c=new AbortController();fetch("/slow",{signal:c.signal}).catch(function(){fetch("/data").then(function(r){return r.text();}).then(function(t){document.title=t;});});setTimeout(function(){c.abort();},300);</script>',
            }
            body, mime = ('<title>waiting</title>'+scripts.get(self.path, '<title>FORBIDDEN</title>')).encode(), 'text/html'
        self.send_response(200)
        self.send_header('Content-Type', mime)
        self.send_header('Content-Length', str(len(body)))
        self.end_headers()
        try: self.wfile.write(body)
        except (BrokenPipeError, ConnectionResetError): pass

server = http.server.ThreadingHTTPServer(('127.0.0.1', 0), Server)
threading.Thread(target=server.serve_forever, daemon=True).start()
origin = f'http://127.0.0.1:{server.server_port}'
try:
    with tempfile.TemporaryDirectory(prefix='win-broker-root-') as content:
        for route in ('/linked', '/fetch', '/tab-header', '/binary', '/wasm', '/cross', '/oversize', '/abort'):
            before = time.monotonic()
            result = subprocess.run([str(OUT/'harness'), '--win', WIN, '--root', content,
                                     '--origin', origin, '--page', origin+route],
                                    capture_output=True, timeout=25)
            assert result.returncode == 0, (route, result.stdout, result.stderr)
            if route == '/abort': assert time.monotonic()-before < 4
            print('PASS broker', route)
        assert '/forbidden' not in hits, hits
        assert slow_closed.wait(2), 'aborted loader was not disconnected/reaped'
        rejected = subprocess.run([WIN, '--sandbox-origin', origin, '--dump', '--page', origin],
                                  capture_output=True, timeout=5)
        assert rejected.returncode == 1 and b'Sandbox origin requires' in rejected.stderr
finally:
    server.shutdown()
print('Sandbox HTTP broker integration passed')
