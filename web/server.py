#!/usr/bin/env python3
import argparse
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer


class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        body = f"Hello from {self.server.identity}\n".encode()
        self.send_response(200)
        self.send_header("Content-Type", "text/plain")
        self.send_header("Content-Length", str(len(body)))
        self.send_header("X-Backend", self.server.identity)
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, fmt, *args):
        print(f"{self.address_string()} {fmt % args}", flush=True)


parser = argparse.ArgumentParser()
parser.add_argument("--identity", required=True)
parser.add_argument("--bind", required=True)
parser.add_argument("--port", type=int, required=True)
args = parser.parse_args()

server = ThreadingHTTPServer((args.bind, args.port), Handler)
server.identity = args.identity
server.serve_forever()
