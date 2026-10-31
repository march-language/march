#!/bin/bash
# test/test_http_bind_host.sh: HttpServer.bind_host("127.0.0.1") makes the
# compiled server listen on the loopback address only.
#
#   test/test_http_bind_host.sh            (from the repo root, after dune build --root .)
#   MARCH_HTTP_EVLOOP=0 test/test_http_bind_host.sh   (the thread-pool listen path)
set -e
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
MARCH_BIN="$ROOT/_build/default/bin/main.exe"
OUT="$(mktemp -d)/bind_host"
"$MARCH_BIN" --compile "$ROOT/test/bind_host/bind_host.march" -o "$OUT"
"$OUT" &
PID=$!
cleanup() { kill $PID 2>/dev/null || true; wait $PID 2>/dev/null || true; rm -f "$OUT"; }
trap cleanup EXIT
for _ in 1 2 3 4 5 6 7 8 9 10; do
  if lsof -nP -iTCP:47811 -sTCP:LISTEN >/dev/null 2>&1; then break; fi
  sleep 0.3
done
ADDRS=$(lsof -nP -a -p $PID -iTCP:47811 -sTCP:LISTEN -Fn | sed -n 's/^n//p' | sort -u)
if [ "$ADDRS" != "127.0.0.1:47811" ]; then
  echo "FAIL: expected only 127.0.0.1:47811, got: $ADDRS"; exit 1
fi
BODY=$(curl -s http://127.0.0.1:47811/)
if [ "$BODY" != "ok" ]; then echo "FAIL: expected ok, got '$BODY'"; exit 1; fi
echo "PASS: listening on $ADDRS, GET / = $BODY"
