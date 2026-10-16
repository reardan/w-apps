#!/usr/bin/env python3
"""Exercise module graph loading in the actual browser, including cache identity."""
import http.server
import pathlib
import subprocess
import sys
import threading

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
finally:
    server.shutdown()
    server.server_close()
    thread.join()
print('browser module graph integration passed')
