#!/usr/bin/env python3
"""Cookie data-adapter admission and missing-driver reporting contracts."""
import hashlib
import importlib.util
from pathlib import Path
import shutil
import tempfile
import unittest
from unittest.mock import patch

HERE = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location('cookie_adapter', HERE / 'run.py')
adapter = importlib.util.module_from_spec(spec)
spec.loader.exec_module(adapter)


class CookieReportContract(unittest.TestCase):
    def test_missing_driver_retains_all_cases_and_nullable_hash(self):
        with tempfile.TemporaryDirectory() as temporary:
            report = adapter.run(Path(temporary) / 'missing-driver')
        self.assertEqual(report['total'], 33)
        self.assertEqual(report['counts'], {'ERROR': 21, 'UNSUPPORTED': 12})
        self.assertEqual(len(report['results']), 33)
        proof = report['evidence']
        self.assertIsNone(proof['driver_sha256'])
        self.assertTrue(proof['driver_hash_error'])
        self.assertEqual(proof['kind'], 'fresh-execution')
        self.assertTrue(proof['recorded_at_utc'].endswith('+00:00'))
        self.assertRegex(proof['application_revision'], r'^[0-9a-f]{40}$')
        self.assertRegex(proof['w_revision'], r'^[0-9a-f]{40}$')
        self.assertEqual(proof['fixture_sha256'], adapter.SOURCE_PINS)
        self.assertEqual(proof['adapter_sha256'], hashlib.sha256((HERE / 'run.py').read_bytes()).hexdigest())

    def test_changed_pinned_license_is_rejected_before_execution(self):
        with tempfile.TemporaryDirectory() as temporary:
            fixtures = Path(temporary)
            for name in adapter.SOURCE_PINS:
                shutil.copyfile(HERE / name, fixtures / name)
            (fixtures / 'LICENSE.md').write_text('changed license')
            with patch.object(adapter, 'HERE', fixtures):
                with self.assertRaisesRegex(ValueError, 'pinned fixture changed: LICENSE.md'):
                    adapter.run(Path('/unused'))


if __name__ == '__main__':
    unittest.main()
