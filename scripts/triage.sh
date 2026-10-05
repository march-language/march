#!/usr/bin/env bash
# Compiler-bug triage: run the triage ladder on one program, print one screen.
#
#   scripts/triage.sh FILE [--opt N] [--expect OUT] [--fn NAME] [--deep] [--timeout N]
#
# Rungs (specs/plans/diagnostics-and-triage-plan.md §12-§13, item T1):
#   1. compiler or program?  FILE interpreted vs compiled (--compile --opt N);
#      stdout + exit code compared.  --expect OUT compares both against a
#      known-good stdout file instead of trusting the interpreter.
#   2. which optional pass?  recompile with each optional-pass switch in turn
#      (MARCH_NO_UNBOX=1, MARCH_NO_HOF_SPEC=1, MARCH_NO_INLINE_RC=1, --no-opt);
#      the first one that makes the compiled output match the reference is
#      blamed.  None helps → a mandatory pass (mono/defun/perceus/drop/escape/
#      trmc).  Runs only when the outputs diverged, or with --deep.
#      These four are every optional-pass switch as of 2026-10-05 (grep
#      MARCH_NO_ / --no- in lib/tir/contract_pipeline.ml, lib/tir/llvm_rc_inline.ml,
#      bin/main.ml); MARCH_NO_TRMC was removed 2026-09-21, TRMC is mandatory.
#   3. which stage?  one MARCH_DUMP_TXT=all compile, split into one file per
#      `===== tir-… =====` section; per stage, the function count and the
#      names added/removed.  --fn NAME also reports the first stage at which
#      that function's printed body changed (modulo fresh-name numbering).
#      With optimisation on, Opt + DCE run between tir-escape and
#      tir-native-map-inline and print no MARCH_DUMP_TXT section of their own.
#   4. sanitizer.  If the compiled run crashed (exit >= 128) or with --deep,
#      rebuild with MARCH_SANITIZE=1 (ASAN+UBSan) and rerun it.
#
# Isolation: FILE and its sibling .march files are copied into a fresh temp
# dir, every compiler run uses a private HOME and that dir as its project, so
# no stale CAS / ~/.cache/march entry can confuse a triage and nothing is
# written into the repo or the user's project.  The temp dir is kept and its
# path printed; the report ends with the next command to run.
#
# Options:
#   --opt N        clang optimisation level for compiled runs (default 2)
#   --expect OUT   known-good stdout to compare against (instead of interp)
#   --fn NAME      track this function through the TIR stages (entry-module
#                  functions print bare, `go`; other modules' as `Mod.go`)
#   --deep         run the switch and sanitizer rungs even when nothing failed
#   --timeout N    seconds before an interpreted or compiled RUN is killed
#                  (default 60; fib-shaped programs take hours interpreted)
#
# Environment: MARCH_BIN (compiler; default _build/default/bin/main.exe),
# TRIAGE_COMPILE_TIMEOUT (seconds per compile, default 600).
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
usage() { sed -n '2,/^set -uo/p' "$0" | sed '$d' | sed 's/^# \{0,1\}//'; }

FILE=""; OPT=2; EXPECT=""; FN=""; DEEP=0; TIMEOUT=60
COMPILE_TIMEOUT="${TRIAGE_COMPILE_TIMEOUT:-600}"
while [ $# -gt 0 ]; do
  case "$1" in
    -h|--help) usage; exit 0 ;;
    --opt) OPT="${2:?--opt needs N}"; shift 2 ;;
    --expect) EXPECT="${2:?--expect needs a file}"; shift 2 ;;
    --fn) FN="${2:?--fn needs a name}"; shift 2 ;;
    --deep) DEEP=1; shift ;;
    --timeout) TIMEOUT="${2:?--timeout needs seconds}"; shift 2 ;;
    -*) echo "triage: unknown option $1 (see --help)" >&2; exit 2 ;;
    *) [ -z "$FILE" ] || { echo "triage: one FILE only" >&2; exit 2; }; FILE="$1"; shift ;;
  esac
done
[ -n "$FILE" ] || { usage >&2; exit 2; }
[ -f "$FILE" ] || { echo "triage: no such file: $FILE" >&2; exit 2; }
if [ -n "$EXPECT" ]; then
  [ -f "$EXPECT" ] || { echo "triage: no such file: $EXPECT" >&2; exit 2; }
  EXPECT="$(cd "$(dirname "$EXPECT")" && pwd)/$(basename "$EXPECT")"
