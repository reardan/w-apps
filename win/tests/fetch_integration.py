#!/usr/bin/env python3
"""Hermetic same-origin Fetch/Promise integration through the actual browser."""
import http.server
import pathlib
import subprocess
import sys
import threading

WIN = str(pathlib.Path(sys.argv[1]).resolve())
REQUESTS = []
PAGES = {
    '/binary': "fetch('/invalid-data').then(function(r){return r.arrayBuffer();}).then(function(b){const v=new Uint8Array(b);if(v.length!==1 || v[0]!==255) throw 'binary';document.title='binary-complete';});",
    '/success': "fetch('/data').then(function(r){if(r.status===200 && r.ok && !r.bodyUsed){return r.text();}throw 'bad response';}).then(function(t){document.title=t;});",
    '/status': "fetch('/missing').then(function(r){if(r.status===404 && !r.ok){return r.text();}throw 'bad status';}).then(function(t){document.title=t;});",
    '/twice': "fetch('/data').then(function(r){r.text();return r.text();}).catch(function(e){document.title='body-consumed';});",
    '/redirect': "fetch('/redirect-data').then(function(r){return r.text();}).then(function(t){document.title=t;});",
    '/cross': "fetch('http://localhost:PORT/forbidden').catch(function(e){document.title='cross-blocked';});",
    '/redirect-cross': "fetch('/redirect-foreign').catch(function(e){document.title='redirect-blocked';});",
    '/invalid': "fetch('/invalid-data').then(function(r){return r.text();}).catch(function(e){document.title='utf8-rejected';});",
    '/large': "fetch('/large-data').then(function(r){return r.text();}).catch(function(e){document.title='size-rejected';});",
    '/options': "fetch('/forbidden',{method:'POST'}).catch(function(e){document.title='options-rejected';});",
    '/microtask': "let order='';queueMicrotask(function(){order=order+'q';});Promise.resolve('p').then(function(v){order=order+v;document.title=order;});order=order+'s';",
}

class Handler(http.server.BaseHTTPRequestHandler):
    def log_message(self, *_):
        pass

    def do_GET(self):
        REQUESTS.append(self.path)
        status, mime = 200, 'text/plain'
        if self.path in PAGES:
            script = PAGES[self.path].replace('PORT', str(self.server.server_port))
            body = ('<title>pending</title><p>fetch-test</p><script>' + script + '</script>').encode()
            mime = 'text/html'
        elif self.path in ('/redirect-data', '/redirect-foreign'):
            self.send_response(302)
            target = '/data' if self.path == '/redirect-data' else f'http://localhost:{self.server.server_port}/forbidden'
            self.send_header('Location', target)
            self.send_header('Content-Length', '0')
            self.end_headers()
            return
        elif self.path == '/data':
            body = b'fetch-complete'
        elif self.path == '/missing':
            status, body = 404, b'http-error-body'
        elif self.path == '/invalid-data':
            body = b'\xff'
        elif self.path == '/large-data':
            body = b'x' * 65537
        else:
            body = b'forbidden'
        self.send_response(status)
        self.send_header('Content-Type', mime)
        self.send_header('Content-Length', str(len(body)))
        self.end_headers()
        self.wfile.write(body)

server = http.server.ThreadingHTTPServer(('127.0.0.1', 0), Handler)
thread = threading.Thread(target=server.serve_forever, daemon=True)
thread.start()
try:
    cases = [('/binary', 'binary-complete'), ('/success', 'fetch-complete'), ('/status', 'http-error-body'),
             ('/twice', 'body-consumed'), ('/redirect', 'fetch-complete'),
             ('/cross', 'cross-blocked'), ('/redirect-cross', 'redirect-blocked'),
             ('/invalid', 'utf8-rejected'), ('/large', 'size-rejected'),
             ('/options', 'options-rejected'), ('/microtask', 'sqp')]
    for path, expected in cases:
        result = subprocess.run([WIN, '--dump', '--page', f'http://127.0.0.1:{server.server_port}{path}'],
                                text=True, capture_output=True, timeout=20)
        assert result.returncode == 0, (path, result.stdout, result.stderr)
        assert result.stdout.splitlines()[1] == expected, (path, result.stdout, result.stderr)
    assert '/forbidden' not in REQUESTS, REQUESTS
finally:
    server.shutdown()
    server.server_close()
    thread.join()
print('fetch integration passed (11 cases)')
