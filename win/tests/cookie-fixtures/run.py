#!/usr/bin/env python3
"""Pinned upstream data-case adapter, not a WPT browser/harness execution."""
import argparse
import collections
import hashlib
import json
from pathlib import Path
import subprocess

HERE = Path(__file__).resolve().parent
PIN = "6d4552a8b1057e42a180119d70273f563e53a264"
HASHES = {
    "expires.html": "0c237f0247b1c1c59b74e832ece358b77c70173f3594dd4faa83351dda95a451",
    "max-age.html": "9a6fe4fd1edb9a8cd094a99b4a6fc191a31fbb698fcc8890e87bdbc7ae487af5",
}
# Execute unchanged inline scripts to enumerate upstream cookie/expected/name
# arguments. This only collects data; Node does not perform the cookie tests.
COLLECT = r"""
const fs = require('fs'), vm = require('vm');
const cases = [];
const context = vm.createContext({
  httpCookieTest: (cookie, expected, name) => cases.push({cookie, expected, name, surface:'HTTP'}),
  domCookieTest: (cookie, expected, name) => cases.push({cookie, expected, name, surface:'DOM'})
});
const html = fs.readFileSync(process.argv[1], 'utf8');
for (const match of html.matchAll(/<script\b([^>]*)>([\s\S]*?)<\/script>/g)) {
  if (!/\bsrc\s*=/.test(match[1])) vm.runInContext(match[2], context, {timeout:1000});
}
process.stdout.write(JSON.stringify(cases));
"""

def run(binary):
    results = []
    for name, digest in HASHES.items():
        path = HERE / name
        if hashlib.sha256(path.read_bytes()).hexdigest() != digest:
            raise ValueError(f"pinned fixture changed: {name}")
        cases = json.loads(subprocess.run(['node', '-e', COLLECT, str(path)],
                                         check=True, capture_output=True, text=True, timeout=5).stdout)
        for index, case in enumerate(cases, 1):
            result = dict(file=name, index=index, **case)
            if case['surface'] == 'DOM':
                result.update(status='UNSUPPORTED', reason='document.cookie is not exposed')
            else:
                headers = case['cookie'] if isinstance(case['cookie'], list) else [case['cookie']]
                try:
                    proc = subprocess.run([str(binary), '--upstream', *headers], capture_output=True,
                                          text=True, timeout=5)
                    result['actual'] = proc.stdout.removesuffix('\n')
                    if proc.returncode:
                        result.update(status='ERROR', reason=f'driver exit {proc.returncode}', stderr=proc.stderr)
                    else:
                        result['status'] = 'PASS' if result['actual'] == case['expected'] else 'FAIL'
                except subprocess.TimeoutExpired:
                    result.update(status='TIMEOUT', reason='driver exceeded 5 seconds')
                except (OSError, UnicodeError) as error:
                    result.update(status='ERROR', reason=str(error))
            results.append(result)
    return dict(kind='upstream-data-case-adapter', upstream_commit=PIN, clock='2026-01-01T00:00:00Z',
                total=len(results), counts=dict(collections.Counter(r['status'] for r in results)), results=results)

if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('binary', type=Path)
    parser.add_argument('--output', type=Path)
    parser.add_argument('--gate', choices=('http', 'all'), default='http',
                        help='http requires all 21 HTTP cases; all also requires all 12 DOM cases')
    args = parser.parse_args()
    report = run(args.binary.resolve())
    http = [r for r in report['results'] if r['surface'] == 'HTTP']
    dom = [r for r in report['results'] if r['surface'] == 'DOM']
    shape = report['total'] == 33 and len(http) == 21 and len(dom) == 12
    selected = http if args.gate == 'http' else report['results']
    passed = shape and all(r['status'] == 'PASS' for r in selected)
    report['gate'] = dict(name=args.gate, selected=len(selected), passed=passed)
    text = json.dumps(report, indent=2) + '\n'
    if args.output:
        args.output.write_text(text)
        print(f"Cookie upstream data adapter: total={report['total']} counts={report['counts']} gate={args.gate} passed={passed}")
    else:
        print(text, end='')
    raise SystemExit(not passed)
