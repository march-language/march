#!/usr/bin/env bash
# Sanitizer sweep over the compiled native test corpus (test/native/*.march that
# have a .expected file). Linux only in practice: ASAN hangs on Macs running
# CrowdStrike Falcon (see specs/lang/golden/sanitize.sh), so run this inside the
# CI image (ci/Dockerfile.ubuntu).
#
#   scripts/native-sanitize-sweep.sh [-l] [-S] [-s "1 14"] [-j N] [-t SECS] [-o DIR] [NAME...]
#
#   -l        leak pass: ASAN_OPTIONS=detect_leaks=1 (default detect_leaks=0),
#             with the suppressions in scripts/lsan-suppressions.txt
#   -S        leak pass without the suppressions file
#   -s LIST   scheduler counts to run each program at (default "1 14")
#   -j N      parallel jobs (default: nproc / 2)
#   -t SECS   per-run timeout (default 60)
#   -o DIR    output directory (default: mktemp)
#   NAME...   restrict to these fixture basenames (default: every .march with
#             a .expected beside it)
#
# Each fixture is compiled with the SAME compiler flags its test/dune rule uses
# (parsed from the rule's `main.exe ... native/X.march` invocation, so --opt 2,
# --ffi-c, --test etc. carry over), with MARCH_SANITIZE=1 MARCH_DEBUG_RUNTIME=1,
# from the test/ directory so the rule's relative paths resolve. The env
# assignments in front of the rule's `./native_X` run command, and the rule's
# `(setenv ...)` wrappers, carry over too, except MARCH_NUM_SCHEDULERS, which the
# sweep sets itself. Fixtures driven over the observe socket are skipped. Fixtures whose rule
# is not a plain native executable compile (--target js, --compile-so,
# --emit-llvm, --check, `test`) are skipped.
#
# Verdicts, one line per (fixture, schedulers) in DIR/results.tsv:
#   ASAN / UBSAN / LSAN    a sanitizer report (excerpt in DIR/<name>.s<N>.err)
#   RCCHECK                a MARCH_RC_CHECKS underflow/overflow report
#   SIGNAL                 killed by a signal (exit >= 128) with no report
#   TIMEOUT                exceeded -t
#   EXIT                   non-zero exit, no report (may be by design)
#   DIFF                   exit 0, stdout differs from .expected (informational:
#                          some rules post-process output)
#   OK                     exit 0, stdout matches
#   COMPILE_FAIL / SKIP    did not run
# Exit status: 1 if any ASAN/UBSAN/LSAN/RCCHECK/SIGNAL verdict, else 0.
set -u
root="$(cd "$(dirname "$0")/.." && pwd)"
bin="${MARCH_BIN:-$root/_build/default/bin/main.exe}"
leak=0; nosupp=0; scheds="1 14"; jobs=$(( $(nproc 2>/dev/null || echo 4) / 2 )); tmo=60; out=""
while getopts "lSs:j:t:o:" o; do
  case $o in
    l) leak=1 ;; S) nosupp=1 ;; s) scheds="$OPTARG" ;; j) jobs="$OPTARG" ;; t) tmo="$OPTARG" ;;
    o) out="$OPTARG" ;; *) sed -n '2,22p' "$0"; exit 2 ;;
  esac
done
shift $((OPTIND - 1))
[ "$jobs" -ge 1 ] || jobs=1
[ -n "$out" ] || out="$(mktemp -d)"
mkdir -p "$out/bin"
[ -x "$bin" ] || { echo "march binary not found at $bin" >&2; exit 2; }

export MARCH_STDLIB="${MARCH_STDLIB:-$root/stdlib}"
export MARCH_RUNTIME_DIR="${MARCH_RUNTIME_DIR:-$root/runtime}"
export MARCH_SANITIZE=1 MARCH_DEBUG_RUNTIME=1
export ASAN_OPTIONS="detect_leaks=$leak:halt_on_error=1"
# The leak pass ignores what is not a leak (process-lifetime runtime caches,
# frames abandoned by design): scripts/lsan-suppressions.txt. -S turns it off.
if [ "$leak" = 1 ] && [ "$nosupp" = 0 ]; then
  export LSAN_OPTIONS="${LSAN_OPTIONS:+$LSAN_OPTIONS:}suppressions=$root/scripts/lsan-suppressions.txt:print_suppressions=0"
fi
export UBSAN_OPTIONS="${UBSAN_OPTIONS:-print_stacktrace=1}"

