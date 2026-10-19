#!/usr/bin/env python3
"""Freeze browser artifacts and record commands with honest idle-host provenance.

This records exploratory measurements. It does not invent presentation timestamps,
calibrate vsync, or qualify the proposed browser completion budgets.
"""
import argparse
import datetime
import fcntl
import hashlib
import json
import os
from pathlib import Path
import platform
import shutil
import statistics
import subprocess
import sys
import time

ROOT = Path(__file__).resolve().parents[2]
DEFAULT_CORPUS = ['w/tools/web/index.html',
                  'w/bin/graphics_demo.wasm', 'w/bin/graphics_ui_mobile.wasm']
BUILDERS = {'wv2', 'wv3', 'wv4', 'wv5', 'wexec', 'wtest', 'wbuild', 'cc1', 'rustc'}


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def command_output(command):
    try:
        return subprocess.check_output(command, cwd=ROOT, text=True,
                                       stderr=subprocess.STDOUT).strip()
    except (OSError, subprocess.CalledProcessError) as error:
        return {'unavailable': str(error)}


def provenance():
    cpu = Path('/proc/cpuinfo').read_text() if Path('/proc/cpuinfo').exists() else ''
    return {'app': command_output(['git', 'rev-parse', 'HEAD']),
            'w': command_output(['git', '-C', 'w', 'rev-parse', 'HEAD']),
            'app_worktree': command_output(['git', 'status', '--short']),
            'w_worktree': command_output(['git', '-C', 'w', 'status', '--short']),
            'utc': datetime.datetime.now(datetime.timezone.utc).isoformat(),
            'os': platform.platform(), 'kernel': platform.release(),
            'cpu': next((line.split(':', 1)[1].strip() for line in cpu.splitlines()
                         if line.startswith('model name')), platform.machine()),
            'affinity': sorted(os.sched_getaffinity(0)),
            'python': platform.python_version(), 'node': command_output(['node', '--version']),
            'locale': {k: os.environ.get(k) for k in ('LANG', 'LC_ALL', 'TZ')},
            'timezone': command_output(['date', '+%Z %z']),
            'graphics': command_output(['glxinfo', '-B']),
            'fonts_sha256': hashlib.sha256(str(command_output(['fc-list'])).encode()).hexdigest(),
            'governors': {str(p): p.read_text().strip() for p in
                          Path('/sys/devices/system/cpu').glob('cpu*/cpufreq/scaling_governor')},
            'qualification': 'exploratory; no end-to-end or percentile budget qualified'}


def freeze(output):
    output.mkdir(parents=True, exist_ok=True)
    paths = set(DEFAULT_CORPUS)
    paths.update(str(p.relative_to(ROOT)) for p in (ROOT / 'w/tools/web').glob('*') if p.is_file())
    paths.update(str(p.relative_to(ROOT)) for p in (ROOT / 'win/fixtures/workflow').rglob('*') if p.is_file())
    paths.update(str(p.relative_to(ROOT)) for p in (ROOT / 'w/graphics').rglob('*.w'))
    records = {}
    for name in sorted(paths):
        source = ROOT / name
        if not source.is_file():
            records[name] = {'status': 'MISSING'}
            continue
        target = output / 'corpus' / name
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(source, target)
        records[name] = {'sha256': digest(source), 'bytes': source.stat().st_size}
    data = {'schema': 1, 'environment': provenance(), 'artifacts': records,
            'build_flags': 'W bin/wv2 wasm; Win bin/wv2 x64 --strict; existing execution/fuel limits',
            'reference_browser': {'recorded_historical': 'Chromium 145.0.7632.6 / Playwright 1.58.0',
                                  'fresh_reference_run': False},
            'missing_measurements': ['presentation/vsync calibration', 'cold/warm 30-sample scenarios',
                                     '1000 input-to-present samples', '1000 presented frames',
                                     '100 navigation/tab cycles', 'real GPU qualification']}
    (output / 'manifest.json').write_text(json.dumps(data, indent=2) + '\n')
    return data


def verify_corpus(manifest):
    failures = []
    for name, record in manifest['artifacts'].items():
        path = ROOT / name
        if 'sha256' not in record or not path.is_file() or digest(path) != record['sha256']:
            failures.append(name)
    return failures


