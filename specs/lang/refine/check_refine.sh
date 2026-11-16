#!/usr/bin/env bash
# Refinement must-reject corpus (see INDEX.md).
#
# Every reject/*.march holds one obligation the checker must report VIOLATED.
# scripts/refine-oracle.sh pins diagnostics that already exist; its corpus had
# no violated obligation, so a checker that proved everything stayed green on
# it. This runner is the check that goes red.
#
# A fixture declares the ledger row it expects and a piece of the diagnostic:
#
#   -- EXPECT-VIOLATED: <kind> <callee>     the --refine-report-sites=all row
#   -- EXPECT-ERROR: <substring>            text of the rendered diagnostic
#
# It PASSES only when all three hold:
#   - `march --check` exits 1;
#   - a row `violated <TAB> user <TAB> <loc> <TAB> <kind> <TAB> <callee>` is
#     listed;
#   - the output contains the EXPECT-ERROR text.
# A site that is proved, skipped, or files no obligation at all FAILS, and the
# report says which of those it was.
#
# known-accepted.txt lists fixtures the checker wrongly ACCEPTS today, one
# basename per line. Such a fixture passes only while it is still accepted
# (exit 0, no violated row). Once the checker rejects it the run FAILS until
# its line is removed, so the list cannot go stale. The list may only shrink:
# KNOWN_ACCEPTED_MAX below is its ceiling, lowered with each removal.
#
# Each fixture runs from its own fresh working directory. The VC cache lives
# under <cwd>/.march/cas, and a warm one replays a stored counterexample
# without asking the solver: a checker that stopped refuting would still look
# right. HOME is private too (~/.cache/march and ~/.march/cas are shared).
#
# z3 must be on PATH. Without it every obligation is undecided, which this
# runner would report as 20-odd failures; it says so up front instead.
#
#   specs/lang/refine/check_refine.sh           # whole corpus
#   MARCH_BIN=/path/to/march MARCH_JOBS=4 specs/lang/refine/check_refine.sh
#   REFINE_ONLY=k0,s03 specs/lang/refine/check_refine.sh   # by name prefix
set -u
KNOWN_ACCEPTED_MAX=3
MIN_FIXTURES=15

here="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "$here/../../.." && pwd)"
bin="${MARCH_BIN:-$root/_build/default/bin/main.exe}"
[ -x "$bin" ] || { echo "FATAL: march binary not found at $bin (dune build --root . bin/main.exe)" >&2; exit 2; }
command -v z3 >/dev/null 2>&1 || {
  echo "FATAL: z3 is not on PATH. The refinement checker decides nothing without it," >&2
  echo "       so no fixture can be reported violated. Install z3 and re-run." >&2
  exit 2
}
"$bin" --help 2>&1 | grep -q -- '--refine-report-sites=all' || {
  echo "FATAL: $bin has no --refine-report-sites=all" >&2; exit 2
}

if [ -n "${MARCH_JOBS:-}" ]; then jobs="$MARCH_JOBS"
else jobs="$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 4)"; fi

known="$here/known-accepted.txt"
[ -f "$known" ] || { echo "FATAL: $known is missing" >&2; exit 2; }
known_names="$(grep -v '^[[:space:]]*#' "$known" | grep -v '^[[:space:]]*$' || true)"
n_known="$(printf '%s' "$known_names" | grep -c . || true)"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/home/.cache" "$tmp/cwd" "$tmp/out"
# The stdlib is read from the source tree: a concurrent `dune build` restages
# _build/default/stdlib, which the compiler would otherwise read mid-copy.
stdlib="${MARCH_STDLIB:-$root/stdlib}"
export bin tmp stdlib known_names

