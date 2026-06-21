#!/usr/bin/env bash
# Verify the `march` Rust FFI layer end-to-end: cargo-build the demo binding
# staticlib (test/native/rust_ffi), link it into a March binary via --ffi-link,
# run, and diff against the expected output. Exercises all four slices:
# #[march] (primitives/String/Result + panic->Err), #[derive(Encoder,Decoder)]
# (struct/enum), ResourceArc, and init! (the generated extern block).
#
# Not a dune `runtest` rule on purpose: it needs the Rust toolchain (cargo),
# which isn't assumed present in every CI environment. Run it manually.
#
# Usage: scripts/verify-rust-ffi.sh
set -euo pipefail

cd "$(dirname "$0")/.."
ROOT="$(pwd)"
export PATH="$HOME/.cargo/bin:$HOME/.opam/march/bin:$PATH"

DEMO="$ROOT/test/native/rust_ffi"
APP="$DEMO/app.march"
EXPECTED="$DEMO/app.expected"
BIN="$(mktemp -t rust_ffi_app.XXXXXX)"

echo "==> cargo build (offline) the march workspace + demo staticlib"
( cd "$ROOT/rust" && CARGO_NET_OFFLINE=true cargo build --release >/dev/null )
( cd "$DEMO" && CARGO_NET_OFFLINE=true cargo build --release >/dev/null )
AR="$DEMO/target/release/libdemo_binding.a"

echo "==> march --compile --ffi-link $AR"
# Clear the CAS so a rebuilt .a is always relinked (the archive content is not
# part of the binary cache key).
rm -rf "$ROOT/.march/cas/artifacts" 2>/dev/null || true
"$ROOT/_build/default/bin/main.exe" --compile --ffi-link "$AR" -o "$BIN" "$APP"

echo "==> run + diff"
GOT="$("$BIN" 2>/dev/null)"
if diff <(cat "$EXPECTED") <(printf '%s\n' "$GOT") >/dev/null; then
  echo "PASS: Rust FFI end-to-end matches $EXPECTED"
  rm -f "$BIN"
else
  echo "FAIL: output mismatch"
  echo "--- expected ---"; cat "$EXPECTED"
  echo "--- got ---"; printf '%s\n' "$GOT"
  rm -f "$BIN"
  exit 1
fi
