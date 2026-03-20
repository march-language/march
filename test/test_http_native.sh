#!/bin/bash
# test/test_http_native.sh
# End-to-end test: compile an HTTP server example and verify it serves requests.
set -e

MARCH_BIN="$(dirname "$0")/../_build/default/bin/main.exe"
if [ ! -f "$MARCH_BIN" ]; then
  MARCH_BIN="$(which march 2>/dev/null || echo march)"
fi

echo "=== Compiling HTTP server ==="
/Users/80197052/.opam/march/bin/dune exec march -- --compile examples/http_hello.march -o /tmp/march_http_test

echo "=== Starting server ==="
/tmp/march_http_test &
SERVER_PID=$!
sleep 1  # Wait for bind

cleanup() {
  kill $SERVER_PID 2>/dev/null || true
  wait $SERVER_PID 2>/dev/null || true
  rm -f /tmp/march_http_test
}
trap cleanup EXIT

echo "=== Testing GET / ==="
RESPONSE=$(curl -s http://localhost:8080/)
if [ "$RESPONSE" = "Hello from compiled March!" ]; then
    echo "PASS: GET / returned correct response"
else
    echo "FAIL: expected 'Hello from compiled March!', got '$RESPONSE'"
    exit 1
fi

echo "=== Testing 404 ==="
STATUS=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:8080/nonexistent)
if [ "$STATUS" = "404" ]; then
    echo "PASS: GET /nonexistent returned 404"
else
    echo "FAIL: expected 404, got $STATUS"
    exit 1
fi

echo "=== All tests passed ==="
