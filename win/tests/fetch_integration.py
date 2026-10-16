#!/usr/bin/env python3
"""Hermetic same-origin Fetch/Promise integration through the actual browser."""
import http.server
import json
import os
import struct
import pathlib
import subprocess
import sys
import threading

WIN = str(pathlib.Path(sys.argv[1]).resolve())
REQUESTS = []
UPLOADS = []
PAGES = {
    '/post-string': "fetch('/echo',{method:'post',body:'a\\u0000😀\\ud800'}).then(function(r){return r.json();}).then(function(v){if(v.method!=='POST'||v.type!=='text/plain;charset=UTF-8'||v.accept!=='*/*'||v.bytes.length!==9||v.bytes[1]!==0||v.bytes[2]!==240||v.bytes[6]!==239) throw 'string upload';document.title='post-string-complete';});",
    '/post-json': "fetch('/echo',{method:'POST',body:'{\"value\":1}',headers:{'Content-Type':'application/json','Accept':'application/json'}}).then(function(r){return r.json();}).then(function(v){if(v.type!=='application/json'||v.accept!=='application/json'||v.bytes.length!==11) throw 'JSON headers';document.title='post-json-complete';});",
    '/post-binary': "const bytes=new Uint8Array(65538);bytes[1]=255;bytes[65536]=97;const view=new Uint8Array(bytes.buffer,1,65536);const sent=fetch('/echo',{method:'POST',body:view});view[0]=0;sent.then(function(r){return r.json();}).then(function(v){if(v.length!==65536||v.first!==255||v.last!==97||v.type!=='') throw 'binary upload snapshot';document.title='post-binary-complete';});",
    '/post-rewrite': "fetch('/redirect-post-302',{method:'POST',body:'discard'}).then(function(r){return r.json();}).then(function(v){if(v.method!=='GET'||v.type!==''||v.length!==0) throw 'redirect rewrite';document.title='post-rewrite-complete';});",
    '/post-replay': "const b=new Uint8Array(3);b[1]=255;fetch('/redirect-post-307',{method:'POST',body:b,headers:{'Content-Type':'application/octet-stream'}}).then(function(r){return r.json();}).then(function(v){if(v.method!=='POST'||v.type!=='application/octet-stream'||v.bytes[0]!==0||v.bytes[1]!==255||v.bytes[2]!==0) throw 'redirect replay';document.title='post-replay-complete';});",
    '/put': "fetch('/echo',{method:'put',body:'put'}).then(function(r){return r.json();}).then(function(v){if(v.method!=='PUT'||v.length!==3) throw 'PUT';document.title='put-complete';});",
    '/head': "fetch('/redirect-head-303',{method:'head'}).then(function(r){return r.text();}).then(function(v){if(v!=='') throw 'HEAD body';document.title='head-complete';});",
    '/post-foreign': "fetch('/redirect-post-foreign',{method:'POST',body:'secret'}).catch(function(){document.title='post-foreign-blocked';});",
    '/post-abort': "const c=new AbortController();const b=new Uint8Array(65536);const reason={abort:true};fetch('/cancel-upload',{method:'POST',body:b,signal:c.signal}).catch(function(e){if(e!==reason) throw 'reason';document.title='post-abort-complete';});c.abort(reason);",
    '/request-invalid': "let count=0;function rejected(){count++;if(count===6)document.title='request-invalid-complete';}fetch('/forbidden',{method:'TRACE'}).catch(rejected);fetch('/forbidden',{body:''}).catch(rejected);fetch('/forbidden',{method:'POST',body:new Uint8Array(65537)}).catch(rejected);fetch('/forbidden',{headers:{'Host':'evil'}}).catch(rejected);fetch('/forbidden',{headers:{'Accept':'x\\r\\nInjected: yes'}}).catch(rejected);fetch('/forbidden',{method:'POST',body:{}}).catch(rejected);",

    '/large-binary': "fetch('/exact-limit-data').then(function(r){return r.arrayBuffer();}).then(function(b){if(b.byteLength!==4194304) throw 'size';document.title='fetch-limit-complete';});",
    '/over-binary': "fetch('/over-limit-data').catch(function(){document.title='fetch-limit-rejected';});",
    '/binary': "fetch('/invalid-data').then(function(r){return r.arrayBuffer();}).then(function(b){const v=new Uint8Array(b);if(v.length!==1 || v[0]!==255) throw 'binary';document.title='binary-complete';});",
    '/success': "fetch('/data').then(function(r){if(r.status===200 && r.ok && !r.bodyUsed){return r.text();}throw 'bad response';}).then(function(t){document.title=t;});",
    '/status': "fetch('/missing').then(function(r){if(r.status===404 && !r.ok){return r.text();}throw 'bad status';}).then(function(t){document.title=t;});",
    '/twice': "fetch('/data').then(function(r){r.text();return r.text();}).catch(function(e){document.title='body-consumed';});",
    '/redirect': "fetch('/redirect-data').then(function(r){return r.text();}).then(function(t){document.title=t;});",
    '/cross': "fetch('http://localhost:PORT/forbidden').catch(function(e){document.title='cross-blocked';});",
    '/redirect-cross': "fetch('/redirect-foreign').catch(function(e){document.title='redirect-blocked';});",
    '/invalid': "fetch('/invalid-data').then(function(r){return r.text();}).catch(function(e){document.title='utf8-rejected';});",
    '/large': "fetch('/large-data').then(function(r){return r.text();}).catch(function(e){document.title='size-rejected';});",
    '/options': "fetch('/forbidden',{mode:'cors'}).catch(function(e){document.title='options-rejected';});",
    '/microtask': "let order='';queueMicrotask(function(){order=order+'q';});Promise.resolve('p').then(function(v){order=order+v;document.title=order;});order=order+'s';",
}

