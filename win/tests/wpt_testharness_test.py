#!/usr/bin/env python3
"""Native async driver and strict result-accounting contracts, not WPT passes."""
import copy
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
import wpt_testharness as runner

DRIVER = runner.ROOT / 'win/bin/wpt_driver'
PAYLOAD = {'status': 0, 'tests': [{'name': 'contract', 'status': 0, 'message': None}]}


class AsyncDriverContract(unittest.TestCase):
    def execute(self, source, timeout=.2):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'contract.js'
            path.write_text(source)
            return runner.execute(DRIVER, [path], timeout)

    def complete(self, payload=PAYLOAD):
        return '__wptComplete(' + json.dumps(json.dumps(payload)) + ');'

    def test_real_timer_and_promise_checkpoint(self):
        source = 'var order=0; Promise.resolve().then(function(){order=1;}); setTimeout(function(){if(order!==1) throw 1;' + self.complete() + '},20);'
        result = self.execute(source)
        self.assertEqual(result['status'], 'PASS', result)
        self.assertGreaterEqual(result['actual']['elapsed_ms'], 20)

    def test_real_suspended_async_function(self):
        source = 'async function f(){await new Promise(function(resolve){setTimeout(resolve,10);});' + self.complete() + '} f();'
        result = self.execute(source)
        self.assertEqual(result['status'], 'PASS', result)

    def test_deliberate_assertion_failure(self):
        payload = copy.deepcopy(PAYLOAD)
        payload['tests'][0]['status'] = 1
        payload['tests'][0]['message'] = 'intentional assertion failure'
        self.assertEqual(self.execute('setTimeout(function(){' + self.complete(payload) + '},1);')['status'], 'FAIL')

    def test_runtime_throw_is_error(self):
        result = self.execute('setTimeout(function(){throw new Error("intentional");},1);')
        self.assertEqual(result['status'], 'ERROR')
        self.assertEqual(result['actual']['script_failures'], 1)

    def test_timeout_is_error(self):
        result = self.execute('new Promise(function(){});', timeout=.03)
        self.assertEqual(result['status'], 'ERROR')
        self.assertIn('timeout', result['reason'])

    def test_duplicate_completion_is_error(self):
        self.assertEqual(self.execute(self.complete() + self.complete())['status'], 'ERROR')

    def test_throw_after_completion_is_error(self):
        self.assertEqual(self.execute(self.complete() + 'throw 1;')['status'], 'ERROR')

    def test_malformed_completion_is_error(self):
        for source in ['__wptComplete(1);', '__wptComplete("not json");', '__wptComplete("{}");', '__wptComplete("{}\\x00junk");']:
            self.assertEqual(self.execute(source)['status'], 'ERROR')

    def test_valid_json_prefix_cannot_hide_nul_suffix(self):
        source = '__wptComplete(' + json.dumps(json.dumps(PAYLOAD) + '\x00junk') + ');'
        result = self.execute(source)
        self.assertEqual(result['status'], 'ERROR', result)
        self.assertEqual(result['actual']['script_failures'], 1)

    def test_fresh_realms(self):
        for _ in range(2):
            source = 'if(typeof previous!=="undefined") throw 1; var previous=1;' + self.complete()
            self.assertEqual(self.execute(source)['status'], 'PASS')

    def test_original_harness_is_pinned(self):
        manifest = runner.load_manifest(runner.CORPUS / 'testharness-manifest.json')
        self.assertEqual(len(manifest['cases']), 3)

    def test_strict_protocol_rejection(self):
        good = {'protocol': 1, 'completions': 1, 'script_failures': 0, 'failed_source': -1,
                'elapsed_ms': 1, 'message': '', 'payload': json.dumps(PAYLOAD)}
        for key, value in [('protocol', True), ('completions', True), ('elapsed_ms', -1), ('failed_source', -2)]:
            report = dict(good, **{key: value})
            with self.assertRaises(ValueError):
                runner.classify(report)
        for payload in [{'status': 0, 'tests': []}, {'status': True, 'tests': PAYLOAD['tests']},
                        {'status': 0, 'tests': PAYLOAD['tests'] * 2}]:
            with self.assertRaises(ValueError):
                runner.classify(dict(good, payload=json.dumps(payload)))
        for status in (2, 3, 4):
            payload = copy.deepcopy(PAYLOAD)
            payload['tests'][0]['status'] = status
            self.assertEqual(runner.classify(dict(good, payload=json.dumps(payload)))[0],
                             'UNSUPPORTED' if status == 4 else 'ERROR')

    def test_duplicate_and_nonfinite_json_are_rejected(self):
        for text in ['{"status":0,"status":1}', '{"value":NaN}', '{"value":Infinity}']:
            with self.assertRaises(ValueError):
                runner.strict_json(text)

    def test_crash_and_malformed_process_output(self):
        with tempfile.TemporaryDirectory() as directory:
            binary = Path(directory) / 'driver'
            for body, reason in [('import os,signal;os.kill(os.getpid(),signal.SIGKILL)', 'process crash'),
                                 ('print("{}")', 'malformed report'),
                                 ("import os;os.write(1,b'\\xff')", 'malformed report')]:
                binary.write_text('#!/usr/bin/env python3\n' + body + '\n')
                binary.chmod(0o755)
                result = runner.execute(binary, [], .1)
                self.assertEqual(result['status'], 'ERROR')
                self.assertIn(reason, result['reason'])

    def test_missing_driver_preserves_case_denominator(self):
        with tempfile.TemporaryDirectory() as directory:
            report = runner.run(runner.CORPUS / 'testharness-manifest.json', Path(directory) / 'absent')
        self.assertEqual(report['selected_files'], 3)
        self.assertEqual(report['counts']['ERROR'], 3)
        self.assertEqual(len(report['results']), 3)
        self.assertIsNone(report['evidence']['driver_sha256'])
        self.assertTrue(report['evidence']['driver_hash_error'])

    def test_inventory_revision_mismatch_is_rejected(self):
        manifest = runner.load_manifest(runner.CORPUS / 'testharness-manifest.json')
        manifest['upstream']['revision'] = '0' * 40
        with patch.object(runner, 'load_manifest', return_value=manifest):
            with self.assertRaisesRegex(ValueError, 'inventory revision mismatch'):
                runner.run(runner.CORPUS / 'testharness-manifest.json', DRIVER)


if __name__ == '__main__':
    unittest.main()
