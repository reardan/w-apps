#!/usr/bin/env python3
"""Execute pinned original testharness.js using Win's native async script host."""
import argparse
from collections import Counter
import hashlib
import json
import re
from pathlib import Path, PurePosixPath
import subprocess
import tempfile
from datetime import datetime, timezone

ROOT = Path(__file__).resolve().parents[2]
CORPUS = Path(__file__).resolve().parent / 'wpt'
STATUSES = ('PASS', 'FAIL', 'UNSUPPORTED', 'ERROR')
BRIDGE = '''setup({output:false, message_events:[]});
add_result_callback(function(t) {
  __wptObserve(JSON.stringify({name:t.name,status:t.status,message:t.message}));
});
add_completion_callback(function(tests, status) {
  __wptComplete(JSON.stringify({status:status.status, message:status.message,
    tests:tests.map(function(t) {return {name:t.name,status:t.status,message:t.message};})}));
});
'''


def require(value, message):
    if not value:
        raise ValueError(message)


def require_relative_source(name):
    require(isinstance(name, str), 'source path must be text')
    path = PurePosixPath(name)
    require(bool(path.parts) and name == path.as_posix() and not path.is_absolute() and
            all(part not in ('.', '..') for part in path.parts), 'source path must be canonical and relative')


def strict_json(text):
    def pairs(items):
        result = {}
        for key, value in items:
            require(key not in result, 'duplicate JSON field: ' + key)
            result[key] = value
        return result
    def constant(value):
        raise ValueError('non-finite JSON value: ' + value)
    return json.loads(text, object_pairs_hook=pairs, parse_constant=constant)


def evidence(driver):
    try:
        binary_hash, hash_error = hashlib.sha256(driver.read_bytes()).hexdigest(), None
    except OSError as error:
        binary_hash, hash_error = None, str(error)
    revisions = {}
    for name, directory in [('application_revision', ROOT), ('w_revision', ROOT / 'w')]:
        proc = subprocess.run(['git', '-C', str(directory), 'rev-parse', 'HEAD'], text=True, capture_output=True)
        revisions[name] = proc.stdout.strip() if proc.returncode == 0 else None
    return {**revisions, 'driver_sha256': binary_hash, 'driver_hash_error': hash_error,
            'recorded_at_utc': datetime.now(timezone.utc).isoformat(), 'kind': 'fresh-execution',
            'adapter_sha256': hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
            'driver_source_sha256': hashlib.sha256((ROOT / 'win/tests/wpt_driver.w').read_bytes()).hexdigest()}


def freeze_inputs(manifest_path, manifest, inventory):
    """Validate the exact bytes copied into each run's private source directory."""
    frozen = {name: (manifest_path.parent / name).read_bytes() for name in manifest['files']}
    for name, data in frozen.items():
        require(hashlib.sha256(data).hexdigest() == manifest['files'][name], 'pin changed before execution: ' + name)
    frozen[manifest_path.name] = manifest_path.read_bytes()
    frozen['wpt-inventory.json'] = (manifest_path.parent / 'wpt-inventory.json').read_bytes()
    require(strict_json(frozen[manifest_path.name]) == manifest, 'manifest changed before execution')
    require(strict_json(frozen['wpt-inventory.json']) == inventory, 'inventory changed before execution')
    return frozen


def write_inputs(directory, frozen):
    for name, data in frozen.items():
        require_relative_source(name)
        path = directory / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(data)


def check_provenance(manifest_path, frozen, driver, execution_evidence, results, adapters=()):
    changed = []
    expected = [(manifest_path.parent / name, hashlib.sha256(data).hexdigest()) for name, data in frozen.items()]
    expected += [(Path(__file__), execution_evidence['adapter_sha256']),
                 (ROOT / 'win/tests/wpt_driver.w', execution_evidence['driver_source_sha256'])]
    expected.extend(adapters)
    expected.append((driver, execution_evidence['driver_sha256']))
    for path, digest in expected:
        try:
            if hashlib.sha256(path.read_bytes()).hexdigest() != digest:
                changed.append(str(path))
        except OSError:
            if digest is not None:
                changed.append(str(path) + ' disappeared')
    execution_evidence['changed_during_execution'] = changed
    if changed:
        for result in results:
            if result.get('admitted', True):
                result['observed_status'], result['observed_reason'] = result['status'], result.get('reason')
                result['status'] = 'ERROR'
                result['reason'] = 'provenance changed during execution: ' + ', '.join(changed)


