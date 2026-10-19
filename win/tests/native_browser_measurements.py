#!/usr/bin/env python3
"""Capture one unqualified native M2 run only after the shared idle gate passes.

Build Win and mobile_native_probe first. This copies their exact binaries and
serves the already-frozen corpus; it never builds inside the measurement window.
Swap-return samples describe submitted work, not presentation or frame pacing.
"""
import argparse
import functools
import http.server
import json
import os
import signal
import shutil
import subprocess
import sys
import threading
from pathlib import Path

import browser_measurements as measure


def write_json(path, value):
    path.write_text(json.dumps(value, indent=2) + '\n')


def verify_frozen(corpus, manifest):
    for name, record in manifest['artifacts'].items():
        path = corpus / name
        if 'sha256' not in record or not path.is_file() or measure.digest(path) != record['sha256']:
            raise ValueError('Missing or changed frozen artifact: ' + name)


class QuietHandler(http.server.SimpleHTTPRequestHandler):
    def log_message(self, *args):
        pass


def run_process_group(command, timeout):
    child = subprocess.Popen(command, start_new_session=True)
    try:
        status = child.wait(timeout=timeout)
        if status:
            raise subprocess.CalledProcessError(status, command)
    except BaseException:
        # Own session only: /usr/bin/time is not the measured browser process.
        # Terminate its entire group so a timeout cannot leak a live probe.
        try:
            os.killpg(child.pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
        child.wait()
        raise


def capture(output):
    inputs = json.loads((output / 'inputs.json').read_text())
    corpus = Path(inputs['corpus'])
    manifest = json.loads((output / 'manifest.json').read_text())
    verify_frozen(corpus, manifest)
    for name in ('win', 'mobile_native_probe'):
        if measure.digest(output / name) != inputs['binaries'][name]['sha256']:
            raise ValueError('Measurement binary changed: ' + name)
    server = http.server.ThreadingHTTPServer(('127.0.0.1', 0),
        functools.partial(QuietHandler, directory=str(corpus)))
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    try:
        with (output / 'graphics.txt').open('w') as graphics:
            subprocess.run(['glxinfo', '-B'], stdout=graphics, stderr=subprocess.STDOUT, check=True, timeout=10)
        url = f'http://127.0.0.1:{server.server_port}/w/tools/web/index.html?module=/w/bin/graphics_ui_mobile.wasm'
        command = ['/usr/bin/time', '-f',
            'wall_seconds=%e\nuser_seconds=%U\nsystem_seconds=%S\nmax_rss_kib=%M',
            '-o', str(output / 'process-resource.txt'), str(output / 'mobile_native_probe'),
            '--browser', str(output / 'win'), '--page', url,
            '--timing-report', str(output / 'raw-mobile.json')]
        run_process_group(command, timeout=180)
        raw = json.loads((output / 'raw-mobile.json').read_text())
        if raw.get('qualification') is not False or len(raw['samples']) < 30:
            raise ValueError('Probe report is incomplete or misclassified')
        summary = {'qualification': False,
            'scope': 'One native M2 acceptance process; final 30 uncapped frames; submission-side work only',
            'raw_sha256': measure.digest(output / 'raw-mobile.json'),
            'navigation_to_canvas_geometry_checked_us': raw['navigation_to_canvas_geometry_checked_us'],
            'teardown_us': raw['teardown_us'], 'all_frame_count': len(raw['samples']),
            'last30': {name: measure.summarize([row[name] for row in raw['samples'][-30:]])
                       for name in ('poll_us', 'render_and_checks_us', 'swap_call_us', 'frame_work_us')}}
        verify_frozen(corpus, manifest)
        write_json(output / 'summary.json', summary)
    finally:
        server.shutdown()
        server.server_close()
        thread.join()


def prepare(output, frozen, browser, probe):
    manifest = json.loads((frozen / 'manifest.json').read_text())
    verify_frozen(frozen / 'corpus', manifest)
    if measure.verify_corpus(manifest):
        raise ValueError('Current source corpus differs from the frozen baseline')
    for source in (browser, probe):
        if not source.is_file():
            raise ValueError('Build the native executable before measurement: ' + str(source))
    output.mkdir(parents=True, exist_ok=False)
    binaries = {}
    for name, source in (('win', browser), ('mobile_native_probe', probe)):
        shutil.copy2(source, output / name)
        binaries[name] = {'input': str(source), 'sha256': measure.digest(output / name)}
    write_json(output / 'manifest.json', manifest)
    write_json(output / 'inputs.json', {'corpus': str(frozen / 'corpus'),
        'binaries': binaries, 'source': measure.provenance(),
        'script_sha256': measure.digest(Path(__file__)), 'qualification': False,
        'limitations': ['No first-presented-frame timestamp', 'No input-to-present samples',
                        'No vsync/pacing qualification', 'One navigation, not the required repeated scenarios']})


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', required=True, type=Path)
    parser.add_argument('--frozen', type=Path, default=measure.ROOT / 'win/bin/completion-baseline/frozen')
    parser.add_argument('--browser', type=Path, default=measure.ROOT / 'win/bin/win')
    parser.add_argument('--probe', type=Path, default=measure.ROOT / 'win/bin/mobile_native_probe')
    parser.add_argument('--capture-child', action='store_true', help=argparse.SUPPRESS)
    args = parser.parse_args()
    output = args.output.resolve()
    if args.capture_child:
        capture(output)
        return 0
    prepare(output, args.frozen.resolve(), args.browser.resolve(), args.probe.resolve())
    return measure.run(output, ['xvfb-run', '-a', sys.executable, str(Path(__file__).resolve()),
                                '--output', str(output), '--capture-child'])


if __name__ == '__main__':
    raise SystemExit(main())
