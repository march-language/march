#!/usr/bin/env bash
# Refactor oracles against a cached baseline from the merge-base.
#
# The oracles (ir, refine, types) are baseline/check pairs, and the usual
# question is "did THIS BRANCH move anything relative to where it forked".
# Doing that by hand means: stash or commit, check out the base, rebuild,
# record a baseline, come back, rebuild, check — and doing it again on every
# iteration.  This script does the base half once per (base commit, oracle
# script) pair and caches it:
#
#   scripts/oracle-base.sh ir                 # check against merge-base(HEAD, origin/main)
#   scripts/oracle-base.sh refine types       # several oracles, one base build
#   scripts/oracle-base.sh all                # ir + refine + types
#   scripts/oracle-base.sh --base REF ir      # a different base
#   scripts/oracle-base.sh --refresh ir       # re-record the cached baseline
#
# The baseline is recorded by THIS tree's oracle script, copied into a pristine
# `git archive` export of the base commit and run there, so it exercises the
# base compiler on the base corpus.  The check then runs on this tree as it is,
# uncommitted edits included.  A fixture the branch added, removed or edited
# therefore shows up in the diff as that fixture changing, which is the truth
# about the branch, not noise.
#
# Cache: ${MARCH_ORACLE_CACHE:-~/.cache/march-oracle-base}/<base-sha>-<script-hash>/<oracle>/
# keyed by the oracle script's content as well as the commit, so editing an
# oracle invalidates its baselines.  Only the manifests are kept (megabytes);
# the base source export is deleted once the baselines are recorded.  The
# check's work files go to _build/oracle-check/<oracle>/ in this tree.
#
# determinism-oracle.sh needs no baseline (it compares the compiler against
# itself) and is not handled here; run it directly.
#
# Exit status: 0 every oracle identical, 1 any oracle reported a change,
# 2 setup error.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CACHE="${MARCH_ORACLE_CACHE:-$HOME/.cache/march-oracle-base}"
BASE_REF=""
REFRESH=0
ORACLES=()

usage() { sed -n '2,/^set -uo/p' "$0" | sed '$d' | sed 's/^# \{0,1\}//'; }

while [ $# -gt 0 ]; do
  case "$1" in
    --base) BASE_REF="${2:?--base needs a ref}"; shift 2 ;;
    --refresh) REFRESH=1; shift ;;
    -h|--help) usage; exit 0 ;;
    all) ORACLES+=(ir refine types); shift ;;
    ir|refine|types) ORACLES+=("$1"); shift ;;
    *) echo "unknown argument: $1 (oracles: ir refine types all)" >&2; exit 2 ;;
  esac
done
[ ${#ORACLES[@]} -gt 0 ] || { usage >&2; exit 2; }

if [ -z "$BASE_REF" ]; then
  # origin/main, not main: a local main can be weeks stale in a worktree.
  BASE_REF=origin/main
fi
BASE_SHA="$(git -C "$ROOT" merge-base HEAD "$BASE_REF" 2>/dev/null)" \
  || { echo "FATAL: no merge-base between HEAD and $BASE_REF (git fetch?)" >&2; exit 2; }
short="${BASE_SHA:0:10}"
echo "==> base: $BASE_REF -> merge-base $short"

# Files each oracle's baseline consists of (everything else in its dir is
# scratch and is not cached).
manifest_files() {
  case "$1" in
    ir) echo "ir.sha256" ;;
    refine) echo "refine.txt" ;;
    types) echo "core_ast.sha256 diagnostics.txt json_base" ;;
  esac
}

script_hash() { shasum -a 256 < "$ROOT/scripts/$1-oracle.sh" | cut -c1-12; }
entry_dir() { echo "$CACHE/$BASE_SHA-$(script_hash "$1")/$1"; }

need_record=()
for o in "${ORACLES[@]}"; do
  d="$(entry_dir "$o")"
  if [ "$REFRESH" -eq 1 ] || [ ! -f "$d/.complete" ]; then
    need_record+=("$o")
  else
    echo "    $o: cached baseline $d"
  fi