def classify(report):
    require(isinstance(report, dict) and type(report.get('protocol')) is int and report['protocol'] == 2, 'invalid protocol')
    for key in ('completions', 'script_failures', 'reported_exceptions', 'completion_script_failures', 'failed_source', 'elapsed_ms'):
        require(type(report.get(key)) is int, 'missing integer ' + key)
    require(report['completions'] >= 0 and report['script_failures'] >= 0 and report['elapsed_ms'] >= 0, 'negative count')
    require(report['failed_source'] >= -1 and isinstance(report.get('message'), str), 'invalid execution evidence')
    require(0 <= report['reported_exceptions'] <= report['script_failures'], 'invalid reported exception count')
    if report['completions']:
        require(0 <= report['completion_script_failures'] <= report['script_failures'], 'invalid completion failure snapshot')
    else:
        require(report['completion_script_failures'] == -1, 'unexpected completion failure snapshot')
    observations = report.get('observed_payloads', [])
    require(isinstance(observations, list), 'invalid observed subtests')
    observed = []
    for raw in observations:
        require(isinstance(raw, str), 'invalid observed payload')
        item = strict_json(raw)
        require(isinstance(item, dict) and isinstance(item.get('name'), str) and item['name'] and
                type(item.get('status')) is int and 0 <= item['status'] <= 4 and
                (item.get('message') is None or isinstance(item.get('message'), str)), 'invalid observed subtest')
        observed.append(item)
    report['observed_subtests'] = observed
    if report['script_failures'] != report['reported_exceptions'] or report['failed_source'] >= 0:
        return 'ERROR', 'script execution failed'
    if report['completions'] and report['script_failures'] > report['completion_script_failures']:
        return 'ERROR', 'script exception after completion callback'
    if report['completions'] == 0:
        return 'ERROR', 'timeout before completion callback'
    require(report['completions'] == 1, 'completion callback must run exactly once')
    payload = strict_json(report['payload'])
    require(isinstance(payload, dict), 'invalid completion payload')
    require(type(payload.get('status')) is int and 0 <= payload['status'] <= 3, 'invalid harness status')
    require(isinstance(payload.get('tests'), list) and payload['tests'], 'completion requires subtest evidence')
    statuses = []
    names = set()
    for test in payload['tests']:
        require(isinstance(test, dict) and isinstance(test.get('name'), str) and test['name'], 'invalid subtest name')
        require(test['name'] not in names, 'duplicate subtest name')
        names.add(test['name'])
        require(type(test.get('status')) is int and 0 <= test['status'] <= 4, 'invalid subtest status')
        require(test.get('message') is None or isinstance(test['message'], str), 'invalid subtest message')
        statuses.append(test['status'])
    report['completion'] = payload
    if payload['status'] or any(status in (2, 3) for status in statuses):
        return 'ERROR', 'harness error, timeout or unexecuted subtest'
    if 1 in statuses:
        return 'FAIL', 'upstream assertion failed'
    if 4 in statuses:
        return 'UNSUPPORTED', 'upstream optional feature unsupported; applicability requires review'
    return 'PASS', 'all upstream subtests passed'


def execute(driver, sources, timeout=10):
    try:
        proc = subprocess.run([str(driver), str(max(1, int(timeout * 1000))), *map(str, sources)],
                              capture_output=True, timeout=timeout + 5)
    except subprocess.TimeoutExpired:
        return {'status': 'ERROR', 'reason': 'process timeout'}
    except OSError as error:
        return {'status': 'ERROR', 'reason': 'process launch failed: ' + str(error)}
    if proc.returncode:
        return {'status': 'ERROR', 'reason': 'process crash' if proc.returncode < 0 else 'driver error',
                'exit_code': proc.returncode, 'stderr': proc.stderr[-4000:].decode('utf-8', errors='replace')}
    try:
        actual = strict_json(proc.stdout.decode('utf-8'))
        status, reason = classify(actual)
        return {'status': status, 'reason': reason, 'actual': actual}
    except (ValueError, KeyError, TypeError) as error:
        return {'status': 'ERROR', 'reason': 'malformed report: ' + str(error), 'stdout_hex': proc.stdout[-4000:].hex()}


