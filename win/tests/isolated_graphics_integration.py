#!/usr/bin/env python3
"""Opt-in WFRM presentation of the unchanged M1 host plus real GL ACK failures."""
import functools
import hashlib
import http.server
import json
import os
from pathlib import Path
import select
import socket
import struct
import subprocess
import sys
import tempfile
import threading

ROOT = Path(__file__).resolve().parents[2]
WIN = str(Path(sys.argv[1]).resolve())
OUTPUT = ROOT / 'win/bin/isolated-graphics'
OUTPUT.mkdir(parents=True, exist_ok=True)
# Keep one dedicated X server for the parent, worker and direct protocol probes.
if not os.environ.get('DISPLAY'):
    raise SystemExit(subprocess.call(['xvfb-run', '-a', sys.executable, __file__, WIN]))
compiler = str(ROOT / 'w/bin/wv2')
source = str(ROOT / 'win/tests/isolated_graphics_probe.w')
imports = ['--import-root', str(ROOT / 'win/src'), '--import-root', str(ROOT / 'w')]
probe = str(OUTPUT / 'probe')
subprocess.run([compiler, 'x64', 'check', '--json', *imports, source], check=True)
subprocess.run([compiler, 'x64', '--strict', *imports, source, '-o', probe], check=True)
subprocess.run([compiler, 'wasm', 'graphics/demo_web.w', '-o', 'bin/graphics_demo.wasm'],
               cwd=ROOT / 'w', check=True)


def receive(sock, count):
    data = bytearray()
    while len(data) < count:
        chunk = sock.recv(count - len(data))
        assert chunk, 'truncated worker record'
        data += chunk
    return bytes(data)


def first_frame(sock):
    magic, size, seq, kind, reserved = struct.unpack('<8siiii', receive(sock, 24))
    assert (magic, seq, kind, reserved) == (b'WINT0001', 0, 102, 2)
    payload = receive(sock, size)
    scripts, resources, count, node = struct.unpack('<4i', payload[:16])
    assert (scripts, resources, count) == (0, 0, 1) and node > 0
    frame = receive(sock, 48)
    fields = struct.unpack('<4s11i', frame)
    assert fields[:6] == (b'WFRM', 1, 1, 9, 1, 1), fields
    assert fields[6:10] == (2, 2, 8, 16), fields
    pixels = receive(sock, 16)
    assert pixels == b'\xff\x00\x00\xff' * 4, pixels
    # No second frame or snapshot is queued before the matching acknowledgement.
    assert not select.select([sock], [], [], 0.05)[0]


with tempfile.TemporaryDirectory(prefix='win-frame-ack-') as directory:
    fixture = Path(directory) / 'canvas.html'
    fixture.write_text('''<canvas id="c" width="2" height="2"></canvas><script>
var gl=document.getElementById('c').getContext('webgl2');
gl.clearColor(1,0,0,1);gl.clear(gl.COLOR_BUFFER_BIT);
</script>''')
    for generation, sequence in ((8, 1), (9, 2)):
        parent, child = socket.socketpair()
        parent.settimeout(5)
        process = subprocess.Popen([WIN, '--interactive-worker', '--page', str(fixture),
            '--worker-limit', '8388608', '--worker-generation', '9',
            '--worker-width', '640', '--worker-height', '480'], stdin=child,
            stdout=subprocess.DEVNULL, stderr=subprocess.PIPE,
            env=dict(os.environ, WIN_SCRIPT_WORKER_PARENT=str(os.getpid())))
        child.close()
        try:
            first_frame(parent)
            # A prior-generation ACK and a future-sequence ACK both terminate.
            parent.sendall(struct.pack('<4s11i', b'WFRM', 1, 2, generation, sequence,
                                       0, 0, 0, 0, 0, 0, 0))
            process.wait(timeout=3)
            assert parent.recv(1) == b''
        finally:
            parent.close()
            if process.poll() is None:
                process.kill()
            process.wait(timeout=3)
            process.stderr.close()


class Handler(http.server.SimpleHTTPRequestHandler):
    def log_message(self, *_):
        pass


server = http.server.ThreadingHTTPServer(('127.0.0.1', 0),
    functools.partial(Handler, directory=str(ROOT)))
thread = threading.Thread(target=server.serve_forever, daemon=True)
thread.start()
try:
    url = f'http://127.0.0.1:{server.server_port}/w/tools/web/index.html?module=/w/bin/graphics_demo.wasm'
    result = subprocess.run([probe, '--browser', WIN, '--page', url],
                            capture_output=True, text=True, timeout=110)
    assert result.returncode == 0, (result.stdout, result.stderr)
    report = json.loads(result.stdout.splitlines()[-1])
    assert report['status'] == 'PASS' and report['painted_frames'] == 36, report
    shot = OUTPUT / 'M1-isolated.ppm'
    diagnostics = OUTPUT / 'M1-window.json'
    result = subprocess.run([WIN, '--isolated-interactive', '--page', url,
        '--reftest', '--screenshot', str(shot), '--report', str(diagnostics)],
        capture_output=True, text=True, timeout=45)
    assert result.returncode == 0, (result.stdout, result.stderr)
    window = json.loads(diagnostics.read_text())
    assert window['title'] == 'W graphics demo' and window['script_failures'] == 0, window
    magic, dimensions, maximum, pixels = shot.read_bytes().split(b'\n', 3)
    width, height = map(int, dimensions.split())
    assert magic == b'P6' and maximum == b'255' and len(pixels) == width * height * 3
    colorful = sum(max(pixels[i:i+3]) - min(pixels[i:i+3]) > 45 and min(pixels[i:i+3]) > 35
                   for i in range(0, len(pixels), 3))
    assert colorful > 10000, ('Worker triangle absent from parent paint', colorful)
    report['window'] = dict(window, colorful_pixels=colorful)
    report['source_sha256'] = {str(p.relative_to(ROOT)): hashlib.sha256(p.read_bytes()).hexdigest()
        for p in sorted((ROOT / 'w/tools/web').glob('*')) if p.suffix in ('.mjs', '.html')}
    report['wasm_sha256'] = hashlib.sha256((ROOT / 'w/bin/graphics_demo.wasm').read_bytes()).hexdigest()
    report['w_commit'] = subprocess.check_output(['git', '-C', str(ROOT / 'w'), 'rev-parse', 'HEAD'], text=True).strip()
    (OUTPUT / 'M1.json').write_text(json.dumps(report, indent=2) + '\n')
    print(json.dumps(report))
finally:
    server.shutdown()
    server.server_close()
    thread.join()
print('isolated M1: parent pixels, resize, 3 generations, crash, partial cancellation, bounded ACK backpressure passed')
