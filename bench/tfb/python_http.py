#!/usr/bin/env python3
"""Minimal Python HTTP server — TFB plaintext + JSON.
Uses http.server (stdlib) for a baseline comparison.
Usage: python3 python_http.py
"""
import http.server
import json

HELLO = b"Hello, World!"
JSON_MSG = json.dumps({"message": "Hello, World!"}).encode()

class Handler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path == "/json":
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(JSON_MSG)))
            self.send_header("Server", "Python-stdlib")
            self.end_headers()
            self.wfile.write(JSON_MSG)
        else:
            self.send_response(200)
            self.send_header("Content-Type", "text/plain")
            self.send_header("Content-Length", str(len(HELLO)))
            self.send_header("Server", "Python-stdlib")
            self.end_headers()
            self.wfile.write(HELLO)

    def log_message(self, format, *args):
        pass  # Suppress request logging

if __name__ == "__main__":
    server = http.server.ThreadingHTTPServer(("", 8080), Handler)
    print("Python http.server listening on :8080")
    server.serve_forever()
