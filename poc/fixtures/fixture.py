# Generic fixture HTTP server for Linux Preview test scenarios.
# Listens on FIXTURE_PORT (default 8000). What the application under test
# is expected to recognize is the process command line, not this file.
import http.server
import os


class Handler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        self.send_response(200)
        self.end_headers()
        self.wfile.write(b"Linux Preview fixture\n")

    def log_message(self, *args):
        pass


port = int(os.environ.get("FIXTURE_PORT", "8000"))
http.server.HTTPServer(("0.0.0.0", port), Handler).serve_forever()
