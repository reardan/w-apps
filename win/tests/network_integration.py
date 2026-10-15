"""Cookie/HTTP-cache worker IPC tests; loopback servers only."""
from collections import Counter
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
import subprocess
import sys
import tempfile
import threading

root = Path(__file__).resolve().parents[2]
counts = Counter()
foreign_requests = []


class Foreign(BaseHTTPRequestHandler):
    def log_message(self, *_):
        pass

    def do_GET(self):
        foreign_requests.append((self.path, self.headers.get("Cookie")))
        payload = (self.headers.get("Cookie") or "empty").encode()
        self.send_response(200)
        self.send_header("Content-Type", "text/html")
        self.send_header("Content-Length", str(len(payload)))
        self.end_headers()
        self.wfile.write(payload)


foreign = ThreadingHTTPServer(("127.0.0.1", 0), Foreign)


class Handler(BaseHTTPRequestHandler):
    def log_message(self, *_):
        pass

    def do_GET(self):
        counts[self.path] += 1
        payload = b"ok"
        status = 200
        headers = []
        if self.path == "/set":
            headers = [("Set-Cookie", "sid=one; Path=/scope; Max-Age=60"),
                       ("Set-Cookie", "second=two; Path=/scope"),
                       ("Set-Cookie", "nope=bad; Domain=localhost; Path=/")]
        elif self.path.endswith("/echo"):
            payload = self.headers.get("Cookie", "").encode()
        elif self.path == "/redirect":
            status = 302
            headers = [("Set-Cookie", "hop=ok; Path=/next"),
                       ("Location", "/next/echo")]
        elif self.path in ("/foreign-cookie", "/foreign-fetch"):
            status = 302
            headers = [("Set-Cookie", "secret=private; Path=/"),
                       ("Location", f"http://localhost:{foreign.server_port}/foreign")]
        elif self.path == "/missing":
            status, payload = 404, b"missing"
        elif self.path == "/cache":
            payload = b"cached"
            headers = [("Cache-Control", "public, max-age=60")]
        elif self.path == "/no-store":
            headers = [("Cache-Control", "max-age=60, no-store")]
        elif self.path == "/cache-redirect":
            status = 302
            headers = [("Location", "/cache"), ("Cache-Control", "max-age=60")]
        self.send_response(status)
        self.send_header("Content-Type", "text/html")
        for key, value in headers:
            self.send_header(key, value)
        self.send_header("Content-Length", str(len(payload)))
        self.end_headers()
        self.wfile.write(payload)


server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
threads = [threading.Thread(target=s.serve_forever, daemon=True) for s in (server, foreign)]
for thread in threads:
    thread.start()
try:
    with tempfile.TemporaryDirectory(prefix="win-network-test-") as temporary:
        probe = Path(temporary) / "network_test"
        subprocess.run([str(root / "w/bin/wv2"), "x64", "--strict",
                        "--import-root", str(root / "win/src"),
                        "--import-root", str(root / "w"),
                        str(root / "win/tests/network_test.w"), "-o", str(probe)],
                       check=True, timeout=60, capture_output=True)
        result = subprocess.run([str(probe), "--network", f"http://127.0.0.1:{server.server_port}"],
                                capture_output=True, text=True, timeout=45)
        assert result.returncode == 0, result.stdout + result.stderr
        assert counts["/cache"] == 3, counts  # one direct + two uncached redirects
        assert counts["/no-store"] == 2, counts
        assert counts["/cache-redirect"] == 2, counts
        assert foreign_requests == [("/foreign", None)], foreign_requests
        print("network integration tests passed (cookies, redirects, fetch status, cache IPC)")
finally:
    for instance in (server, foreign):
        instance.shutdown()
        instance.server_close()
    for thread in threads:
        thread.join(timeout=2)
