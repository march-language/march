#!/usr/bin/env bash
#
# gen-perihelion-assets.sh — regenerate the committed Perihelion .mjs assets
# served at /docs/perihelion/.
#
# docs/perihelion.html hosts the compiled Perihelion demo as a static
# fullscreen page. CI (deploy-pages.yml) only runs `jekyll build` — it never
# invokes the March compiler — so the compiled JS under docs/assets/perihelion/
# is a checked-in build artifact, not something Jekyll produces. Whenever the
# March source (demo_app/perihelion/lib/*.march) or the JS runtime shims
# (runtime/march_{runtime,dom,canvas,audio}.mjs) change, this script must be
# re-run and the result committed, or the live page drifts from source (the
# same staleness problem gen-stdlib-docs.sh solves for the stdlib reference).
#
# Usage:  scripts/gen-perihelion-assets.sh
#
# Requirements: dune + the OCaml toolchain on PATH (in CI, after `eval $(opam env)`).
set -euo pipefail

ROOT="$(git -C "$(dirname "$0")" rev-parse --show-toplevel)"
cd "$ROOT"

DEMO="$ROOT/demo_app/perihelion"
OUT_DIR="$ROOT/docs/assets/perihelion"
BUILD="$ROOT/_build/default"
MARCH_EXE="$BUILD/bin/main.exe"
MARCH_STDLIB="$BUILD/stdlib"

echo "Building march compiler..."
dune build --root "$ROOT" bin/main.exe

echo "Compiling perihelion -> $OUT_DIR/perihelion.mjs..."
mkdir -p "$OUT_DIR"
MARCH_STDLIB="$MARCH_STDLIB" MARCH_LIB_PATH="$DEMO/lib" "$MARCH_EXE" --target js \
  --no-copy-runtime -o "$OUT_DIR/perihelion.mjs" "$DEMO/lib/perihelion.march"

echo "Copying runtimes..."
cp "$ROOT/runtime/march_runtime.mjs" "$OUT_DIR/"
cp "$ROOT/runtime/march_dom.mjs" "$OUT_DIR/"
cp "$ROOT/runtime/march_canvas.mjs" "$OUT_DIR/"
cp "$ROOT/runtime/march_audio.mjs" "$OUT_DIR/"

# Not committed (matches docs/assets/tetris/'s existing precedent of no
# source map on the static fallback) -- the compiler still emits one and a
# sourceMappingURL comment pointing at it, so drop both.
rm -f "$OUT_DIR/perihelion.mjs.map"
sed -i.bak '/^\/\/# sourceMappingURL=/d' "$OUT_DIR/perihelion.mjs"
rm -f "$OUT_DIR/perihelion.mjs.bak"

echo "Done. $OUT_DIR is up to date with demo_app/perihelion/lib/*.march."
