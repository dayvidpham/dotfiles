#!/usr/bin/env python3
"""clipd — a tiny clipboard API over a unix socket.

Runs on the machine that owns a graphical clipboard (laptop/niri) and exposes
text/plain + image/png through wl-clipboard, so a peer machine can reach it via
an ssh reverse tunnel.

Protocol: HTTP/1.1 over a unix socket.

    GET  /clip                       -> {"type": T, "data": base64}
    PUT  /clip   {"type": T, "data": base64}
                                          -> {"ok": true}
    GET  /info                       -> {"types": [...]}

Only text/plain and image/png are offered, per the agreed content scope.
Security: the socket is mode 0600 in a private runtime dir, so only the owning
user — or a peer tunnel they opened — can read or write the clipboard.
"""
import base64
import http.server
import json
import os
import socketserver
import subprocess
import sys
import urllib.parse

SUPPORTED = ("text/plain", "image/png")
MAX_BODY = 32 * 1024 * 1024


def wl_paste(mime: str):
    try:
        proc = subprocess.run(
            ["wl-paste", "--no-newline", "--type", mime],
            stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, timeout=10,
        )
    except (subprocess.TimeoutExpired, FileNotFoundError):
        return None
    return proc.stdout if proc.returncode == 0 else None


def wl_copy(mime: str, data: bytes) -> bool:
    try:
        proc = subprocess.run(
            ["wl-copy", "--type", mime],
            input=data, stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL, timeout=15,
        )
    except (subprocess.TimeoutExpired, FileNotFoundError):
        return False
    return proc.returncode == 0


def available_types():
    try:
        proc = subprocess.run(
            ["wl-paste", "--list-types"],
            stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, timeout=10,
        )
    except (subprocess.TimeoutExpired, FileNotFoundError):
        return []
    if proc.returncode != 0:
        return []
    types = [t.strip() for t in proc.stdout.decode("utf-8", "replace").splitlines() if t.strip()]
    for wanted in SUPPORTED:
        if wanted not in types:
            types.append(wanted)
    return types


class Handler(http.server.BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def log_message(self, *args):  # keep the journal quiet
        pass

    def _send(self, status: str, payload: bytes, content_type: str):
        self.send_response(int(status.split(" ", 1)[0]))
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(payload)))
        self.send_header("Connection", "close")
        self.end_headers()
        self.wfile.write(payload)

    def _json(self, status: str, obj):  # noqa: ANN001
        self._send(status, json.dumps(obj).encode(), "application/json")

    def _read_body(self) -> bytes:
        length = 0
        if self.headers.get("Content-Length"):
            length = int(self.headers["Content-Length"])
        return self.rfile.read(length) if length else b""

    def do_GET(self):  # noqa: N802
        parsed = urllib.parse.urlparse(self.path)
        if parsed.path == "/info":
            return self._json("200 OK", {"types": available_types()})
        if parsed.path != "/clip":
            return self._json("404 Not Found", {"error": "no such path"})
        wanted = urllib.parse.parse_qs(parsed.query).get("type", [None])[0]
        if wanted is not None:
            if wanted not in SUPPORTED:
                return self._json("415 Unsupported Media Type", {"error": f"unsupported type {wanted}"})
            data = wl_paste(wanted)
            if data is None:
                return self._json("204 No Content", {})
            return self._json("200 OK", {"type": wanted, "data": base64.b64encode(data).decode()})
        for mime in SUPPORTED:
            data = wl_paste(mime)
            # Skip empty offers: a copied image often advertises an empty
            # text/plain, and we want the image, not the empty text.
            if data:
                return self._json(
                    "200 OK",
                    {"type": mime, "data": base64.b64encode(data).decode()},
                )
        return self._json("204 No Content", {})

    def do_PUT(self):  # noqa: N802
        path = urllib.parse.urlparse(self.path).path
        if path != "/clip":
            return self._json("404 Not Found", {"error": "no such path"})
        if self.headers.get("Content-Length") and int(self.headers["Content-Length"]) > MAX_BODY:
            return self._json("413 Payload Too Large", {"error": "body too large"})
        try:
            body = json.loads(self._read_body() or b"{}")
            mime = body["type"]
            data = base64.b64decode(body["data"], validate=True)
        except (ValueError, KeyError, TypeError):
            return self._json("400 Bad Request", {"error": "expected {type, data}"})
        if mime not in SUPPORTED:
            return self._json("415 Unsupported Media Type", {"error": f"unsupported type {mime}"})
        if not wl_copy(mime, data):
            return self._json("500 Internal Server Error", {"error": "wl-copy failed"})
        return self._json("200 OK", {"ok": True})


class Server(socketserver.ThreadingMixIn, socketserver.UnixStreamServer):
    allow_reuse_address = True
    daemon_threads = True

    # BaseHTTPRequestHandler expects a (host, port) client address for logging
    # and address_string(); unix sockets have none, so synthesise one.
    def get_request(self):  # noqa: ANN201
        request, _ = super().get_request()
        return request, ("localhost", 0)


def main():
    socket_path = sys.argv[1] if len(sys.argv) > 1 else os.environ.get("CLIPD_SOCKET")
    if not socket_path:
        print("usage: clipd.py <socket-path>", file=sys.stderr)
        return 2
    if os.path.exists(socket_path):
        os.unlink(socket_path)
    with Server(socket_path, Handler) as server:
        os.chmod(socket_path, 0o600)
        server.serve_forever()
    return 0


if __name__ == "__main__":
    sys.exit(main())
