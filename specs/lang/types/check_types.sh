#!/usr/bin/env bash
# Core March static-semantics conformance check (see ../core-march-types.md).
# accept/*.march must typecheck (march --check exit 0).
# reject/*.march must be rejected (exit 1) AND the --check output must contain
# the substring in their `-- EXPECT-ERROR: <substring>` first-line annotation.
# Exit 0 iff every program behaves as declared.
#
# Each file is INDEPENDENT — one `march --check` per program, no shared state —
# so the corpus is checked in PARALLEL. It was serial until 2026-08-12, when
# the ~290-file corpus grew past CI's 10-minute budget for this step on the
# macOS runner (each check pays a fresh stdlib load, ~1-2s there). Parallel
# execution is the fix that scales with the corpus instead of shrinking it.
#
# Output stays deterministic: workers write one result line per file, and the
# lines are SORTED before printing, so the report does not depend on
# scheduling order. Set MARCH_JOBS to override the worker count.
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

# One file → one result line, prefixed PASS/FAIL for the tally.
check_one() {
  local f="$1" kind="$2" b
  b="$(basename "$f")"
  if [ "$kind" = accept ]; then
    if "$bin" --check "$f" >/dev/null 2>&1; then
      echo "PASS   [accept/$b] OK (typechecks)"
    else
      echo "FAIL   [accept/$b] FAIL — should typecheck but was rejected"
    fi
  else
    local want out ec
    want="$(sed -n 's/^-- EXPECT-ERROR: //p' "$f" | head -1)"
    out="$("$bin" --check "$f" 2>&1)"; ec=$?
    if [ $ec -eq 0 ]; then
      echo "FAIL   [reject/$b] FAIL — should be rejected but typechecked"
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

printf '%s\n' "$here"/accept/*.march \
  | xargs -P "$jobs" -I{} bash -c 'check_one "$1" accept' _ {} \
  > "$tmp/acc" 2>/dev/null
printf '%s\n' "$here"/reject/*.march \
  | xargs -P "$jobs" -I{} bash -c 'check_one "$1" reject' _ {} \
  > "$tmp/rej" 2>/dev/null
cat "$tmp/acc" "$tmp/rej" > "$tmp/results"

sort -k2 "$tmp/results" | sed 's/^PASS   /  /; s/^FAIL   /  /'
pass="$(grep -c '^PASS' "$tmp/results" || true)"
fail="$(grep -c '^FAIL' "$tmp/results" || true)"
echo "=== core-march-types: $pass passed, $fail failed ==="
[ "$fail" -eq 0 ]
