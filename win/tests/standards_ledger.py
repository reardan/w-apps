#!/usr/bin/env python3
"""Validate ownership/accounting of the completion backlog without claiming compliance."""
import hashlib
import json
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[2]


def validate(ledger, snapshots):
    rows = ledger['requirements']
    ids = {row['id'] for row in rows}
    assert len(ids) == len(rows), 'duplicate requirement ID'
    for row in rows:
        assert row['owner'] in {'A', 'B', 'C', 'D', 'E', 'F', 'G', 'coordinator'}, row['id']
        assert isinstance(row['mandatory'], bool), row['id']
        assert row['implementation_paths'] and row['negative_tests'], row['id']
        assert row['performance_fixture'] and row['applicability'], row['id']
        assert set(row['dependencies']) <= ids, row['id']
        assert row['spec']['snapshot'] in snapshots['specifications'] or row['spec']['snapshot'] == 'engineering-plan', row['id']
        counts = row['upstream']
        assert counts['executed'] >= 0, row['id']
        if counts['total'] is not None:
            assert counts['executed'] <= counts['total'], row['id']
        if row['status'] == 'closed':
            assert row['closure_evidence'], row['id']
            assert counts['total'] is not None and counts['executed'] == counts['total'], row['id']
            assert counts['counts'] is not None, row['id']
            assert all(counts['counts'].get(s, 0) == 0 for s in
                       ('FAIL', 'ERROR', 'UNSUPPORTED', 'TIMEOUT', 'SKIP', 'NOT_RUN')), row['id']
        else:
            assert row['status'] in {'mandatory-open', 'in-progress', 'blocked', 'optional'}, row['id']
        if row['mandatory']:
            assert row['status'] != 'optional', row['id']
    for evidence in ledger['compatibility_evidence']:
        assert evidence['tracked_by'] in ids
        assert hashlib.sha256(evidence['text'].encode()).hexdigest() == evidence['sha256']
    assert ledger['performance_budgets']['status'] == 'proposed-unqualified'


def main():
    ledger = json.loads((ROOT / 'win/docs/standards-ledger.json').read_text())
    snapshots = json.loads((ROOT / 'win/docs/standards-snapshots.json').read_text())
    validate(ledger, snapshots)
    sources = {}
    for item in ledger['compatibility_evidence']:
        source = item['source']
        if source not in sources:
            sources[source] = subprocess.check_output(['git', 'show', ledger['baseline']['app'] + ':' + source], cwd=ROOT, text=True)
        assert item['text'] in sources[source], source
    print(f"Ledger: {len(ledger['requirements'])} owned families, {len(ledger['compatibility_evidence'])} retained baseline gap excerpts; completion remains open")


if __name__ == '__main__':
    main()
