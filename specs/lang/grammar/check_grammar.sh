#!/usr/bin/env bash
# Resolved-grammar conformance check (see ../grammar.md).
# parse/*.march must parse (and typecheck: march --check exit 0).
# reject/*.march must fail to parse (exit 1) AND the --check output must
# contain the substring in their `-- EXPECT-ERROR: <substring>` first-line
# annotation.
# Exit 0 iff every program behaves as declared.
#
# Parallel for the same reason as ../types/check_types.sh: one `march --check`
# per file, no shared state, and each check pays a fresh stdlib load — so the
# serial cost grew with the corpus until it threatened CI's per-step budget.
# Output is sorted so the report does not depend on scheduling order; set
# MARCH_JOBS to override the worker count.
set -u
here="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "$here/../../.." && pwd)"
bin="${MARCH_BIN:-$root/_build/default/bin/main.exe}"
[ -x "$bin" ] || { echo "march binary not found at $bin" >&2; exit 2; }

if [ -n "${MARCH_JOBS:-}" ]; then jobs="$MARCH_JOBS"
elif command -v nproc >/dev/null 2>&1; then jobs="$(nproc)"
elif command -v sysctl >/dev/null 2>&1; then jobs="$(sysctl -n hw.ncpu)"
else jobs=4; fi

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

check_one() {
  local f="$1" kind="$2" b
  b="$(basename "$f")"
  if [ "$kind" = parse ]; then
    if "$bin" --check "$f" >/dev/null 2>&1; then
      echo "PASS   [parse/$b] OK (parses)"
    else
      echo "FAIL   [parse/$b] FAIL — should parse but was rejected"
    fi
  else
    local want out ec
    want="$(sed -n 's/^-- EXPECT-ERROR: //p' "$f" | head -1)"
    out="$("$bin" --check "$f" 2>&1)"; ec=$?
    if [ $ec -eq 0 ]; then
      echo "FAIL   [reject/$b] FAIL — should be rejected but parsed"
    elif [ -z "$want" ]; then
      echo "FAIL   [reject/$b] FAIL — no EXPECT-ERROR annotation"
    elif printf '%s' "$out" | grep -qF "$want"; then
      echo "PASS   [reject/$b] OK (rejected: \"$want\")"
    else
      echo "FAIL   [reject/$b] FAIL — rejected but message lacks \"$want\""
    fi
  fi
}
export -f check_one
export bin

printf '%s\n' "$here"/parse/*.march \
  | xargs -P "$jobs" -I{} bash -c 'check_one "$1" parse' _ {} \
  > "$tmp/par" 2>/dev/null
printf '%s\n' "$here"/reject/*.march \
  | xargs -P "$jobs" -I{} bash -c 'check_one "$1" reject' _ {} \
  > "$tmp/rej" 2>/dev/null
cat "$tmp/par" "$tmp/rej" > "$tmp/results"

sort -k2 "$tmp/results" | sed 's/^PASS   /  /; s/^FAIL   /  /'
pass="$(grep -c '^PASS' "$tmp/results" || true)"
fail="$(grep -c '^FAIL' "$tmp/results" || true)"
echo "=== grammar: $pass passed, $fail failed ==="
[ "$fail" -eq 0 ]
