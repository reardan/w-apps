"""Native capture success/failure contracts; run under X11 or xvfb-run."""
from pathlib import Path
import subprocess
import sys
import tempfile

from wpt_reftests import read_ppm


def check(binary):
    with tempfile.TemporaryDirectory(prefix='win-capture-') as directory:
        root = Path(directory)
        page = root / 'page.html'
        shot = root / 'page.ppm'
        cases = [
            ('ready', '<p style="color:green">Ready</p>', True),
            ('half-byte RGB', '<div style="width:100px;height:100px;background:rgb(0% 50% 0%)"></div>', True),
            ('script failure', '<script>missingFunction()</script><p>Broken</p>', False),
            ('truncated runs', '<p>' + 'x ' * 21000 + '</p>', False),
            ('missing page', None, False),
        ]
        for name, content, success in cases:
            shot.unlink(missing_ok=True)
            if content is None:
                page.unlink(missing_ok=True)
            else:
                page.write_text(content)
            result = subprocess.run([str(binary), '--page', str(page), '--reftest', '--screenshot', str(shot)],
                                    capture_output=True, text=True, timeout=30)
            assert (result.returncode == 0) == success, (name, result.returncode, result.stderr)
            if success:
                pixels = read_ppm(shot)
                assert any(value != 255 for value in pixels), 'ready page was blank'
                if name == 'half-byte RGB':
                    colors = set(zip(pixels[0::3], pixels[1::3], pixels[2::3]))
                    assert colors == {(255, 255, 255), (0, 128, 0)}, colors
            else:
                assert not shot.exists(), (name, 'failed capture emitted a screenshot')
    print('Win reftest capture: readiness, RGB rounding, script errors, truncation and missing page: OK')


if __name__ == '__main__':
    check(Path(sys.argv[1]).resolve())
