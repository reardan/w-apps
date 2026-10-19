#!/usr/bin/env python3
"""Measurement integrity guards; no latency assertions on shared CI hosts."""
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
import browser_measurements as measure


class MeasurementIntegrity(unittest.TestCase):
    def test_percentiles_keep_raw_tail_and_sample_count(self):
        result = measure.summarize(list(range(1, 101)))
        self.assertEqual((result['n'], result['median'], result['p95'], result['p99']),
                         (100, 50.5, 95, 99))
        self.assertFalse(result['qualification'])
        for samples in ([], [-1], [float('nan')], [float('inf')]):
            with self.assertRaises(ValueError):
                measure.summarize(samples)

    def test_corpus_mutation_and_missing_are_not_passes(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / 'fixture').write_bytes(b'original\x00binary')
            manifest = {'artifacts': {'fixture': {'sha256': measure.digest(root / 'fixture')}}}
            with patch.object(measure, 'ROOT', root):
                self.assertEqual(measure.verify_corpus(manifest), [])
                (root / 'fixture').write_bytes(b'edited')
                self.assertEqual(measure.verify_corpus(manifest), ['fixture'])
                (root / 'fixture').unlink()
                self.assertEqual(measure.verify_corpus(manifest), ['fixture'])
                self.assertEqual(measure.verify_corpus({'artifacts': {'absent': {'status': 'MISSING'}}}), ['absent'])

    def test_busy_host_refuses_before_starting_command(self):
        with tempfile.TemporaryDirectory() as directory:
            out = Path(directory)
            (out / 'manifest.json').write_text(json.dumps({'artifacts': {}}))
            busy = {99999: {'parent': 1, 'name': 'wexec', 'ticks': 10}}
            with patch.object(measure, 'processes', return_value=busy), \
                 patch.object(measure.time, 'sleep'), \
                 patch.object(measure.subprocess, 'Popen') as popen:
                with self.assertRaisesRegex(ValueError, 'Host is busy'):
                    measure.run(out, ['must-not-run'])
                popen.assert_not_called()
                self.assertEqual(json.loads((out / 'idle-refusal.json').read_text())[0]['name'], 'wexec')

    def test_only_measured_process_tree_excluded(self):
        records = {1: {'parent': 0, 'ticks': 0, 'name': 'init'},
                   2: {'parent': 1, 'ticks': 0, 'name': 'runner'},
                   3: {'parent': 2, 'ticks': 0, 'name': 'win'},
                   4: {'parent': 3, 'ticks': 0, 'name': 'worker'},
                   5: {'parent': 1, 'ticks': 0, 'name': 'wv2'}}
        excluded = measure.descendants(records, 2)
        self.assertEqual(excluded, {2, 3, 4})
        self.assertEqual([p['pid'] for p in measure.contention(records, records, 1, excluded)], [5])


if __name__ == '__main__':
    unittest.main()
