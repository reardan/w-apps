#!/usr/bin/env python3
"""Exercise module graph loading in the actual browser, including cache identity."""
import http.server
import pathlib
import subprocess
import sys
import threading
import tempfile
import json

WIN = str(pathlib.Path(sys.argv[1]).resolve())
requests = []
fixtures = {
    '/index.html': ('text/html', """<title>pending</title><p>modules</p>
<script type="module">
import {label} from './dep.js';
document.title=label;
</script>
<script type="module" src="second.js"></script>"""),
    '/dep.js': ('text/javascript', "document.body.setAttribute('data-count','once'); export const label='module-loaded';"),
    '/second.js': ('text/javascript', "import {label} from './dep.js'; if(document.title!==label) throw 'order'; document.title=label+'-twice';"),
    '/async.html': ('text/html', """<title>waiting</title>
<script type="module">
import {label} from './async-dep.js';
document.title = label;
document.addEventListener('DOMContentLoaded', () => { document.title += '-ready'; });
</script><script type="module">document.title += '-second';</script>"""),
    '/async-dep.js': ('text/javascript', "await new Promise(resolve=>setTimeout(resolve,20)); const response=await fetch('./answer.txt'); export const label=await response.text();"),
    '/answer.txt': ('text/plain', 'awaited'),
    '/rejected.html': ('text/html', """<title>waiting</title>
<script type="module">import {label} from './rejected-dep.js'; document.title='should-not-run';</script>
<script type="module">document.title='continued';</script>"""),
    '/rejected-dep.js': ('text/javascript', "await Promise.reject(new Error('dependency rejected')); export const label='unreachable';"),
}

class Handler(http.server.BaseHTTPRequestHandler):
    def log_message(self, *_):
        pass

    def do_GET(self):
        requests.append(self.path)
        mime, source = fixtures.get(self.path, ('text/plain', 'missing'))
        body = source.encode()
        self.send_response(200 if self.path in fixtures else 404)
        self.send_header('Content-Type', mime)
        self.send_header('Content-Length', str(len(body)))
        self.end_headers()
        self.wfile.write(body)

server = http.server.ThreadingHTTPServer(('127.0.0.1', 0), Handler)
thread = threading.Thread(target=server.serve_forever, daemon=True)
thread.start()
try:
    result = subprocess.run([WIN, '--dump', '--page', f'http://127.0.0.1:{server.server_port}/index.html'],
                            text=True, capture_output=True, timeout=20)
    assert result.returncode == 0, (result.stdout, result.stderr)
    assert result.stdout.splitlines()[1] == 'module-loaded-twice', (result.stdout, result.stderr)
    assert requests.count('/dep.js') == 1, requests
    assert requests.count('/second.js') == 1, requests
    with tempfile.TemporaryDirectory() as directory:
        for path, title, failures in [('/async.html', 'awaited-second-ready', 0),
                                      ('/rejected.html', 'continued', 1)]:
            report = pathlib.Path(directory) / 'report.json'
            result = subprocess.run([WIN, '--dump', '--report', str(report), '--page',
                                     f'http://127.0.0.1:{server.server_port}{path}'],
                                    text=True, capture_output=True, timeout=20)
            assert result.returncode == 0, (result.stdout, result.stderr)
            data = json.loads(report.read_text())
            assert data['title'] == title, (path, data)
            assert data['script_failures'] == failures, (path, data)
            assert data['resource_failures'] == 0, (path, data)
        assert requests.count('/async-dep.js') == 1, requests
        assert requests.count('/answer.txt') == 1, requests
finally:
    server.shutdown()
    server.server_close()
    thread.join()
print('browser module graph integration passed')
