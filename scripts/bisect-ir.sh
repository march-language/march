#!/usr/bin/env bash
# bisect-ir.sh — which commit changed the LLVM IR emitted for one program?
#
#   scripts/bisect-ir.sh GOOD BAD FILE [--opt N] [--exact] [--keep]
#
# Diagnostics plan T2 (specs/plans/diagnostics-and-triage-plan.md §15).
# `git bisect run` keyed on the sha256 of `march --emit-llvm FILE` (the IR is
# byte-stable across runs and paths; scripts/ir-oracle.sh relies on the same
# property).  A commit is "good" when it emits the SAME IR as GOOD, "bad"
# when it differs.  The bisection follows first parents (main's history of
# PR merges), so the blamed commit is usually a PR merge; it is printed with
# its subject and the specs/progress/ entry it names (or adds), if any.  If GOOD and BAD already
# emit identical IR there is nothing to bisect and it says "no change".
#
# Isolation: everything happens in a throwaway `git worktree` (your checkout,
# index and branch are untouched) with a private HOME (no ~/.cache/march
# cross-talk) and the worktree's own stdlib (MARCH_STDLIB, so a targeted
# build's stale _build/default/stdlib copy cannot leak an old stdlib in).
# Each step rebuilds `bin/main.exe` only (`dune build --root .`): the IR does
# not depend on the C runtime.  A commit that does not build is skipped (exit
# 125).  FILE may be outside the repo; it is copied once, so every step
# compiles the same bytes.
#
# Normalisation (default; --exact turns it off).  Several fresh-name counters
# are global (Defun's lambda counter, ...; observability plan B1), so a commit
# that merely adds a lambda ANYWHERE in the stdlib renumbers every `$lamN` in
# every program and changes its IR hash without changing a single
# instruction.  Measured: across #807..#814 the raw hash first changes at a
# topology.march edit, purely by renumbering.  So before hashing, every
# compiler-generated `$<name><digits>` is renumbered in order of first
# appearance, as is every numbered LLVM local (`%ld36`, `%go_i8851`).  Use
# --exact when the renumbering itself is what you are after.
#
# For a change in program OUTPUT rather than IR (runtime changes included)
# use scripts/bisect-output.sh.
set -euo pipefail

usage() { sed -n '2,25p' "$0" | sed 's/^# \{0,1\}//'; exit 2; }
[ $# -ge 3 ] || usage
GOOD="$1"; BAD="$2"; FILE="$3"; shift 3
OPT=2; KEEP=0; EXACT=0
while [ $# -gt 0 ]; do
  case "$1" in
    --opt) OPT="$2"; shift 2 ;;
    --keep) KEEP=1; shift ;;
    --exact) EXACT=1; shift ;;
    -h|--help) usage ;;
    *) echo "bisect-ir: unknown argument $1" >&2; exit 2 ;;
  esac
done

ROOT="$(git -C "$(dirname "$0")/.." rev-parse --show-toplevel)"
[ -f "$FILE" ] || { echo "bisect-ir: no such file: $FILE" >&2; exit 2; }
GOOD_SHA=$(git -C "$ROOT" rev-parse --verify "$GOOD^{commit}")
BAD_SHA=$(git -C "$ROOT" rev-parse --verify "$BAD^{commit}")

WORK="$(mktemp -d "${TMPDIR:-/tmp}/bisect-ir.XXXXXX")"
WT="$WORK/wt"
mkdir -p "$WORK/home/.cache" "$WORK/prog"
cp "$FILE" "$WORK/prog/prog.march"
cleanup() {
  git -C "$ROOT" worktree remove --force "$WT" >/dev/null 2>&1 || true
  [ "$KEEP" = 1 ] || rm -rf "$WORK"
}
trap cleanup EXIT

git -C "$ROOT" worktree add --quiet --detach "$WT" "$GOOD_SHA"

