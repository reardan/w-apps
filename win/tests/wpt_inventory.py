#!/usr/bin/env python3
"""Inventory complete immutable upstream archives, without claiming applicability.

Network is used only by this explicit refresh tool, never by ordinary gates.
"""
import argparse
from collections import Counter
import hashlib
import json
from pathlib import Path
import tarfile
import sys
import urllib.request

ARCHIVE_SHA256 = {
    'test262': 'f8e99225426343b50672313f46c4c0b5e0f228f5d10e1ea6782c14ef34784cb4',
    'wpt': '844093aab72997ed0c0a7146376421cb8864557fd5a9bdddabd10fc2ab690ed4',
}

SUITES = {
    'test262': ('tc39/test262', '2e0a56762801e275a9fdf96dc49d90ba0cddcf63'),
    'wpt': ('web-platform-tests/wpt', '6d4552a8b1057e42a180119d70273f563e53a264'),
}


def inventory(suite, directory):
    repository, revision = SUITES[suite]
    url = f'https://codeload.github.com/{repository}/tar.gz/{revision}'
    archive = directory / (suite + '.tar.gz')
    digest = hashlib.sha256()
    with urllib.request.urlopen(url, timeout=120) as source, archive.open('wb') as target:
        while data := source.read(1024 * 1024):
            digest.update(data)
            target.write(data)
    counts = Counter()
    families = Counter()
    files = []
    with tarfile.open(archive) as source:
        for item in source:
            if not item.isfile():
                continue
            path = item.name.split('/', 1)[1]
            content = source.extractfile(item).read()
            files.append([path, hashlib.sha256(content).hexdigest()])
            counts['regular_files'] += 1
            families[path.split('/')[0]] += 1
            if suite == 'test262' and path.startswith('test/') and path.endswith('.js'):
                counts['javascript_files_under_test'] += 1
                if '_FIXTURE' not in path:
                    counts['candidate_test_files_excluding_fixtures'] += 1
            if suite == 'wpt':
                if path.endswith(('.html', '.htm', '.xhtml', '.xht', '.svg', '.js')):
                    counts['candidate_web_source_files'] += 1
                if b'/resources/testharness.js' in content and path.endswith(('.html', '.htm', '.xhtml', '.xht', '.svg')):
                    counts['markup_files_referencing_testharness'] += 1
                if path.endswith(('.any.js', '.window.js', '.worker.js')):
                    counts['generated_test_source_files'] += 1
    files.sort()
    index = (json.dumps(files, separators=(',', ':')) + '\n').encode()
    index_path = directory / (suite + '-files.json')
    index_path.write_bytes(index)
    report = {
        'protocol': 1, 'suite': suite, 'repository': 'https://github.com/' + repository,
        'revision': revision, 'archive_url': url, 'archive_sha256': digest.hexdigest(),
        'file_index_sha256': hashlib.sha256(index).hexdigest(), 'counts': dict(counts),
        'top_level_regular_files': dict(sorted(families.items())), 'complete_archive_inventory': True,
        'applicable_tests': None, 'runnable_variants': None,
        'limitations': 'File inventory is complete. Candidate files are not an applicability or runnable variant denominator. WPT MANIFEST/environment/variant expansion and Test262 metadata expansion remain required. Unselected files are unexecuted, not passes or exclusions.',
    }
    (directory / (suite + '-inventory.json')).write_text(json.dumps(report, indent=2) + '\n')
    print(json.dumps(report), flush=True)