fi

MARCH="${MARCH_BIN:-$ROOT/_build/default/bin/main.exe}"
[ -x "$MARCH" ] || {
  echo "FATAL: compiler $MARCH not built. Run: dune build --root . bin/main.exe @runtime/all" >&2
  exit 2; }

T="$(mktemp -d "${TMPDIR:-/tmp}/triage.XXXXXX")"
SRCDIR="$(cd "$(dirname "$FILE")" && pwd)"
BASE="$(basename "$FILE")"
mkdir -p "$T/src" "$T/dump" "$T/home" "$T/stages"
cp "$SRCDIR"/*.march "$T/src/" 2>/dev/null
cp "$SRCDIR"/*.march "$T/dump/" 2>/dev/null

# ── helpers ──────────────────────────────────────────────────────────────

# run_capped DIR OUT ERR SECS [VAR=VAL ...] CMD ARGS...
# Runs under env with the triage knobs scrubbed and a private HOME; sets RC
# and TIMED_OUT.  `exec` makes the background pid the command itself, so the
# watchdog's signal reaches it.  On timeout: SIGTERM, 5 s grace, then SIGKILL
# ONLY when KILL_OK=1 (the OCaml compiler/interpreter).  A compiled March
# binary is never SIGKILLed: one wedged in a green-thread fault path sits in
# an uninterruptible kernel wait, and SIGKILL (plus a debugger) on that state
# has kernel-panicked a Mac (runtime/march_scheduler.c fault handler).  Such
# a pid is left running and listed in STUCK.
KILL_OK=1; STUCK=""
run_capped() {
  local dir="$1" out="$2" err="$3" secs="$4"; shift 4
  ( cd "$dir" && exec env -u MARCH_NO_UNBOX -u MARCH_NO_HOF_SPEC -u MARCH_NO_INLINE_RC \
      -u MARCH_DUMP_TXT -u MARCH_SANITIZE HOME="$T/home" "$@" ) >"$out" 2>"$err" </dev/null &
  local pid=$! ticks=0 limit=$((secs * 10))
  TIMED_OUT=0
  while kill -0 "$pid" 2>/dev/null; do
    if [ "$ticks" -ge "$limit" ]; then
      TIMED_OUT=1; RC=124
      # disown first: bash still reaps it, but prints no "Terminated" job
      # notice into the report.
      disown "$pid" 2>/dev/null
      kill -TERM "$pid" 2>/dev/null
      ticks=0
      while kill -0 "$pid" 2>/dev/null && [ "$ticks" -lt 50 ]; do sleep 0.1; ticks=$((ticks + 1)); done
      if kill -0 "$pid" 2>/dev/null; then
        if [ "$KILL_OK" = 1 ]; then kill -9 "$pid" 2>/dev/null; else STUCK="$STUCK $pid"; fi
      fi
      return
    fi
    sleep 0.1; ticks=$((ticks + 1))
  done
  wait "$pid"; RC=$?
}

nlines() { awk 'END{print NR}' "$1"; }

# first_diff A B: first differing line number (empty when identical).
first_diff() {
  awk -v A="$1" -v B="$2" 'BEGIN{
    for (i = 1; ; i++) {
      ra = (getline la < A); rb = (getline lb < B)
      if (ra <= 0 && rb <= 0) exit
      if (ra <= 0 || rb <= 0 || la != lb) { print i; exit } } }'
}

# line_at FILE N: line N, trimmed to 40 chars, or <EOF>.
line_at() {
  awk -v n="$2" 'NR==n{s=$0; if (length(s)>40) s=substr(s,1,37) "..."; print s; f=1; exit}
                 END{if(!f) print "<EOF>"}' "$1"
}

# describe_vs REF_OUT REF_RC OUT RC NAME: "MATCH" or a DIFFER phrase.
describe_vs() {
  local d; d="$(first_diff "$1" "$3")"
  if [ -n "$d" ]; then
    echo "DIFFER at line $d  ($5: $(line_at "$1" "$d") / compiled: $(line_at "$3" "$d"))"
  elif [ "$2" != "-" ] && [ "$2" != "$4" ]; then
    echo "exit codes DIFFER ($5 $2 / compiled $4)"
  else
    echo "MATCH"
  fi
}

run_desc() {  # RC OUT TIMED_OUT
  if [ "$3" = 1 ]; then echo "TIMED OUT after ${TIMEOUT}s (stopped)"; return; fi
  local s="exit $1, $(nlines "$2") lines"
  [ "$1" -ge 128 ] && s="$s  CRASHED (signal $(($1 - 128)))"
  echo "$s"
}

first_err() { grep -m1 -iE 'error|fatal|exception' "$1" || head -1 "$1"; }

# compile_and_run TAG [VAR=VAL ...] [-- EXTRA compiler flags]: builds
# $T/TAG.bin in $T/src and runs it.  Sets C_RC (compile), RC, TIMED_OUT.
compile_and_run() {
  local tag="$1"; shift
  local envs=() flags=()
  while [ $# -gt 0 ] && [ "$1" != "--" ]; do envs+=("$1"); shift; done
  [ "${1:-}" = "--" ] && shift
  while [ $# -gt 0 ]; do flags+=("$1"); shift; done
  run_capped "$T/src" "$T/$tag.compile.out" "$T/$tag.compile.err" "$COMPILE_TIMEOUT" \
    ${envs[@]+"${envs[@]}"} "$MARCH" --compile --opt "$OPT" ${flags[@]+"${flags[@]}"} \
    "$BASE" -o "$T/$tag.bin"
  C_RC=$RC
  if [ "$C_RC" -ne 0 ] || [ ! -x "$T/$tag.bin" ]; then
    [ "$C_RC" -eq 0 ] && C_RC=1
    RC=-1; TIMED_OUT=0; return
  fi
  KILL_OK=0
  run_capped "$T/src" "$T/$tag.out" "$T/$tag.err" "$TIMEOUT" ${envs[@]+"${envs[@]}"} "$T/$tag.bin"
  KILL_OK=1
}

# ── header ───────────────────────────────────────────────────────────────

SHA="$(git -C "$ROOT" rev-parse --short HEAD 2>/dev/null || echo '?')"
[ -n "$(git -C "$ROOT" status --porcelain -- lib bin runtime 2>/dev/null)" ] && SHA="$SHA+dirty"
[ -n "${MARCH_BIN:-}" ] && SHA="MARCH_BIN=$MARCH"
echo "triage: $BASE  (march $SHA, --opt $OPT)   artifacts: $T/"

# ── rung 1: compiler or program? ─────────────────────────────────────────

run_capped "$T/src" "$T/interp.out" "$T/interp.err" "$TIMEOUT" "$MARCH" "$BASE"
I_RC=$RC; I_TO=$TIMED_OUT
I_DESC="$(run_desc "$I_RC" "$T/interp.out" "$I_TO")"

REF_OUT=""; REF_RC="-"; REF_NAME=""
if [ -n "$EXPECT" ]; then
  REF_OUT="$EXPECT"; REF_NAME="expect"
  if [ "$I_TO" = 0 ]; then
    v="$(describe_vs "$EXPECT" - "$T/interp.out" "$I_RC" expect)"
    I_DESC="$I_DESC  → interp vs expect: ${v/compiled:/interp:}"
  fi
elif [ "$I_TO" = 0 ]; then
  REF_OUT="$T/interp.out"; REF_RC="$I_RC"; REF_NAME="interp"
fi
printf '%-9s: %s\n' interp "$I_DESC"

compile_and_run compiled --
M_CRC=$C_RC; M_RC=$RC; M_TO=$TIMED_OUT
DIVERGED=0; CRASHED=0; AGREE=0
if [ "$M_CRC" -ne 0 ]; then
  if [ "$M_CRC" = 124 ]; then M_DESC="COMPILE TIMED OUT after ${COMPILE_TIMEOUT}s"
  else M_DESC="COMPILE FAILED (exit $M_CRC): $(first_err "$T/compiled.compile.err" | cut -c1-70)"; fi
else
  M_DESC="$(run_desc "$M_RC" "$T/compiled.out" "$M_TO")"
  [ "$M_TO" = 0 ] && [ "$M_RC" -ge 128 ] && CRASHED=1
  if [ "$M_TO" = 1 ]; then
    [ -n "$REF_OUT" ] && DIVERGED=1
  elif [ -n "$REF_OUT" ]; then
    v="$(describe_vs "$REF_OUT" "$REF_RC" "$T/compiled.out" "$M_RC" "$REF_NAME")"
    if [ "$v" = MATCH ]; then M_DESC="$M_DESC  → outputs MATCH ($REF_NAME)"
    else M_DESC="$M_DESC  → outputs $v"; DIVERGED=1; fi
    # Both backends wrong the same way: no TIR pass is to blame (the
    # interpreter never sees TIR); the program, the expect file, or the
    # shared front end (parse/desugar/typecheck) is.
    if [ "$DIVERGED" = 1 ] && [ -n "$EXPECT" ] && [ "$I_TO" = 0 ] && \
       [ -z "$(first_diff "$T/interp.out" "$T/compiled.out")" ] && [ "$I_RC" = "$M_RC" ]; then
      AGREE=1; M_DESC="$M_DESC  (= interp)"
    fi
  else
    M_DESC="$M_DESC  → no reference (interp timed out; pass --expect OUT)"
  fi
fi
printf '%-9s: %s\n' compiled "$M_DESC"

# ── rung 2: which optional pass? ─────────────────────────────────────────

BLAMED=""; BLAMED_SW=""
if [ "$M_CRC" -ne 0 ]; then
  echo "switches : skipped (compile failed)"
elif [ -z "$REF_OUT" ]; then
  echo "switches : skipped (no reference output)"
elif [ "$DIVERGED" = 0 ] && [ "$DEEP" = 0 ]; then
  echo "switches : skipped (outputs match; --deep to force)"
elif [ "$AGREE" = 1 ] && [ "$DEEP" = 0 ]; then
  echo "switches : skipped (interp and compiled agree, both differ from expect: program, expect file or front end, not a TIR pass)"
else
  label="switches :"
  for sw in MARCH_NO_UNBOX=1 MARCH_NO_HOF_SPEC=1 MARCH_NO_INLINE_RC=1 --no-opt; do
    case "$sw" in
      --no-opt) tag=sw-no-opt; compile_and_run "$tag" -- --no-opt; what="TIR optimizer (Opt)" ;;
      *) tag="sw-$(echo "${sw%=1}" | tr 'A-Z_' 'a-z-')"; compile_and_run "$tag" "$sw"
         case "$sw" in
           MARCH_NO_UNBOX*) what="unboxing" ;;
           MARCH_NO_HOF_SPEC*) what="HOF specialisation (Hof_spec)" ;;
           *) what="inline RC fast path (Llvm_rc_inline)" ;;
         esac ;;
    esac
    if [ "$C_RC" -ne 0 ]; then r="compile failed (exit $C_RC)"
    elif [ "$TIMED_OUT" = 1 ]; then r="timed out"
    else
      v="$(describe_vs "$REF_OUT" "$REF_RC" "$T/$tag.out" "$RC" "$REF_NAME")"
      if [ "$v" = MATCH ]; then
        r="matches $REF_NAME"
        if [ "$DIVERGED" = 1 ] && [ -z "$BLAMED" ]; then
          BLAMED="$what"; BLAMED_SW="$sw"; r="$r      ← blamed: $what"; fi
      elif [ "$DIVERGED" = 1 ]; then r="still differs"
      else r="$v"; fi
    fi
    printf '%-10s %-21s → %s\n' "$label" "$sw" "$r"
    label=""
  done
  if [ "$DIVERGED" = 1 ] && [ -z "$BLAMED" ]; then
    echo "           no optional switch fixes it → mandatory pass (mono/defun/perceus/drop/escape/trmc); read the stage dumps"
  fi
fi

# ── rung 3: which stage? ─────────────────────────────────────────────────

run_capped "$T/dump" "$T/dump.out" "$T/dump.err" "$COMPILE_TIMEOUT" \
  MARCH_DUMP_TXT=all "$MARCH" --compile --opt "$OPT" "$BASE" -o "$T/dump/dump.bin"
# One pass over the (~1M-line, stdlib included) dump: a file per stage, its
# function names, and with --fn the matching functions' lines tagged by name.
# A function is every line from its `fn NAME(` header to the next header.
# --fn matches the printed base name exactly (specialisation suffix `$…`
# ignored): entry-module functions print unqualified (`go`), every other
# module's qualified (`JsonStream.go`).  Defun's `NAME$apply$N` wrappers are
# skipped: every stdlib nested `go` closure becomes one, and none is FN.
mkdir -p "$T/fn"
awk -v D="$T/stages" -v F="$T/fn" -v N="$FN" '
  /^===== tir-[^ ]+ =====$/ {
    if (out != "") { close(out); close(names); if (N != "") close(fnf) }
    stage = $2; print stage >> (D "/order")
    out = D "/" stage ".txt"; names = D "/" stage ".names"; fnf = F "/" stage ".raw"
    printf "" > names; if (N != "") printf "" > fnf
    keep = 0; next }
  out == "" { next }
  { print > out }
  /^fn / { name = $2; sub(/\(.*/, "", name); print name > names
           base = name; sub(/\$.*/, "", base); keep = (N != "" && base == N && name !~ /\$apply/) }
  keep { printf "%s\t%s\n", name, $0 > fnf }' "$T/dump.err"
