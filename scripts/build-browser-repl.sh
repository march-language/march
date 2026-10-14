#!/usr/bin/env bash
#
# build-browser-repl.sh — build every committed in-browser March artifact.
#
# march-lang.org serves docs/ as committed files (see scripts/gen-stdlib-docs.sh), so
# the browser REPL and the Tetris playground's live compiler are committed build
# outputs. Built by hand, they went stale: the July bundles predated stdlib builtins
# and modules (Json failed with `unbound variable: string_byte_at`, the live compiler
# could not compile anything), and they were development builds ten times larger than
# needed. This script is the one way to produce them; CI runs it with --check.
#
# Produces:
#   docs/assets/march.js                  interpreter REPL (cookbook, landing, playground)
#   docs/assets/march_compile.js          live compiler (Tetris playground)
#   docs/assets/march_stdlib.js           stdlib sources both read (scripts/gen-browser-stdlib.py)
#   docs/assets/tetris/tetris-source.march.txt   editable Tetris source (gen-tetris-playground-source.py)
#   docs/assets/tetris/tetris.mjs         that source compiled with `march --target js`
#   docs/assets/tetris/march_runtime.mjs  copied from runtime/
#   docs/assets/tetris/march_dom.mjs      copied from runtime/
#
# Both js_of_ocaml bundles are built with `--profile release` (whole-program, dead code
# removed, minified) into a private build dir, so the developer's dev-profile _build/
# is never rebuilt in release mode or the reverse. js_of_ocaml output is byte-identical
# across checkout paths, which is what lets --check compare byte for byte.
#
# Usage:  scripts/build-browser-repl.sh           write the artifacts
#         scripts/build-browser-repl.sh --check   compare instead; exit 1 naming every stale file
set -euo pipefail

CHECK=0
case "${1:-}" in
  --check) CHECK=1 ;;
  "") ;;
  *) echo "usage: $0 [--check]" >&2; exit 2 ;;
esac

ROOT="$(git -C "$(dirname "$0")" rev-parse --show-toplevel)"
cd "$ROOT"

BUILD_DIR="$ROOT/_build_browser"
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
mkdir -p "$STAGE/tetris"

echo "==> Building browser bundles (release profile)"
dune build --root "$ROOT" --profile release --build-dir "$BUILD_DIR" \
  js/march_browser.bc.js js/march_browser_compile.bc.js
echo "==> Building the compiler (for tetris.mjs)"
dune build --root "$ROOT" bin/main.exe

cp "$BUILD_DIR/default/js/march_browser.bc.js" "$STAGE/march.js"
cp "$BUILD_DIR/default/js/march_browser_compile.bc.js" "$STAGE/march_compile.js"
python3 scripts/gen-browser-stdlib.py "$STAGE/march_stdlib.js" >/dev/null
python3 scripts/gen-tetris-playground-source.py "$STAGE/tetris/tetris-source.march.txt" >/dev/null
cp runtime/march_runtime.mjs runtime/march_dom.mjs "$STAGE/tetris/"

# The compiler writes <out> next to a .march input; compile a copy in the stage dir.
# A private HOME keeps ~/.cache/march (shared across worktrees) out of the build.
cp "$STAGE/tetris/tetris-source.march.txt" "$STAGE/tetris/tetris.march"
(cd "$STAGE/tetris" && HOME="$STAGE/home" "$ROOT/_build/default/bin/main.exe" \
   --target js -o tetris.mjs tetris.march >"$STAGE/tetris-compile.log" 2>&1) || {
  cat "$STAGE/tetris-compile.log" >&2
  echo "error: compiling the Tetris source failed" >&2
  exit 1
}
rm -f "$STAGE/tetris/tetris.march"
chmod u+w "$STAGE"/*.js "$STAGE"/tetris/*

ARTIFACTS=(march.js march_compile.js march_stdlib.js
           tetris/tetris-source.march.txt tetris/tetris.mjs
           tetris/march_runtime.mjs tetris/march_dom.mjs)

if [ "$CHECK" = 1 ]; then
  stale=()
  for a in "${ARTIFACTS[@]}"; do
    cmp -s "$STAGE/$a" "docs/assets/$a" || stale+=("docs/assets/$a")
  done
  if [ "${#stale[@]}" -gt 0 ]; then
    echo "error: ${#stale[@]} committed browser artifact(s) are stale:" >&2
    printf '  %s\n' "${stale[@]}" >&2
    echo "Regenerate with scripts/build-browser-repl.sh and commit the result." >&2
    exit 1
  fi
  echo "==> All ${#ARTIFACTS[@]} browser artifacts are current"
  exit 0
fi

# Everything built: only now touch docs/assets/.
for a in "${ARTIFACTS[@]}"; do
  mv -f "$STAGE/$a" "docs/assets/$a"
done
echo "==> Wrote:"
for a in "${ARTIFACTS[@]}"; do
  printf '  %-42s %10d bytes  (gzip %d)\n' "docs/assets/$a" \
    "$(wc -c <"docs/assets/$a")" "$(gzip -9c "docs/assets/$a" | wc -c)"
done