# name \t compile-args \t run-env, one line per runnable fixture.
python3 - "$root" "$@" > "$out/plan.tsv" <<'PY'
import os, re, sys, shlex
root, only = sys.argv[1], set(sys.argv[2:])
dune = open(os.path.join(root, "test/dune")).read()
runs = {}
for m in re.finditer(r'\(run %\{exe:\.\./bin/main\.exe\}([^()]*?)native/([A-Za-z0-9_]+)\.march\s*\)', dune):
    args, name = m.group(1), m.group(2)
    if name in runs: continue
    toks = shlex.split(args)
    tgt = None
    if "-o" in toks:
        i = toks.index("-o"); tgt = toks[i + 1]; del toks[i:i + 2]
    runs[name] = (toks, tgt, m.end())
for f in sorted(os.listdir(os.path.join(root, "test/native"))):
    if not f.endswith(".march"): continue
    name = f[:-6]
    if only and name not in only: continue
    if not os.path.exists(os.path.join(root, "test/native", name + ".expected")): continue
    if name not in runs:
        print(f"{name}\tSKIP:no-rule\t"); continue
    toks, tgt, pos = runs[name]
    if "--compile" not in toks or "--target" in toks or "--compile-so" in toks:
        print(f"{name}\tSKIP:not-native-compile\t"); continue
    # The rest of this rule: up to the next top-level "(rule".
    end = dune.find("\n(rule", pos)
    rest = dune[pos:end if end > 0 else pos + 4000]
    if "MARCH_OBSERVE_SOCKET" in rest:
        print(f"{name}\tSKIP:needs-observe-client\t"); continue
    env = [f"{k}={v}" for k, v in re.findall(r'\(setenv ([A-Z_]+) "?([^\s")]+)"?', rest)]
    if tgt:
        sm = re.search(r'\(system "((?:[A-Z_]+=\S+ )*)\./' + re.escape(tgt) + r'\b', rest)
        if sm: env += sm.group(1).split()
    env = " ".join(a for a in env if not a.startswith("MARCH_NUM_SCHEDULERS="))
    print(f"{name}\t{' '.join(shlex.quote(t) for t in toks)}\t{env}")
PY

one() {
  local name="$1" args="$2" env="$3" b="$out/bin/$1"
  if [ "${args#SKIP}" != "$args" ]; then printf '%s\t-\t%s\n' "$name" "$args"; return; fi
  if ! ( cd "$root/test" && eval "\"$bin\" $args -o \"$b\" native/$name.march" ) \
       > "$out/$name.compile.log" 2>&1 < /dev/null; then
    printf '%s\t-\tCOMPILE_FAIL\n' "$name"; return
  fi
  local s rc v err
  for s in $scheds; do
    err="$out/$name.s$s.err"
    ( cd "$root/test" && eval "env $env MARCH_NUM_SCHEDULERS=$s timeout -s KILL $tmo \"$b\"" ) \
      > "$out/$name.s$s.out" 2> "$err" < /dev/null
    rc=$?
    if grep -q 'ERROR: LeakSanitizer' "$err"; then v=LSAN
    elif grep -q 'ERROR: AddressSanitizer' "$err"; then v=ASAN
    elif grep -qE '[0-9]: runtime error:|UndefinedBehaviorSanitizer' "$err"; then v=UBSAN
    elif grep -qiE 'march_free of a SHARED object|TRMC hole fill into|rc underflow|refcount underflow' "$err"; then v=RCCHECK
    elif [ $rc -eq 137 ]; then v=TIMEOUT
    elif [ $rc -ge 128 ]; then v=SIGNAL
    elif [ $rc -ne 0 ]; then v=EXIT
    elif cmp -s "$out/$name.s$s.out" "$root/test/native/$name.expected"; then v=OK
    else v=DIFF; fi
    printf '%s\t%s\t%s\t%s\n' "$name" "$s" "$v" "$rc"
  done
}
export -f one
export bin out scheds tmo root

awk -F'\t' '{print $1 "\x1f" $2 "\x1f" $3}' "$out/plan.tsv" |
  xargs -P "$jobs" -d '\n' -I{} bash -c 'IFS=$'"'"'\x1f'"'"' read -r n a e <<< "$1"; one "$n" "$a" "$e"' _ {} \
  | tee "$out/results.tsv"

echo "--- $(wc -l < "$out/plan.tsv") fixtures; results in $out/results.tsv"
cut -f3 "$out/results.tsv" | sort | uniq -c
! cut -f3 "$out/results.tsv" | grep -qE '^(ASAN|UBSAN|LSAN|RCCHECK|SIGNAL)$'
