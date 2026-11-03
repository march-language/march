#!/usr/bin/env bash
#
# build-browser-repl.sh — build every committed in-browser March artifact.
#
# march-lang.org serves docs/ as committed files (see scripts/gen-stdlib-docs.sh), so
# the browser REPL and the Tetris playground's live compiler are committed build
# outputs. Built by hand, they went stale: the July bundles predated stdlib builtins
# and modules (Json failed with `unbound variable: string_byte_at`, the live compiler
# could not compile anything), and they were development builds ten times larger than
# needed. This script is the one way to produce them. The committed copies are
# BOT-OWNED: .github/workflows/gen-browser-repl.yml reruns this on every push to main
# that can change them and commits the result, so a pull request never has to. PR CI
# (ci.yml, job browser-repl) builds them with --out and runs
# scripts/browser-repl-smoke.js against the fresh build.
#
# Produces:
#   docs/assets/march.js                  interpreter REPL (cookbook, landing, playground)
#   docs/assets/march_compile.js          live compiler (Tetris playground)
#   docs/assets/march_stdlib.js           stdlib sources both read at startup (scripts/gen-browser-stdlib.py)
#   docs/assets/march_stdlib_index.js     module -> file index for on-demand loading (same script)
#   docs/assets/stdlib/<file>.js          one per stdlib file, fetched on demand (same script)
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
# Usage:  scripts/build-browser-repl.sh             write the artifacts into docs/assets/
#         scripts/build-browser-repl.sh --out DIR   write them into DIR instead (same layout)
#         scripts/build-browser-repl.sh --check     compare with docs/assets/; exit 1 naming
#                                                   every stale file
set -euo pipefail

CHECK=0
DEST=""
case "${1:-}" in
  --check) CHECK=1 ;;
  --out) [ -n "${2:-}" ] || { echo "usage: $0 [--check | --out DIR]" >&2; exit 2; }
         mkdir -p "$2/tetris" "$2/stdlib"; DEST="$(cd "$2" && pwd)" ;;
  "") ;;
  *) echo "usage: $0 [--check | --out DIR]" >&2; exit 2 ;;
esac

ROOT="$(git -C "$(dirname "$0")" rev-parse --show-toplevel)"
cd "$ROOT"
DEST="${DEST:-$ROOT/docs/assets}"

# Byte-for-byte comparison is only meaningful with the js_of_ocaml that built the
# committed bundles; each records it in its header (`//# buildInfo: ... version=X`).
# CI installs that version first (see the browser-repl job in ci.yml).
if [ "$CHECK" = 1 ]; then
  want="$(sed -n '2s/.*version=\([0-9][0-9.]*\).*/\1/p' docs/assets/march.js)"
  have="$(js_of_ocaml --version 2>/dev/null || echo none)"
  if [ "$want" != "$have" ]; then
    echo "error: committed bundles were built with js_of_ocaml $want; installed is $have." >&2
    echo "Install $want to check them, or rebuild them with $have in the PR that bumps it." >&2
    exit 1
  fi
fi

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
python3 scripts/gen-browser-stdlib.py "$STAGE" >/dev/null
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

ARTIFACTS=(march.js march_compile.js march_stdlib.js march_stdlib_index.js
           tetris/tetris-source.march.txt tetris/tetris.mjs
           tetris/march_runtime.mjs tetris/march_dom.mjs)
for f in "$STAGE"/stdlib/*.js; do ARTIFACTS+=("stdlib/$(basename "$f")"); done
# A per-module file for a stdlib file that no longer exists: removed on write,
# reported as stale by --check.
orphans=()
for f in "$DEST"/stdlib/*.js; do
  [ -e "$f" ] || continue
  [ -e "$STAGE/stdlib/$(basename "$f")" ] || orphans+=("stdlib/$(basename "$f")")
done

if [ "$CHECK" = 1 ]; then
  stale=()
  for a in "${ARTIFACTS[@]}"; do
    cmp -s "$STAGE/$a" "docs/assets/$a" || stale+=("docs/assets/$a")
  done
  for o in "${orphans[@]+"${orphans[@]}"}"; do stale+=("docs/assets/$o (no longer generated)"); done
  if [ "${#stale[@]}" -gt 0 ]; then
    echo "error: ${#stale[@]} committed browser artifact(s) are stale:" >&2
    printf '  %s\n' "${stale[@]}" >&2
    echo "Regenerate with scripts/build-browser-repl.sh and commit the result." >&2
    exit 1
  fi
  echo "==> All ${#ARTIFACTS[@]} browser artifacts are current"
  exit 0
fi

# Everything built: only now touch the destination.
mkdir -p "$DEST/stdlib"
for a in "${ARTIFACTS[@]}"; do
  mv -f "$STAGE/$a" "$DEST/$a"
done
for o in "${orphans[@]+"${orphans[@]}"}"; do rm -f "$DEST/$o"; done
echo "==> Wrote:"
for a in "${ARTIFACTS[@]}"; do
  case "$a" in stdlib/*) continue ;; esac
  printf '  %-42s %10d bytes  (gzip %d)\n' "$DEST/$a" \
    "$(wc -c <"$DEST/$a")" "$(gzip -9c "$DEST/$a" | wc -c)"
done
printf '  %-42s %10d files\n' "$DEST/stdlib/" "$(ls "$DEST"/stdlib/*.js | wc -l)"
[ "${#orphans[@]}" -eq 0 ] || printf '  removed %s\n' "${orphans[@]}"
