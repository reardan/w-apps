"""First-image GIF worker output equals independent PNG over local and HTTP loads."""
from functools import partial
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
import struct
import subprocess
import sys
import threading


def payload(binary, address):
    result = subprocess.run([str(binary), '--resource', address, '--kind', 'image'],
                            capture_output=True, timeout=15)
    assert result.returncode == 0, (address, result.stdout[:300], result.stderr[:300])
    status, _, pixels = result.stdout.split(b'\n', 2)
    assert status == b'OK'
    width, height = struct.unpack('>II', pixels[:8])
    assert len(pixels) == 8 + width * height * 4
    # Alpha-zero colors are invisible, and GIF initializes them to transparent black.
    pixels = bytearray(pixels)
    for start in range(8, len(pixels), 4):
        if pixels[start + 3] == 0:
            pixels[start:start + 3] = b'\x00\x00\x00'
    return pixels


def check(binary):
    fixtures = Path(__file__).resolve().parents[1] / 'fixtures/gif'
    server = ThreadingHTTPServer(('127.0.0.1', 0), partial(SimpleHTTPRequestHandler, directory=str(fixtures)))
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    try:
        for name in ('offset', 'background', 'interlace', 'animated'):
            expected = payload(binary, str(fixtures / f'{name}.png'))
            for base in (str(fixtures), f'http://127.0.0.1:{server.server_port}'):
                actual = payload(binary, f'{base}/{name}.gif')
                assert actual == expected, (name, base)
    finally:
        server.shutdown()
        server.server_close()
        thread.join()
    print('GIF local/HTTP first-image worker: 8 exact RGBA comparisons: OK')


if __name__ == '__main__':
    check(Path(sys.argv[1]).resolve())
