#!/usr/bin/env bash
# Resolved-grammar conformance check (see ../grammar.md).
# parse/*.march must parse (and typecheck: march --check exit 0).
# reject/*.march must fail to parse (exit 1) AND the --check output must
# contain the substring in their `-- EXPECT-ERROR: <substring>` first-line
# annotation.
# Exit 0 iff every program behaves as declared.
set -u
here="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "$here/../../.." && pwd)"
bin="${MARCH_BIN:-$root/_build/default/bin/main.exe}"
[ -x "$bin" ] || { echo "march binary not found at $bin" >&2; exit 2; }
pass=0; fail=0
for f in "$here"/parse/*.march; do
  "$bin" --check "$f" >/dev/null 2>&1
  if [ $? -eq 0 ]; then echo "  [parse/$(basename "$f")] OK (parses)"; pass=$((pass+1))
  else echo "  [parse/$(basename "$f")] FAIL — should parse but was rejected"; fail=$((fail+1)); fi
done
for f in "$here"/reject/*.march; do
  want="$(sed -n 's/^-- EXPECT-ERROR: //p' "$f" | head -1)"
  out="$("$bin" --check "$f" 2>&1)"; ec=$?
  b="$(basename "$f")"
  if [ $ec -eq 0 ]; then echo "  [reject/$b] FAIL — should be rejected but parsed"; fail=$((fail+1))
  elif [ -z "$want" ]; then echo "  [reject/$b] FAIL — no EXPECT-ERROR annotation"; fail=$((fail+1))
  elif echo "$out" | grep -qF "$want"; then echo "  [reject/$b] OK (rejected: \"$want\")"; pass=$((pass+1))
  else echo "  [reject/$b] FAIL — rejected but message lacks \"$want\""; fail=$((fail+1)); fi
done
echo "=== grammar: $pass passed, $fail failed ==="
[ $fail -eq 0 ]
