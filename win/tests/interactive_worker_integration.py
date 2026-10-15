#!/usr/bin/env python3
"""Exercise the real persistent child, event state, navigation and broken IPC."""
import os
import http.server
import shutil
import threading
import time
import pathlib
import re
import socket
import struct
import subprocess
import sys
import tempfile

binary = str(pathlib.Path(sys.argv[1]).resolve())


def receive(sock, count):
    chunks = bytearray()
    while len(chunks) < count:
        chunk = sock.recv(count - len(chunks))
        assert chunk, 'unexpected EOF'
        chunks.extend(chunk)
    return bytes(chunks)


def snapshot(sock, sequence):
    header = receive(sock, 24)
    magic, size, seq, kind, reserved = struct.unpack('<8siiii', header)
    assert (magic, seq, kind, reserved) == (b'WINT0001', sequence, 100, 0)
    assert 11 <= size <= 8 * 1024 * 1024 - 24
    payload = receive(sock, size)
    scripts, resources = struct.unpack('<ii', payload[:8])
    assert (scripts, resources) == (0, 0), (scripts, resources)
    address, title, html, empty = payload[8:].split(b'\0')
    assert not empty
    return address.decode(), title.decode(), html.decode()


def request(sock, sequence, kind, node=0, value=''):
    payload = struct.pack('<i', node) + value.encode()
    sock.sendall(struct.pack('<8siiii', b'WINT0001', len(payload), sequence, kind, 0) + payload)
    return snapshot(sock, sequence)


def node_id(html, name):
    tag = re.search(r'<[^>]+\bid="' + name + r'"[^>]*>', html)
    assert tag, (name, html)
    return int(re.search(r'data-win-node="(\d+)"', tag[0])[1])


with tempfile.TemporaryDirectory() as directory:
    page = pathlib.Path(directory) / 'page.html'
    next_page = pathlib.Path(directory) / 'next.html'
    next_page.write_text('<title>Next page</title><p>navigated</p>')
    page.write_text('''<title>Initial</title><p id="result">before</p>
<button id="button">increment</button><input id="input"><a id="link" href="next.html">next</a>
<script>
var count=0;
document.getElementById('button').addEventListener('click',function(){count=count+1;if(count===1){document.title='click 1';document.getElementById('result').textContent='changed 1';}else if(count===2){document.title='click 2';document.getElementById('result').textContent='changed 2';}else{throw 'bad retained count';}});
document.getElementById('input').addEventListener('input',function(){document.title=this.value;});
document.title='Loaded';
</script>''')
    parent, child = socket.socketpair()
    parent.settimeout(5)
    env = dict(os.environ, WIN_SCRIPT_WORKER_PARENT=str(os.getpid()))
    process = subprocess.Popen([binary, '--interactive-worker', '--page', str(page),
                                '--worker-limit', '8388608'], stdin=child,
                               stdout=subprocess.DEVNULL, stderr=subprocess.PIPE, env=env)
    child.close()
    try:
        _, title, html = snapshot(parent, 0)
        assert title == 'Loaded' and '<script' not in html, (title, html)
        pid = process.pid
        for seq in (1, 2):
            _, title, html = request(parent, seq, 2, node_id(html, 'button'))
            assert title == f'click {seq}' and f'changed {seq}' in html, (title, html)
            assert process.poll() is None and process.pid == pid
        _, title, html = request(parent, 3, 3, node_id(html, 'input'), 'typed & text')
        assert title == 'typed & text' and 'typed &amp; text' in html, (title, html)
        _, title, html = request(parent, 4, 1)
        assert title == 'typed & text'
        address, title, html = request(parent, 5, 2, node_id(html, 'link'))
        assert title == 'Next page' and 'navigated' in html and address.endswith('next.html'), (address, title, html)
        # Out-of-sequence requests must close the protocol, never dispatch.
        parent.sendall(struct.pack('<8siiii', b'WINT0001', 4, 99, 1, 0) + struct.pack('<i', 0))
        process.wait(timeout=3)
        try:
            assert parent.recv(1) == b''
        except ConnectionResetError:
            pass  # Rejected header leaves unread payload when the child closes.
    finally:
        parent.close()
        if process.poll() is None:
            process.kill()
        process.wait(timeout=3)
        process.stderr.close()
    result = subprocess.run([binary, '--isolated-interactive', '--dump', '--page', str(page)],
                            capture_output=True, text=True, timeout=8)
    assert result.returncode == 0 and 'Loaded' in result.stdout and 'before' in result.stdout, result
# A real native UI must finish its frame budget while the content child waits
# for a slow resource. This is conditional only on display availability.
class SlowHandler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        time.sleep(5)
        self.send_response(200)
        self.end_headers()
        try:
            self.wfile.write(b'<p>late content</p>')
        except (BrokenPipeError, ConnectionResetError):
            pass

    def log_message(self, *_):
        pass


if os.environ.get('DISPLAY') or shutil.which('xvfb-run'):
    server = http.server.ThreadingHTTPServer(('127.0.0.1', 0), SlowHandler)
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    try:
        with tempfile.TemporaryDirectory() as directory:
            capture = pathlib.Path(directory) / 'responsive.ppm'
            prefix = [] if os.environ.get('DISPLAY') else ['xvfb-run', '-a']
            result = subprocess.run(prefix + [binary, '--isolated-interactive', '--page',
                                    f'http://127.0.0.1:{server.server_port}/slow', '--frames', '24',
                                    '--screenshot', str(capture)], capture_output=True, text=True, timeout=4)
            assert result.returncode == 0 and capture.read_bytes().startswith(b'P6\n'), result
    finally:
        server.shutdown()
        server.server_close()
    print('isolated native UI stays responsive during slow child loading: OK')
else:
    print('isolated native UI check skipped: no X11 display or xvfb-run')
print('interactive worker real events, persistent state, navigation and parent dump: OK')
