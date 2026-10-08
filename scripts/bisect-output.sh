#!/usr/bin/env bash
# bisect-output.sh — which commit changed what a compiled program PRINTS?
#
#   scripts/bisect-output.sh GOOD BAD FILE [--expect OUT] [--opt N] [--timeout S] [--keep]
#
# Diagnostics plan T2 (specs/plans/diagnostics-and-triage-plan.md §15).
# `git bisect run` keyed on the compiled program's stdout plus exit code.  A
# commit is "good" when the program behaves as expected: like `--expect OUT`
# (a file holding the known-good stdout; exit code must be 0), or, without
# --expect, exactly as it does when compiled at GOOD.  The first bad commit is
# printed with its subject and the specs/progress/ entry it names or adds.
# If GOOD and BAD behave the same there is nothing to bisect: "no change".
#
# Runtime changes are exactly what output bisection is for, so each step must
# compile against THAT commit's C runtime and stdlib.  A targeted
# `dune build bin/main.exe` does not restage runtime/ into _build (CLAUDE.md),
# and a target-less `dune build --root .` can wedge at 0% CPU on this repo, so
# instead each step builds bin/main.exe and points the compiler at the step's
# own SOURCE trees: MARCH_RUNTIME_DIR=<worktree>/runtime,
# MARCH_STDLIB=<worktree>/stdlib.  The CAS key digests the runtime directory
# the compiler actually uses, so a changed runtime is never a cache hit.
#
# Like scripts/bisect-ir.sh: throwaway `git worktree` (your checkout is
# untouched), private HOME, first-parent bisection along main's PR merges, a
# commit that does not build or compile is skipped (125).  The program run is
# time-boxed (--timeout, default 30 s); a timeout counts as bad.
set -euo pipefail

usage() { sed -n '2,27p' "$0" | sed 's/^# \{0,1\}//'; exit 2; }
[ $# -ge 3 ] || usage
GOOD="$1"; BAD="$2"; FILE="$3"; shift 3
OPT=2; KEEP=0; EXPECT=""; TMO=30
while [ $# -gt 0 ]; do
  case "$1" in
    --expect) EXPECT="$2"; shift 2 ;;
    --opt) OPT="$2"; shift 2 ;;
    --timeout) TMO="$2"; shift 2 ;;
    --keep) KEEP=1; shift ;;
    -h|--help) usage ;;
    *) echo "bisect-output: unknown argument $1" >&2; exit 2 ;;
  esac
done

ROOT="$(git -C "$(dirname "$0")/.." rev-parse --show-toplevel)"
[ -f "$FILE" ] || { echo "bisect-output: no such file: $FILE" >&2; exit 2; }
GOOD_SHA=$(git -C "$ROOT" rev-parse --verify "$GOOD^{commit}")
BAD_SHA=$(git -C "$ROOT" rev-parse --verify "$BAD^{commit}")

WORK="$(mktemp -d "${TMPDIR:-/tmp}/bisect-output.XXXXXX")"
WT="$WORK/wt"
mkdir -p "$WORK/home/.cache" "$WORK/prog"
cp "$FILE" "$WORK/prog/prog.march"
if [ -n "$EXPECT" ]; then
  { cat "$EXPECT"; echo "exit: 0"; } > "$WORK/expected.out"
fi
cleanup() {
  git -C "$ROOT" worktree remove --force "$WT" >/dev/null 2>&1 || true
  [ "$KEEP" = 1 ] || rm -rf "$WORK"
}
trap cleanup EXIT
git -C "$ROOT" worktree add --quiet --detach "$WT" "$GOOD_SHA"

# step.sh [-] : build, compile, run; write the observed behaviour to
# $WORK/actual.out.  With "-" just record it; otherwise compare against
# $WORK/expected.out (0 = same = good, 1 = differs = bad, 125 = skip).
cat > "$WORK/step.sh" <<EOF
#!/usr/bin/env bash
set -u
cd "$WT"
dune build --root . bin/main.exe > "$WORK/build.log" 2>&1 || exit 125
rm -f "$WORK/prog/bin"
( cd "$WORK/prog" && HOME="$WORK/home" MARCH_STDLIB="$WT/stdlib" \\
    MARCH_RUNTIME_DIR="$WT/runtime" \\
    "$WT/_build/default/bin/main.exe" --compile --opt $OPT prog.march -o bin \\
    > "$WORK/compile.log" 2>&1 ) || exit 125
