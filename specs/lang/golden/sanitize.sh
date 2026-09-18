#!/usr/bin/env bash
# AddressSanitizer gate over two corpora (see ../core-march.md §5).
# Compiles each program with MARCH_SANITIZE=1 and asserts a clean exit plus no
# sanitizer report — the standing guard against RC/UAF regressions.
# Exit 0 iff every program in every corpus runs clean under ASAN.
#
#   MARCH_BIN=/path/to/main.exe specs/lang/golden/sanitize.sh
# (defaults MARCH_BIN to _build/default/bin/main.exe relative to the repo root)
#
# The two corpora, kept SEPARATE in the output so a failure names its source:
#
#   golden — every specs/lang/golden/*.march. The RC-heavy core-language
#            programs; swept wholesale because the whole directory is, by
#            construction, deterministic and terminating.
#
#   native — a CURATED, EXPLICITLY-NAMED subset of test/native/*.march covering
#            the SIMD / NativeArray-narrow-width / array-backed-Bytes lowerings.
#            These have real CI coverage via `dune runtest` on both OSes, but
#            until 2026-08-20 no sanitizer had ever compiled them: the golden
#            corpus contains zero SIMD/NativeArray/Bytes programs, so every
#            raw-memory path in that area (native <4 x float> loads/stores,
#            narrow-width i8/i16/i32 element access, Bytes' array backing) was
#            outside the only ASAN gate the project runs.
#
# WHY A CURATED LIST AND NOT NEW GOLDENS
# --------------------------------------
# The obvious fix — drop a few SIMD programs into specs/lang/golden/ and let the
# existing glob pick them up — has blast radius well beyond ASAN, because this
# directory is NOT just the ASAN corpus:
#
#   * specs/lang/golden IS the cross-compile oracle corpus. In cross mode
#     test/test_oracle.ml narrows its sweep to examples/ + specs/lang/golden/,
#     so anything landing here is also cross-compiled to linux/amd64 and
#     differentially compared against the native run. A SIMD program would drag
#     arm64-vs-x86_64 vector codegen differences into that diff — a separate
#     project, not a sanitizer change.
#   * specs/lang/golden/INDEX.md pins the corpus count and scripts/check-docs.sh
#     Check C enforces it, so an addition here reddens doc-lint until the count
#     is updated in lockstep.
#
# So the SIMD/NativeArray programs stay where they are and this gate reaches out
# to them by name. The repo already has this exact pattern: test/test_oracle.ml
# pulls a `test_native_allowlist` of individually-named test/native/ programs
# into its sweep for the same reason. An explicit list, NOT a glob over
# test/native — that directory holds 165 fixtures including deliberately
# non-terminating, panic-asserting, FFI-shim and --target js programs.
#
# Please do not "simplify" either corpus back into a single glob.
#
# TIMEOUTS. The per-program wall-clock guard is a HANG backstop, not a
# performance budget — it exists so a non-terminating program fails loudly
# instead of eating the job's 30-minute ceiling. Both corpora use 25s, which is
# enormous headroom: measured 2026-08-20 under ASAN on linux/arm64, the slowest
# curated native program runs in 0.06s and the whole sweep's cost is COMPILE
# time, not run time. That headroom is only true because the two multi-million-
# iteration leak probes are excluded (see below) — re-add one and this bound
# becomes the thing that fails, so exclude heavy probes rather than raising it.
#
# WHAT THIS GATE DOES NOT CATCH. ASAN_OPTIONS sets detect_leaks=0 below, so this
# is a use-after-free / out-of-bounds / UBSan gate, NOT leak coverage. Leaks in
# this area are guarded separately by the live_allocs() probes in test/native
# (simd_leak_probe.march, native_arr_fold_leak_probe.march), which assert an
# exact live-object count and need no sanitizer.

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
  echo "Run this gate on a host without Falcon (e.g. CI, or ci/Dockerfile.ubuntu) instead." >&2
  echo "*** 0 programs compiled, 0 run — this is a SKIP, not a pass. ***" >&2
  exit 0
fi

export ASAN_OPTIONS="detect_leaks=0:halt_on_error=1"
export MARCH_STDLIB="${MARCH_STDLIB:-$root/stdlib}"

