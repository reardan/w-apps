#!/usr/bin/env python3
"""Run a pinned static WPT reftest slice through Win's actual native renderer."""
from __future__ import annotations

import argparse
from functools import partial
import hashlib
from html.parser import HTMLParser
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
import json
from pathlib import Path
import re
import subprocess
import sys
import threading
from urllib.parse import unquote, urljoin, urlsplit

ROOT = Path(__file__).resolve().parent


class Unsupported(ValueError):
    pass


def require(condition, message):
    if not condition:
        raise ValueError(message)


def local_path(root, name):
    require(isinstance(name, str) and name and '\\' not in name, 'invalid fixture path')
    parts = urlsplit(name)
    require(not (parts.scheme or parts.netloc or parts.query or parts.fragment), 'fixture must be a plain relative path')
    require(not name.startswith('/') and unquote(name) == name, 'invalid fixture path')
    path = (root / name).resolve()
    require(path.is_relative_to(root.resolve()), 'fixture escapes corpus')
    return path


def load_manifest(path):
    data = json.loads(path.read_text())
    require(isinstance(data, dict) and set(data) == {'version', 'upstream', 'files', 'cases'} and data['version'] == 1, 'invalid manifest')
    require(isinstance(data['upstream'], dict) and set(data['upstream']) == {'repository', 'revision'}, 'invalid upstream pin')
    require(data['upstream']['repository'] == 'https://github.com/web-platform-tests/wpt', 'invalid upstream repository')
    require(isinstance(data['upstream']['revision'], str) and re.fullmatch('[0-9a-f]{40}', data['upstream']['revision']), 'invalid upstream revision')
    require(isinstance(data['files'], dict) and 'LICENSE.md' in data['files'], 'missing pinned license')
    for name, digest in data['files'].items():
        require(isinstance(digest, str) and re.fullmatch('[0-9a-f]{64}', digest), 'invalid hash')
        require(hashlib.sha256(local_path(path.parent, name).read_bytes()).hexdigest() == digest, 'source pin mismatch: ' + name)
    require(isinstance(data['cases'], list) and data['cases'], 'empty cases')
    seen = set()
    for case in data['cases']:
        require(isinstance(case, dict) and set(case) <= {'path', 'expected', 'reason'} and {'path', 'expected'} <= set(case), 'invalid case fields')
        require(isinstance(case['path'], str) and case['path'] in data['files'] and case['path'] not in seen, 'unpinned or duplicate case')
        seen.add(case['path'])
        require(case['expected'] in ('PASS', 'FAIL'), 'invalid expected status')
        if case['expected'] == 'FAIL':
            require(isinstance(case.get('reason'), str) and case['reason'].strip(), 'expected failure needs a reason')
    return data


class Metadata(HTMLParser):
    def __init__(self):
        super().__init__(convert_charrefs=True)
        self.references = []
        self.unsupported = []
        self.styles = []
        self.in_style = False

    def handle_starttag(self, tag, attrs):
        a = {key: value or '' for key, value in attrs}
        if tag in {'script', 'iframe', 'object', 'embed', 'canvas', 'video', 'audio', 'svg', 'math'}:
            self.unsupported.append('non-static HTML element: ' + tag)
        if any(k.startswith('on') for k in a) or any(k in a for k in ('src', 'srcset', 'background')):
            self.unsupported.append('script or external resource attribute')
        if tag == 'base':
            self.unsupported.append('base URL override')
        if 'reftest-wait' in a.get('class', '').split() or 'reftest-wait' in a:
            self.unsupported.append('asynchronous reftest-wait')
        if tag == 'meta':
            if a.get('name', '').lower() in {'fuzzy', 'flags', 'viewport', 'variant', 'timeout'} or 'http-equiv' in a:
                self.unsupported.append('unsupported reftest metadata: ' + a.get('name', 'http-equiv'))
        if tag == 'link':
            rel = a.get('rel', '').lower().split()
            if 'match' in rel or 'mismatch' in rel:
                require(len(rel) == 1 and a.get('href'), 'invalid reference link')
                self.references.append((rel[0], a['href']))
            elif any(r not in {'author', 'help', 'reviewer'} for r in rel):
                self.unsupported.append('external or unknown link relation')
        if tag == 'style':
            self.in_style = True
        if 'style' in a:
            self.styles.append(a['style'])

    def handle_endtag(self, tag):
        if tag == 'style':
            self.in_style = False

    def handle_data(self, data):
        if self.in_style:
            self.styles.append(data)


def metadata(path):
    if path.suffix != '.html' or path.name.endswith('.sub.html'):
        raise Unsupported('only text/html static fixtures are supported')
    source = path.read_text(encoding='utf-8')
    if '{{' in source or Path(str(path) + '.headers').exists():
        raise Unsupported('WPT server substitution or response headers')
    info = Metadata()
    info.feed(source)
    css = re.sub(r'/\*.*?\*/', '', '\n'.join(info.styles), flags=re.S)
    # These need resource loading/readiness, animations, or font synchronization.
    if '\\' in css:
        info.unsupported.append('CSS escapes need token-aware resource inspection')
    if re.search(r'url\s*\(|@import\b|@font-face\b|@keyframes\b|\banimation[\w-]*\s*:|\btransition[\w-]*\s*:', css, re.I):
        info.unsupported.append('external CSS resources, fonts, or animation')
    if info.unsupported:
        raise Unsupported('; '.join(sorted(set(info.unsupported))))
    return info