STAGES=""
[ -f "$T/stages/order" ] && STAGES="$(cat "$T/stages/order")"

NEXT_DIFF=""
if [ -z "$STAGES" ]; then
  echo "stages   : no TIR dumps (compile stopped before lowering; see $T/dump.err)"
else
  : > "$T/stages/summary.txt"
  line=""; prev=""; out_lines=""
  for s in $STAGES; do
    sort -u "$T/stages/$s.names" > "$T/stages/$s.fns"
    n="$(nlines "$T/stages/$s.fns")"
    item="$s $n"
    if [ -n "$prev" ]; then
      comm -13 "$T/stages/$prev.fns" "$T/stages/$s.fns" > "$T/stages/$s.added"
      comm -23 "$T/stages/$prev.fns" "$T/stages/$s.fns" > "$T/stages/$s.removed"
      add="$(nlines "$T/stages/$s.added")"; rem="$(nlines "$T/stages/$s.removed")"
      ch=""; [ "$add" -gt 0 ] && ch="+$add"; [ "$rem" -gt 0 ] && ch="$ch${ch:+ }-$rem"
      [ -n "$ch" ] && item="$item ($ch)"
      { echo "== $prev → $s: +$add -$rem"
        sed 's/^/  + /' "$T/stages/$s.added"; sed 's/^/  - /' "$T/stages/$s.removed"
      } >> "$T/stages/summary.txt"
    else
      echo "== $s: $n fns" >> "$T/stages/summary.txt"
    fi
    if [ -n "$line" ] && [ $(( ${#line} + ${#item} )) -gt 88 ]; then
      out_lines="$out_lines$line"$'\n'; line=""
    fi
    line="$line${line:+ · }$item"; prev="$s"
  done
  out_lines="$out_lines$line"
  echo "$out_lines" | awk 'NR==1{print "stages   : " $0; next} {print "           " $0}'
  echo "           (names added/removed per stage: $T/stages/summary.txt)"

  if [ -n "$FN" ]; then
    # Sorted by name (so a pass that only reorders functions is no change),
    # fresh-name digits normalised (so one that only renumbers temporaries
    # is no change either).
    prev=""; first=""; first_prev=""; found_any=0
    for s in $STAGES; do
      sort -s -t "$(printf '\t')" -k1,1 "$T/fn/$s.raw" | cut -f2- \
        | sed -E "s/([\$'][A-Za-z_.]*)[0-9]+/\1N/g" > "$T/fn/$s.txt"
      [ -s "$T/fn/$s.txt" ] && found_any=1
      if [ -n "$prev" ] && [ -z "$first" ] && ! cmp -s "$T/fn/$prev.txt" "$T/fn/$s.txt"; then
        first="$s"; first_prev="$prev"; NEXT_DIFF="diff $T/fn/$prev.txt $T/fn/$s.txt"
      fi
      prev="$s"
    done
    if [ "$found_any" = 0 ]; then
      echo "           --fn $FN: no function of that name at any stage (other modules' fns are Mod.name)"
    elif [ -z "$first" ]; then
      echo "           --fn $FN: body unchanged across all stages"
    else
      note=""
      [ "$first" = tir-native-map-inline ] && note=" (that step includes Opt + DCE)"
      [ ! -s "$T/fn/$first.txt" ] && note=" (gone: inlined or pruned)$note"
      [ ! -s "$T/fn/$first_prev.txt" ] && note=" (first appears here)$note"
      echo "           --fn $FN: body first changes at $first$note"
    fi
  fi
fi

# ── rung 4: sanitizer ────────────────────────────────────────────────────

SAN_FINDINGS=0
if [ "$M_CRC" -ne 0 ]; then
  echo "sanitize : skipped (compile failed)"
elif [ "$CRASHED" = 0 ] && [ "$DEEP" = 0 ]; then
  echo "sanitize : not run (compiled run did not crash; pass --deep to force)"
else
  # detect_leaks=0: the runtime leaks some handles on purpose, so leak
  # reports are noise here; leaks are MARCH_TRACE_GC's job (below).
  compile_and_run san MARCH_SANITIZE=1 \
    "ASAN_OPTIONS=${ASAN_OPTIONS:-detect_leaks=0:halt_on_error=1:abort_on_error=0}"
  if [ "$C_RC" -ne 0 ]; then
    echo "sanitize : sanitizer build FAILED (exit $C_RC; $T/san.compile.err)"
  elif [ "$TIMED_OUT" = 1 ]; then
    echo "sanitize : sanitizer run timed out after ${TIMEOUT}s"
  else
    at="$(grep -nE 'AddressSanitizer|UndefinedBehaviorSanitizer|LeakSanitizer|runtime error:' "$T/san.err" | head -1 | cut -d: -f1)"
    if [ -n "$at" ]; then
      SAN_FINDINGS=1
      echo "sanitize : FINDINGS (exit $RC; full output $T/san.err):"
      tail -n "+$at" "$T/san.err" | head -20 | sed 's/^/           /'
    else
      echo "sanitize : clean (ASAN+UBSan, exit $RC)"
    fi
  fi
  echo "           leak symptom? cd $T/src && MARCH_TRACE_GC=1 $T/compiled.bin && $MARCH analyze-trace"
fi

# ── next ─────────────────────────────────────────────────────────────────

if [ "$M_CRC" -ne 0 ]; then
  if [ "$I_TO" = 0 ] && [ "$I_RC" -ne 0 ] && [ -s "$T/interp.err" ]; then
    NEXT="cat $T/interp.err   # the interpreter rejects it too: likely a program error"
  else
    NEXT="cat $T/compiled.compile.err"
  fi
elif [ "$SAN_FINDINGS" = 1 ]; then
  NEXT="less $T/san.err"
elif [ -n "$NEXT_DIFF" ] && { [ "$DIVERGED" = 1 ] || [ "$CRASHED" = 1 ] || [ -n "$FN" ]; }; then
  NEXT="$NEXT_DIFF"
elif [ -n "$BLAMED" ] && [ -n "$FN" ]; then
  NEXT="cd $T/src && $BLAMED_SW $MARCH --compile --opt $OPT $BASE   # $FN's TIR is unchanged by every stage: try --fn on its callers/callees"
elif [ -n "$BLAMED" ]; then
  NEXT="scripts/triage.sh $FILE --opt $OPT --fn <fn whose output is wrong>   # then diff its stages; repro: cd $T/src && $BLAMED_SW $MARCH --compile --opt $OPT $BASE"
elif [ "$AGREE" = 1 ]; then
  NEXT="diff $EXPECT $T/interp.out"
elif [ "$DIVERGED" = 1 ] || [ "$CRASHED" = 1 ]; then
  NEXT="scripts/triage.sh $FILE --opt $OPT --fn <suspect fn>   # stage dumps: $T/stages/"
elif [ -z "$REF_OUT" ]; then
  NEXT="scripts/triage.sh $FILE --expect <known-good stdout file>"
else
  NEXT="nothing diverged; if the interpreter is suspect, rerun with --expect OUT (or --deep)"
fi
[ -n "$STUCK" ] && echo "WARNING  : timed-out compiled run(s) ignored SIGTERM and were left running (pid$STUCK); not SIGKILLed on purpose, see run_capped"
echo "next     : $NEXT"