done

if [ ${#need_record[@]} -gt 0 ]; then
  # Two worktrees on the same base would otherwise export and record into the
  # same directories at once.  mkdir is atomic; a lock older than 2 hours is
  # from a killed run and is broken.
  mkdir -p "$CACHE"
  lock="$CACHE/lock-$BASE_SHA"
  until mkdir "$lock" 2>/dev/null; do
    if [ -n "$(find "$lock" -maxdepth 0 -mmin +120 2>/dev/null)" ]; then
      rmdir "$lock" 2>/dev/null; continue
    fi
    echo "    waiting for another session recording $short ($lock)"; sleep 20
  done
  trap 'rmdir "$lock" 2>/dev/null' EXIT
  # Re-check under the lock: the other session may have recorded them.
  pending=()
  for o in "${need_record[@]}"; do
    if [ "$REFRESH" -eq 1 ] || [ ! -f "$(entry_dir "$o")/.complete" ]; then pending+=("$o"); fi
  done
  need_record=(${pending[@]+"${pending[@]}"})
fi

if [ ${#need_record[@]} -gt 0 ]; then
  src="$CACHE/src-$BASE_SHA"
  rm -rf "$src"; mkdir -p "$src"
  echo "==> exporting $short to $src"
  git -C "$ROOT" archive "$BASE_SHA" | tar -x -C "$src" \
    || { echo "FATAL: git archive failed" >&2; rm -rf "$src"; exit 2; }
  echo "==> building base compiler (shared dune cache: mostly hits)"
  (cd "$src" && dune build --root . bin/main.exe 2>&1 | tail -20)
  [ -x "$src/_build/default/bin/main.exe" ] \
    || { echo "FATAL: base compiler did not build; see output above" >&2; rm -rf "$src"; exit 2; }
  for o in "${need_record[@]}"; do
    d="$(entry_dir "$o")"
    rm -rf "$d"; mkdir -p "$d"
    # THIS tree's oracle script, run from inside the base export: ROOT, the
    # corpus and the compiler are all the base's; the recording logic is ours,
    # so baseline and check cannot disagree about format.
    cp "$ROOT/scripts/$o-oracle.sh" "$src/scripts/$o-oracle.sh"
    echo "==> recording $o baseline at $short"
    # MARCH_STDLIB/MARCH_ORACLE_EXE from the caller's env would point the base
    # run at this tree; clear them.
    if ! env -u MARCH_STDLIB -u MARCH_ORACLE_EXE \
         bash "$src/scripts/$o-oracle.sh" baseline "$d/raw"; then
      echo "FATAL: $o baseline failed at $short (log above)" >&2
      rm -rf "$d"; rm -rf "$src"; exit 2
    fi
    for m in $(manifest_files "$o"); do cp -R "$d/raw/$m" "$d/$m"; done
    rm -rf "$d/raw"
    echo "$BASE_SHA" > "$d/.complete"
  done
  rm -rf "$src"
fi

echo "==> building this tree's compiler"
(cd "$ROOT" && dune build --root . bin/main.exe 2>&1 | tail -20)

rc=0
summary=()
for o in "${ORACLES[@]}"; do
  d="$(entry_dir "$o")"
  w="$ROOT/_build/oracle-check/$o"
  rm -rf "$w"; mkdir -p "$w"
  for m in $(manifest_files "$o"); do cp -R "$d/$m" "$w/$m"; done
  echo ""
  echo "==> $o oracle: check against $short"
  st=0
  bash "$ROOT/scripts/$o-oracle.sh" check "$w" || st=$?
  case "$st" in
    0) summary+=("$o: IDENTICAL") ;;
    1) summary+=("$o: CHANGED (details: $w)"); [ "$rc" -eq 0 ] && rc=1 ;;
    *) summary+=("$o: ERROR exit $st"); rc=2 ;;
  esac
done

echo ""
echo "==> oracle summary vs $short"
for s in "${summary[@]}"; do echo "    $s"; done
exit "$rc"
