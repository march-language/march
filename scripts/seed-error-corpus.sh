#!/usr/bin/env bash
# seed-error-corpus.sh — add test/errors twins for the reject corpora and the
# `march --explain` pages (diagnostics plan §11, D7).
#
# Sources, in order:
#   specs/lang/types/reject/*.march, specs/lang/grammar/reject/*.march
#     copied verbatim (their `-- EXPECT-ERROR:` line comes along, and
#     test/run_errors.exe asserts the fragment is in the rendered output);
#   specs/lang/errors/<slug>.md
#     the page's FIRST ```march block (its failing program).
#
# Each program is named test/errors/<slug>_<n>.march, where <slug> is the code
# of the FIRST diagnostic `march --check` prints for it and <n> counts up per
# slug. A program whose text is already in test/errors is skipped, so the script
# is idempotent and never renames or overwrites an existing case. Generate the
# expected files afterwards:
#
#   UPDATE_ERRORS=1 ./_build/default/test/run_errors.exe -e
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"
bin="${MARCH_BIN:-$root/_build/default/bin/main.exe}"
[ -x "$bin" ] || { echo "march binary not found at $bin (dune build --root . bin/main.exe)" >&2; exit 2; }
out=test/errors
mkdir -p "$out"
home="$(mktemp -d)"; mkdir -p "$home/.cache"
work="$(mktemp -d)"
trap 'rm -rf "$home" "$work"' EXIT

already() {  # is this exact program text already in the corpus?
  local f
  for f in "$out"/*.march; do
    [ -f "$f" ] && cmp -s "$1" "$f" && return 0
  done
  return 1
}

add() {  # add <program file>
  local src="$1" slug n
  already "$src" && return 0
  slug=$(HOME="$home" "$bin" --check "$src" 2>&1 \
           | grep -oE '\[[a-z_]+(:[^]]*)?\]$' | head -1 | sed -E 's/^\[([a-z_]+).*$/\1/' || true)
  if [ -z "$slug" ]; then echo "  skip (no diagnostic): $2" >&2; return 0; fi
  n=1
  while [ -e "$out/${slug}_$n.march" ]; do n=$((n + 1)); done
  cp "$src" "$out/${slug}_$n.march"
  echo "  $out/${slug}_$n.march  <- $2"
}

for f in specs/lang/errors/*.md; do
  [ -f "$f" ] || continue
  p="$work/$(basename "$f" .md).march"
  awk '/^```march$/{f=1;next} f&&/^```$/{exit} f' "$f" > "$p"
  add "$p" "$f"
done
for f in specs/lang/types/reject/*.march specs/lang/grammar/reject/*.march; do
  add "$f" "$f"
done
