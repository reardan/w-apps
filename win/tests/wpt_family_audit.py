#!/usr/bin/env python3
"""Audit every original manifest item in the pinned asynchronous parent families."""
import argparse
from collections import Counter
import hashlib
import json
from pathlib import Path
import tempfile
import wpt_testharness as runner

MANIFEST = runner.CORPUS / 'async-family-manifest.json'


def load_manifest(path):
    data = runner.strict_json(path.read_text())
    runner.require(data.get('version') == 1 and isinstance(data.get('cases'), list) and data['cases'], 'invalid family inventory')
    inventory = runner.strict_json((path.parent / 'wpt-inventory.json').read_text())
    runner.require(data['upstream']['revision'] == inventory['revision'] and
                   data['upstream']['repository'] == inventory['repository'], 'suite inventory revision mismatch')
    runner.require(data['official_manifest_sha256'] == inventory['metadata_expansion']['manifest_sha256'], 'official manifest hash mismatch')
    runner.require(data['families'] and all(f.endswith('/') and '..' not in f.split('/') for f in data['families']), 'invalid family paths')
    for name, digest in data['files'].items():
        runner.require_relative_source(name)
        source = (path.parent / name).resolve()
        runner.require(source.is_relative_to(path.parent.resolve()), 'source escapes corpus')
        runner.require(hashlib.sha256(source.read_bytes()).hexdigest() == digest, 'pin mismatch: ' + name)
    ids = set()
    for case in data['cases']:
        runner.require(set(case) == {'id', 'source', 'type', 'environment', 'metadata'}, 'invalid family case fields')
        runner.require(case['id'] not in ids and case['source'] in data['files'], 'duplicate or unpinned family item')
        runner.require(any(case['source'].startswith(f) for f in data['families']), 'case outside declared families')
        runner.require(case['environment'] in {'window-script', 'worker', 'html-document'}, 'invalid environment')
        ids.add(case['id'])
    return data, inventory


def admission(case):
    if case['type'] != 'testharness':
        return 'unsupported upstream test type: ' + case['type']
    if case['environment'] != 'window-script':
        return 'mandatory ' + case['environment'] + ' execution is not implemented by the native script seam'
    if '?' in case['id'] or '#' in case['id']:
        return 'URL query/fragment variant setup is not implemented'
    for key, value in case['metadata'].get('script_metadata', []):
        if key not in {'global', 'title', 'spec', 'timeout'}:
            return 'script metadata requires resource/environment integration: ' + key
    if case['metadata'].get('testdriver') or case['metadata'].get('jsshell'):
        return 'testdriver or alternative host integration is not implemented'
    return None


def run(manifest_path, driver, timeout=10):
    manifest, inventory = load_manifest(manifest_path)
    evidence = runner.evidence(driver)
    frozen = runner.freeze_inputs(manifest_path, manifest, inventory)
    adapter_hash = hashlib.sha256(Path(__file__).read_bytes()).hexdigest()
    results = []
    with tempfile.TemporaryDirectory(prefix='win-wpt-family-') as directory:
        sources = Path(directory) / 'corpus'
        runner.write_inputs(sources, frozen)
        bridge = Path(directory) / 'bridge.js'
        bridge.write_text(runner.BRIDGE)
        for case in manifest['cases']:
            blocker = admission(case)
            result = {'status': 'UNSUPPORTED', 'reason': blocker} if blocker else runner.execute(
                driver, [sources / 'resources/testharness.js', bridge, sources / case['source']], timeout)
            results.append({**case, 'admitted': blocker is None, **result})
    runner.check_provenance(manifest_path, frozen, driver, evidence, results, [(Path(__file__), adapter_hash)])
    counts = Counter(item['status'] for item in results)
    admitted = Counter(item['status'] for item in results if item['admitted'])
    return {'protocol': 1, 'profile': 'native-window-script-parent-families-v1', 'upstream': manifest['upstream'],
            'families': manifest['families'], 'official_manifest_sha256': manifest['official_manifest_sha256'],
            'family_manifest_sha256': hashlib.sha256(frozen[manifest_path.name]).hexdigest(),
            'family_adapter_sha256': adapter_hash,
            'source_pins': manifest['files'], 'evidence': evidence, 'inventory': inventory,
            'declared_items': len(results), 'source_files': len({r['source'] for r in results}),
            'support_files': manifest['support_files'], 'admitted_items': sum(admitted.values()),
            'counts': {key: counts[key] for key in runner.STATUSES},
            'admitted_counts': {key: admitted[key] for key in runner.STATUSES}, 'results': results,
            'limitations': manifest['limitations']}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--manifest', type=Path, default=MANIFEST)
    parser.add_argument('--driver', type=Path, default=runner.ROOT / 'win/bin/wpt_driver')
    parser.add_argument('--timeout', type=float, default=10)
    parser.add_argument('--json', type=Path)
    args = parser.parse_args()
    try:
        runner.require(0 < args.timeout <= 60, 'invalid timeout')
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
