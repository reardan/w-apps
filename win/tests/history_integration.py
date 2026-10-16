#!/usr/bin/env python3
"""History routing stays in one realm and resolves Fetch from the changed URL."""
from collections import Counter
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
import subprocess
import sys
import threading

WIN = str(Path(sys.argv[1]).resolve())
counts = Counter()

class Handler(BaseHTTPRequestHandler):
    def log_message(self, *_):
        pass

    def do_GET(self):
        counts[self.path] += 1
        if self.path == '/folder/data':
            data = b'payload'
        else:
            data = b'''<title>PENDING</title><script>
let count=0;
history.replaceState({view:'form'},'');
history.pushState({view:'settings'},'', '/folder/view?view=settings');
window.addEventListener('popstate',event=>{
  count++;
  if(count===1){
    if(location.search!==''||event.state.view!=='form')throw 'back';
    history.forward();
  }else{
    if(count!==2||event.state.view!=='settings'||location.search!=='?view=settings')throw 'forward';
    document.title='PASS';
  }
});
fetch('data').then(response=>response.text()).then(text=>{
  if(text!=='payload')throw 'relative fetch';
  history.back();
});
</script>'''
        self.send_response(200)
        self.send_header('Content-Type', 'text/html')
        self.send_header('Content-Length', str(len(data)))
        self.end_headers()
        self.wfile.write(data)

server = ThreadingHTTPServer(('127.0.0.1', 0), Handler)
thread = threading.Thread(target=server.serve_forever, daemon=True)
thread.start()
try:
    for mode in ('--dump', '--isolated-dump'):
        result = subprocess.run([WIN, mode, '--page', f'http://127.0.0.1:{server.server_port}/start'],
                                capture_output=True, text=True, timeout=30)
        assert result.returncode == 0 and result.stdout.splitlines()[1:2] == ['PASS'], (mode, result)
    assert counts == {'/start': 2, '/folder/data': 2}, counts
finally:
    server.shutdown()
    server.server_close()
    thread.join()
print('history integration: native/isolated routing, queued popstate and relative Fetch passed')
