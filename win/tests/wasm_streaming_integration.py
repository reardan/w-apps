#!/usr/bin/env python3
"""Streaming wasm native Response identity, MIME/status, body and cache contract."""
from collections import Counter
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
import subprocess
import sys
import threading

WIN = str(Path(sys.argv[1]).resolve())
COUNTS = Counter()
WASM = bytes.fromhex('0061736d010000000105016000017f03020100070501016600000a0601040041000b')
PAGES = {
    'compile': "WebAssembly.compileStreaming(fetch('/valid')).then(m=>new WebAssembly.Instance(m).exports.f())",
    'instantiate': "WebAssembly.instantiateStreaming(fetch('/valid')).then(p=>p.instance.exports.f())",
    'case': "WebAssembly.compileStreaming(fetch('/case')).then(m=>new WebAssembly.Instance(m).exports.f())",
    'cached': "WebAssembly.compileStreaming(fetch('/cached')).then(()=>WebAssembly.compileStreaming(fetch('/cached'))).then(m=>new WebAssembly.Instance(m).exports.f())",
    'forged': "WebAssembly.compileStreaming({ok:true,status:200,arrayBuffer:()=>{throw 'must not call';}})",
    'missing': "WebAssembly.compileStreaming(fetch('/no-mime'))",
    'wrong': "WebAssembly.compileStreaming(fetch('/wrong'))",
    'parameters': "WebAssembly.compileStreaming(fetch('/parameters'))",
    'empty-parameters': "WebAssembly.compileStreaming(fetch('/empty-parameters'))",
    'duplicate': "WebAssembly.compileStreaming(fetch('/duplicate'))",
    'status': "fetch('/404').then(r=>{r.ok=true;r.status=200;return WebAssembly.compileStreaming(r);})",
    'used': "fetch('/valid').then(r=>r.arrayBuffer().then(()=>{r.bodyUsed=false;return WebAssembly.compileStreaming(r);}))",
    'redirect': "WebAssembly.compileStreaming(fetch('/redirect')).then(m=>new WebAssembly.Instance(m).exports.f())",
    'bad-redirect': "WebAssembly.compileStreaming(fetch('/bad-redirect'))",
    'body-method': "fetch('/valid').then(r=>{r.arrayBuffer=()=>{throw 'overridden';};return WebAssembly.compileStreaming(r);}).then(m=>new WebAssembly.Instance(m).exports.f())",
    'invalid': "WebAssembly.compileStreaming(fetch('/invalid'))",
    'upstream': "WebAssembly.compileStreaming(Promise.reject('upstream'))",
    'unconsumed': "fetch('/wrong').then(r=>WebAssembly.compileStreaming(r).catch(e=>{if(e.name!=='TypeError'||r.bodyUsed)throw 'consumed';return r.arrayBuffer();})).then(b=>b.byteLength===34?0:1)",
}
SUCCESS = {'compile', 'instantiate', 'case', 'cached', 'redirect', 'body-method', 'unconsumed'}

class Handler(BaseHTTPRequestHandler):
    def log_message(self, *_):
        pass

    def do_GET(self):
        COUNTS[self.path] += 1
        if self.path.startswith('/page/'):
            case = self.path.removeprefix('/page/')
            expected = "v===0" if case in SUCCESS else "false"
            error = "e.name==='CompileError'" if case == 'invalid' else "e==='upstream'" if case == 'upstream' else "e.name==='TypeError'" if case not in SUCCESS else "false"
            js = f"({PAGES[case]}).then(v=>{{document.title={expected}?'PASS':'BAD success';}},e=>{{document.title={error}?'PASS':'BAD error '+e.name+': '+e.message;}});"
            body = f'<title>PENDING</title><script>{js}</script>'.encode()
            self.send_response(200)
            self.send_header('Content-Type', 'text/html')
        else:
            body = b'bad wasm' if self.path == '/invalid' else WASM
            self.send_response(404 if self.path == '/404' else 302 if self.path in ('/redirect', '/bad-redirect') else 200)
            if self.path != '/no-mime':
                mime = {'/wrong':'text/plain', '/case':'APPLICATION/WASM\t ', '/parameters':'application/wasm; charset=utf-8', '/empty-parameters':'application/wasm;'}.get(self.path, 'application/wasm')
                self.send_header('Content-Type', mime)
            if self.path == '/duplicate':
                self.send_header('Content-Type', 'application/wasm')
            if self.path in ('/redirect', '/bad-redirect'):
                self.send_header('Location', '/valid' if self.path == '/redirect' else '/wrong')
            if self.path == '/cached':
                self.send_header('Cache-Control', 'max-age=60')
        self.send_header('Content-Length', str(len(body)))
        self.end_headers()
        self.wfile.write(body)

server = ThreadingHTTPServer(('127.0.0.1', 0), Handler)
thread = threading.Thread(target=server.serve_forever, daemon=True)
thread.start()
try:
    for case in PAGES:
        result = subprocess.run([WIN, '--isolated-dump', '--page', f'http://127.0.0.1:{server.server_port}/page/{case}'], capture_output=True, text=True, timeout=30)
        assert result.returncode == 0 and result.stdout.splitlines()[1:2] == ['PASS'], (case, result.stdout, result.stderr)
    assert COUNTS['/cached'] == 1, COUNTS
finally:
    server.shutdown()
    server.server_close()
    thread.join()
print(f'wasm streaming integration: {len(PAGES)} cases passed')
