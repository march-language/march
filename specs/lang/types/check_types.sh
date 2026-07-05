#!/usr/bin/env bash
# Core March static-semantics conformance check (see ../core-march-types.md).
# accept/*.march must typecheck (march --check exit 0).
# reject/*.march must be rejected (exit 1) AND the --check output must contain
# the substring in their `-- EXPECT-ERROR: <substring>` first-line annotation.
# Exit 0 iff every program behaves as declared.
set -u
here="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "$here/../../.." && pwd)"
bin="${MARCH_BIN:-$root/_build/default/bin/main.exe}"
[ -x "$bin" ] || { echo "march binary not found at $bin" >&2; exit 2; }
pass=0; fail=0
for f in "$here"/accept/*.march; do
  "$bin" --check "$f" >/dev/null 2>&1
  if [ $? -eq 0 ]; then echo "  [accept/$(basename "$f")] OK (typechecks)"; pass=$((pass+1))
  else echo "  [accept/$(basename "$f")] FAIL — should typecheck but was rejected"; fail=$((fail+1)); fi
done
for f in "$here"/reject/*.march; do
  want="$(sed -n 's/^-- EXPECT-ERROR: //p' "$f" | head -1)"
  out="$("$bin" --check "$f" 2>&1)"; ec=$?
  b="$(basename "$f")"
  if [ $ec -eq 0 ]; then echo "  [reject/$b] FAIL — should be rejected but typechecked"; fail=$((fail+1))
  elif [ -z "$want" ]; then echo "  [reject/$b] FAIL — no EXPECT-ERROR annotation"; fail=$((fail+1))
  elif echo "$out" | grep -qF "$want"; then echo "  [reject/$b] OK (rejected: \"$want\")"; pass=$((pass+1))
  else echo "  [reject/$b] FAIL — rejected but message lacks \"$want\""; fail=$((fail+1)); fi
done
echo "=== core-march-types: $pass passed, $fail failed ==="
[ $fail -eq 0 ]
