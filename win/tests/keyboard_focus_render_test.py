"""Focused document boxes remain visibly outlined in native and isolated UI."""
from pathlib import Path
import subprocess
import sys
import tempfile


def ppm(path):
    data = path.read_bytes()
    header, size, maximum, pixels = data.split(b'\n', 3)
    assert header == b'P6' and maximum == b'255'
    width, height = map(int, size.split())
    assert len(pixels) == width * height * 3
    return width, pixels


def check(binary):
    with tempfile.TemporaryDirectory(prefix='win-focus-ring-') as directory:
        root = Path(directory)
        page = root / 'focus.html'
        page.write_text('<body style="margin:0"><a id="link" href="#target" '
                        'style="display:block;margin:20px;width:100px;height:30px">link</a>'
                        '<script>document.getElementById("link").focus();</script></body>')
        for mode in ('native', 'isolated'):
            shot = root / f'{mode}.ppm'
            command = [str(binary), '--page', str(page), '--frames', '40', '--screenshot', str(shot)]
            if mode == 'isolated':
                command.append('--isolated-interactive')
            result = subprocess.run(command, capture_output=True, text=True, timeout=30)
            assert result.returncode == 0, (mode, result.stderr)
            width, pixels = ppm(shot)
            # Browser viewport (12,138), box (20,20,100,30), outer ring 2px.
            for x, y in [(31, 160), (80, 157), (132, 170), (80, 189)]:
                at = (y * width + x) * 3
                actual = tuple(pixels[at:at+3])
                assert all(abs(a - b) <= 1 for a, b in zip(actual, (103, 80, 164))), (mode, x, y, actual)
    print('Keyboard focus ring native and isolated GL pixels: OK')


if __name__ == '__main__':
    check(Path(sys.argv[1]).resolve())
