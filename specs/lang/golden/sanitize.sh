#!/usr/bin/env bash
# AddressSanitizer gate over the core-march golden corpus (see ../core-march.md §5).
# Compiles each golden .march with MARCH_SANITIZE=1 and asserts a clean exit plus
# no sanitizer report — the standing guard against RC/UAF regressions in the
# RC-heavy golden programs. Exit 0 iff every golden runs clean under ASAN.
#
#   MARCH_BIN=/path/to/main.exe specs/lang/golden/sanitize.sh
# (defaults MARCH_BIN to _build/default/bin/main.exe relative to the repo root)
#
# All 46 goldens terminate (the sibling verify.sh runs them compiled with no
# exclusions); a 25s per-run wall-clock guard is kept as a defensive backstop so
# a future non-terminating golden fails loudly instead of hanging the gate.

set -u
here="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "$here/../../.." && pwd)"
bin="${MARCH_BIN:-$root/_build/default/bin/main.exe}"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

if [ ! -x "$bin" ]; then
  echo "march binary not found at $bin — build it (dune build bin/main.exe) or set MARCH_BIN" >&2
  exit 2
fi

if [ "$(uname -s)" = "Darwin" ] && pgrep -qf 'com\.crowdstrike\.falcon\.Agent' 2>/dev/null; then
  echo "SKIP: CrowdStrike Falcon (EndpointSecurity system extension) detected on this Mac." >&2
  echo "Falcon's syscall interception hangs ASAN's shadow-memory mmap setup on every binary," >&2
  echo "even a no-op 'printf' program — this is environmental, not a golden regression." >&2
  echo "Run this gate on a host without Falcon (e.g. CI) instead." >&2
  exit 0
fi

export ASAN_OPTIONS="detect_leaks=0:halt_on_error=1"
export MARCH_STDLIB="${MARCH_STDLIB:-$root/stdlib}"

pass=0; fail=0
for f in "$here"/*.march; do
  b="$(basename "$f" .march)"
  if ! MARCH_SANITIZE=1 "$bin" --compile "$f" -o "$work/$b.bin" >"$work/$b.clog" 2>&1; then
    echo "  [$b] COMPILE FAIL"; sed 's/^/    /' "$work/$b.clog"; fail=$((fail+1)); continue
  fi
  perl -e 'alarm 25; exec @ARGV' "$work/$b.bin" >"$work/$b.out" 2>"$work/$b.err"; rc=$?
  if [ $rc -ne 0 ] || grep -qiE "AddressSanitizer|runtime error:|LeakSanitizer" "$work/$b.err"; then
    echo "  [$b] SANITIZER FAIL (rc=$rc)"; sed 's/^/    /' "$work/$b.err"; fail=$((fail+1))
  else
    echo "  [$b] CLEAN"; pass=$((pass+1))
  fi
done

echo "=== golden sanitize: $pass clean, $fail failed ==="
[ $fail -eq 0 ]
