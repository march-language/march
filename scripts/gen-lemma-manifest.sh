#!/usr/bin/env bash
# Regenerate stdlib/lemmas.verified: the stdlib lemmas the refinement checker
# proves, each with a digest of the files its theorem and proof reach
# (reflection design, phase 3).  A stdlib lemma whose line still matches is
# admitted without re-proving it.  Needs z3 on PATH and a built compiler.
#
#   scripts/gen-lemma-manifest.sh          # rewrite stdlib/lemmas.verified
#   scripts/gen-lemma-manifest.sh --check  # exit 1 if it is stale
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
bin="${MARCH_BIN:-$root/_build/default/bin/main.exe}"
[ -x "$bin" ] || { echo "march binary not found at $bin (dune build --root . bin/main.exe)" >&2; exit 2; }
command -v z3 >/dev/null || { echo "z3 not on PATH: the lemmas cannot be proved" >&2; exit 2; }
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
printf 'mod LemmaManifest do\n  fn f(n : Int) : Int do n end\nend\n' > "$tmp/m.march"
(cd "$tmp" && HOME="$tmp/home" "$bin" --check --emit-lemma-manifest m.march) > "$tmp/out" 2>/dev/null || true
grep -E '^(#|[A-Za-z])' "$tmp/out" > "$tmp/manifest" || true
if [ "${1:-}" = "--check" ]; then
  if ! diff -u "$root/stdlib/lemmas.verified" "$tmp/manifest"; then
    echo "stdlib/lemmas.verified is stale: run scripts/gen-lemma-manifest.sh and commit it" >&2
    exit 1
  fi
  echo "stdlib/lemmas.verified: fresh"
else
  cp "$tmp/manifest" "$root/stdlib/lemmas.verified"
  echo "wrote stdlib/lemmas.verified ($(grep -vc '^#' "$root/stdlib/lemmas.verified") lemmas)"
fi
