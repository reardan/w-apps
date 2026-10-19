#!/usr/bin/env python3
"""Real isolated worker Tab ordering, focus snapshots and Enter navigation."""
import os
from pathlib import Path
import re
import socket
import struct
import subprocess
import sys
import tempfile

WIN = str(Path(sys.argv[1]).resolve())


def read(sock, size):
    data = bytearray()
    while len(data) < size:
        chunk = sock.recv(size - len(data))
        assert chunk, 'truncated worker reply'
        data += chunk
    return bytes(data)


def snapshot(sock, sequence):
    magic, length, seq, kind, revision = struct.unpack('<8s4i', read(sock, 24))
    assert (magic, seq, kind, revision) == (b'WINT0001', sequence, 102, 2)
    data = read(sock, length)
    assert struct.unpack_from('<3i', data) == (0, 0, 0)
    meta = struct.unpack_from('<9i', data, 12)
    address, title, html, empty = data[48:].split(b'\0')
    assert not empty
    return meta, address.decode(), title.decode(), html.decode()


def send(sock, sequence, document, events):
    payload = struct.pack('<9i', 9, document, 390, 300, len(events), 0, 0, 0, 0)
    payload += b''.join(struct.pack('<5i', *event) for event in events)
    sock.sendall(struct.pack('<8s4i', b'WINT0001', len(payload), sequence, 5, 2) + payload)


def focus_id(html, element):
    tag = re.search(r'<[^>]+id="' + element + r'"[^>]*>', html)[0]
    return int(re.search(r'data-win-node="(\d+)"', tag)[1])


with tempfile.TemporaryDirectory(prefix='win-keyboard-focus-') as directory:
    page = Path(directory) / 'focus.html'
    page.write_text('''<body><a id="link" href="#target"><span>First link</span></a>
<button id="priority" tabindex="1">Priority</button>
<div id="generic" tabindex="0" style="pointer-events:none">Generic focus</div>
<a id="cancel" href="#blocked">Cancelled link</a><input id="editor" value="a">
<div style="height:500px"></div><div id="target">Target</div><script>
document.addEventListener('focusin',function(e){document.title='focus:'+e.target.id;});
document.getElementById('link').onclick=function(e){if(!e.isTrusted)throw 'untrusted';document.title='click:link';};
document.getElementById('cancel').onclick=function(e){e.preventDefault();document.title='click:cancel';};
document.getElementById('editor').oninput=function(){document.title='edit:'+this.value;};
</script></body>''')
    parent, child = socket.socketpair()
    parent.settimeout(15)
    process = subprocess.Popen([WIN, '--interactive-worker', '--page', str(page),
        '--worker-limit', '8388608', '--worker-generation', '9',
        '--worker-width', '390', '--worker-height', '300'], stdin=child,
        stdout=subprocess.DEVNULL, stderr=subprocess.PIPE,
        env=dict(os.environ, WIN_SCRIPT_WORKER_PARENT=str(os.getpid())))
    child.close()
    try:
        meta, original, _, _ = snapshot(parent, 0)
        document = meta[1]
        for sequence, scalar, mods, expected in [(1, 9, 0, 'priority'), (2, 9, 0, 'link'),
                                                 (3, 9, 1, 'priority'), (4, 9, 0, 'link')]:
            send(parent, sequence, document, [(3, scalar, 0, 0, mods)])
            meta, address, title, html = snapshot(parent, sequence)
            assert title == f'focus:{expected}', (sequence, title)
            assert meta[2] == focus_id(html, expected), (meta, html)
        send(parent, 5, document, [(3, 13, 0, 0, 0)])
        meta, address, title, html = snapshot(parent, 5)
        assert title == 'click:link' and address == original + '#target', (title, address)
        assert meta[6] > 0, meta
        send(parent, 6, document, [(3, 9, 0, 0, 0)])
        meta, address, title, html = snapshot(parent, 6)
        assert title == 'focus:generic' and meta[2] == focus_id(html, 'generic'), (title, meta)
        send(parent, 7, document, [(3, 9, 0, 0, 0), (3, 13, 0, 0, 0)])
        meta, address, title, html = snapshot(parent, 7)
        assert title == 'click:cancel' and address == original + '#target', (title, address)
        send(parent, 8, document, [(3, 9, 0, 0, 0), (3, ord('z'), 0, 0, 0)])
        meta, address, title, html = snapshot(parent, 8)
        assert title == 'edit:za' and meta[2] == focus_id(html, 'editor'), (title, meta)
    finally:
        parent.close()
        if process.poll() is None:
            process.terminate()
        process.wait(timeout=5)
        process.stderr.close()
print('Isolated sequential focus, focus snapshots, Enter navigation and editing: OK')
