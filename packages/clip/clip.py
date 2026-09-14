#!/usr/bin/env python3
"""clip — talk to a peer's clipd over a unix socket.

Typical use on the headless side, where the desktop's own session is not up:

    clip info                 # what does the peer offer?
    clip get                  # peer text  -> stdout
    clip get image/png > a.png
    clip put < notes.txt
    clip put image/png < shot.png
"""
import argparse
import base64
import json
import os
import socket
import sys
import urllib.parse

DEFAULT_SOCKET = "/run/user/1000/clipd.sock"
TEXT = "text/plain"
PNG = "image/png"


def normalise_type(value: str) -> str:
    aliases = {"text": TEXT, "png": PNG, "image": PNG}
    return aliases.get(value, value)


def request(socket_path: str, method: str, path: str, body=None, timeout: float = 30):
    payload = b"" if body is None else body
    req = (
        f"{method} {path} HTTP/1.1\r\n"
        "Host: localhost\r\n"
        f"Content-Type: application/json\r\n"
        f"Content-Length: {len(payload)}\r\n"
        "Connection: close\r\n\r\n"
    ).encode() + payload

    with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as sock:
        sock.settimeout(timeout)
        sock.connect(socket_path)
        sock.sendall(req)
        chunks = []
        while True:
            chunk = sock.recv(65536)
            if not chunk:
                break
            chunks.append(chunk)

    raw = b"".join(chunks)
    head, _, data = raw.partition(b"\r\n\r\n")
    status = int(head.split(b"\r\n", 1)[0].split(b" ")[1])
    return status, data


def main() -> int:
    parser = argparse.ArgumentParser(prog="clip", description=__doc__)
    parser.add_argument(
        "--socket",
        default=os.environ.get("CLIP_SOCKET", DEFAULT_SOCKET),
        help="peer clipd unix socket (default: %(default)s, or $CLIP_SOCKET)",
    )
    sub = parser.add_subparsers(dest="cmd", required=True)

    sub.add_parser("info", help="list MIME types the peer offers")
    sub.add_parser("ping", help="check the peer daemon is reachable")

    get = sub.add_parser("get", help="read the peer clipboard")
    get.add_argument("type", nargs="?", default=None, help="text or image/png (default: whatever is set)")

    put = sub.add_parser("put", help="write the peer clipboard")
    put.add_argument("type", nargs="?", default=TEXT, help="text or image/png")

    args = parser.parse_args()
    try:
        if args.cmd == "ping":
            status, _ = request(args.socket, "GET", "/info", timeout=5)
            return 0 if status == 200 else 1
        if args.cmd == "info":
            status, data = request(args.socket, "GET", "/info")
            if status != 200:
                print(f"clip: info failed (HTTP {status})", file=sys.stderr)
                return 1
            print("\n".join(json.loads(data)["types"]))
            return 0
        if args.cmd == "get":
            query = ""
            if args.type:
                query = "?type=" + urllib.parse.quote(normalise_type(args.type))
            status, data = request(args.socket, "GET", "/clip" + query)
            if status == 204:
                print("clip: peer clipboard is empty", file=sys.stderr)
                return 1
            if status != 200:
                print(f"clip: get failed (HTTP {status})", file=sys.stderr)
                return 1
            obj = json.loads(data)
            sys.stdout.buffer.write(base64.b64decode(obj["data"]))
            return 0
        if args.cmd == "put":
            mime = normalise_type(args.type)
            payload = json.dumps(
                {"type": mime, "data": base64.b64encode(sys.stdin.buffer.read()).decode()}
            ).encode()
            status, data = request(args.socket, "PUT", "/clip", body=payload)
            if status != 200:
                print(f"clip: put failed (HTTP {status})", file=sys.stderr)
                return 1
            return 0
    except FileNotFoundError:
        print(f"clip: no daemon socket at {args.socket} (tunnel down?)", file=sys.stderr)
        return 1
    except (ConnectionError, socket.timeout) as exc:
        print(f"clip: cannot reach daemon: {exc}", file=sys.stderr)
        return 1
    return 1


if __name__ == "__main__":
    sys.exit(main())
