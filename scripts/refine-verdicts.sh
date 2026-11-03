#!/usr/bin/env bash
# refine-verdicts.sh — every refinement verdict in the corpus, one per line,
# in a form that is the same on every platform.
#
# Usage: scripts/refine-verdicts.sh OUT [--rlimit N]
#
# Runs `march --check --refine-report-sites=all` over test/native/*.march and
# specs/lang/types/{accept,reject}/*.march (every run also reports the
# stdlib's own obligations), each fixture from a fresh cwd with a private
# HOME so no cache answers for z3.  Keeps only the per-site verdict lines
# (verdict, origin, file:line:col, kind, callee, predicate), with paths made
# repo-relative, prefixed by the fixture, sorted, in OUT/verdicts.txt.
#
# CI's refine-agreement job runs this with the pinned z3 on each tier-1
# platform and fails on any line that differs
# (specs/2026-11-02-bundled-z3-design.md, "cross-platform agreement is
# enforced").  --rlimit N sets MARCH_REFINE_RLIMIT, the perturbation that
# proves a comparison of two outputs can go red.
#
# z3 comes from the usual lookup (MARCH_Z3, then PATH for a dev build).
# MARCH_ORACLE_JOBS sets the parallelism (default: CPU count).
set -euo pipefail

[ $# -ge 1 ] || { sed -n '2,20p' "$0" >&2; exit 2; }
OUT="$1"; shift
RLIMIT=""
while [ $# -gt 0 ]; do
  case "$1" in
    --rlimit) RLIMIT="$2"; shift 2 ;;
    *) echo "refine-verdicts: unknown argument $1" >&2; exit 2 ;;
  esac
done

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
EXE="${MARCH_ORACLE_EXE:-$ROOT/_build/default/bin/main.exe}"
[ -x "$EXE" ] || { echo "refine-verdicts: $EXE not built (dune build --root . bin/main.exe)" >&2; exit 2; }
mkdir -p "$OUT"
OUT="$(cd "$OUT" && pwd)"
rm -rf "$OUT/cwd" "$OUT/parts" "$OUT/home"
mkdir -p "$OUT/cwd" "$OUT/parts" "$OUT/home"
export HOME="$OUT/home"
unset XDG_CACHE_HOME MARCH_REFINE_Z3_LOG MARCH_REFINE_RLIMIT_LOG
if [ -n "$RLIMIT" ]; then export MARCH_REFINE_RLIMIT="$RLIMIT"; else unset MARCH_REFINE_RLIMIT; fi
JOBS="${MARCH_ORACLE_JOBS:-$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 4)}"
export EXE ROOT OUT

one() {
  f="$1"
  tag="$(basename "$(dirname "$f")")_$(basename "$f" .march)"
  d="$OUT/cwd/$tag"
  mkdir -p "$d"
  (cd "$d" && "$EXE" --check --refine-report-sites=all "$f" 2>&1 || true) \
    | grep -E $'^(proved|violated|trusted|skipped[^\t]*)\t' \
    | ROOT="$ROOT" TAG="$tag" perl -pe '
        # perl, not sed: BSD sed reads "\t" in a bracket as the letters, so the
        # two platforms would normalise the same line differently.
        s/\Q$ENV{ROOT}\E\///g;
        s#(^|\t)[^\t]*/stdlib/#$1stdlib/#g;
        $_ = "$ENV{TAG}\t$_"' > "$OUT/parts/$tag" || true
  rm -rf "$d"
}
export -f one

ls "$ROOT"/test/native/*.march \
   "$ROOT"/specs/lang/types/accept/*.march \
   "$ROOT"/specs/lang/types/reject/*.march > "$OUT/fixtures.txt"
tr '\n' '\0' < "$OUT/fixtures.txt" | xargs -0 -P "$JOBS" -n 1 bash -c 'one "$1"' _
cat "$OUT"/parts/* | LC_ALL=C sort > "$OUT/verdicts.txt"
n=$(wc -l < "$OUT/verdicts.txt" | tr -d ' ')
f=$(wc -l < "$OUT/fixtures.txt" | tr -d ' ')
z3="${MARCH_Z3:-$(command -v z3 || echo none)}"
echo "refine-verdicts: $n verdicts from $f fixtures -> $OUT/verdicts.txt (z3: $z3, $("$z3" --version 2>/dev/null || echo unknown))"
