#!/usr/bin/env python3
"""Family admission/report accounting; synthetic executor outcomes are not WPT passes."""
import copy
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
import wpt_family_audit as audit


class FamilyAuditContract(unittest.TestCase):
    def test_complete_original_parent_inventory(self):
        manifest, _ = audit.load_manifest(audit.MANIFEST)
        self.assertEqual(len(manifest['cases']), 35)
        self.assertEqual(len({c['source'] for c in manifest['cases']}), 20)
        self.assertEqual(len(manifest['support_files']), 2)
        self.assertEqual(sum(audit.admission(c) is None for c in manifest['cases']), 12)
        self.assertEqual(sum(c['environment'] == 'worker' for c in manifest['cases']), 15)
        self.assertEqual(sum(c['environment'] == 'html-document' for c in manifest['cases']), 8)

    def test_missing_driver_preserves_every_manifest_item(self):
        with tempfile.TemporaryDirectory() as directory:
            report = audit.run(audit.MANIFEST, Path(directory) / 'missing')
        self.assertEqual(report['declared_items'], 35)
        self.assertEqual(report['admitted_items'], 12)
        self.assertEqual(report['counts'], {'PASS': 0, 'FAIL': 0, 'UNSUPPORTED': 23, 'ERROR': 12})
        self.assertEqual(len(report['results']), 35)
        self.assertIsNone(report['evidence']['driver_sha256'])

    def test_failure_cannot_disappear_from_admitted_denominator(self):
        calls = []
        def execute(driver, sources, timeout):
            calls.append(sources[-1])
            return {'status': 'FAIL' if len(calls) == 1 else 'PASS', 'reason': 'synthetic accounting fixture'}
        with patch.object(audit.runner, 'execute', side_effect=execute):
            report = audit.run(audit.MANIFEST, audit.runner.ROOT / 'win/bin/wpt_driver')
        self.assertEqual(len(calls), 12)
        self.assertEqual(report['counts'], {'PASS': 11, 'FAIL': 1, 'UNSUPPORTED': 23, 'ERROR': 0})
        self.assertEqual(report['admitted_counts']['FAIL'], 1)

    def test_resource_and_variant_requirements_stay_unsupported(self):
        manifest, _ = audit.load_manifest(audit.MANIFEST)
        case = copy.deepcopy(next(c for c in manifest['cases'] if c['environment'] == 'window-script'))
        case['metadata'] = {'script_metadata': [['script', '/resources/extra.js']]}
        self.assertIn('resource/environment', audit.admission(case))
        case['metadata'] = {}
        case['id'] += '?variant'
        self.assertIn('variant', audit.admission(case))


if __name__ == '__main__':
    unittest.main()
