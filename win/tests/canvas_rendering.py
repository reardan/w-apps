"""Canvas/RAF native pixels; run with X11/OpenGL or xvfb-run.

Usage: xvfb-run -a python3 win/tests/canvas_rendering.py win/bin/win
Separate from the headless integration glob because this requires native GL.
"""
from pathlib import Path
import subprocess
import sys
import tempfile


def read_ppm(path: Path) -> tuple[int, int, bytes]:
    with path.open("rb") as image:
        assert image.readline() == b"P6\n", "expected native RGB PPM"
        width, height = map(int, image.readline().split())
        assert image.readline() == b"255\n"
        pixels = image.read()
    assert len(pixels) == width * height * 3, "truncated screenshot"
    return width, height, pixels


def check(binary: Path) -> None:
    fixture = Path(__file__).resolve().parents[1] / "fixtures/canvas.html"
    headless = subprocess.run(
        [str(binary), "--dump", "--page", str(fixture)],
        capture_output=True, text=True, timeout=30,
    )
    assert headless.returncode == 0, headless.stderr
    assert "WebGL unavailable" in headless.stdout, headless.stdout
    with tempfile.TemporaryDirectory(prefix="win-canvas-") as directory:
        screenshot = Path(directory) / "canvas.ppm"
        result = subprocess.run(
            [str(binary), "--page", str(fixture), "--frames", "40",
             "--screenshot", str(screenshot)],
            capture_output=True, text=True, timeout=30,
        )
        assert result.returncode == 0, (result.stdout, result.stderr)
        width, height, pixels = read_ppm(screenshot)
        green = []
        for y in range(height):
            for x in range(width):
                at = (y * width + x) * 3
                if pixels[at:at + 3] == b"\x00\xff\x00":
                    green.append((x, y))
        # Only the RAF callback clears the canvas: this verifies scheduling,
        # the offscreen GL target, layout sizing, and the final UI composite.
        assert len(green) == 160 * 120, ("RAF green pixel count", len(green))
        xs, ys = zip(*green)
        bounds = min(xs), min(ys), max(xs) + 1, max(ys) + 1
        assert bounds[2] - bounds[0] == 160, ("CSS canvas width", bounds)
        assert bounds[3] - bounds[1] == 120, ("CSS canvas height", bounds)
        for y in range(bounds[1], bounds[3]):
            start = (y * width + bounds[0]) * 3
            assert pixels[start:start + 160 * 3] == b"\x00\xff\x00" * 160
    print("Win canvas: headless unavailable, RAF, native GL and 160x120 composite: OK")


if __name__ == "__main__":
    check(Path(sys.argv[1]).resolve())
