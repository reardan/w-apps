#!/usr/bin/env python3
"""Parent chrome History shares the ordered raw-input queue and live realm."""
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
import subprocess
import sys
import threading

ROOT = Path(__file__).resolve().parents[2]
WIN = Path(sys.argv[1]).resolve()
requests = []
HTML = b'''<title>Ready</title><button id="push">Push</button><input id="name"><script>
let count=0,pops=0;
const input=document.getElementById('name'), button=document.getElementById('push');
history.replaceState({n:0,unicode:'\\ud800\\u0000'},'');
const r=button.getBoundingClientRect();
button.setAttribute('data-x',JSON.stringify(r.x+5));
button.setAttribute('data-y',JSON.stringify(r.y+5));
button.onclick=function(){count++;history.pushState({n:count},'', '?n='+count);document.title='pushed';};
window.addEventListener('popstate',function(e){pops++;
 if(count!==1)throw 'realm reset';
 if(e.state.n===0 && (e.state.unicode!=='\\ud800\\u0000'))throw 'state encoding';
 document.title='pop:'+e.state.n+':'+pops;input.focus();});
input.oninput=function(){document.title='typed:'+input.value;};
</script>'''

class Handler(BaseHTTPRequestHandler):
    def log_message(self, *_): pass
    def do_GET(self):
        requests.append(self.path)
        self.send_response(200)
        self.send_header('Content-Type', 'text/html')
        self.send_header('Content-Length', str(len(HTML)))
        self.end_headers()
        self.wfile.write(HTML)

server = ThreadingHTTPServer(('127.0.0.1', 0), Handler)
thread = threading.Thread(target=server.serve_forever, daemon=True)
thread.start()
try:
    probe = ROOT / 'win/bin/isolated_history_probe'
    command = [ROOT / 'w/bin/wv2', 'x64', '--strict', '--import-root', ROOT / 'win/src',
               '--import-root', ROOT / 'w', ROOT / 'win/tests/isolated_history_probe.w', '-o', probe]
    subprocess.run(list(map(str, command)), check=True, capture_output=True, timeout=120)
    result = subprocess.run([str(probe), '--win', str(WIN), '--origin', f'http://127.0.0.1:{server.server_port}'],
                            capture_output=True, text=True, timeout=60)
    assert result.returncode == 0, (result.stdout, result.stderr, requests)
    assert requests == ['/first', '/second', '/first', '/second'], requests
    print(result.stdout.strip())
finally:
    server.shutdown()
    server.server_close()
    thread.join()