# ── Curated test/native subset ────────────────────────────────────────────
# Every program here is deterministic, terminating, self-contained (no
# MARCH_LIB_PATH, no capability grant beyond what it declares itself) and exits
# 0 — all four are required by the runner below, which treats any non-zero exit
# as a failure. Each was confirmed to compile and run clean uninstrumented
# before being added.
#
# DELIBERATELY EXCLUDED from test/native's SIMD/NativeArray/Bytes fixtures, so
# the next person does not re-add them and get a red gate:
#   * simd_bounds_panic, simd_lane_panic, native_arr_map2_inline_length_panic —
#     these assert a runtime panic, i.e. a NON-ZERO exit by design. The runner
#     below cannot express "expected to abort", and weakening it to accept
#     non-zero exits would blind it to the crashes it exists to catch.
#   * simd_leak_probe (~2,000,000 calls), native_arr_fold_leak_probe
#     (2 x 4,000,000-element folds) — multi-million-iteration probes that blow
#     the wall-clock budget under ASAN's 2-20x slowdown. They are live_allocs()
#     LEAK probes, and detect_leaks=0 is set above, so ASAN would add nothing
#     to what they already assert. They keep their own `dune runtest` coverage.
#   * peak_rss — allocates a 64,000,000-element u8 array and asserts an RSS
#     band. ASAN's shadow memory and redzones invalidate that band by
#     construction.
native_curated=(
  # actor record ownership: a running actor holds its own reference, and
  # every pid-producing builtin returns an owned one. Both were use-after-frees
  # only ASAN saw (specs/progress/2026-09-14-live-actor-freed-by-dropping-its-last-pid.md,
  # …/2026-09-14-pid-ownership-settled-send-borrows-self-owned.md).
  actor_enumeration
  # array-backed Bytes
  bytes_u8_bridge
  closure_param_shadows_import
  # closure environments: who releases a lambda's captures, and when. Every one
  # of these guarded a release that was wrong in one direction or the other
  # (specs/progress/2026-09-13-closure-environment-released.md,
  # …/2026-09-14-closure-calls-consume-their-arguments.md,
  # …/2026-09-15-closure-captures-released-by-the-hof-loop.md). They are
  # 5,000-iteration probes, not the multi-million ones excluded above.
  closure_capture_release_probe
  closure_capture_hof_loop_probe
  closure_call_arg_ownership_probe
  # an `if` whose two sides disagree about a heap value: the release on the dead
  # side was missing entirely until 2026-09-16
  # (specs/progress/2026-09-16-if-else-drops-the-dead-side.md). It is here for
  # the OTHER direction — a release that fires on a path where the value is
  # still owned elsewhere is a use-after-free, and detect_leaks=0 means the
  # probe's own flat assertions are what cover the leak half.
  if_branch_dead_value_probe
  # a sorted insert into a list of pairs: the else arm released the list cell
  # ahead of dup'ing a string borrowed from inside it. ASAN is what named this
  # use-after-free, so it is the gate the fix has to keep passing
  # (specs/2026-09-18-perceus-releases-a-parent-before-its-borrowed-child.md).
  perceus_borrowed_child_release
  # the Msgpack/actor/socket program whose guard-page crash is why the
  # closure deep-drop gate exists at all
  node_discovery
  # NativeArray: narrow widths, fold, map/map2, and the inline-loop lowerings
  native_arr_fold
  # the two length-independent Float boxes at a fold_float call boundary,
  # released 2026-09-16; here for the double-free direction, since the release
  # is new on paths that never had one
  native_arr_fold_boundary_box_probe
  native_arr_map2
  native_arr_map2_inline
  native_arr_map_closure_abi
  native_arr_map_inline_capture
  native_arr_map_inline_float_box_reuse
  native_arr_map_inline_reuse
  native_arr_map_inline_unboxed
  native_arr_map_inline_vectorize
  native_arr_narrow
  native_arr_narrow_inline
  float_arr_list_boxing
  # SIMD
  simd_actor_msg
  simd_fma_fuzz
  simd_mutual_tco
  simd_nested_closure_acc
  simd_poly_eq
  simd_residency
  simd_to_string
  simd_vector_core
  simd_vector_escape_arg
  simd_vector_mem
)

# Resolve the curated names to paths. A name that no longer resolves is a HARD
# ERROR, not a silent skip: a fixture rename must not quietly shrink this gate
# to nothing while it keeps reporting green. (test/test_oracle.ml's sibling
# allowlist filters missing entries instead — correct for a differential sweep
# that reports per-file verdicts, wrong for a pass/fail gate.)
native_files=()
missing=()
for b in "${native_curated[@]}"; do
  p="$root/test/native/$b.march"
  if [ -f "$p" ]; then native_files+=("$p"); else missing+=("$b"); fi
