#!/usr/bin/env python3
"""Actual native control pixels: CSS variables, alpha, borders and passwords."""
import os
from pathlib import Path
import subprocess
import sys
import tempfile

WIN = str(Path(sys.argv[1]).resolve())
if not os.environ.get('DISPLAY'):
    raise SystemExit(subprocess.call(['xvfb-run', '-a', sys.executable, __file__, WIN]))
HTML = '''<style>
body { margin:0; background:blue }
button,input { position:fixed; top:20px; width:80px; height:40px }
#accent { left:20px; --accent:#245a78; background:var(--accent); color:white; border:0 }
#alpha { left:120px; background:#ff000080; border:0 }
#clear { left:220px; background:transparent; border:0 }
#border { left:320px; border:2px solid white }
#editor { left:20px; top:100px; background:#123456; color:white; border:0 }
#password { left:320px; top:100px; background:transparent; color:white; border:0 }
</style>
<button id="accent">Accent</button><button id="alpha"></button>
<button id="clear"></button><input id="border" value="">
<input id="editor" value="Text"><input id="password" type="password" value="PASSWORD">
SCRIPT'''

def pixel(data, x, y):
    return tuple(data[(y*800+x)*3:(y*800+x)*3+3])

def near(actual, expected):
    return all(abs(a-e) <= 1 for a, e in zip(actual, expected))

with tempfile.TemporaryDirectory(prefix='win-form-paint-') as directory:
    root = Path(directory)
    results = []
    for name, password, script, accent in (
        ('blue', 'WWWW', '', (36,90,120)),
        ('green', 'WWWW', '<script>document.getElementById("accent").style.setProperty("--accent","#24634c")</script>', (36,99,76)),
        ('password', 'iiii', '', (36,90,120)),
    ):
        page, shot = root / f'{name}.html', root / f'{name}.ppm'
        page.write_text(HTML.replace('PASSWORD', password).replace('SCRIPT', script))
        result = subprocess.run([WIN, '--page', str(page), '--reftest', '--screenshot', str(shot)], capture_output=True, text=True, timeout=30)
        assert result.returncode == 0, (name, result.stdout, result.stderr)
        magic, dimensions, maximum, data = shot.read_bytes().split(b'\n', 3)
        assert (magic, dimensions, maximum) == (b'P6', b'800 600', b'255')
        for x,y,expected in ((21,21,accent), (121,21,(128,0,127)), (221,21,(0,0,255)), (320,20,(255,255,255)), (403,20,(255,255,255)), (21,101,(18,52,86)), (321,101,(0,0,255))):
            assert near(pixel(data,x,y),expected), (name,x,y,pixel(data,x,y),expected)
        white = sum(pixel(data,x,y) == (255,255,255) for y in range(20,60) for x in range(20,100))
        assert white > 5, (name,'CSS white label is missing',white)
        results.append(data)
    # Same-length password values with very different glyph widths must have
    # identical visible pixels even when their author background is transparent.
    for y in range(100,140):
        for x in range(320,400):
            assert pixel(results[0],x,y) == pixel(results[2],x,y), ('password plaintext leak',x,y)
print('native form paint: blue/green custom-property accents, white text, alpha once, transparent fill, borders and password masking passed')
