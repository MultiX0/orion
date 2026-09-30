# How long does each host keep an idle TLS connection open, and what is the
# cheapest request that opens one? Both decide how orion_cloud_prewarm works:
# a warm socket that the server has already dropped by the time the board uses
# it is worth nothing.
#
#   python tools/cloud/keepalive_probe.py

import http.client
import socket
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import cloud_api as c

HOSTS = [
    ("api.fish.audio", "fish", c.env("FISH_API_KEY")),
    ("api.deepinfra.com", "deepinfra", c.env("DEEPINFRA_API_KEY")),
]

CHEAP = {
    "fish": [("HEAD", "/v1/tts"), ("GET", "/model?page_size=1&self=true")],
    "deepinfra": [("HEAD", "/v1/openai/models"), ("HEAD", "/v1/openai/chat/completions")],
}


def request(conn, method, path, key):
    t0 = time.perf_counter()
    conn.request(method, path, headers={"Authorization": "Bearer " + key,
                                        "Connection": "keep-alive"})
    r = conn.getresponse()
    body = r.read()
    return r.status, len(body), r.getheader("Connection"), (time.perf_counter() - t0) * 1000


def cheapest(host, name, key):
    print("\n%s" % host)
    for method, path in CHEAP[name]:
        conn = http.client.HTTPSConnection(host, timeout=20)
        t0 = time.perf_counter()
        conn.connect()
        hs = (time.perf_counter() - t0) * 1000
        status, n, hdr, ms = request(conn, method, path, key)
        status2, _, _, ms2 = request(conn, method, path, key)
        print("  %-5s %-32s handshake %4.0f ms  first %4.0f ms (%d, %d B, Connection: %s)  reused %4.0f ms (%d)" % (
            method, path, hs, ms, status, n, hdr, ms2, status2))
        conn.close()


def idle_limit(host, name, key, waits=(5, 15, 30, 60, 90)):
    method, path = CHEAP[name][0]
    results = []
    for w in waits:
        conn = http.client.HTTPSConnection(host, timeout=20)
        request(conn, method, path, key)
        time.sleep(w)
        try:
            request(conn, method, path, key)
            results.append((w, "alive"))
        except (http.client.RemoteDisconnected, ConnectionResetError, BrokenPipeError,
                socket.timeout, OSError) as e:
            results.append((w, "closed (%s)" % type(e).__name__))
        conn.close()
    print("  idle %s: %s" % (host, ", ".join("%d s %s" % r for r in results)))


def main():
    for host, name, key in HOSTS:
        cheapest(host, name, key)
    print()
    for host, name, key in HOSTS:
        idle_limit(host, name, key)


if __name__ == "__main__":
    main()
