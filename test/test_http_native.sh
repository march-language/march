#!/bin/bash
# test/test_http_native.sh
#
# SUPERSEDED — this is a hand-run smoke script, NOT the project's coverage of
# the compiled HTTP server.  That lives in test/test_http_native.ml, which
# rides run_stdlib.exe and therefore runs under `dune runtest` and in CI:
#
#   ./_build/default/test/run_stdlib.exe test 'http server' -e
#
# This script is kept only as a quick manual poke (it uses a fixed port 8080 and
# an absolute dune path, so it is not safe to run concurrently).  Do not treat a
# green run of it as evidence: it compiles WITHOUT --opt, makes one request per
# assertion, never checks the server survives a sustained sequence, and asserts
# only a status code on the 404 — so it passed against a server that answered a
# well-formed empty 200, and against one that segfaulted on request 2.  Those
# were real, shipped bugs; see test/test_http_native.ml's header.
#
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
