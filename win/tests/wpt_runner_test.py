"""Contract checks for the static WPT adapter; no display required."""
import copy
import hashlib
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

import wpt_reftests as runner


class RunnerTests(unittest.TestCase):
    def test_actual_corpus_is_pinned(self):
        manifest = runner.load_manifest(runner.ROOT / 'wpt/manifest.json')
        for case in manifest['cases']:
            self.assertTrue(runner.references(runner.ROOT / 'wpt', case['path'], manifest['files']))

    def test_reference_logic_and_exact_pixels(self):
        self.assertEqual(runner.compare(bytes([0, 2, 4, 0, 0, 0]), bytes([0, 3, 4, 0, 0, 0])),
                         {'max_channel_difference': 1, 'different_pixels': 1})
        match = lambda n: {'relation': 'match', 'different_pixels': n}
        mismatch = lambda n: {'relation': 'mismatch', 'different_pixels': n}
        self.assertTrue(runner.relationships_pass([match(4), match(0), mismatch(1)]))
        self.assertFalse(runner.relationships_pass([match(4), mismatch(1)]))
        self.assertFalse(runner.relationships_pass([match(0), mismatch(0)]))
        self.assertTrue(runner.relationships_pass([mismatch(1)]))
        with self.assertRaises(ValueError):
            runner.compare(b'a', b'a')

    def test_paths_are_confined(self):
        for name in ['../escape', '/absolute', 'https://example.com/', 'x?y', '%2e%2e/x', 'x\\y']:
            with self.subTest(name=name), self.assertRaises(ValueError):
                runner.local_path(Path('/tmp/corpus'), name)

    def test_unsupported_readiness_never_runs_as_static(self):
        for markup in ['<script></script>', '<html class="reftest-wait">', '<meta name="fuzzy" content="1;1">',
                       '<link rel="stylesheet" href="a.css">', '<img src="a.png">', '<body onload="x()">',
                       '<style>div {background:url(a.png)}</style>', '<style>@font-face {}</style>',
                       '<style>div {animation: blink 1s}</style>', '<base href="/">',
                       r'<style>@\69mport "missing.css";</style>', r'<style>div {background:u\72l(x)}</style>',
                       '<p>{{host}}</p>']:
            with self.subTest(markup=markup), tempfile.TemporaryDirectory() as directory:
                path = Path(directory) / 'test.html'
                path.write_text(markup)
                with self.assertRaises(runner.Unsupported):
                    runner.metadata(path)

    def make_manifest(self, root):
        contents = {'LICENSE.md': 'test license', 'test.html': '<link rel="match" href="ref.html"><p>test</p>',
                    'ref.html': '<p>test</p>'}
        for name, text in contents.items():
            (root / name).write_text(text)
        manifest = {'version': 1, 'upstream': {'repository': 'https://github.com/web-platform-tests/wpt', 'revision': 'a' * 40},
                    'files': {name: hashlib.sha256(text.encode()).hexdigest() for name, text in contents.items()},
                    'cases': [{'path': 'test.html', 'expected': 'PASS'}]}
        path = root / 'manifest.json'
        path.write_text(json.dumps(manifest))
        return path, manifest

    def test_hashes_and_expected_failure_validation(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            path, manifest = self.make_manifest(root)
            runner.load_manifest(path)
            bad = copy.deepcopy(manifest)
            bad['cases'][0]['expected'] = 'FAIL'
            path.write_text(json.dumps(bad))
            with self.assertRaisesRegex(ValueError, 'reason'):
                runner.load_manifest(path)
            path.write_text(json.dumps(manifest))
            (root / 'ref.html').write_text('changed')
            with self.assertRaisesRegex(ValueError, 'pin mismatch'):
                runner.load_manifest(path)

    def test_report_does_not_hide_known_failure_or_error(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            path, manifest = self.make_manifest(root)
            manifest['cases'][0].update(expected='FAIL', reason='known pixel difference')
            path.write_text(json.dumps(manifest))
            with patch.object(runner, 'capture', side_effect=[b'\0\0\0', b'\0\1\0']):
                report = runner.run_suite(path, path, root / 'out')
            self.assertEqual(report['counts'], {'PASS': 0, 'FAIL': 1, 'UNSUPPORTED': 0, 'ERROR': 0})
            self.assertEqual(report['unexpected'], 0)
            with patch.object(runner, 'capture', return_value=b'\0\0\0'):
                report = runner.run_suite(path, path, root / 'out')
            self.assertEqual(report['counts'], {'PASS': 1, 'FAIL': 0, 'UNSUPPORTED': 0, 'ERROR': 0})
            self.assertEqual(report['unexpected'], 1)  # Fixed baseline needs review.
            with patch.object(runner, 'capture', side_effect=ValueError('renderer failed')):
                report = runner.run_suite(path, path, root / 'out')
            self.assertEqual(report['counts'], {'PASS': 0, 'FAIL': 0, 'UNSUPPORTED': 0, 'ERROR': 1})
            self.assertEqual(report['unexpected'], 1)

    def test_malformed_manifest_shapes(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            path, manifest = self.make_manifest(root)
            invalid = [None, [], {**manifest, 'upstream': None},
                       {**manifest, 'cases': [None]}, {**manifest, 'cases': [{'path': [], 'expected': 'PASS'}]}]
            for data in invalid:
                with self.subTest(data=data):
                    path.write_text(json.dumps(data))
                    with self.assertRaises(ValueError):
                        runner.load_manifest(path)
            fixture = root / 'boolean-attributes.html'
            fixture.write_text('<meta name><p hidden>test</p>')
            runner.metadata(fixture)

    def test_ppm_shape(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'capture.ppm'
            path.write_bytes(b'P6\n800 600\n255\n' + bytes(800 * 600 * 3))
            self.assertEqual(len(runner.read_ppm(path)), 800 * 600 * 3)
            path.write_bytes(b'P6\n800 600\n255\n' + bytes(10))
            with self.assertRaisesRegex(ValueError, 'truncated'):
                runner.read_ppm(path)


if __name__ == '__main__':
    unittest.main()
