#!/usr/bin/env python3
"""Full viewport pixels for fixed boxes, independent nested roots and CSSOM."""
import os
from pathlib import Path
import subprocess
import sys
import tempfile

WIN = str(Path(sys.argv[1]).resolve())
if not os.environ.get('DISPLAY'):
    raise SystemExit(subprocess.call(['xvfb-run', '-a', sys.executable, __file__, WIN]))

cases = [
    ('viewport', '<style>body{margin:0}#fixed{position:fixed;left:0;top:0;width:100%;height:100vh;background:green}</style><div id="fixed"></div>',
     lambda x, y: (0, 128, 0)),
    ('insets', '<style>body{margin:0;background:blue}#fixed{position:fixed;left:10%;top:10%;right:20px;bottom:30px;background:green}#nested{position:fixed;left:5px;top:7px;width:20px;height:10px;background:red}</style><div id="fixed"><div id="nested"></div></div>',
     lambda x, y: (255, 0, 0) if 5 <= x < 25 and 7 <= y < 17 else (0, 128, 0) if 80 <= x < 780 and 60 <= y < 570 else (0, 0, 255)),
    ('cssom', '<style>body{margin:0;background:blue}#fixed{position:fixed;width:40px;height:30px;background:green}</style><div id="fixed"></div><script>const f=document.getElementById("fixed");f.style.right="10px";f.style.bottom="20px";</script>',
     lambda x, y: (0, 128, 0) if 750 <= x < 790 and 550 <= y < 580 else (0, 0, 255)),
]
with tempfile.TemporaryDirectory(prefix='win-fixed-layout-') as directory:
    root = Path(directory)
    for name, html, expected in cases:
        page, shot = root / f'{name}.html', root / f'{name}.ppm'
        page.write_text(html)
        result = subprocess.run([WIN, '--page', str(page), '--reftest', '--screenshot', str(shot)],
                                capture_output=True, text=True, timeout=30)
        assert result.returncode == 0, (name, result.stdout, result.stderr)
        magic, dimensions, maximum, data = shot.read_bytes().split(b'\n', 3)
        assert (magic, dimensions, maximum) == (b'P6', b'800 600', b'255')
        assert len(data) == 800 * 600 * 3
        for y in range(600):
            for x in range(800):
                actual = tuple(data[(y * 800 + x) * 3:(y * 800 + x) * 3 + 3])
                assert actual == expected(x, y), (name, x, y, actual, expected(x, y))
print('fixed layout: three exact full-viewport paint checks passed')