done
if [ ${#missing[@]} -ne 0 ]; then
  echo "ERROR: curated test/native fixtures no longer exist: ${missing[*]}" >&2
  echo "Update native_curated in $0 (a rename must not silently shrink this gate)." >&2
  exit 2
fi

total_pass=0; total_fail=0; total_ran=0

# sweep <label> <timeout-seconds> <file>...
# Compiles and runs each file under ASAN. Every result line is prefixed with the
# corpus label so a failure says which corpus it came from.
sweep() {
  local label="$1" tmo="$2"; shift 2
  local pass=0 fail=0 f b tag rc
  for f in "$@"; do
    b="$(basename "$f" .march)"
    tag="$label/$b"
    if ! MARCH_SANITIZE=1 "$bin" --compile "$f" -o "$work/$label-$b.bin" \
         >"$work/$label-$b.clog" 2>&1; then
      echo "  [$tag] COMPILE FAIL"; sed 's/^/    /' "$work/$label-$b.clog"
      fail=$((fail+1)); continue
    fi
    perl -e 'alarm shift; exec @ARGV' "$tmo" "$work/$label-$b.bin" \
      >"$work/$label-$b.out" 2>"$work/$label-$b.err"; rc=$?
    if [ $rc -ne 0 ] || grep -qiE "AddressSanitizer|runtime error:|LeakSanitizer" "$work/$label-$b.err"; then
      echo "  [$tag] SANITIZER FAIL (rc=$rc)"; sed 's/^/    /' "$work/$label-$b.err"
      fail=$((fail+1))
    else
      echo "  [$tag] CLEAN"; pass=$((pass+1))
    fi
  done
  echo "=== $label sanitize: $pass clean, $fail failed (of $# programs) ==="
  total_pass=$((total_pass+pass)); total_fail=$((total_fail+fail)); total_ran=$((total_ran+$#))
}

sweep golden 25 "$here"/*.march
echo
sweep native 25 "${native_files[@]}"

# ── Corpus 3: the two-node scenarios ──────────────────────────────────────
# Two compiled programs as two OS processes over a real socket, with a fault
# applied from outside (scripts/two-node.sh). They are the ONLY fixtures that
# exercise ownership across the actor plane and a live connection, and that is
# not a theoretical distinction: on 2026-09-16 a closure deep drop released a
# node id that the members Map still owned, and BOTH corpora above swept clean
# while `two-node[skew]` died. This corpus is that gate
# (specs/progress/2026-09-15-closure-captures-released-by-the-hof-loop.md).
#
# Slower than the per-program sweeps (two processes, real timeouts, ASAN's
# 2-20x), so each scenario gets its own generous deadline via the harness's own
# TWO_NODE_TIMEOUT rather than the `perl alarm` the sweep() helper uses.
# A scenario that needs root it does not have (partition, iptables) exits 3;
# that is reported as SKIP, not as a pass — the count at the end is what says
# whether this gate ran.
two_node_sweep() {
  local pass=0 fail=0 skip=0 s rc
  for s in $("$root/scripts/two-node.sh" --list); do
    MARCH_BIN="$bin" MARCH_SANITIZE=1 TWO_NODE_TIMEOUT="${TWO_NODE_ASAN_TIMEOUT:-240}" \
      "$root/scripts/two-node.sh" "$s" >"$work/two-node-$s.log" 2>&1; rc=$?
    if [ $rc -eq 3 ]; then
      echo "  [two-node/$s] SKIP (needs root)"; skip=$((skip+1))
    elif [ $rc -ne 0 ] || grep -qiE "AddressSanitizer|runtime error:" "$work/two-node-$s.log"; then
      echo "  [two-node/$s] SANITIZER FAIL (rc=$rc)"; sed 's/^/    /' "$work/two-node-$s.log"
      fail=$((fail+1))
    else
      echo "  [two-node/$s] CLEAN"; pass=$((pass+1))
    fi
  done
  echo "=== two-node sanitize: $pass clean, $fail failed, $skip skipped ==="
  total_pass=$((total_pass+pass)); total_fail=$((total_fail+fail))
  total_ran=$((total_ran+pass+fail))
}

echo
two_node_sweep

# Report the program count explicitly. A green exit code alone is NOT evidence
# this gate ran: the Darwin/Falcon branch above exits 0 having compiled nothing,
# and a glob that matches no files would too. Judge by the count, not the code.
echo
echo "=== sanitize TOTAL: $total_ran programs swept — $total_pass clean, $total_fail failed ==="
[ $total_ran -gt 0 ] || { echo "ERROR: swept 0 programs — the gate is vacuous." >&2; exit 2; }
[ $total_fail -eq 0 ]
