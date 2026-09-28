# The test server for recording the XMLNetwork fixtures (the replay tests start the same server in Swift,
# NetworkFixtureServer). Run: python3 serve.py <port> <folder of files>
#   GET /files/<name>           the file
#   GET or POST /echo?<query>   <request method="…" query="…" body="…"><header name="x-…">value</header>…</request>
#                               with the request's X- headers
#   GET /missing                404 with an HTML body
import sys
from http.server import BaseHTTPRequestHandler, HTTPServer
from urllib.parse import urlsplit, unquote
from xml.sax.saxutils import quoteattr, escape

FOLDER = sys.argv[2]

class Handler(BaseHTTPRequestHandler):
    def respond(self, status, body, kind="application/xml"):
        self.send_response(status)
        self.send_header("Content-Type", kind)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def handle_any(self, method):
        url = urlsplit(self.path)
        if url.path.startswith("/files/"):
            name = unquote(url.path[len("/files/"):])
            if not name or "/" in name or name in (".", ".."):
                return self.respond(404, b"<html><body>Not found</body></html>", "text/html")
            try:
                with open(FOLDER + "/" + name, "rb") as f:
                    return self.respond(200, f.read())
            except OSError:
                return self.respond(404, b"<html><body>Not found</body></html>", "text/html")
        if url.path == "/echo":
            length = int(self.headers.get("Content-Length") or 0)
            body = self.rfile.read(length).decode() if length else ""
            headers = "".join(f"<header name={quoteattr(k.lower())}>{escape(v)}</header>"
                              for k, v in sorted(self.headers.items()) if k.lower().startswith("x-"))
            text = f"<request method={quoteattr(method)} query={quoteattr(url.query)} body={quoteattr(body)}>{headers}</request>"
            return self.respond(200, text.encode())
        self.respond(404, b"<html><body>Not found</body></html>", "text/html")

    def do_GET(self):
        self.handle_any("GET")

    def do_POST(self):
        self.handle_any("POST")

    def log_message(self, *args):
        pass

HTTPServer(("127.0.0.1", int(sys.argv[1])), Handler).serve_forever()
