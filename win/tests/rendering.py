"""Native GL pixel regressions; run under an X11 display or xvfb-run.

Usage: python3 win/tests/rendering.py win/bin/win [output.ppm]
Kept separate from the headless suite because it requires X11/OpenGL.
"""
from pathlib import Path
import subprocess
import sys
import tempfile


def check(binary: Path, screenshot: Path) -> None:
    fixture = Path(__file__).resolve().parents[1] / "fixtures/layout.html"
    subprocess.run(
        [str(binary), "--page", str(fixture), "--frames", "40",
         "--screenshot", str(screenshot)],
        check=True, timeout=30,
    )
    with screenshot.open("rb") as image:
        assert image.readline() == b"P6\n", "expected native PPM screenshot"
        width, height = map(int, image.readline().split())
        assert image.readline() == b"255\n"
        pixels = image.read()
    assert (width, height) == (1000, 760), (width, height)
    assert len(pixels) == width * height * 3

    def bounds(color: tuple[int, int, int]) -> tuple[int, int, int, int]:
        # Allow one channel level for GL conversion; ignore font antialiasing.
        points = []
        for y in range(138, height - 44):
            for x in range(12, width - 12):
                at = (y * width + x) * 3
                if all(abs(pixels[at + c] - color[c]) <= 1 for c in range(3)):
                    points.append((x, y))
        assert points, f"missing rendered fixture color {color}"
        xs, ys = zip(*points)
        return min(xs), min(ys), max(xs) + 1, max(ys) + 1

    green = bounds((0x12, 0xAB, 0x34))
    red = bounds((0xAB, 0x12, 0x34))
    blue = bounds((0x34, 0x56, 0xCD))
    purple = bounds((0xCD, 0x34, 0xEF))
    yellow = bounds((0xF1, 0xC2, 0x32))
    tall = bounds((0x46, 0xA1, 0xB9))
    following = bounds((0x7E, 0x57, 0xC2))
    assert green[2] - green[0] == 200, ("percentage flex width", green)
    assert red[2] - red[0] == 100, ("neighbor width", red)
    assert red[0] - green[2] == 10, ("flex gap", green, red)
    assert blue[0] - green[0] == 230, ("intrinsic input width plus gap", blue, green)
    assert purple[0] - green[0] == 12, ("CSSOM shorthand margin", purple, green)
    assert yellow[3] - yellow[1] == 20, ("fixed parent height", yellow)
    assert following[1] - yellow[1] == 20, ("following sibling flow", following, yellow)
    assert tall[3] - yellow[1] == 50, ("visible overflow", tall, yellow)
    grow_a = bounds((0x21, 0x6A, 0x94))
    grow_b = bounds((0x94, 0x78, 0x21))
    justify_a = bounds((0x8F, 0x47, 0x94))
    justify_b = bounds((0x47, 0x94, 0x8F))
    assert grow_a[2] - grow_a[0] == 100, ("flex-grow 1", grow_a)
    assert grow_b[2] - grow_b[0] == 300, ("flex-grow 3", grow_b)
    assert grow_b[0] - grow_a[2] == 10, ("explicit growth gap", grow_a, grow_b)
    assert justify_b[0] - justify_a[0] == 330, ("space-between alignment", justify_a, justify_b)
    print("Win native rendering: flex sizing, controls, CSSOM and overflow: OK")


if __name__ == "__main__":
    binary = Path(sys.argv[1]).resolve()
    if len(sys.argv) > 2:
        check(binary, Path(sys.argv[2]).resolve())
    else:
        with tempfile.TemporaryDirectory(prefix="win-rendering-") as directory:
            check(binary, Path(directory) / "layout.ppm")
