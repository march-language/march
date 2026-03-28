#!/bin/sh
# Build march_runtime.c for WASM using wasi-sdk.
#
# Prerequisites:
#   wasi-sdk  — brew install wasi-sdk
#               OR download from https://github.com/WebAssembly/wasi-sdk/releases
#               OR set WASI_SDK_PATH=/path/to/wasi-sdk
#   wasmtime  — brew install wasmtime
#               OR https://wasmtime.dev
#
# Usage:
#   ./runtime/build_wasm.sh                     # build runtime only
#   ./runtime/build_wasm.sh test/wasm_tier1.march  # build + run a March program
#
# This script uses wasm64-wasi (64-bit WASM) to avoid pointer-size changes
# in the codegen.  Wasmtime supports wasm64.

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# --- locate wasi-sdk ----------------------------------------------------------
if [ -n "$WASI_SDK_PATH" ]; then
    WASI_SDK="$WASI_SDK_PATH"
elif [ -d "/opt/wasi-sdk" ]; then
    WASI_SDK="/opt/wasi-sdk"
elif command -v brew >/dev/null 2>&1 && brew --prefix wasi-sdk 2>/dev/null | grep -q wasi-sdk; then
    WASI_SDK="$(brew --prefix wasi-sdk)"
else
    echo "ERROR: wasi-sdk not found."
    echo "  Install: brew install wasi-sdk"
    echo "  Or:      export WASI_SDK_PATH=/path/to/wasi-sdk"
    exit 1
fi

WASI_CLANG="$WASI_SDK/bin/clang"
WASI_SYSROOT="$WASI_SDK/share/wasi-sysroot"

if [ ! -x "$WASI_CLANG" ]; then
    echo "ERROR: wasi clang not found at $WASI_CLANG"
    exit 1
fi

echo "Using wasi-sdk: $WASI_SDK"

# --- build runtime .o for wasm32-unknown-unknown ------------------------------
# Use march_runtime_wasm.c (the stripped-down browser runtime) rather than
# the native march_runtime.c which requires ucontext.h, pthreads, etc.
RUNTIME_C="$SCRIPT_DIR/march_runtime_wasm.c"
RUNTIME_O="$SCRIPT_DIR/march_runtime_wasm32.o"

echo "Compiling runtime..."
"$WASI_CLANG" \
    --target=wasm32-unknown-unknown \
    -nostdlib \
    -O2 \
    -DMARCH_WASM \
    -Wno-unused-command-line-argument \
    -c "$RUNTIME_C" \
    -o "$RUNTIME_O"

echo "Runtime object: $RUNTIME_O"

# --- optionally build a March program ----------------------------------------
if [ -n "$1" ]; then
    MARCH_FILE="$1"
    BASENAME="$(basename "$MARCH_FILE" .march)"
    OUT_WASM="${BASENAME}.wasm"

    # Find the march compiler
    MARCH_BIN=""
    for candidate in \
        "$REPO_ROOT/_build/default/bin/main.exe" \
        "$REPO_ROOT/_build/install/default/bin/march"; do
        if [ -f "$candidate" ]; then
            MARCH_BIN="$candidate"
            break
        fi
    done
    if [ -z "$MARCH_BIN" ]; then
        echo "ERROR: march compiler not found. Run: dune build"
        exit 1
    fi

    echo "Compiling $MARCH_FILE -> $OUT_WASM ..."
    WASI_SDK_PATH="$WASI_SDK" "$MARCH_BIN" --compile --target wasm32-unknown-unknown "$MARCH_FILE" -o "$OUT_WASM"

    echo "Done: $OUT_WASM"

    # --- run with wasmtime if available ----------------------------------------
    if command -v wasmtime >/dev/null 2>&1; then
        echo ""
        echo "Running with wasmtime:"
        wasmtime "$OUT_WASM"
    else
        echo ""
        echo "wasmtime not found. To run:"
        echo "  brew install wasmtime"
        echo "  wasmtime $OUT_WASM"
    fi
fi
