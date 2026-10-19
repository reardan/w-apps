#!/usr/bin/env python3
"""Measurement supervisor lifecycle checks; these do not run browser benchmarks."""
import importlib.util
from pathlib import Path
import subprocess
import sys
import tempfile
import time
import unittest

# Resolve the same directory in the installed tests tree and staged review copy.
spec = importlib.util.spec_from_file_location('native_measurements',
    Path(__file__).with_name('native_browser_measurements.py'))
measure = importlib.util.module_from_spec(spec)
spec.loader.exec_module(measure)


class ProcessOwnership(unittest.TestCase):
    def test_success_and_failure_status(self):
        measure.run_process_group([sys.executable, '-c', 'pass'], 5)
        with self.assertRaises(subprocess.CalledProcessError) as result:
            measure.run_process_group([sys.executable, '-c', 'raise SystemExit(7)'], 5)
        self.assertEqual(result.exception.returncode, 7)

    def test_timeout_stops_descendant_but_preserves_unrelated_process(self):
        unrelated = subprocess.Popen([sys.executable, '-c', 'import time;time.sleep(30)'])
        try:
            with tempfile.TemporaryDirectory() as temporary:
                pidfile = Path(temporary) / 'probe.pid'
                code = ('import os,pathlib,time;pathlib.Path(' + repr(str(pidfile)) +
                        ').write_text(str(os.getpid()));time.sleep(30)')
                with self.assertRaises(subprocess.TimeoutExpired):
                    measure.run_process_group(['/usr/bin/time', sys.executable, '-c', code], 1)
                self.assertTrue(pidfile.is_file(), 'descendant did not start before deadline')
                status = Path('/proc') / pidfile.read_text() / 'stat'
                # SIGKILL delivery is asynchronous; a stopped zombie is already
                # unable to execute and its new parent owns the final reap.
                for _ in range(100):
                    try:
                        state = status.read_text().split(') ', 1)[1][0]
                    except FileNotFoundError:
                        break
                    if state == 'Z':
                        break
                    time.sleep(.01)
                else:
                    self.fail('owned descendant survived process-group timeout')
                self.assertIsNone(unrelated.poll())
        finally:
            unrelated.kill()
            unrelated.wait()


if __name__ == '__main__':
    unittest.main()
