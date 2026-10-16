"""Local calc/viewport fixtures compared to native explicit-value reference pixels."""
from pathlib import Path
import subprocess
import sys
import tempfile

from wpt_reftests import read_ppm


def check(binary):
    cases = [
        ('viewport-column',
         ':root{--inset:10px}#outer{width:50vw;height:50vh;display:flex;flex-direction:column}'
         '#a{width:calc(100% - var(--inset));flex:0 0 calc(50% - 10px)}'
         '#b{width:calc(100px - 10%);flex:0 0 calc(50% + 10px)}',
         '#outer{width:400px;height:300px}'
         '#a{width:390px;height:140px}#b{width:60px;height:160px}'),
        ('row-relative-basis',
         '#outer{display:flex;width:calc(40vw - 20px);height:100px;gap:calc(2 * 5px)}'
         '#a{flex:1 0 calc(50% - 15px);padding:calc(1vmin - 1px)}'
         '#b{flex:1 0 calc(25% + 50px)}',
         '#outer{display:flex;width:300px;height:100px;gap:10px}'
         '#a{width:145px;padding:5px}#b{width:135px}'),
    ]
    with tempfile.TemporaryDirectory(prefix='win-css-math-') as directory:
        root = Path(directory)
        for name, math_css, reference_css in cases:
            images = []
            for label, css in [('test', math_css), ('reference', reference_css)]:
                page = root / f'{name}-{label}.html'
                shot = root / f'{name}-{label}.ppm'
                page.write_text('<style>div{margin:0;padding:0}#a{background:green}'
                                '#b{background:blue}' + css +
                                '</style><div id="outer"><div id="a"></div><div id="b"></div></div>')
                result = subprocess.run([str(binary), '--page', str(page), '--reftest',
                                         '--screenshot', str(shot)], capture_output=True,
                                        text=True, timeout=30)
                assert result.returncode == 0, (name, label, result.stderr)
                images.append(read_ppm(shot))
            assert images[0] == images[1], f'{name}: reference pixels differ'
            assert any(value != 255 for value in images[0]), f'{name}: empty capture'
    print('CSS calc/viewport native rendering: 2 exact reference comparisons: OK')


if __name__ == '__main__':
    check(Path(sys.argv[1]).resolve())
