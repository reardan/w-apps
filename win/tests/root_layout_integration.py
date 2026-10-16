#!/usr/bin/env python3
"""Exact viewport paint checks for overridable body margins and canvas backgrounds."""
import os
from pathlib import Path
import subprocess
import sys
import tempfile

WIN = str(Path(sys.argv[1]).resolve())
if not os.environ.get('DISPLAY'):
    raise SystemExit(subprocess.call(['xvfb-run', '-a', sys.executable, __file__, WIN]))

cases = [
    ('author-zero', '<style>body{margin:0}div{margin:0;width:100%;height:100vh;background:green}</style><div></div>',
     lambda x, y: (0, 128, 0)),
    ('body-propagation', '<style>body{background:red}</style>', lambda x, y: (255, 0, 0)),
    ('root-propagation', '<html style="margin:20px;background:blue"><body style="display:none"></body></html>',
     lambda x, y: (0, 0, 255)),
    ('single-alpha', '<body style="background:rgba(255,0,0,.5);height:40px"></body>',
     lambda x, y: (255, 127, 127)),
    ('root-and-body', '<style>html{background:blue}body{margin:0;background:red;height:20px}</style>',
     lambda x, y: (255, 0, 0) if y < 20 else (0, 0, 255)),
    ('explicit-margins', '<body style="margin:3px 4px 5px 6px"><div style="margin:0;height:7px;background:green"></div></body>',
     lambda x, y: (0, 128, 0) if 6 <= x < 796 and 3 <= y < 10 else (255, 255, 255)),
]
with tempfile.TemporaryDirectory(prefix='win-root-layout-') as directory:
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
                wanted = expected(x, y)
                # GL's blend conversion may round half-alpha up or down by one.
                tolerance = 1 if name == 'single-alpha' else 0
                assert max(abs(a - b) for a, b in zip(actual, wanted)) <= tolerance, (name, x, y, actual, wanted)
print('root layout: six exact full-viewport paint checks passed')
