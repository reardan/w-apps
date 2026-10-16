#!/usr/bin/env python3
"""Loopback M3 app/API server. Names 'error'/'slow' select failure/abort paths."""
import argparse
import functools
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
import json
from pathlib import Path
import time

ROOT = Path(__file__).resolve().parents[2]

class WorkflowHandler(SimpleHTTPRequestHandler):
    def do_POST(self):
        if self.path != '/api/profile':
            self.send_error(404)
            return
        try:
            length = int(self.headers.get('Content-Length', '0'))
            if not 0 < length <= 4096:
                raise ValueError('body size')
            profile = json.loads(self.rfile.read(length))
            name = profile['name']
            if not isinstance(name, str) or len(name) > 256:
                raise ValueError('name')
        except (ValueError, KeyError, TypeError):
            self.send_error(400)
            return
        if name == 'slow':
            time.sleep(2)
        body = json.dumps({'name': name}).encode()
        self.send_response(503 if name == 'error' else 200)
        self.send_header('Content-Type', 'application/json')
        self.send_header('Content-Length', str(len(body)))
        self.end_headers()
        try:
            self.wfile.write(body)
        except (BrokenPipeError, ConnectionResetError):
            pass

def make_server(port=0):
    return ThreadingHTTPServer(('127.0.0.1', port), functools.partial(WorkflowHandler, directory=str(ROOT)))

if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--port', type=int, default=8000)
    args = parser.parse_args()
    with make_server(args.port) as server:
        print(f'http://127.0.0.1:{server.server_port}/win/fixtures/workflow/', flush=True)
        try:
            server.serve_forever()
        except KeyboardInterrupt:
            pass