def load_manifest(path):
    manifest = strict_json(path.read_text())
    require(manifest.get('version') == 1 and isinstance(manifest.get('files'), dict), 'invalid manifest')
    upstream = manifest.get('upstream')
    require(isinstance(upstream, dict) and upstream.get('repository') == 'https://github.com/web-platform-tests/wpt' and
            isinstance(upstream.get('revision'), str) and re.fullmatch(r'[0-9a-f]{40}', upstream['revision']), 'invalid upstream provenance')
    require(isinstance(manifest.get('cases'), list) and manifest['cases'], 'empty cases')
    for name, digest in manifest['files'].items():
        require_relative_source(name)
        file = (path.parent / name).resolve()
        require(file.is_relative_to(path.parent.resolve()), 'path escapes corpus')
        require(hashlib.sha256(file.read_bytes()).hexdigest() == digest, 'pin mismatch: ' + name)
    require('resources/testharness.js' in manifest['files'] and 'LICENSE.md' in manifest['files'], 'missing harness/license pin')
    ids = set()
    for case in manifest['cases']:
        require(set(case) == {'id', 'source', 'environment', 'blockers'}, 'invalid case fields')
        require(case['id'] not in ids, 'duplicate case')
        ids.add(case['id'])
        require(case['source'] in manifest['files'], 'unpinned case')
        require(case['environment'] == 'window-script', 'unsupported execution environment')
        require(isinstance(case['blockers'], list), 'invalid blocker inventory')
    return manifest


def run(manifest_path, driver, timeout=10):
    manifest = load_manifest(manifest_path)
    inventory = strict_json((manifest_path.parent / 'wpt-inventory.json').read_text())
    require(all(inventory.get(key) == manifest['upstream'][key] for key in ('repository', 'revision')),
            'suite inventory revision mismatch')
    execution_evidence = evidence(driver)
    frozen = freeze_inputs(manifest_path, manifest, inventory)
    results = []
    with tempfile.TemporaryDirectory(prefix='win-wpt-') as directory:
        sources = Path(directory) / 'corpus'
        write_inputs(sources, frozen)
        bridge = Path(directory) / 'bridge.js'
        bridge.write_text(BRIDGE)
        for case in manifest['cases']:
            result = execute(driver, [sources / 'resources/testharness.js', bridge,
                                      sources / case['source']], timeout)
            results.append({'id': case['id'], 'blockers': case['blockers'], **result})
    check_provenance(manifest_path, frozen, driver, execution_evidence, results)
    counts = Counter(item['status'] for item in results)
    return {'protocol': 1, 'profile': 'native-window-script-testharness-v1', 'upstream': manifest['upstream'],
            'evidence': execution_evidence, 'source_pins': manifest['files'], 'manifest_sha256': hashlib.sha256(frozen[manifest_path.name]).hexdigest(),
            'bridge_sha256': hashlib.sha256(BRIDGE.encode()).hexdigest(), 'wall_timeout_seconds': timeout, 'inventory': inventory,
            'selected_files': len(results), 'executed_files': sum('actual' in r and r['actual']['failed_source'] == -1 for r in results),
            'counts': {key: counts[key] for key in STATUSES}, 'results': results,
            'limitations': 'Window script seam only: not wptrunner/WebDriver, HTML/resource loading, multi-origin/TLS, variants or testdriver. Failures and mandatory unsupported features remain blockers.'}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--manifest', type=Path, default=CORPUS / 'testharness-manifest.json')
    parser.add_argument('--driver', type=Path, default=ROOT / 'win/bin/wpt_driver')
    parser.add_argument('--json', type=Path)
    parser.add_argument('--timeout', type=float, default=10)
    args = parser.parse_args()
    try:
        require(0 < args.timeout <= 60, 'invalid timeout')
        report = run(args.manifest.resolve(), args.driver.resolve(), args.timeout)
        status = int(any(report['counts'][key] for key in ('FAIL', 'UNSUPPORTED', 'ERROR')))
    except (ValueError, OSError, KeyError, TypeError) as error:
        report, status = {'protocol': 1, 'harness_error': str(error)}, 2
    if args.json:
        args.json.write_text(json.dumps(report, indent=2) + '\n')
    print(json.dumps(report, sort_keys=True))
    return status


if __name__ == '__main__':
    raise SystemExit(main())
