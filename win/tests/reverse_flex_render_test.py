"""Compare reverse main axes and pointer-events painting to native references."""
from pathlib import Path
import subprocess
import sys
import tempfile

from wpt_reftests import read_ppm


def check(binary):
    common = ('body{margin:0}#outer{width:120px;display:flex;gap:10px}'
              '#a,#b,#c{flex:0 0 40px;height:30px}'
              '#a{background:green}#b{background:blue}#c{background:red}')
    first = '<div id="a"></div><div id="b"></div>'
    reversed_pair = '<div id="b"></div><div id="a"></div>'
    cases = [
        ('row-asymmetric-margins',
         '#outer{flex-direction:row-reverse}#a{margin-left:3px;margin-right:7px}', first,
         '#outer{justify-content:flex-end}#a{margin-left:3px;margin-right:7px}', reversed_pair),
        ('row-wrap',
         '#outer{flex-direction:row-reverse;flex-wrap:wrap}', first + '<div id="c"></div>',
         '#outer{justify-content:flex-end;flex-wrap:wrap}', reversed_pair + '<div id="c"></div>'),
        ('column-natural',
         '#outer{flex-direction:column-reverse}', first,
         '#outer{flex-direction:column}', reversed_pair),
        ('column-definite-end',
         '#outer{flex-direction:column-reverse;height:160px;justify-content:flex-end}', first,
         '#outer{flex-direction:column;height:160px}', reversed_pair),
        ('column-growth',
         '#outer{flex-direction:column-reverse;height:160px}#a{flex:1 1 0px}#b{flex:2 1 0px}', first,
         '#outer{flex-direction:column;height:160px}#a{flex:1 1 0px}#b{flex:2 1 0px}', reversed_pair),
        ('pointer-events-paint',
         '#outer{pointer-events:none}#a{pointer-events:auto}', first,
         '#outer{pointer-events:auto}', first),
    ]
    with tempfile.TemporaryDirectory(prefix='win-reverse-flex-') as directory:
        root = Path(directory)
        for name, test_css, test_body, ref_css, ref_body in cases:
            images = []
            for label, css, body in [('test', test_css, test_body), ('reference', ref_css, ref_body)]:
                page = root / f'{name}-{label}.html'
                shot = root / f'{name}-{label}.ppm'
                page.write_text(f'<style>{common}{css}</style><div id="outer">{body}</div>')
                result = subprocess.run([str(binary), '--page', str(page), '--reftest',
                                         '--screenshot', str(shot)], capture_output=True,
                                        text=True, timeout=30)
                assert result.returncode == 0, (name, label, result.stderr)
                images.append(read_ppm(shot))
            assert images[0] == images[1], f'{name}: reference pixels differ'
            assert any(value != 255 for value in images[0]), f'{name}: empty capture'
    print(f'Reverse flex and pointer-events native rendering: {len(cases)} exact comparisons: OK')


if __name__ == '__main__':
    check(Path(sys.argv[1]).resolve())
