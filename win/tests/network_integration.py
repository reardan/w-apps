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
        elif self.path.startswith("/cookie-large/"):
            payload = b"x" * 1048576
            headers = [("Set-Cookie", f"large{i}={'v' * 1800}; Path=/large") for i in range(32)]
        elif self.path == "/date-fields":
            headers = [("Set-Cookie", "test=2; Path=/dates; Expires=Fri 01 Jan 2038 00:00:00 GMT, baz=qux"),
                       ("Set-Cookie", "other=3; Path=/dates; HttpOnly"),
                       ("Set-Cookie", "expired=gone; Path=/dates; Expires=Thu Apr 10 1980 16:33:12 GMT")]
        elif self.path == "/nameless-fields":
            headers = [("Set-Cookie", "named=value; Path=/nameless"),
                       ("Set-Cookie", "=named=other; Path=/nameless; HttpOnly")]
        elif self.path == "/cookie-cap":
            headers = [("Set-Cookie", f"cap{i}=yes; Path=/cap") for i in range(33)]
        elif self.path == "/cookie-cap-redirect":
            status = 302
            headers = [("Set-Cookie", f"hop{i}=yes; Path=/cap") for i in range(31)]
            headers.append(("Location", "/cookie-cap-final"))
        elif self.path == "/cookie-cap-final":
            headers = [("Set-Cookie", "last=yes; Path=/cap"),
                       ("Set-Cookie", "over=bad; Path=/cap")]
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
        # Treat the loader child protocol as untrusted: independently bound
        # metadata, final envelope, and decoded body even if a child lies.
        cookie = b"COOKIE\nhttp://example.test/\nprobe=must-not-persist\n"
        ok = b"OK\nhttp://example.test/\n"
        cap = 32 * (4096 + 2048 + 9) + 1024
        cases = {
            "body-over": cookie + ok + b"x" * 1048577,
            "body-cookie-prefix": cookie + ok + b"COOKIE\n" + b"x" * 1048576,
            "cookie-count-over": cookie * 33 + ok,
            "cookie-field-over": b"COOKIE\nhttp://example.test/\n" + b"x" * 2049 + b"\n" + ok,
            "cookie-url-over": b"COOKIE\nhttp://example.test/" + b"x" * 4096 + b"\np=1\n" + ok,
            "metadata-over": (b"STATUS\n200\n" * 100) + ok,
            "metadata-over-error": cookie * 33 + b"ERROR\nfailed",
            "status-malformed": cookie + b"STATUS\nwrong\n" + ok,
            "mime-malformed": cookie + b"WASM-MIME\nwrong\n" + ok,
            "cache-malformed": cookie + b"CACHE\nwrong\n" + ok,
            "total-over": b"x" * (1048576 + 4096 + 4 + cap + 1),
            "cookie-incomplete": cookie + b"COOKIE\nhttp://example.test/\nincomplete",
            "envelope-incomplete": cookie + b"OK\nhttp://example.test/",
        }
        long_url = b"http://example.test/" + b"x" * (4096 - len(b"http://example.test/"))
        full_field = b"p=" + b"v" * 2046
        cases["maximum-valid"] = (b"COOKIE\n" + long_url + b"\n" + full_field + b"\n") * 32 + ok + b"x" * 1048576
        for name, payload in cases.items():
            worker = Path(temporary) / (name + ".py")
            data_file = Path(temporary) / (name + ".bin")
            data_file.write_bytes(payload)
            worker.write_text("#!/usr/bin/python3\nfrom pathlib import Path\nimport sys\nsys.stdout.buffer.write(Path(" + repr(str(data_file)) + ").read_bytes())\nsys.exit(" + ("1" if name.endswith("-error") else "0") + ")\n")
            worker.chmod(0o700)
            expected = "accept" if name == "maximum-valid" else "reject"
            checked = subprocess.run([str(probe), "--protocol", str(worker), "--expect", expected],
                                     capture_output=True, text=True, timeout=15)
            assert checked.returncode == 0, (name, checked.stdout, checked.stderr)
        print("network integration tests passed (cookies, redirects, cache IPC, metadata/body bounds)")
finally:
    for instance in (server, foreign):
        instance.shutdown()
        instance.server_close()
    for thread in threads:
        thread.join(timeout=2)
