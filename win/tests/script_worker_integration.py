#!/usr/bin/env python3
"""Real child-only page execution, external scripts and watchdog regression."""
import ctypes
import http.server
import os
import signal
import pathlib
import subprocess
import sys
import tempfile
import threading
import time

binary = str(pathlib.Path(sys.argv[1]).resolve())
# Collect killed descendants ourselves rather than depending on container PID 1.
assert ctypes.CDLL(None, use_errno=True).prctl(36, 1, 0, 0, 0) == 0



class Handler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path == '/slow':
            time.sleep(2)
        content = {
            '/page': b"<title>initial</title><p id='target'>initial</p><script>document.getElementById('target').textContent='inline';</script><script src='/script.js'></script>",
            '/script.js': b"document.getElementById('target').textContent+=' external'; document.title='worker finished';",
            '/error': b"<p>survives</p><script>throw 'expected';</script>",
            '/missing': b"<p>survives</p><script src='/404.js'></script>",
            '/slow': b'<p>too late</p>',
        }.get(self.path)
        self.send_response(200 if content is not None else 404)
        self.send_header('Content-Type', 'application/javascript' if self.path.endswith('.js') else 'text/html')
        self.end_headers()
        try:
            self.wfile.write(content or b'missing')
        except (BrokenPipeError, ConnectionResetError):
            pass

    def log_message(self, *_):
        pass


server = http.server.ThreadingHTTPServer(('127.0.0.1', 0), Handler)
thread = threading.Thread(target=server.serve_forever, daemon=True)
thread.start()
base = f'http://127.0.0.1:{server.server_port}'


def run(path, *flags):
    return subprocess.run([binary, '--page', base + path, *flags], capture_output=True, text=True, timeout=8)


def children(pid):
    try:
        return [int(x) for x in pathlib.Path(f'/proc/{pid}/task/{pid}/children').read_text().split()]
    except FileNotFoundError:
        return []


def reap_killed(pid):
    deadline = time.monotonic() + 3
    while time.monotonic() < deadline:
        got, status = os.waitpid(pid, os.WNOHANG)
        if got:
            assert os.WIFSIGNALED(status) and os.WTERMSIG(status) == signal.SIGKILL, status
            return
        time.sleep(.005)
    raise AssertionError(f'descendant {pid} survived parent death')


def descendant_case(kill_parent):
    process = subprocess.Popen([binary, '--isolated-dump', '--page', base + '/slow',
                                '--worker-timeout', '1200'], stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    deadline = time.monotonic() + 1
    worker = loader = None
    while time.monotonic() < deadline:
        direct = children(process.pid)
        if direct:
            worker = direct[0]
            nested = children(worker)
            if nested:
                loader = nested[0]
                # Give exec'd loader time to install its parent-death guard.
                time.sleep(.03)
                break
        time.sleep(.005)
    assert worker and loader, (worker, loader)
    if kill_parent:
        process.kill()
    output, error = process.communicate(timeout=3)
    assert not output, output
    if kill_parent:
        assert process.returncode == -signal.SIGKILL
        reap_killed(worker)
    else:
        assert process.returncode == 1 and 'timed out' in error, error
    reap_killed(loader)


try:
    normal = run('/page', '--dump')
    isolated = run('/page', '--isolated-dump')
    assert normal.returncode == isolated.returncode == 0, (normal.stderr, isolated.stderr)
    assert isolated.stdout == normal.stdout, (isolated.stdout, normal.stdout)
    assert 'worker finished' in isolated.stdout and 'inline external' in isolated.stdout, isolated.stdout
    for path in ('/error', '/missing'):
        result = run(path, '--isolated-dump')
        assert result.returncode == 1 and 'survives' in result.stdout, result
        assert 'script or resource errors' in result.stderr, result.stderr
    began = time.monotonic()
    result = run('/slow', '--isolated-dump', '--worker-timeout', '100')
    assert result.returncode == 1 and not result.stdout and 'timed out' in result.stderr, result
    assert time.monotonic() - began < 1.5
    result = run('/page', '--isolated-dump', '--worker-timeout', '0')
    assert result.returncode == 1 and not result.stdout and 'Invalid' in result.stderr, result
    with tempfile.TemporaryDirectory() as directory:
        local = pathlib.Path(directory) / 'local.html'
        local.write_text("<p id='p'>before</p><script>document.getElementById('p').textContent='local worker';</script>")
        result = subprocess.run([binary, '--isolated-dump', '--page', str(local)], capture_output=True, text=True, timeout=8)
        assert result.returncode == 0 and 'local worker' in result.stdout, result
    descendant_case(False)
    descendant_case(True)
    print('script worker integration: passed')
finally:
    server.shutdown()
    server.server_close()
