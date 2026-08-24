#!/usr/bin/env python3
"""Serial HTTP client for bench/interp/http_server.march.
Prints checksum=<number of 200 responses> and reqps=<req/s>."""
import sys, time, urllib.request
n = int(sys.argv[1]) if len(sys.argv) > 1 else 500
port = int(sys.argv[2]) if len(sys.argv) > 2 else 18080
ok = 0
deadline = time.time() + 15
while time.time() < deadline:          # wait for listen()
    try:
        urllib.request.urlopen(f"http://127.0.0.1:{port}/", timeout=1).read(); break
    except Exception:
        time.sleep(0.1)
t = time.time()
for i in range(n):
    path = "/" if i % 2 == 0 else f"/echo/{i}"
    with urllib.request.urlopen(f"http://127.0.0.1:{port}{path}", timeout=5) as r:
        body = r.read().decode()
        if r.status == 200 and (path == "/" and body == "hello" or body == str(i)):
            ok += 1
dt = time.time() - t
print(f"checksum={ok}")
print(f"reqps={n/dt:.0f}")
