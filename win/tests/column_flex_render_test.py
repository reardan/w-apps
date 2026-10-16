"""Local column-flex adaptations compared to explicit reference geometry pixels."""
from pathlib import Path
import subprocess
import sys
import tempfile

from wpt_reftests import read_ppm


def check(binary):
    cases = [
        ('nested-growth',
         '#outer{display:flex;flex-direction:column;height:180px}'
         '#nested{display:flex;flex-direction:column;flex:1 1 0px}'
         '#a{flex:1 1 0px}#b{flex:2 1 0px}',
         '#outer,#nested{height:180px}#a{height:60px}#b{height:120px}'),
        ('scaled-shrink',
         '#outer,#nested{display:flex;flex-direction:column;height:120px}'
         '#a{flex:0 1 100px}#b{flex:0 1 200px}',
         '#outer,#nested{height:120px}#a{height:40px}#b{height:80px}'),
        ('percentage-basis-border-box',
         '#outer,#nested{display:flex;flex-direction:column;height:200px}'
         '#a{flex:0 0 50%;box-sizing:border-box;padding:10px;border:2px solid black}'
         '#b{flex:0 0 60px}',
         '#outer,#nested{height:200px}'
         '#a{height:100px;box-sizing:border-box;padding:10px;border:2px solid black}'
         '#b{height:60px}'),
    ]
    with tempfile.TemporaryDirectory(prefix='win-column-flex-') as directory:
        root = Path(directory)
        for name, flex_css, reference_css in cases:
            images = []
            for label, css in [('test', flex_css), ('reference', reference_css)]:
                page = root / f'{name}-{label}.html'
                shot = root / f'{name}-{label}.ppm'
                page.write_text('<style>div{margin:0;padding:0}#outer{width:160px}'
                                '#a{background:green}#b{background:blue}' + css +
                                '</style><div id="outer"><div id="nested">'
                                '<div id="a"></div><div id="b"></div></div></div>')
                result = subprocess.run([str(binary), '--page', str(page), '--reftest',
                                         '--screenshot', str(shot)], capture_output=True,
                                        text=True, timeout=30)
                assert result.returncode == 0, (name, label, result.stderr)
                images.append(read_ppm(shot))
            assert images[0] == images[1], f'{name}: reference pixels differ'
            assert any(value != 255 for value in images[0]), f'{name}: empty capture'
    print('Column flex native rendering: 3 exact reference comparisons: OK')


if __name__ == '__main__':
    check(Path(sys.argv[1]).resolve())
