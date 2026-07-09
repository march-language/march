#!/usr/bin/env bash
# Build tetris to JS via forge build --target=js.
set -e
DEMO="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(git -C "$DEMO" rev-parse --show-toplevel)"
BUILD="$ROOT/_build/default"
FORGE="$BUILD/forge/bin/main.exe"

echo "Building march..."
(cd "$ROOT" && dune build --root "$ROOT")

SHIM_DIR="$(mktemp -d)"
EMPTY_MARCH_HOME="$(mktemp -d)"
cat > "$SHIM_DIR/march" << SHIM
#!/usr/bin/env bash
cd "$ROOT" && exec "$ROOT/_build/default/bin/main.exe" "\$@"
SHIM
chmod +x "$SHIM_DIR/march"
trap 'rm -rf "$SHIM_DIR" "$EMPTY_MARCH_HOME"' EXIT

echo "Compiling tetris → .march/build/debug/tetris.mjs..."
# MARCH_HOME points at an empty dir so forge's toolchain resolution finds no
# `current` symlink and falls back to the ambient PATH (our shim) instead of
# silently using a globally-installed `march` — otherwise Toolchain.path_prefix()
# prepends the installed toolchain's bin dir, which wins over the shim.
(cd "$DEMO" && MARCH_HOME="$EMPTY_MARCH_HOME" PATH="$SHIM_DIR:$PATH" "$FORGE" build --target=js)

echo "Copying runtimes..."
cp "$DEMO/.march/build/debug/tetris.mjs" "$DEMO/"
cp "$ROOT/runtime/march_runtime.mjs" "$DEMO/"
cp "$ROOT/runtime/march_dom.mjs" "$DEMO/"

echo "Done! Open demo_app/tetris/index.html in a browser."