[ -x "$WORK/prog/bin" ] || exit 125
( cd "$WORK/prog" && perl -e 'alarm shift; exec @ARGV' $TMO ./bin > "$WORK/run.out" 2>/dev/null )
rc=\$?
{ cat "$WORK/run.out"; echo "exit: \$rc"; } > "$WORK/actual.out"
if [ "\${1:-}" = "-" ]; then exit 0; fi
cmp -s "$WORK/actual.out" "$WORK/expected.out" && exit 0 || exit 1
EOF
chmod +x "$WORK/step.sh"

run_at() {  # run_at <sha> <dest> : record behaviour at that commit
  git -C "$WT" checkout --quiet --detach "$1"
  "$WORK/step.sh" - || return 1
  cp "$WORK/actual.out" "$2"
}

echo "bisect-output: $FILE  (--opt $OPT, ${EXPECT:+--expect $EXPECT, }timeout ${TMO}s)"
run_at "$GOOD_SHA" "$WORK/good.out" \
  || { echo "bisect-output: GOOD ($GOOD) does not build/compile; see $WORK/{build,compile}.log" >&2; KEEP=1; exit 2; }
run_at "$BAD_SHA" "$WORK/bad.out" \
  || { echo "bisect-output: BAD ($BAD) does not build/compile; see $WORK/{build,compile}.log" >&2; KEEP=1; exit 2; }
[ -n "$EXPECT" ] || cp "$WORK/good.out" "$WORK/expected.out"
echo "  good $(git -C "$ROOT" rev-parse --short "$GOOD_SHA"): $(cmp -s "$WORK/good.out" "$WORK/expected.out" && echo as expected || echo DIFFERS from --expect)"
echo "  bad  $(git -C "$ROOT" rev-parse --short "$BAD_SHA"): $(cmp -s "$WORK/bad.out" "$WORK/expected.out" && echo as expected || echo differs)"
if cmp -s "$WORK/bad.out" "$WORK/expected.out"; then
  echo "no change: BAD behaves as expected"
  exit 0
fi
if ! cmp -s "$WORK/good.out" "$WORK/expected.out"; then
  echo "bisect-output: GOOD itself does not match --expect; nothing to bisect" >&2
  diff "$WORK/expected.out" "$WORK/good.out" | head -10 >&2 || true
  exit 2
fi

git -C "$WT" bisect start --first-parent "$BAD_SHA" "$GOOD_SHA" >/dev/null
git -C "$WT" bisect run "$WORK/step.sh" > "$WORK/bisect.log" 2>&1 || true
BLAMED=$(git -C "$WT" rev-parse --verify --quiet refs/bisect/bad || true)
git -C "$WT" bisect reset >/dev/null 2>&1 || true
if [ -z "$BLAMED" ] || [ "$BLAMED" = "$GOOD_SHA" ]; then
  echo "bisect-output: bisection did not converge; log kept at $WORK/bisect.log" >&2
  KEEP=1; exit 1
fi
echo "first commit whose program behaviour differs:"
git -C "$ROOT" log -1 --format='  %h %s%n  %an, %ad' --date=short "$BLAMED"
echo "  expected vs. bad (first lines):"
diff "$WORK/expected.out" "$WORK/bad.out" | grep '^[<>]' | head -6 | sed 's/^/    /' || true
if grep -q "skip" "$WORK/bisect.log"; then
  echo "  (some commits did not build and were skipped; the blame may be a range: see 'git bisect log')"
fi
PROG=$(git -C "$ROOT" log -1 --format=%B "$BLAMED" | grep -oE 'specs/progress/[A-Za-z0-9._-]+\.md' | head -1 || true)
[ -n "$PROG" ] || PROG=$(git -C "$ROOT" diff --name-only --diff-filter=A "$BLAMED^1" "$BLAMED" -- specs/progress | head -1 || true)
if [ -n "$PROG" ]; then echo "  progress entry: $PROG"; else echo "  progress entry: (none named or added)"; fi
