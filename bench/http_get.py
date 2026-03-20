"""HTTP GET benchmark - Python urllib (stdlib, no deps)."""
import urllib.request
import time

N = 20
URL = "http://httpbin.org/get"

print(f"Python urllib HTTP GET benchmark: {N} sequential requests to {URL}")
start = time.monotonic()
for i in range(N):
    with urllib.request.urlopen(URL) as resp:
        resp.read()
elapsed = time.monotonic() - start
print(f"done in {elapsed:.3f}s ({elapsed/N*1000:.1f}ms/req)")