def processes():
    found = {}
    for entry in Path('/proc').iterdir():
        if not entry.name.isdigit():
            continue
        try:
            text = (entry / 'stat').read_text()
            fields = text[text.rindex(')') + 2:].split()
            found[int(entry.name)] = {'parent': int(fields[1]),
                                     'ticks': int(fields[11]) + int(fields[12]),
                                     'name': text[text.index('(') + 1:text.rindex(')')]}
        except (OSError, ValueError, IndexError):
            pass  # Process vanished during the observation.
    return found


def descendants(snapshot, parent):
    result = {parent}
    while True:
        expanded = result | {pid for pid, p in snapshot.items() if p['parent'] in result}
        if expanded == result:
            return result
        result = expanded


def contention(before, after, elapsed, excluded):
    hz = os.sysconf('SC_CLK_TCK')
    active = []
    for pid, proc in after.items():
        if pid in excluded:
            continue
        delta = max(0, proc['ticks'] - before.get(pid, proc)['ticks'])
        cores = delta / hz / elapsed
        if cores > 0.02 or proc['name'] in BUILDERS:
            active.append({'pid': pid, 'name': proc['name'], 'cpu_cores': cores})
    return active


def run(output, argv):
    manifest = json.loads((output / 'manifest.json').read_text())
    failures = verify_corpus(manifest)
    if failures:
        raise ValueError('Frozen corpus missing or changed: ' + ', '.join(failures))
    # Cross-worktree lease. Workers also stop their builders before this command.
    with open('/tmp/win-browser-measurement.lock', 'a') as lock:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        initial = processes()
        start = time.monotonic()
        time.sleep(1)
        ready = processes()
        noise = contention(initial, ready, time.monotonic() - start, descendants(ready, os.getpid()))
        if noise:
            (output / 'idle-refusal.json').write_text(json.dumps(noise, indent=2) + '\n')
            raise ValueError('Host is busy; see idle-refusal.json. No measurement executed.')
        report = {'schema': 1, 'command': argv, 'environment': provenance(),
                  'scope': 'command wall time only; inspect probe raw data for metric semantics',
                  'qualification': False, 'external_activity': []}
        before = processes()
        start = previous_time = time.monotonic()
        with (output / 'measurement.log').open('w') as log:
            child = subprocess.Popen(argv, cwd=ROOT, stdout=log, stderr=subprocess.STDOUT)
            while True:
                try:
                    child.wait(timeout=0.25)
                except subprocess.TimeoutExpired:
                    pass
                now = time.monotonic()
                after = processes()
                report['external_activity'].extend(contention(before, after, now - previous_time,
                                                               descendants(after, os.getpid())))
                before, previous_time = after, now
                if child.returncode is not None:
                    break
        report['seconds'] = time.monotonic() - start
        report['exit_code'] = child.returncode
        report['idle_valid'] = not report['external_activity']
        report['corpus_changes'] = verify_corpus(manifest)
        report['valid'] = report['idle_valid'] and child.returncode == 0 and not report['corpus_changes']
        (output / 'measurement.json').write_text(json.dumps(report, indent=2) + '\n')
        return 0 if report['valid'] else 1


def summarize(samples):
    if not samples or any(not isinstance(v, (int, float)) or not 0 <= v < float('inf') for v in samples):
        raise ValueError('Expected nonempty finite nonnegative raw samples')
    ordered = sorted(samples)
    # Nearest rank: never interpolate a p99 beyond observed data.
    import math
    return {'n': len(samples), 'median': statistics.median(samples),
            'p95': ordered[math.ceil(len(samples) * .95) - 1],
            'p99': ordered[math.ceil(len(samples) * .99) - 1],
            'qualification': False}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('action', choices=('freeze', 'verify', 'run'))
    parser.add_argument('--output', type=Path, default=ROOT / 'win/bin/completion-baseline/frozen')
    parser.add_argument('command', nargs=argparse.REMAINDER)
    args = parser.parse_args()
    if args.action == 'freeze':
        if (args.output / 'manifest.json').exists():
            parser.error('Refusing to overwrite a frozen manifest; use a new output directory')
        freeze(args.output)
        return 0
    if args.action == 'verify':
        failures = verify_corpus(json.loads((args.output / 'manifest.json').read_text()))
        print(json.dumps({'changed_or_missing': failures}))
        return int(bool(failures))
    command = args.command[1:] if args.command[:1] == ['--'] else args.command
    if not command:
        parser.error('run requires a command after --')
    try:
        return run(args.output, command)
    except (ValueError, BlockingIOError) as error:
        print(error, file=sys.stderr)
        return 2


if __name__ == '__main__':
    sys.exit(main())
