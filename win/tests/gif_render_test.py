"""Compare first-image GIF presentation with independently decoded PNGs on GL."""
from pathlib import Path
import subprocess
import sys
import tempfile

from wpt_reftests import read_ppm


def check(binary):
    fixtures = Path(__file__).resolve().parents[1] / 'fixtures/gif'
    with tempfile.TemporaryDirectory(prefix='win-gif-') as directory:
        root = Path(directory)
        for name in ('offset', 'background', 'interlace', 'animated'):
            images = []
            for extension in ('gif', 'png'):
                page = root / f'{name}-{extension}.html'
                shot = root / f'{name}-{extension}.ppm'
                page.write_text('<style>body{background:#b4b4b4}img{width:90px;height:90px}</style>'
                                f'<img src="{fixtures / (name + "." + extension)}">')
                result = subprocess.run([str(binary), '--page', str(page), '--reftest',
                                         '--screenshot', str(shot)], capture_output=True,
                                        text=True, timeout=30)
                assert result.returncode == 0, (name, extension, result.stderr)
                images.append(read_ppm(shot))
            assert images[0] == images[1], f'{name}: GIF/PNG pixels differ'
            # Exclude matching missing-image fallbacks: red must actually render.
            assert any(r > g + 80 and r > b + 80 for r, g, b in
                       zip(images[0][::3], images[0][1::3], images[0][2::3])), \
                f'{name}: missing colored image pixels'
    print('GIF first-image native rendering: 4 exact PNG comparisons: OK')


if __name__ == '__main__':
    check(Path(sys.argv[1]).resolve())
