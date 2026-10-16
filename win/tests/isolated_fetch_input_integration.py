#!/usr/bin/env python3
"""An in-flight Fetch cannot block the worker's native Cancel button."""
import http.server
import os
from pathlib import Path
import re
import socket
import struct
import subprocess
import sys
import threading

WIN = str(Path(sys.argv[1]).resolve())
started, release = threading.Event(), threading.Event()
HTML = b'''<button id="start">Start</button><button id="cancel">Cancel</button><script>
let pending=null;
const start=document.getElementById('start'), cancel=document.getElementById('cancel');
for (const button of [start,cancel]) {
 const r=button.getBoundingClientRect();
 button.setAttribute('data-x',JSON.stringify(r.x+5));
 button.setAttribute('data-y',JSON.stringify(r.y+5));
}
start.onclick=function(){pending=new AbortController();document.title='pending';
 fetch('/slow',{signal:pending.signal}).then(function(){document.title='completed';})
 .catch(function(error){document.title=error.name;});};
cancel.onclick=function(){pending.abort();if(pending.signal.aborted)document.title='abort-called';};
</script>'''

class Handler(http.server.BaseHTTPRequestHandler):
    def log_message(self, *_): pass
    def do_GET(self):
        body = HTML
        if self.path == '/slow':
            started.set()
            release.wait(15)
            body = b'late response'
        self.send_response(200)
        self.send_header('Content-Type', 'text/html' if self.path == '/' else 'text/plain')
        self.send_header('Content-Length', str(len(body)))
        self.end_headers()
        try: self.wfile.write(body)
        except (BrokenPipeError, ConnectionResetError): pass

def read(sock, length):
    data = bytearray()
    while len(data) < length:
        part = sock.recv(length - len(data))
        assert part, 'truncated child snapshot'
        data.extend(part)
    return bytes(data)

def snapshot(sock, sequence):
    magic, length, seq, kind, revision = struct.unpack('<8s4i', read(sock, 24))
    assert (magic, seq, kind, revision) == (b'WINT0001', sequence, 102, 2)
    payload = read(sock, length)
    assert struct.unpack_from('<3i', payload) == (0, 0, 0)
    metadata = struct.unpack_from('<9i', payload, 12)
    _, title, html, empty = payload[48:].split(b'\0')
    assert not empty
    return metadata, title.decode(), html.decode()

def request(sock, sequence, document, kind=0, x=0, y=0):
    count = int(kind != 0)
    payload = struct.pack('<9i', 9, document, 390, 720, count, x, y, 0, 0)
    if kind: payload += struct.pack('<5i', kind, 1, x, y, 0)
    sock.sendall(struct.pack('<8s4i', b'WINT0001', len(payload), sequence, 5, 2) + payload)
    return snapshot(sock, sequence)

server = http.server.ThreadingHTTPServer(('127.0.0.1', 0), Handler)
thread = threading.Thread(target=server.serve_forever, daemon=True)
thread.start()
parent, child = socket.socketpair()
parent.settimeout(5)
process = subprocess.Popen([WIN, '--interactive-worker', '--page', f'http://127.0.0.1:{server.server_port}/',
    '--worker-limit', '8388608', '--worker-generation', '9', '--worker-width', '390', '--worker-height', '720'],
    stdin=child, stdout=subprocess.DEVNULL, stderr=subprocess.PIPE,
    env=dict(os.environ, WIN_SCRIPT_WORKER_PARENT=str(os.getpid())))
child.close()
try:
    metadata, _, html = snapshot(parent, 0)
    document = metadata[1]
    def point(name):
        tag = re.search(r'<button[^>]*id="' + name + r'"[^>]*>', html)[0]
        return tuple(int(float(re.search(r'data-' + key + r'="([^"]+)"', tag)[1])) for key in ('x', 'y'))
    request(parent, 1, document, 4, *point('start'))
    _, title, _ = request(parent, 2, document, 5, *point('start'))
    assert title == 'pending', title
    _, title, _ = request(parent, 3, document)
    assert title == 'pending', title
    assert started.wait(5), 'Fetch never reached HTTP server'
    # The server deliberately cannot finish until after both native edges.
    _, title, _ = request(parent, 4, document, 4, *point('cancel'))
    assert title == 'pending', title
    _, title, _ = request(parent, 5, document, 5, *point('cancel'))
    assert title in ('abort-called', 'AbortError'), title
    _, title, _ = request(parent, 6, document)
    assert title == 'AbortError', title
    release.set()
    for sequence in range(7, 12):
        _, title, _ = request(parent, sequence, document)
        assert title == 'AbortError', ('late completion overwrote cancellation', title)
finally:
    release.set()
    parent.close()
    if process.poll() is None: process.kill()
    process.wait(timeout=5)
    process.stderr.close()
    server.shutdown()
    server.server_close()
    thread.join()
print('Isolated native input remains responsive during Fetch; cancellation rejects without late completion: OK')
