"""Query-driven routing and Fetch through native and isolated page execution."""
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import threading


SCRIPT = r"""
const query = new URLSearchParams(location.search);
if (query.getAll('tag').length !== 2 || query.get('q') !== 'hello world') throw 'initial query';
query.delete('tag', 'old');
query.append('tag', 'new & fresh');
query.set('page', 2);
query.sort();
const expected = 'page=2&q=hello+world&tag=kept&tag=new+%26+fresh';
if (query.toString() !== expected || query.size !== 4) throw 'filter update';
history.replaceState({page: 2}, '', '?' + query.toString());
if (location.search !== '?' + expected || history.state.page !== 2) throw 'route';
const cloned = new URLSearchParams(query);
query.delete('tag');
const response = await fetch('/echo?' + cloned.toString());
const echoed = await response.text();
if (echoed !== expected) throw 'request encoding';
let trace = '';
cloned.forEach(function(value, key, params) {
  trace += key + ':' + value + ';';
  if (key === 'page') params.append('late', 'yes');
});
if (trace !== 'page:2;q:hello world;tag:kept;tag:new & fresh;late:yes;') throw 'live callback';
document.getElementById('result').textContent = 'QUERY WORKFLOW PASS';
document.title = 'QUERY WORKFLOW PASS';
"""


class Handler(BaseHTTPRequestHandler):
    def log_message(self, *_):
        pass

    def do_GET(self):
        if self.path.startswith('/echo?'):
            data, mime = self.path.partition('?')[2].encode(), 'text/plain'
        else:
            data = ('<title>PENDING</title><body><p id="result">PENDING</p>'
                    '<script type="module">' + SCRIPT + '</script></body>').encode()
            mime = 'text/html; charset=utf-8'
        self.send_response(200)
        self.send_header('Content-Type', mime)
        self.send_header('Content-Length', str(len(data)))
        self.end_headers()
        self.wfile.write(data)


def check(binary):
    server = ThreadingHTTPServer(('127.0.0.1', 0), Handler)
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    try:
        with tempfile.TemporaryDirectory(prefix='win-search-params-') as directory:
            for mode in (['--dump'], ['--isolated-dump'], ['--dump', '--isolated-interactive']):
                report = Path(directory) / 'report.json'
                command = [str(binary), *mode, '--report', str(report), '--page',
                           f'http://127.0.0.1:{server.server_port}/?tag=old&q=hello+world&tag=kept']
                result = subprocess.run(command, capture_output=True, text=True, timeout=30)
                assert result.returncode == 0, (mode, result.stdout, result.stderr)
                assert 'QUERY WORKFLOW PASS' in result.stdout, (mode, result.stdout, result.stderr)
                if '--isolated-dump' not in mode:
                    data = json.loads(report.read_text())
                    assert data['title'] == 'QUERY WORKFLOW PASS', data
                    assert data['script_failures'] == 0 and data['resource_failures'] == 0, data
    finally:
        server.shutdown()
        server.server_close()
        thread.join()
    print('URLSearchParams native/isolated routing, live callbacks and Fetch: OK')


if __name__ == '__main__':
    check(Path(sys.argv[1]).resolve())
