#!/usr/bin/env bash
set -e
ROOT="$(git -C "$(dirname "$0")" rev-parse --show-toplevel)"
DEMO="$(cd "$(dirname "$0")" && pwd)"

echo "Building march..."
(cd "$ROOT" && dune build 2>&1 | grep -v "^$" || true)

echo "Compiling dom_demo.march → dom_demo.mjs..."
"$ROOT/_build/default/bin/main.exe" --target js -o "$DEMO/dom_demo.mjs" "$DEMO/dom_demo.march"

echo "Copying runtimes..."
cp "$ROOT/runtime/march_runtime.mjs" "$DEMO/"
cp "$ROOT/runtime/march_dom.mjs" "$DEMO/"

echo "Done! Open demo_app/dom_demo/index.html in a browser."