def references(root, case, files):
    info = metadata(local_path(root, case))
    require(info.references, 'test has no reference links')
    result = []
    for relation, href in info.references:
        require(not href.startswith('/'), 'root-relative references are not supported')
        name = urljoin(case, href)
        target = local_path(root, name)
        require(name in files and name != case, 'unpinned or self reference')
        metadata(target)
        result.append((relation, name))
    return result


def read_ppm(path):
    with path.open('rb') as source:
        require(source.readline() == b'P6\n', 'bad PPM header')
        require(source.readline().strip() == b'800 600', 'capture is not an 800x600 viewport')
        require(source.readline() == b'255\n', 'bad PPM channel range')
        pixels = source.read()
    require(len(pixels) == 800 * 600 * 3, 'truncated or oversized PPM')
    return pixels


def compare(left, right):
    require(len(left) == len(right) and len(left) % 3 == 0, 'incompatible pixel buffers')
    maximum = 0
    different = 0
    for at in range(0, len(left), 3):
        delta = max(abs(left[at + c] - right[at + c]) for c in range(3))
        maximum = max(maximum, delta)
        different += delta != 0
    return {'max_channel_difference': maximum, 'different_pixels': different}


def relationships_pass(comparisons):
    matches = [x for x in comparisons if x['relation'] == 'match']
    mismatches = [x for x in comparisons if x['relation'] == 'mismatch']
    return (not matches or any(x['different_pixels'] == 0 for x in matches)) and all(x['different_pixels'] != 0 for x in mismatches)


def capture(binary, base_url, name, output, timeout):
    output.unlink(missing_ok=True)
    completed = subprocess.run([str(binary), '--page', base_url + name, '--reftest', '--screenshot', str(output)],
                               capture_output=True, text=True, timeout=timeout)
    require(completed.returncode == 0, 'renderer failed: ' + (completed.stderr or completed.stdout)[-2000:])
    return read_ppm(output)


class QuietHandler(SimpleHTTPRequestHandler):
    def log_message(self, *args):
        pass


def run_suite(manifest_path, binary, output, timeout=30):
    manifest = load_manifest(manifest_path)
    require(binary.is_file(), 'browser binary is missing')
    output.mkdir(parents=True, exist_ok=True)
    server = ThreadingHTTPServer(('127.0.0.1', 0), partial(QuietHandler, directory=str(manifest_path.parent)))
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    base_url = f'http://127.0.0.1:{server.server_port}/'
    results = []
    try:
        for case in manifest['cases']:
            result = dict(case)
            try:
                refs = references(manifest_path.parent, case['path'], manifest['files'])
                stem = hashlib.sha256(case['path'].encode()).hexdigest()[:16]
                test_path = output / (stem + '-test.ppm')
                test = capture(binary, base_url, case['path'], test_path, timeout)
                comparisons = []
                for index, (relation, name) in enumerate(refs):
                    ref_path = output / f'{stem}-ref-{index}.ppm'
                    ref = capture(binary, base_url, name, ref_path, timeout)
                    comparisons.append({'relation': relation, 'reference': name, 'screenshot': str(ref_path), **compare(test, ref)})
                result.update(status='PASS' if relationships_pass(comparisons) else 'FAIL',
                              screenshot=str(test_path), comparisons=comparisons)
            except Unsupported as error:
                result.update(status='UNSUPPORTED', detail=str(error))
            except (OSError, ValueError, subprocess.SubprocessError) as error:
                result.update(status='ERROR', detail=str(error))
            result['unexpected'] = result['status'] != case['expected']
            results.append(result)
    finally:
        server.shutdown()
        server.server_close()
        thread.join()
    return {'suite': 'win-static-wpt-reftests', 'upstream': manifest['upstream'], 'viewport': [800, 600],
            'browser_sha256': hashlib.sha256(binary.read_bytes()).hexdigest(),
            'counts': {status: sum(r['status'] == status for r in results) for status in ('PASS', 'FAIL', 'UNSUPPORTED', 'ERROR')},
            'unexpected': sum(r['unexpected'] for r in results), 'results': results}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--binary', type=Path, default=ROOT.parent / 'bin/win')
    parser.add_argument('--manifest', type=Path, default=ROOT / 'wpt/manifest.json')
    parser.add_argument('--output', type=Path, default=ROOT.parent / 'bin/wpt-results')
    parser.add_argument('--timeout', type=float, default=30)
    args = parser.parse_args()
    try:
        require(0 < args.timeout <= 300, 'timeout must be between 0 and 300 seconds')
        report = run_suite(args.manifest.resolve(), args.binary.resolve(), args.output.resolve(), args.timeout)
        (args.output / 'report.json').write_text(json.dumps(report, indent=2) + '\n')
        for result in report['results']:
            print(result['status'], result['path'], '(unexpected)' if result['unexpected'] else '')
        print(json.dumps({'counts': report['counts'], 'unexpected': report['unexpected']}))
        return int(report['unexpected'] != 0)
    except (OSError, ValueError) as error:
        print('WPT setup error:', error, file=sys.stderr)
        return 2


if __name__ == '__main__':
    sys.exit(main())
