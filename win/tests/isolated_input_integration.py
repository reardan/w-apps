#!/usr/bin/env python3
"""Real child raw-input validation, Unicode edits, composition and stale epochs."""
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
        assert chunk, 'truncated reply'
        data += chunk
    return bytes(data)


def snapshot(sock, sequence):
    magic, length, seq, kind, revision = struct.unpack('<8s4i', read(sock, 24))
    assert (magic, seq, kind, revision) == (b'WINT0001', sequence, 102, 2)
    data = read(sock, length)
    scripts, resources, count = struct.unpack_from('<3i', data)
    assert (scripts, resources, count) == (0, 0, 0), (scripts, resources, count)
    meta = struct.unpack_from('<9i', data, 12)
    address, title, html, empty = data[48:].split(b'\0')
    assert not empty
    return meta, title.decode(), html.decode()


def send(sock, sequence, document, events, generation=9):
    mouse = next(((event[2], event[3]) for event in reversed(events) if event[0] in (4, 5)), (30, 150))
    payload = struct.pack('<9i', generation, document, 390, 720, len(events), *mouse, 0, 0)
    payload += b''.join(struct.pack('<5i', *event) for event in events)
    sock.sendall(struct.pack('<8s4i', b'WINT0001', len(payload), sequence, 5, 2) + payload)


with tempfile.TemporaryDirectory(prefix='win-raw-input-') as directory:
    page = Path(directory) / 'input.html'
    page.write_text('''<textarea id="editor">old</textarea><button id="button">Add</button><script>
const editor=document.getElementById('editor');let log='';
const button=document.getElementById('button');const bounds=button.getBoundingClientRect();
button.setAttribute('data-x',JSON.stringify(bounds.x+5));button.setAttribute('data-y',JSON.stringify(bounds.y+5));
button.onclick=function(){document.title='clicked';};
editor.focus({preventScroll:true});
editor.oninput=function(e){document.title=editor.value;};
editor.onbeforeinput=function(e){if(e.data==='X')e.preventDefault();};
editor.oncompositionstart=function(e){log+='s';};
editor.oncompositionupdate=function(e){log+='u'+e.data;};
editor.oncompositionend=function(e){document.title=log+'e'+e.data;};
</script>''')
    for invalid in ('document', 'generation', 'kind', 'scalar'):
        parent, child = socket.socketpair()
        parent.settimeout(10)
        process = subprocess.Popen([WIN, '--interactive-worker', '--page', str(page),
            '--worker-limit', '8388608', '--worker-generation', '9', '--worker-width', '390', '--worker-height', '720'],
            stdin=child, stdout=subprocess.DEVNULL, stderr=subprocess.PIPE,
            env=dict(os.environ, WIN_SCRIPT_WORKER_PARENT=str(os.getpid())))
        child.close()
        try:
            meta, _, html = snapshot(parent, 0)
            generation, document, focus, start, end, direction, scroll, width, height = meta
            assert generation == 9 and document > 0 and focus > 0 and (width, height) == (390, 720), meta
            button = re.search(r'<button[^>]*>', html)[0]
            x = int(float(re.search(r'data-x="([^"]+)"', button)[1]))
            y = int(float(re.search(r'data-y="([^"]+)"', button)[1]))
            # CHAR-only Select All and Unicode use the same native editing seam.
            send(parent, 1, document, [(3, 1, 0, 0, 2), (3, 88, 0, 0, 0),
                                      (3, 233, 0, 0, 0), (3, 128578, 0, 0, 0)])
            meta, title, html = snapshot(parent, 1)
            assert title == 'é🙂', (title, html)
            assert meta[3:6] == (3, 3, 0), meta
            send(parent, 2, document, [(10, 0, 0, 0, 0), (11, 233, 0, 0, 0), (12, 0, 0, 0, 0)])
            meta, title, _ = snapshot(parent, 2)
            assert title == 'suée', title
            send(parent, 3, document, [(4, 1, x, y, 0)])
            snapshot(parent, 3)
            send(parent, 4, document, [(5, 1, x, y, 0)])
            _, title, _ = snapshot(parent, 4)
            assert title == 'clicked', title
            events = [(3, 65, 0, 0, 0)]
            next_document, next_generation = document, generation
            if invalid == 'document': next_document += 1
            if invalid == 'generation': next_generation += 1
            if invalid == 'kind': events.append((99, 0, 0, 0, 0))
            if invalid == 'scalar': events.append((3, 55296, 0, 0, 0))
            send(parent, 5, next_document, events, next_generation)
            process.wait(timeout=5)
            try:
                assert parent.recv(1) == b''
            except ConnectionResetError:
                pass
        finally:
            parent.close()
            if process.poll() is None: process.kill()
            process.wait(timeout=5)
            process.stderr.close()
print('Isolated raw native editing, UTF-16 selection, composition and malformed/stale rejection: OK')
