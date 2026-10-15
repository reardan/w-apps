#!/usr/bin/env python3
"""Hermetic resource MIME, redirect/base, decoding and bounded loading checks."""
from __future__ import annotations
import gzip
import http.server
import pathlib
import struct
import subprocess
import sys
import threading
import time
import zlib

WIN = str(pathlib.Path(sys.argv[1]).resolve())
ROOT = pathlib.Path(__file__).resolve().parents[1]
PNG = (ROOT / 'fixtures/resources/checker.png').read_bytes()
REQUESTS: list[str] = []
FORM_REQUESTS: list[tuple[str, bytes]] = []

class Handler(http.server.BaseHTTPRequestHandler):
    def log_message(self, *_):
        pass

    def do_POST(self):
        body = self.rfile.read(int(self.headers.get('Content-Length', '0')))
        if self.path == '/form-loop':
            self.send_response(302)
            self.send_header('Location', '/form-loop')
            self.send_header('Content-Length', '0')
            self.end_headers()
            return
        if self.path.startswith('/post-'):
            self.send_response(int(self.path.removeprefix('/post-')))
            self.send_header('Location', '/form-result')
            self.send_header('Content-Length', '0')
            self.end_headers()
            return
        FORM_REQUESTS.append(('POST', body))
        result = b'<p>POST-result</p>'
        self.send_response(200)
        self.send_header('Content-Type', 'text/html')
        self.send_header('Content-Length', str(len(result)))
        self.end_headers()
        self.wfile.write(result)

    def do_GET(self):
        REQUESTS.append(self.path)
        if self.path == '/form-loop':
            self.send_response(302)
            self.send_header('Location', '/form-loop')
            self.send_header('Content-Length', '0')
            self.end_headers()
            return
        if self.path == '/redirect':
            self.send_response(302)
            self.send_header('Location', '/site/index.html')
            self.send_header('Content-Length', '0')
            self.end_headers()
            return
        if self.path == '/image-redirect':
            self.send_response(302)
            self.send_header('Location', '/site/checker.png')
            self.send_header('Content-Length', '0')
            self.end_headers()
            return
        mime = 'text/html'
        encoding = None
        status = 200
        if self.path == '/form-result':
            body = b'<p>GET-result</p>'
            FORM_REQUESTS.append(('GET', self.rfile.read(int(self.headers.get('Content-Length', '0')))))
        elif self.path == '/site/index.html':
            body = b'''<title>Initial</title><link rel="stylesheet" href="theme.css">
<script src="first.js"></script><script src="second.js"></script>
<p class="hidden">resource-hidden-marker</p><p id="message">initial-marker</p>
<img src="checker.png" alt="checker"><img src="missing.png" alt="missing-fallback">'''
        elif self.path == '/site/theme.css':
            body = b'.hidden { display:none; }'
            mime = 'text/css; charset=utf-8'
        elif self.path == '/site/first.js':
            # The second response is faster; execution must still follow DOM order.
            time.sleep(0.15)
            body = b'document.title = "First script";'
            mime = 'application/javascript'
        elif self.path == '/site/second.js':
            body = b'if (document.title === "First script") { document.title = "Ordered scripts"; document.getElementById("message").textContent = "script-updated-marker"; }'
            mime = 'text/javascript'
        elif self.path == '/site/slow.css':
            time.sleep(0.5)
            body, mime = b'p { display:none; }', 'text/css'
        elif self.path == '/site/slow.js':
            time.sleep(0.5)
            body, mime = b'document.title = "Stale script";', 'text/javascript'
        elif self.path == '/site/slow.png':
            time.sleep(0.3)
            body, mime = PNG, 'image/png'
        elif self.path == '/site/checker.png':
            body, mime = PNG, 'image/png'
        elif self.path == '/compressed.css':
            body, mime, encoding = gzip.compress(b'p { color: red; }'), 'text/css', 'gzip'
        elif self.path == '/huge-image':
            header = struct.pack('>IIBBBBB', 4097, 1, 8, 6, 0, 0, 0)
            chunk = b'IHDR' + header
            body = PNG[:8] + struct.pack('>I', len(header)) + chunk + struct.pack('>I', zlib.crc32(chunk))
            mime = 'image/png'
        elif self.path == '/bad-image':
            body, mime = b'not a png image', 'image/png'
        elif self.path == '/oversized.css':
            body, mime = b'x' * (1048576 + 1), 'text/css'
        elif self.path == '/compressed-limit.css':
            body, mime, encoding = gzip.compress(b'x' * (1048576 + 1)), 'text/css', 'gzip'
        elif self.path == '/bad-utf8.js':
            body, mime = b'\xff', 'text/javascript'
        elif self.path == '/mime-prefix':
            body, mime = b'p { color: red; }', 'text/css-fake'
        elif self.path == '/mime-case':
            body, mime = b'p { color: red; }', 'Text/CSS; charset=UTF-8'
        elif self.path == '/bad-utf8.html':
            body = b'<script src="/bad-utf8.js"></script><p>survives-bad-script</p>'
        elif self.path == '/wrong-type':
            body = b'<html>an error document</html>'
        else:
            status, body = 404, b'not found'
        self.send_response(status)
        self.send_header('Content-Type', mime)
        if encoding:
            self.send_header('Content-Encoding', encoding)
        self.send_header('Content-Length', str(len(body)))
        self.end_headers()
        try:
            self.wfile.write(body)
        except (BrokenPipeError, ConnectionResetError):
            pass

