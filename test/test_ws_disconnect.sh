#!/bin/bash
# test/test_ws_disconnect.sh
#
# Regression test for the march_ws_recv uninitialized-payload free (runtime/march_http.c).
#
# The bug: when a WebSocket client closes the connection before sending a full
# frame, the first `recv_exact(hdr2, 2)` fails and `march_ws_recv` jumps to its
# `closed:` cleanup, which calls `free(payload)`. `payload` used to be declared
# BELOW that goto, so it was freed while uninitialized (free of a garbage stack
# pointer) — a SIGSEGV on essentially every WebSocket disconnect. A second bug
# double-freed `payload` on a mid-payload read failure.
#
# This test compiles the WS echo server, then opens a WebSocket, completes the
# upgrade, and closes abruptly (no Close frame) many times. With the bug the
# server crashes on the first disconnect; with the fix it stays up and keeps
# accepting connections.
#
# Standalone (not a dune test), like test_http_native.sh:
#   bash test/test_ws_disconnect.sh
set -e

HERE="$(cd "$(dirname "$0")" && pwd)"
MARCH_BIN="$HERE/../_build/default/bin/main.exe"
if [ ! -f "$MARCH_BIN" ]; then
  MARCH_BIN="$(which march 2>/dev/null || echo march)"
fi
PORT=9877
BIN=/tmp/march_ws_disconnect_test
ulimit -c 0 2>/dev/null || true   # no core dumps if a (regressed) server aborts

echo "=== Compiling WebSocket echo server ==="
"$MARCH_BIN" --compile "$HERE/../examples/ws_echo.march" -o "$BIN"

echo "=== Starting server on :$PORT ==="
"$BIN" >/tmp/march_ws_disconnect_test.log 2>&1 &
SERVER_PID=$!

cleanup() {
  kill -9 "$SERVER_PID" 2>/dev/null || true   # -9: don't block on a process stuck aborting
  rm -f "$BIN"
}
trap cleanup EXIT

# Wait for the listen socket to come up.
for _ in $(seq 1 20); do
  if curl -s -m 2 -o /dev/null "http://127.0.0.1:$PORT/"; then break; fi
  sleep 0.25
done

echo "=== Hammering with truncated + abrupt WebSocket disconnects ==="
# Two disconnect shapes exercise both `goto closed` failure paths:
#   (a) close immediately after the upgrade  -> the header read fails (payload
#       is freed while still NULL — the uninitialized-free path).
#   (b) send a frame header claiming a 10-byte payload + the mask, then close
#       before sending the payload -> the payload read fails AFTER malloc. The
#       buggy version freed `payload` here AND again at `closed:` (a double
#       free -> abort); the fixed version frees exactly once. This shape is
#       deterministic, so it reliably catches a regression.
python3 - "$PORT" <<'PY'
import socket, sys, time
port = int(sys.argv[1])
handshake = (
    "GET /ws HTTP/1.1\r\n"
    "Host: 127.0.0.1:%d\r\n"
    "Upgrade: websocket\r\nConnection: Upgrade\r\n"
    "Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==\r\n"
    "Sec-WebSocket-Version: 13\r\n\r\n"
) % port
# FIN+text(0x81), MASK+len=10(0x8A), 4-byte mask key, then NO payload bytes.
truncated_frame = bytes([0x81, 0x8A, 0x00, 0x00, 0x00, 0x00])
upgraded = 0
for i in range(20):
    try:
        s = socket.create_connection(("127.0.0.1", port), timeout=3)
        s.sendall(handshake.encode())
        s.settimeout(2)
        try:
            resp = s.recv(256)
        except Exception:
            resp = b""
        if b"101" in resp:
            upgraded += 1
        if i % 2 == 0:
            s.sendall(truncated_frame)   # (b) truncated payload -> double-free path
        # else (a) bare close -> header-read-failure path
        s.close()
        time.sleep(0.05)
    except Exception as e:
        print("connection error:", e)
print("upgrades_101=%d/20" % upgraded)
sys.exit(0 if upgraded >= 18 else 1)
PY

echo "=== Verifying the server survived (no crash) ==="
if ! kill -0 "$SERVER_PID" 2>/dev/null; then
  echo "FAIL: server crashed during WebSocket disconnects (march_ws_recv regression)"
  tail -5 /tmp/march_ws_disconnect_test.log 2>/dev/null || true
  exit 1
fi
# Still accepting connections after the disconnect storm.
STATUS=$(curl -s -m 5 -o /dev/null -w "%{http_code}" "http://127.0.0.1:$PORT/")
if [ "$STATUS" != "200" ]; then
  echo "FAIL: server alive but not serving (got HTTP $STATUS)"
  exit 1
fi

echo "PASS: server survived 20 abrupt WebSocket disconnects and still serves requests"
echo "=== All tests passed ==="
