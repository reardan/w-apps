#!/usr/bin/env python3
"""Real process restart, origin/session separation, atomic mutation and locking."""
import fcntl
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import json
from pathlib import Path
import stat
import subprocess
import sys
import tempfile
import threading

WIN = str(Path(sys.argv[1]).resolve())
PAGES = {
    '/write': "localStorage.setItem('theme','green');sessionStorage.setItem('tab','private');document.title='written';",
    '/read': "document.title=String(localStorage.getItem('theme'))+':'+String(sessionStorage.getItem('tab'));",
    '/other': "localStorage.setItem('theme','blue');document.title='other';",
    '/remove': "localStorage.removeItem('theme');document.title='removed';",
    '/clear': "localStorage.clear();document.title='cleared';",
    '/unicode': "localStorage.setItem('a\\n☃','value\\n😀');document.title=localStorage.getItem('a\\n☃');",
}
class Handler(BaseHTTPRequestHandler):
    def log_message(self, *_):
        pass
    def do_GET(self):
        body = ('<title>pending</title><script>' + PAGES[self.path] + '</script>').encode()
        self.send_response(200)
        self.send_header('Content-Type', 'text/html')
        self.send_header('Content-Length', str(len(body)))
        self.end_headers()
        self.wfile.write(body)

servers = [ThreadingHTTPServer(('127.0.0.1', 0), Handler) for _ in range(2)]
threads = [threading.Thread(target=s.serve_forever, daemon=True) for s in servers]
for t in threads:
    t.start()
try:
    with tempfile.TemporaryDirectory(prefix='win-storage-') as directory:
        path = Path(directory) / 'local.bin'
        report = Path(directory) / 'report.json'
        def visit(route, origin=0, expected=None, success=True):
            result = subprocess.run([WIN, '--dump', '--storage', str(path), '--report', str(report), '--page',
                f'http://127.0.0.1:{servers[origin].server_port}{route}'], capture_output=True, text=True, timeout=20)
            assert (result.returncode == 0) == success, (result.returncode, result.stdout, result.stderr)
            if success:
                data = json.loads(report.read_text())
                assert data['script_failures'] == 0, data
                assert data['title'] == expected, data
            return result
        visit('/write', expected='written')
        assert stat.S_IMODE(path.stat().st_mode) == 0o600
        visit('/read', expected='green:null')
        visit('/read', origin=1, expected='null:null')
        visit('/other', origin=1, expected='other')
        visit('/read', expected='green:null')
        visit('/remove', expected='removed')
        visit('/read', expected='null:null')
        visit('/read', origin=1, expected='blue:null')
        visit('/unicode', expected='value\n😀')
        visit('/clear', expected='cleared')
        visit('/read', origin=1, expected='blue:null')
        assert not list(Path(directory).glob('*.tmp*'))
        saved = path.read_bytes()
        with open(str(path) + '.lock', 'a') as lock:
            fcntl.flock(lock.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB)
            visit('/write', success=False)
        assert path.read_bytes() == saved
        for malformed in (b'', b'WINLS999', b'WINLS001\xff\xff\xff\xff', saved + b'x', b'x' * 1060877):
            path.write_bytes(malformed)
            visit('/write', success=False)
            assert path.read_bytes() == malformed
        path.write_bytes(saved)
        visit('/read', origin=1, expected='blue:null')
        result = subprocess.run([WIN, '--isolated-dump', '--storage', str(path), '--page', '/missing'], capture_output=True, timeout=10)
        assert result.returncode != 0
finally:
    for s in servers:
        s.shutdown()
        s.server_close()
    for t in threads:
        t.join()
print('storage persistence: restart, origins, sessions, mutation, locking and malformed records passed')