# step.sh <expected-hash|-> : build the checked-out commit, hash its IR.
# Prints the hash; exits 125 when the commit does not build or emit.
# Renumber every compiler-generated $<name><digits> and LLVM local
# %<name><digits> (including a bare $<digits> / %<digits>) by first
# appearance, per name, so a shifted counter hashes the same (see the header).
cat > "$WORK/norm.pl" <<'PERL'
my (%m, %n);
while (<>) {
  s{([\$%])([A-Za-z_.]*?)(\d+)}{ my $k = "$1$2:$3"; $m{$k} //= ++$n{"$1$2"}; "$1$2#$m{$k}" }ge;
  print;
}
PERL

cat > "$WORK/step.sh" <<EOF
#!/usr/bin/env bash
set -u
cd "$WT"
dune build --root . bin/main.exe > "$WORK/build.log" 2>&1 || exit 125
rm -f "$WORK/prog/prog.ll"
( cd "$WORK/prog" && HOME="$WORK/home" MARCH_STDLIB="$WT/stdlib" \\
    "$WT/_build/default/bin/main.exe" --emit-llvm --opt $OPT prog.march \\
    > "$WORK/emit.log" 2>&1 ) || exit 125
[ -s "$WORK/prog/prog.ll" ] || exit 125
if [ "$EXACT" = 1 ]; then
  h=\$(shasum -a 256 < "$WORK/prog/prog.ll" | cut -d' ' -f1)
else
  h=\$(perl "$WORK/norm.pl" "$WORK/prog/prog.ll" | shasum -a 256 | cut -d' ' -f1)
fi
echo "\$h" > "$WORK/last.hash"
if [ "\${1:-}" = "-" ]; then exit 0; fi
[ "\$h" = "\$1" ] && exit 0 || exit 1
EOF
chmod +x "$WORK/step.sh"

hash_at() {  # hash_at <sha> : IR hash at that commit, or empty if it cannot build
  git -C "$WT" checkout --quiet --detach "$1"
  if "$WORK/step.sh" - ; then cat "$WORK/last.hash"; else echo ""; fi
}

echo "bisect-ir: $FILE  (--opt $OPT$( [ "$EXACT" = 1 ] && echo ", exact" || echo ", fresh names normalised"))"
H_GOOD=$(hash_at "$GOOD_SHA")
[ -n "$H_GOOD" ] || { echo "bisect-ir: GOOD ($GOOD) does not build or emit; see $WORK/build.log" >&2; KEEP=1; exit 2; }
H_BAD=$(hash_at "$BAD_SHA")
[ -n "$H_BAD" ] || { echo "bisect-ir: BAD ($BAD) does not build or emit; see $WORK/build.log" >&2; KEEP=1; exit 2; }
echo "  good $(git -C "$ROOT" rev-parse --short "$GOOD_SHA")  ir $H_GOOD"
echo "  bad  $(git -C "$ROOT" rev-parse --short "$BAD_SHA")  ir $H_BAD"
if [ "$H_GOOD" = "$H_BAD" ]; then
  echo "no change: GOOD and BAD emit identical IR for this program"
  exit 0
fi

# --first-parent: walk main's own history (PR and merge-train merges), not
# the PR branches' internal commits.  Those sit on older bases of main, so
# their IR differs from GOOD for reasons unrelated to the change being
# hunted; measured, a plain bisect over #807..#814 blamed a topology commit
# inside #808's branch.
git -C "$WT" bisect start --first-parent "$BAD_SHA" "$GOOD_SHA" >/dev/null
git -C "$WT" bisect run "$WORK/step.sh" "$H_GOOD" > "$WORK/bisect.log" 2>&1 || true
BLAMED=$(git -C "$WT" rev-parse --verify --quiet refs/bisect/bad || true)
git -C "$WT" bisect reset >/dev/null 2>&1 || true
if [ -z "$BLAMED" ] || [ "$BLAMED" = "$GOOD_SHA" ]; then
  echo "bisect-ir: bisection did not converge; log kept at $WORK/bisect.log" >&2
  KEEP=1; exit 1
fi

echo "first commit whose IR differs from GOOD:"
git -C "$ROOT" log -1 --format='  %h %s%n  %an, %ad' --date=short "$BLAMED"
if grep -q "skip" "$WORK/bisect.log"; then
  echo "  (some commits did not build and were skipped; the blame may be a range: see 'git bisect log')"
fi
# Its progress entry: one the message names, else one the commit adds.
PROG=$(git -C "$ROOT" log -1 --format=%B "$BLAMED" | grep -oE 'specs/progress/[A-Za-z0-9._-]+\.md' | head -1 || true)
# (relative to the first parent, so a PR merge reports the PR's own entry)
[ -n "$PROG" ] || PROG=$(git -C "$ROOT" diff --name-only --diff-filter=A "$BLAMED^1" "$BLAMED" -- specs/progress | head -1 || true)
if [ -n "$PROG" ]; then echo "  progress entry: $PROG"; else echo "  progress entry: (none named or added)"; fi