class Handler(http.server.BaseHTTPRequestHandler):
    def log_message(self, *_):
        pass

    def do_HEAD(self):
        if self.path == '/redirect-head-303':
            self.send_response(303)
            self.send_header('Location', '/echo')
            self.send_header('Content-Length', '0')
            self.end_headers()
        else:
            UPLOADS.append(('HEAD', self.path, b'', dict(self.headers)))
            self.send_response(200)
            self.send_header('Content-Length', '9')
            self.end_headers()

    def echo(self):
        body = self.rfile.read(int(self.headers.get('Content-Length', '0')))
        UPLOADS.append((self.command, self.path, body, dict(self.headers)))
        if self.path.startswith('/redirect-post-'):
            foreign = self.path.endswith('foreign')
            status = 302 if self.path.endswith('302') else 307
            self.send_response(status)
            self.send_header('Location', f'http://localhost:{self.server.server_port}/forbidden' if foreign else '/echo')
            self.send_header('Content-Length', '0')
            self.end_headers()
            return
        data = json.dumps({'method': self.command, 'type': self.headers.get('Content-Type', ''),
                           'accept': self.headers.get('Accept', ''), 'length': len(body),
                           'first': body[0] if body else -1, 'last': body[-1] if body else -1,
                           'bytes': list(body) if len(body) < 32 else []}).encode()
        self.send_response(200)
        self.send_header('Content-Type', 'application/json')
        self.send_header('Cache-Control', 'max-age=60')
        self.send_header('Content-Length', str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    do_POST = echo
    do_PUT = echo
    do_PATCH = echo
    do_DELETE = echo
    do_OPTIONS = echo

    def do_GET(self):
        REQUESTS.append(self.path)
        if self.path == '/echo':
            self.echo()
            return
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
        elif self.path == '/exact-limit-data':
            body = b'x' * 4194304
        elif self.path == '/over-limit-data':
            body = b'x' * 4194305
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
    cases = [('/post-string', 'post-string-complete'), ('/post-json', 'post-json-complete'),
             ('/post-binary', 'post-binary-complete'), ('/post-rewrite', 'post-rewrite-complete'),
             ('/post-replay', 'post-replay-complete'), ('/put', 'put-complete'), ('/head', 'head-complete'),
             ('/post-foreign', 'post-foreign-blocked'), ('/post-abort', 'post-abort-complete'),
             ('/request-invalid', 'request-invalid-complete'), ('/large-binary', 'fetch-limit-complete'), ('/over-binary', 'fetch-limit-rejected'),
             ('/binary', 'binary-complete'), ('/success', 'fetch-complete'), ('/status', 'http-error-body'),
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
    assert not any(path in ('/forbidden', '/cancel-upload') for _, path, _, _ in UPLOADS), UPLOADS
    assert any(method == 'HEAD' and path == '/echo' for method, path, _, _ in UPLOADS), UPLOADS
    # Reject malformed version, negative/overflow lengths, truncated payload,
    # trailing data, and forbidden methods before making any HTTP request.
    url = f'http://127.0.0.1:{server.server_port}/forbidden'
    env = dict(os.environ, WIN_FETCH_ORIGIN=url)
    frame = lambda method, body=b'': b'WFET0001' + struct.pack('<iiii', len(method), 0, 3, len(body)) + method + b'*/*' + body
    malformed = [b'', b'BAD00001'+bytes(16), b'WFET0001'+struct.pack('<iiii', 3, 0, 0, -1),
                 b'WFET0001'+struct.pack('<iiii', 3, 0, 0, 2147483647), frame(b'GET')[:-1],
                 frame(b'GET')+b'x', frame(b'TRACE'), frame(b'POST', b'x')[:-1]]
    for data in malformed:
        result = subprocess.run([WIN, '--resource', url, '--kind', 'fetch'], input=data,
                                capture_output=True, env=env, timeout=8)
        assert result.returncode == 1 and result.stdout.startswith(b'ERROR\n'), (data, result)
    stalled = subprocess.Popen([WIN, '--resource', url, '--kind', 'fetch'], stdin=subprocess.PIPE,
                               stdout=subprocess.PIPE, stderr=subprocess.PIPE, env=env)
    try:
        assert stalled.wait(timeout=8) == 1
        assert stalled.stdout.read().startswith(b'ERROR\n')
    finally:
        stalled.stdin.close()
        stalled.stdout.close()
        stalled.stderr.close()
        if stalled.poll() is None:
            stalled.kill()
            stalled.wait()
    assert '/forbidden' not in REQUESTS, REQUESTS
finally:
    server.shutdown()
    server.server_close()
    thread.join()
print('fetch integration passed (23 page cases 8 malformed request frames, and stalled-input timeout)')
