#!/usr/bin/env python3
"""Parent-owned Storage: real children, commits, graphics and wire failures."""
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import json
import os
from pathlib import Path
import socket
import struct
import subprocess
import sys
import tempfile
import threading

ROOT = Path(__file__).resolve().parents[2]
WIN = str(Path(sys.argv[1]).resolve())
if not os.environ.get('DISPLAY'):
    raise SystemExit(subprocess.call(['xvfb-run', '-a', sys.executable, __file__, WIN]))
PAGES = {
    '/write': "localStorage.setItem('theme','green');sessionStorage.setItem('tab','private');if(localStorage.getItem('theme')!=='green')throw 'sync';document.title='written';",
    '/read': "document.title=String(localStorage.getItem('theme'))+':'+String(sessionStorage.getItem('tab'));",
    '/other': "localStorage.setItem('theme','blue');document.title='other';",
    '/unicode': "localStorage.setItem('key ☃','value 😀');document.title=localStorage.getItem('key ☃');",
    '/bounds': "let value='x';for(let i=0;i<16;i++)value=value+value;localStorage.setItem('max',value);if(localStorage.getItem('max').length!==65536)throw 'bound';let over='☃';for(let i=0;i<15;i++)over=over+over;let caught=0;try{localStorage.setItem('over',over);}catch(e){if(e.name==='QuotaExceededError')caught=1;}if(caught!==1||localStorage.getItem(over)!==null)throw 'quota';localStorage.removeItem(over);localStorage.removeItem('max');if(localStorage.getItem('max')!==null)throw 'remove';sessionStorage.clear();if(sessionStorage.length!==0||sessionStorage.key(0)!==null)throw 'clear';sessionStorage.setItem('tab','private');document.title='bounds';",
    '/parallel-a': "localStorage.setItem('a','A');document.title='a';",
    '/parallel-b': "localStorage.setItem('b','B');document.title='b';",
    '/parallel-read': "document.title=localStorage.getItem('a')+':'+localStorage.getItem('b');",
    '/destination': "document.title='cross-executed';",
    '/rpc': "localStorage.getItem('wire');document.title='reply';",
}
servers = []
class Handler(BaseHTTPRequestHandler):
    def log_message(self, *_): pass
    def do_GET(self):
        if self.path in ('/same', '/cross'):
            self.send_response(302)
            location = '/read' if self.path == '/same' else f'http://127.0.0.1:{servers[1].server_port}/destination'
            self.send_header('Location', location)
            self.send_header('Content-Length', '0')
            self.end_headers()
            return
        body = ('<title>pending</title><script>' + PAGES[self.path] + '</script>').encode()
        self.send_response(200)
        self.send_header('Content-Type', 'text/html')
        self.send_header('Content-Length', str(len(body)))
        self.end_headers()
        self.wfile.write(body)

def receive(sock, count):
    result = bytearray()
    while len(result) < count:
        chunk = sock.recv(count-len(result))
        assert chunk, 'truncated response'
        result += chunk
    return bytes(result)

servers = [ThreadingHTTPServer(('127.0.0.1', 0), Handler) for _ in range(2)]
threads = [threading.Thread(target=s.serve_forever, daemon=True) for s in servers]
for thread in threads: thread.start()
try:
    with tempfile.TemporaryDirectory(prefix='win-isolated-storage-') as temp:
        temp = Path(temp)
        probe = temp / 'probe'
        source = ROOT / 'win/tests/isolated_storage_probe.w'
        imports = ['--import-root', str(ROOT / 'win/src'), '--import-root', str(ROOT / 'w')]
        compiler = ROOT / 'w/bin/wv2'
        subprocess.run([str(compiler), 'x64', 'check', '--json', *imports, str(source)], check=True)
        subprocess.run([str(compiler), 'x64', '--strict', *imports, str(source), '-o', str(probe)], check=True)
        origins = [f'http://127.0.0.1:{s.server_port}' for s in servers]
        path = temp / 'state'
        subprocess.run([str(probe), '--win', WIN, '--origin', origins[0], '--other', origins[1], '--path', str(path)], check=True, timeout=120)
        assert path.stat().st_mode & 0o777 == 0o600
        # CLI profile wiring and real displayed window, with fresh process state.
        report = temp / 'report.json'
        subprocess.run([WIN, '--isolated-interactive', '--storage', str(path), '--page', origins[0]+'/read', '--frames', '160', '--report', str(report)], check=True, timeout=30)
        data = json.loads(report.read_text())
        assert data['title'] == 'green:null' and data['script_failures'] == 0, data
        # Child rejects stale generation/sequence or oversized reply before alloc.
        # Valid reply is deliberately fragmented one byte at a time over AF_UNIX.
        for fault in ('fragmented', 'generation', 'sequence', 'oversized', 'disconnect'):
            parent, child = socket.socketpair()
            parent.settimeout(10)
            proc = subprocess.Popen([WIN, '--interactive-worker', '--page', origins[0]+'/rpc', '--home', '', '--worker-limit', '8388608', '--worker-generation', '0', '--worker-storage-origin', origins[0]], stdin=child, stdout=subprocess.DEVNULL, stderr=subprocess.PIPE)
            child.close()
            try:
                header = receive(parent, 24)
                magic, size, seq, kind, revision = struct.unpack('<8siiii', header)
                assert (magic, seq, kind, revision) == (b'WINT0001', 1, 200, 1)
                payload = receive(parent, size)
                generation, session, operation, index, keylen, vallen = struct.unpack('<6i', payload[:24])
                assert (generation, session, operation, keylen) == (0, 0, 0, 4)
                assert payload[24:28] == b'wire'
                if fault == 'disconnect':
                    parent.close()
                    proc.wait(timeout=5)
                    continue
                replygen = 1 if fault == 'generation' else 0
                replyseq = 2 if fault == 'sequence' else 1
                textlen = 2147483647 if fault == 'oversized' else 0
                response = struct.pack('<8s9i', b'WINT0001', 20+textlen if textlen < 100 else 20, replyseq, 201, 1, replygen, 0, 1, 0, textlen)
                for byte in response: parent.sendall(bytes([byte]))
                snapshot = receive(parent, 24)
                _, size, seq, kind, revision = struct.unpack('<8siiii', snapshot)
                body = receive(parent, size)
                failures = struct.unpack('<i', body[:4])[0]
                assert failures == (0 if fault == 'fragmented' else 1), (fault, failures, body[:100])
            finally:
                parent.close()
                proc.kill()
                proc.wait(timeout=5)
finally:
    for server in servers:
        server.shutdown()
        server.server_close()
    for thread in threads: thread.join()
print('isolated parent storage: shared owners, restart, origin pinning, CLI, fragmented/malformed replies passed')
