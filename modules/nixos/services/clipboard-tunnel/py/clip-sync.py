#!/usr/bin/env python3
"""clip-sync — mirror a peer clipboard into a local (headless) compositor.

Polls the peer's clipd over the shared socket and, whenever the content
changes, writes it to the local clipboard so applications on this machine can
paste it.

Direction is deliberately one-way (peer -> local). A two-way mirror needs
change-origin tagging on both ends to avoid feedback loops; this stays local
and loop-free. Empty clips are treated as "no change", never as a clear.
"""
import base64
import hashlib
import json
import os
import signal
import subprocess
import sys
import threading
import time

# clip.py sits next to this file; import it without needing a package.
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from clip import TEXT, PNG, request  # noqa: E402

STOP = threading.Event()


def local_copy(mime: str, data: bytes) -> bool:
    try:
        proc = subprocess.run(
            ["wl-copy", "--type", mime],
            input=data, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
            timeout=15,
        )
    except (subprocess.TimeoutExpired, FileNotFoundError):
        return False
    return proc.returncode == 0


def fetch_peer(socket_path: str):
    status, body = request(socket_path, "GET", "/clip", timeout=10)
    if status != 200:
        return None
    obj = json.loads(body)
    mime = obj.get("type", TEXT)
    if mime not in (TEXT, PNG):
        mime = TEXT
    return mime, base64.b64decode(obj["data"])


def main() -> int:
    socket_path = sys.argv[1]
    interval = float(sys.argv[2]) if len(sys.argv) > 2 else 1.0
    last = None
    for sig in (signal.SIGINT, signal.SIGTERM):
        signal.signal(sig, lambda *_: STOP.set())
    while not STOP.is_set():
        try:
            item = fetch_peer(socket_path)
        except Exception:  # tunnel down or daemon restarting: retry, don't die
            item = None
        if item is not None:
            mime, data = item
            digest = hashlib.sha256(data).digest()
            if digest != last:
                if local_copy(mime, data):
                    last = digest
        STOP.wait(interval)
    return 0


if __name__ == "__main__":
    sys.exit(main())
