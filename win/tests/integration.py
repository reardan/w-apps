"""Real subprocess/loopback integration; no public internet or third-party packages."""
import gzip
from urllib.parse import urlparse, parse_qs
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
import subprocess
import sys
import tempfile
import threading

binary, home = map(lambda value: str(Path(value).resolve()), sys.argv[1:])
body = b"<title>Network fixture</title><h1>Network loaded</h1><p>hello</p>"
form_requests = []
form_body = b"""<title>Form fixture</title>
<form action='/submitted?discard=yes#tail'><input name='q' value='a b&amp;c'><button id='get' name='action' value='get'>GET</button></form>
<form method='post' action='/submitted'><input name='q' value='post data'><button id='post' name='action' value='post'>POST</button></form>
<form id='prevent'><button id='cancel'>Cancel</button></form><p id='result'>initial</p>
<script>document.getElementById('prevent').addEventListener('submit', function(e) { e.preventDefault(); document.getElementById('result').textContent = 'prevented'; });</script>"""
slow_started = threading.Event()
slow_release = threading.Event()


class Handler(BaseHTTPRequestHandler):
    def log_message(self, *_):
        pass

    def respond(self, payload):
        self.send_response(200)
        self.send_header("Content-Type", "text/html")
        self.send_header("Content-Length", str(len(payload)))
        self.end_headers()
        self.wfile.write(payload)

    def do_POST(self):
        payload = self.rfile.read(int(self.headers.get("Content-Length", "0")))
        form_requests.append(("POST", self.path, self.headers.get("Content-Type"), parse_qs(payload.decode())))
        self.respond(b"<title>Submitted POST</title><p>posted</p>")

    def do_GET(self):
        if self.path == "/forms":
            self.respond(form_body)
            return
        if urlparse(self.path).path == "/submitted":
            form_requests.append(("GET", self.path, None, parse_qs(urlparse(self.path).query)))
            self.respond(b"<title>Submitted GET</title><p>submitted</p>")
            return
        if self.path == "/slow":
            slow_started.set()
            slow_release.wait(8)
            return
        if self.path == "/redirect":
            self.send_response(302)
            self.send_header("Location", "/gzip#part")
            self.send_header("Content-Length", "0")
            self.end_headers()
            return
        if self.path == "/missing":
            self.send_response(404)
            self.send_header("Content-Length", "0")
            self.end_headers()
            return
        payload = body
        encoding = None
        if self.path == "/gzip":
            payload = gzip.compress(body[:30]) + gzip.compress(body[30:])
            encoding = "gzip"
        if self.path == "/bad-gzip":
            payload = gzip.compress(body) + b"unvalidated trailing data"
            encoding = "gzip"
        if self.path == "/oversized":
            payload = gzip.compress(b"x" * (1048576 + 1))
            encoding = "gzip"
        self.send_response(200)
        self.send_header("Content-Type", "image/png" if self.path == "/image" else "text/html; charset=utf-8")
        if encoding:
            self.send_header("Content-Encoding", encoding)
        self.send_header("Content-Length", str(len(payload)))
        self.end_headers()
        self.wfile.write(payload)


def run(page, success=True):
    result = subprocess.run([binary, "--dump", "--page", page], capture_output=True, text=True, timeout=16)
    assert (result.returncode == 0) == success, (page, result.returncode, result.stdout, result.stderr)
    return result


server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
thread = threading.Thread(target=server.serve_forever, daemon=True)
thread.start()
base = f"http://127.0.0.1:{server.server_port}"
try:
    assert "Welcome to Win" in run(home).stdout
    article = run(str(Path(home).with_name("article.html"))).stdout
    assert "café" in article
    assert "HIDDEN_FIXTURE_TEXT" not in article
    assert "SHOULD_NOT_RENDER_OR_EXECUTE" not in article
    for path in ("/", "/gzip", "/redirect"):
        response = run(base + path)
        assert "Network fixture" in response.stdout and "Network loaded" in response.stdout
    assert base + "/gzip#part" in run(base + "/redirect").stdout
    for path in ("/missing", "/bad-gzip", "/oversized", "/image"):
        run(base + path, success=False)
    subprocess.run([str(Path(binary).with_name("browser_test")), "--slow", binary, base + "/slow"], check=True, timeout=5)
    assert slow_started.is_set(), "cancellation test must reach the server"
    slow_release.set()
    run("javascript:alert(1)", success=False)
    subprocess.run([str(Path(binary).with_name("browser_test")), "--forms", binary, base + "/forms"], check=True, timeout=16)
    assert len(form_requests) == 2, form_requests
    assert form_requests[0][0] == "GET" and form_requests[0][3] == {"q": ["a b&c"], "action": ["get"]}, form_requests
    assert form_requests[1][0] == "POST" and form_requests[1][2] == "application/x-www-form-urlencoded", form_requests
    assert form_requests[1][3] == {"q": ["post data"], "action": ["post"]}, form_requests
    with tempfile.TemporaryDirectory(prefix="win-fixtures-") as directory:
        path = Path(directory) / "a document.html"
        path.write_bytes(body)
        assert "Network fixture" in run(str(path)).stdout
        path.write_bytes(b"<p>\xff</p>")
        run(str(path), success=False)
        path.write_bytes(b"x" * (1048576 + 1))
        run(str(path), success=False)
finally:
    slow_release.set()
    server.shutdown()
    server.server_close()
    thread.join()
print("Win local/HTTP/gzip/redirect/error integration: OK")
