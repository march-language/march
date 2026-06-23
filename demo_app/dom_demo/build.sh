#!/usr/bin/env bash
# Build dom_demo to JS via forge build --target=js.
# Uses dev march/forge binaries from the dune build output,
# since the installed opam versions may be behind.
set -e
DEMO="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(git -C "$DEMO" rev-parse --show-toplevel)"
BUILD="$ROOT/_build/default"
FORGE="$BUILD/forge/bin/main.exe"

echo "Building march..."
(cd "$ROOT" && dune build)

# Create a wrapper script so forge picks up the dev march with the right stdlib.
# A symlink won't work: on macOS Sys.executable_name returns the symlink path,
# so find_stdlib_dir() can't locate the stdlib. A script that sets MARCH_STDLIB
# explicitly avoids the issue entirely.
SHIM_DIR="$(mktemp -d)"
MARCH_EXE="$BUILD/bin/main.exe"
MARCH_STDLIB="$BUILD/stdlib"
cat > "$SHIM_DIR/march" << SHIM
#!/usr/bin/env bash
exec env MARCH_STDLIB="$MARCH_STDLIB" "$MARCH_EXE" "\$@"
SHIM
chmod +x "$SHIM_DIR/march"
trap 'rm -rf "$SHIM_DIR"' EXIT

echo "Compiling dom_demo → .march/build/debug/dom_demo.mjs..."
(cd "$DEMO" && PATH="$SHIM_DIR:$PATH" "$FORGE" build --target=js)

echo "Copying runtimes..."
cp "$DEMO/.march/build/debug/dom_demo.mjs" "$DEMO/"
cp "$ROOT/runtime/march_runtime.mjs" "$DEMO/"
cp "$ROOT/runtime/march_dom.mjs" "$DEMO/"

echo "Done! Open demo_app/dom_demo/index.html in a browser."
