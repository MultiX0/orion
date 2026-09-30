"""Exercises the board's LAN API from this PC, the way the phone app does.

    python tools/cloud/lan_api_test.py                 find the board by beacon
    python tools/cloud/lan_api_test.py --ip 192.168.1.40

Token: logs/ble_pair_token.txt (written by ble_pair_test.py) or APP_TOKEN in
.env. Never printed. Standard library only, so the WebSocket part is a raw
client: handshake, then unmasked server frames.
"""

import argparse
import base64
import http.client
import json
import os
import secrets
import socket
import sys
import time
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
BEACON_PORT = 7332


def token():
    f = REPO / "logs" / "ble_pair_token.txt"
    if f.exists():
        return f.read_text().strip()
    for line in (REPO / ".env").read_text(encoding="utf-8").splitlines():
        if line.startswith("APP_TOKEN="):
            return line.split("=", 1)[1].strip().strip('"')
    sys.exit("no token: run ble_pair_test.py first or set APP_TOKEN in .env")


def find_by_beacon(timeout_s):
    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    s.bind(("", BEACON_PORT))
    s.settimeout(timeout_s)
    t0 = time.time()
    try:
        # The app project's mock device beacons on the same port from this PC
        # with fw "0.1.0-mock"; a real board says hw t-cameraplus-s3 via
        # /api/info, and its beacon never comes from a local address.
        while time.time() - t0 < timeout_s:
            data, addr = s.recvfrom(512)
            msg = json.loads(data.decode())
            if "mock" in str(msg.get("fw", "")):
                continue
            print(f"beacon from {addr[0]} after {time.time() - t0:.1f} s: {msg}")
            return msg.get("ip", addr[0]), msg
    except socket.timeout:
        pass
    finally:
        s.close()
    return None, None


def get(ip, path, tok, timeout=10):
    c = http.client.HTTPConnection(ip, 80, timeout=timeout)
    t0 = time.time()
    c.request("GET", path, headers={"X-Orion-Token": tok} if tok else {})
    r = c.getresponse()
    body = r.read()
    c.close()
    return r.status, body, round((time.time() - t0) * 1000)


def stream_frames(ip, tok, seconds):
    c = http.client.HTTPConnection(ip, 80, timeout=10)
    c.request("GET", "/stream", headers={"X-Orion-Token": tok})
    r = c.getresponse()
    if r.status != 200:
        c.close()
        return r.status, 0, 0
    t0 = time.time()
    frames = 0
    total = 0
    buf = b""
    while time.time() - t0 < seconds:
        chunk = r.read1(65536) if hasattr(r, "read1") else r.read(65536)
        if not chunk:
            break
        buf += chunk
        total += len(chunk)
        while True:
            i = buf.find(b"\xff\xd8")
            j = buf.find(b"\xff\xd9", i + 2) if i >= 0 else -1
            if i < 0 or j < 0:
                break
            frames += 1
            buf = buf[j + 2:]
    c.close()
    return 200, frames, total


def ws_read(ip, tok, seconds):
    """Minimal WebSocket client: handshake then text frames from the server."""
    s = socket.create_connection((ip, 80), timeout=5)
    key = base64.b64encode(secrets.token_bytes(16)).decode()
    s.sendall((f"GET /ws?token={tok} HTTP/1.1\r\nHost: {ip}\r\nUpgrade: websocket\r\n"
               f"Connection: Upgrade\r\nSec-WebSocket-Key: {key}\r\n"
               "Sec-WebSocket-Version: 13\r\n\r\n").encode())
    head = b""
    while b"\r\n\r\n" not in head:
        head += s.recv(1024)
    status = head.split(b"\r\n", 1)[0].decode()
    rest = head.split(b"\r\n\r\n", 1)[1]
    events = []
    # A masked ping the way a client sends it.
    payload = b'{"type":"ping"}'
    mask = secrets.token_bytes(4)
    masked = bytes(b ^ mask[i % 4] for i, b in enumerate(payload))
    s.sendall(bytes([0x81, 0x80 | len(payload)]) + mask + masked)
    s.settimeout(seconds)
    buf = rest
    t0 = time.time()
    try:
        while time.time() - t0 < seconds:
            while len(buf) >= 2:
                ln = buf[1] & 0x7F
                off = 2
                if ln == 126:
                    ln = int.from_bytes(buf[2:4], "big")
                    off = 4
                if len(buf) < off + ln:
                    break
                events.append(buf[off:off + ln].decode("utf-8", "replace"))
                buf = buf[off + ln:]
            buf += s.recv(4096)
    except (socket.timeout, ConnectionError):
        pass
    s.close()
    return status, events


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--ip")
    ap.add_argument("--stream-seconds", type=float, default=5)
    ap.add_argument("--ws-seconds", type=float, default=8)
    a = ap.parse_args()
    tok = token()

    ip = a.ip
    beacon = None
    if not ip:
        ip, beacon = find_by_beacon(8)
        if not ip:
            sys.exit("no beacon heard on 7332 in 8 s")

    status, body, ms = get(ip, "/api/info", None)
    print(f"GET /api/info no token -> {status} in {ms} ms: {body.decode()[:80]}")
    status, body, ms = get(ip, "/api/info", "wrong-token-000000")
    print(f"GET /api/info wrong token -> {status} in {ms} ms")
    status, body, ms = get(ip, "/api/info", tok)
    print(f"GET /api/info -> {status} in {ms} ms: {body.decode()}")
    status, body, ms = get(ip, "/api/state", tok)
    print(f"GET /api/state -> {status} in {ms} ms: {body.decode()}")

    status, body, ms = get(ip, "/capture", tok, timeout=15)
    print(f"GET /capture -> {status}, {len(body)} bytes in {ms} ms")
    if status == 200:
        out = REPO / "logs" / "lan_capture.jpg"
        out.write_bytes(body)
        print(f"  saved {out}, jpeg magic {body[:2].hex()} {body[-2:].hex()}")

    st, frames, total = stream_frames(ip, tok, a.stream_seconds)
    print(f"GET /stream -> {st}, {frames} frames, {total // 1024} KB in {a.stream_seconds} s, "
          f"{frames / a.stream_seconds:.1f} fps")

    status, events = ws_read(ip, tok, a.ws_seconds)
    print(f"WS /ws -> {status}, {len(events)} events in {a.ws_seconds} s")
    for e in events[:6]:
        print("  ", e[:160])
    status, events = ws_read(ip, "bad-token", 2)
    print(f"WS /ws bad token -> {status}, first event {events[:1]}")


if __name__ == "__main__":
    main()
