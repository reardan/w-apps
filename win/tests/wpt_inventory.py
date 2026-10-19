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
import urllib.request

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


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('suite', choices=SUITES)
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=True)
    inventory(args.suite, args.output)