server = http.server.ThreadingHTTPServer(('127.0.0.1', 0), Handler)
thread = threading.Thread(target=server.serve_forever, daemon=True)
thread.start()
base = f'http://127.0.0.1:{server.server_port}'

def worker(path: str, kind: str, ok: bool = True) -> bytes:
    result = subprocess.run([WIN, '--resource', base + path, '--kind', kind], capture_output=True, timeout=15)
    assert (result.returncode == 0) == ok, (path, result.returncode, result.stdout[:300], result.stderr[:300])
    assert result.stdout.startswith(b'OK\n' if ok else b'ERROR\n'), (path, result.stdout[:300])
    return result.stdout

try:
    for status in (301, 302, 303, 307, 308):
        result = subprocess.run([WIN, '--fetch', base + '/post-' + str(status), '--method', 'POST', '--body', 'a=one&b=two'], capture_output=True, timeout=15)
        assert result.returncode == 0, (status, result.stdout, result.stderr)
        expected = ('GET', b'') if status in (301, 302, 303) else ('POST', b'a=one&b=two')
        assert FORM_REQUESTS[-1] == expected, (status, FORM_REQUESTS)
        assert result.stdout.split(b'\n', 2)[1].decode() == base + '/form-result'
    loop = subprocess.run([WIN, '--fetch', base + '/form-loop', '--method', 'POST', '--body', 'a=one'], capture_output=True, timeout=15)
    assert loop.returncode != 0 and b'too many redirects' in loop.stdout, loop.stdout
    output = worker('/image-redirect', 'image')
    _, address, pixels = output.split(b'\n', 2)
    assert address.decode() == base + '/site/checker.png', address
    assert struct.unpack('>II', pixels[:8]) == (8, 8)
    assert len(pixels) == 8 + 8 * 8 * 4
    assert pixels[8:12] == bytes([220, 64, 48, 255])
    assert worker('/compressed.css', 'css').endswith(b'p { color: red; }')
    worker('/wrong-type', 'css', False)
    worker('/wrong-type', 'script', False)
    worker('/bad-image', 'image', False)
    worker('/huge-image', 'image', False)
    worker('/mime-prefix', 'css', False)
    worker('/mime-case', 'css')
    worker('/oversized.css', 'css', False)
    worker('/compressed-limit.css', 'css', False)
    worker('/site/missing.png', 'image', False)
    resource_test = pathlib.Path(WIN).parent / 'resources_test'
    if resource_test.exists():
        before = len(REQUESTS)
        subprocess.run([str(resource_test), '--slow', WIN, base + '/site/index.html'], check=True, timeout=8)
        dynamic_requests = REQUESTS[before:]
        for path in ('/site/checker.png', '/site/theme.css', '/site/second.js'):
            assert dynamic_requests.count(path) == 1, dynamic_requests
    invalid = subprocess.run([WIN, '--dump', '--page', base + '/bad-utf8.html'], capture_output=True, text=True, timeout=20)
    assert invalid.returncode == 0 and 'survives-bad-script' in invalid.stdout, (invalid.stdout, invalid.stderr)
    result = subprocess.run([WIN, '--dump', '--page', base + '/redirect'], capture_output=True, text=True, timeout=20)
    assert result.returncode == 0, result.stderr
    assert 'Ordered scripts' in result.stdout, result.stdout
    assert 'script-updated-marker' in result.stdout, result.stdout
    assert 'resource-hidden-marker' not in result.stdout, result.stdout
    assert 'missing-fallback' in result.stdout, result.stdout
    for resource in ['theme.css', 'first.js', 'second.js', 'checker.png', 'missing.png']:
        assert '/site/' + resource in REQUESTS, REQUESTS
    print('HTTP resource integration tests passed')
finally:
    server.shutdown()
    server.server_close()