def expand(suite, directory):
    """Run original upstream metadata code from the verified immutable archive."""
    archive = directory / (suite + '.tar.gz')
    if hashlib.sha256(archive.read_bytes()).hexdigest() != ARCHIVE_SHA256[suite]:
        raise ValueError('upstream archive hash mismatch')
    _, revision = SUITES[suite]
    if suite == 'test262':
        parser_dir = directory / 'test262-tools'
        parser_dir.mkdir(exist_ok=True)
        parser_hashes = {}
        counts, flags, features, families = Counter(), Counter(), Counter(), {}
        diagnostics, unexpanded = [], []
        with tarfile.open(archive) as source:
            prefix = 'test262-' + revision + '/'
            for name in ('parseTestRecord.py', 'monkeyYaml.py'):
                data = source.extractfile(prefix + 'tools/packaging/' + name).read()
                (parser_dir / name).write_bytes(data)
                parser_hashes[name] = hashlib.sha256(data).hexdigest()
            sys.path.insert(0, str(parser_dir.resolve()))
            from parseTestRecord import parseTestRecord
            for item in source.getmembers():
                path = item.name.removeprefix(prefix)
                if not item.isfile() or not path.startswith('test/') or not path.endswith('.js') or '_FIXTURE' in path:
                    continue
                counts['files'] += 1
                try:
                    metadata = parseTestRecord(source.extractfile(item).read().decode('utf-8'), path, lambda error: diagnostics.append([path, str(error)]))
                    case_flags = metadata.get('flags', [])
                    variants = 1 if any(flag in case_flags for flag in ('raw', 'noStrict', 'onlyStrict', 'module')) else 2
                    counts['upstream_declared_variants'] += variants
                    flags.update(case_flags)
                    features.update(metadata.get('features', []))
                    family = '/'.join(path.split('/')[1:3])
                    entry = families.setdefault(family, {'files': 0, 'variants': 0})
                    entry['files'] += 1
                    entry['variants'] += variants
                except Exception as error:
                    unexpanded.append([path, str(error)])
        report = {'protocol': 1, 'revision': revision, 'counts': dict(counts), 'flags': dict(flags),
                  'features': dict(features), 'families': dict(sorted(families.items())),
                  'diagnostics': diagnostics, 'unexpanded': unexpanded, 'metadata_parser_sha256': parser_hashes,
                  'applicability': 'unresolved; declared variant count is not an execution/pass count'}
        target = directory / 'test262-metadata.json'
    else:
        source_dir = directory / 'wpt-source'
        source_dir.mkdir(exist_ok=True)
        # Python 3.12+ for the safe extraction filter. Only verified archive code runs.
        with tarfile.open(archive) as source:
            source.extractall(source_dir, filter='data')
        source_root = source_dir / ('wpt-' + revision)
        sys.path[:0] = [str(source_root / 'tools')] + [str(p) for p in (source_root / 'tools/third_party').iterdir() if p.is_dir()]
        from manifest.manifest import load_and_update
        manifest_path = directory / 'WPT-MANIFEST.json'
        manifest = load_and_update(str(source_root), str(manifest_path), '/', rebuild=True,
                                   parallel=False, cache_root=str(directory / 'wpt-manifest-cache'))
        files, items = Counter(), Counter()
        for kind, path, tests in manifest:
            files[kind] += 1
            items[kind] += len(tests)
        report = {'protocol': 1, 'revision': revision, 'generator': 'unchanged upstream tools/manifest',
                  'manifest_version': manifest.to_json()['version'],
                  'manifest_sha256': hashlib.sha256(manifest_path.read_bytes()).hexdigest(),
                  'source_files_by_type': dict(files), 'declared_items_by_type': dict(items),
                  'applicability': 'Unresolved. Manifest items are candidates, not executed/passed tests; support and manual items remain separate.'}
        target = directory / 'wpt-manifest-inventory.json'
    target.write_text(json.dumps(report, indent=2) + '\n')
    print(json.dumps(report), flush=True)

if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('suite', choices=SUITES)
    parser.add_argument('--expand-existing', action='store_true', help='offline metadata/manifest expansion from verified archive (WPT requires Python 3.12+)')
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=True)
    if args.expand_existing:
        expand(args.suite, args.output.resolve())
    else:
        inventory(args.suite, args.output)