# One fixture -> one result line, prefixed PASS / FAIL / KNOWN.
check_one() {
  local f="$1" b name want_row want_err kind callee out ec row seen is_known=0
  b="$(basename "$f")"; name="${b%.march}"
  if printf '%s\n' "$known_names" | grep -qxF "$b"; then is_known=1; fi
  want_row="$(sed -n 's/^-- EXPECT-VIOLATED: //p' "$f" | head -1)"
  want_err="$(sed -n 's/^-- EXPECT-ERROR: //p' "$f" | head -1)"
  if [ -z "$want_row" ] || [ -z "$want_err" ]; then
    echo "FAIL   [$b] needs both an EXPECT-VIOLATED and an EXPECT-ERROR line"; return
  fi
  kind="${want_row%% *}"; callee="${want_row#* }"
  rm -rf "$tmp/cwd/$name"; mkdir -p "$tmp/cwd/$name"
  out="$tmp/out/$name"
  (cd "$tmp/cwd/$name" && HOME="$tmp/home" MARCH_STDLIB="$stdlib" \
     "$bin" --check --refine-report --refine-report-sites=all "$f") > "$out" 2>&1
  ec=$?
  row=0
  if awk -F'\t' -v k="$kind" -v c="$callee" \
       '$1=="violated" && $2=="user" && $4==k && $5==c {found=1} END {exit !found}' "$out"; then
    row=1
  fi
  # What the checker said about this callee instead, for the failure message.
  seen="$(awk -F'\t' -v c="$callee" '
      $2=="user" && $1=="skip" && $6==c  {print "skip (" $4 ")"}
      $2=="user" && $1!="skip" && $5==c  {print $1}' "$out" | sort -u | paste -sd, - | sed 's/,/, /g')"
  [ -n "$seen" ] || seen="no obligation filed"

  if [ "$is_known" = 1 ]; then
    if [ "$row" = 1 ]; then
      echo "FAIL   [$b] is now reported violated: remove it from known-accepted.txt and lower KNOWN_ACCEPTED_MAX"
    elif [ $ec -ne 0 ]; then
      echo "FAIL   [$b] is listed in known-accepted.txt but is no longer accepted (exit $ec; $callee: $seen): make the fixture a violation, or correct its EXPECT lines, and remove it from the list"
    else
      echo "KNOWN  [$b] wrongly accepted, as known-accepted.txt records ($callee: $seen)"
    fi
    return
  fi
  if [ "$row" = 0 ]; then
    echo "FAIL   [$b] not reported violated: wanted a violated $kind of \`$callee\`, got: $seen (exit $ec)"
  elif [ $ec -ne 1 ]; then
    echo "FAIL   [$b] violated row listed but --check exited $ec, not 1"
  elif ! grep -qF -- "$want_err" "$out"; then
    echo "FAIL   [$b] violated, but the diagnostic lacks \"$want_err\""
  else
    echo "PASS   [$b] violated ($kind of \`$callee\`: \"$want_err\")"
  fi
}
export -f check_one

ls "$here"/reject/*.march > "$tmp/all" 2>/dev/null
# REFINE_ONLY=k0,s03 limits the run to fixtures whose name starts with one of
# the prefixes (the edit loop; the fixture floor is not applied to it).
if [ -n "${REFINE_ONLY:-}" ]; then
  pat="$(printf '%s' "$REFINE_ONLY" | sed 's/,/|/g')"
  grep -E "/($pat)[^/]*$" "$tmp/all" > "$tmp/fixtures" || true
  MIN_FIXTURES=1
else
  cp "$tmp/all" "$tmp/fixtures"
fi
n="$(wc -l < "$tmp/fixtures" | tr -d ' ')"
[ "$n" -gt 0 ] || { echo "FATAL: no fixtures selected"; exit 2; }
# One serial run first, so the private HOME's stdlib cache is written once
# and not raced by every worker.
check_one "$(head -1 "$tmp/fixtures")" > /dev/null
tr '\n' '\0' < "$tmp/fixtures" | xargs -0 -P "$jobs" -n 1 bash -c 'check_one "$1"' _ > "$tmp/results"

fatal=0
sort -k2 "$tmp/results" | sed -E 's/^(PASS|FAIL|KNOWN) +/  \1  /'
# Every listed name must be a fixture.
for k in $known_names; do
  [ -f "$here/reject/$k" ] || { echo "  FAIL  known-accepted.txt names $k, which is not in reject/"; fatal=1; }
done
got="$(wc -l < "$tmp/results" | tr -d ' ')"
pass="$(grep -c '^PASS' "$tmp/results" || true)"
fail="$(grep -c '^FAIL' "$tmp/results" || true)"
kn="$(grep -c '^KNOWN' "$tmp/results" || true)"
echo "=== refine must-reject: $pass violated, $kn known-accepted, $fail failed ($n fixtures) ==="
if [ "$got" -ne "$n" ]; then echo "FATAL: $got of $n fixtures produced a result"; fatal=1; fi
if [ "$n" -lt "$MIN_FIXTURES" ]; then echo "FATAL: only $n fixtures (expected at least $MIN_FIXTURES): wrong directory?"; fatal=1; fi
if [ "$n_known" -gt "$KNOWN_ACCEPTED_MAX" ]; then
  echo "FATAL: known-accepted.txt lists $n_known fixtures; the ceiling is $KNOWN_ACCEPTED_MAX. The list may only shrink:"
  echo "       a newly found gap needs its own todo and a deliberate change to KNOWN_ACCEPTED_MAX in this script."
  fatal=1
fi
[ "$fail" -eq 0 ] && [ "$fatal" -eq 0 ]
