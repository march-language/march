#!/usr/bin/env bash
# Build perihelion to JS by invoking the dev march compiler directly.
# perihelion has no external forge dependencies (just stdlib), so it
# compiles straight from the dune build output rather than going through
# `forge build` — forge resolves its own pinned toolchain version
# (~/.march/versions/<tag>/bin/march) ahead of PATH, which would silently
# ignore a dev-march PATH shim and use a stale installed compiler instead.
set -e
DEMO="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(git -C "$DEMO" rev-parse --show-toplevel)"
BUILD="$ROOT/_build/default"
MARCH_EXE="$BUILD/bin/main.exe"
MARCH_STDLIB="$BUILD/stdlib"

echo "Building march..."
# --root pinned explicitly: a plain `dune build` here would let dune's
# upward project-marker search escape to an outer repo when $ROOT itself
# is a nested worktree (e.g. .claude/worktrees/<name>), which has its own
# dune-project markers but sits inside a parent repo that also has them.
# Target just the compiler binary this script needs, not the default
# alias — a plain `dune build`/`dune build --root` with no target also
# pulls in the full test suite (including unrelated, possibly-failing or
# environment-dependent test/dune rules), which this script doesn't need.
(cd "$ROOT" && dune build --root "$ROOT" bin/main.exe)

echo "Compiling perihelion → perihelion.mjs..."
MARCH_STDLIB="$MARCH_STDLIB" MARCH_LIB_PATH="$DEMO/lib" "$MARCH_EXE" --target js \
  -o "$DEMO/perihelion.mjs" "$DEMO/lib/perihelion.march"

echo "Copying runtimes..."
cp "$ROOT/runtime/march_runtime.mjs" "$DEMO/"
cp "$ROOT/runtime/march_dom.mjs" "$DEMO/"
cp "$ROOT/runtime/march_canvas.mjs" "$DEMO/"

echo "Done! Open demo_app/perihelion/index.html in a browser."
