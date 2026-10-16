"""Native CSS Variables adaptations, compared to explicit-value reference pixels.

Run with xvfb-run -a python3 win/tests/css_custom_render_test.py win/bin/win.
This is a local regression fixture, not an unmodified upstream WPT test.
"""
from pathlib import Path
import subprocess
import sys
import tempfile

from wpt_reftests import read_ppm


def check(binary):
    cases = [
        ("inheritance", """
:root { --width: 140px; --ink: rgb(0 128 0); --pad: 8px 12px }
#outer { width: var(--width); padding: var(--pad); background: var(--ink) }
#inner { --width: 60px; width: var(--width); height: 30px;
         background: var(--absent, rgb(0 0 255)) }
""", """
#outer { width: 140px; padding: 8px 12px; background: rgb(0 128 0) }
#inner { width: 60px; height: 30px; background: rgb(0 0 255) }
"""),
        ("cycles-and-cascade", """
:root { --a: var(--b, 10px); --b: var(--a, 20px); --good: green }
#outer { width: var(--a, 140px); background: var(--good); padding: 8px }
#inner { width: 10px; width: var(--missing); height: var(--b, 30px);
         background: var(--missing, blue) }
""", """
#outer { width: 140px; background: green; padding: 8px }
#inner { width: auto; height: 30px; background: blue }
"""),
    ]
    with tempfile.TemporaryDirectory(prefix='win-custom-css-') as directory:
        root = Path(directory)
        for name, variable_css, reference_css in cases:
            images = []
            for label, css in [('test', variable_css), ('reference', reference_css)]:
                page = root / f'{name}-{label}.html'
                shot = root / f'{name}-{label}.ppm'
                page.write_text('<style>div{margin:0}' + css +
                                '</style><div id="outer"><div id="inner"></div></div>')
                result = subprocess.run([str(binary), '--page', str(page), '--reftest',
                                         '--screenshot', str(shot)], capture_output=True,
                                        text=True, timeout=30)
                assert result.returncode == 0, (name, label, result.stderr)
                images.append(read_ppm(shot))
            assert images[0] == images[1], f'{name}: reference pixels differ'
            assert any(value != 255 for value in images[0]), f'{name}: empty capture'
    print('CSS custom properties native rendering: 2 exact reference comparisons: OK')


if __name__ == '__main__':
    check(Path(sys.argv[1]).resolve())
