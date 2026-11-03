#!/usr/bin/env bash
# error-one-turn.sh — the one-turn metric (diagnostics-depth plan §M1, triage plan D8).
#
# For each test/errors/<case>.march, give a model the program and the rendered
# `march --check` output, ask for the fixed program, and score it:
#
#   fixed     the answer passes `--check` (exit 0, or for a warning-only case, the
#             case's code is gone) and keeps the program's intent;
#   intent    it passes `--check` but fails the intent check below;
#   rejected  the compiler still rejects it;
#   noanswer  the model returned no program.
#
# The intent check is mechanical, so it is a proxy for the reviewer the plan asks
# for: every top-level name the program declares (fn, pfn, type, actor, mod,
# interface, protocol, extern) is still declared; at most max(4, 25%) of its
# non-blank lines are deleted or changed (no "fixed it by deleting main"); and a
# case carrying `-- EXPECT-FIXED-BY: <fragment>` must contain the fragment. Each
# case's directory keeps the prompt, the answer and the diff for a human to read.
#
# The program the model sees has its full-line `--` comments stripped (the corpus
# comments often explain the bug, which a real program would not) and its error
# rendered from that stripped text, so line numbers agree.
#
# Not a CI gate: run it before and after a diagnostics change and quote the delta.
#
# Usage:
#   scripts/error-one-turn.sh [options]             prepare, ask, score
#   scripts/error-one-turn.sh --prepare DIR [opts]  only write DIR/<case>/prompt.txt
#   scripts/error-one-turn.sh --score DIR           only score DIR/<case>/answer.txt
#
# Options:
#   --model M        model for the default ask command (default: haiku)
#   --jobs N         parallel model calls (default: 6)
#   --only P1,P2     only cases whose name starts with one of the prefixes
#   --dir DIR        working directory to keep (default: a temp dir, printed)
#
# The ask command reads the prompt on stdin and prints the answer. It defaults to
# `claude -p --model $MODEL`; set ONE_TURN_CMD to use anything else. `--prepare`
# plus `--score` lets the answers come from somewhere else entirely (a batch API,
# subagents): write each DIR/<case>/answer.txt, then score.
#
# Output: DIR/results.tsv (case, code, verdict) and a per-code table on stdout,
# worst codes first, with the overall score last.
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"
bin="${MARCH_BIN:-$root/_build/default/bin/main.exe}"
[ -x "$bin" ] || { echo "march binary not found at $bin (dune build --root . bin/main.exe)" >&2; exit 2; }
# The compiler reads the stdlib staged under _build, which a targeted `dune build bin/main.exe`
# does not refresh; a stale copy adds errors from generated code to every protocol program.
if [ -z "${MARCH_BIN:-}" ] && [ -n "$(diff -rq stdlib "$root/_build/default/stdlib" 2>/dev/null | grep -v '^Only in ')" ]; then
  echo "_build/default/stdlib is stale; restage it first (dune build --root . with the stdlib targets)" >&2; exit 2
fi

model=haiku jobs=6 only="" dir="" mode=all
while [ $# -gt 0 ]; do
  case "$1" in
    --model) model="$2"; shift 2 ;;
    --jobs) jobs="$2"; shift 2 ;;
    --only) only="$2"; shift 2 ;;
    --dir) dir="$2"; shift 2 ;;
    --prepare) mode=prepare; dir="$2"; shift 2 ;;
    --score) mode=score; dir="$2"; shift 2 ;;
    --score-one) mode=score-one; dir="$2"; shift 2 ;;  # internal: one case dir
    -h|--help) sed -n '2,/^set -euo/p' "$0" | sed '$d; s/^# \{0,1\}//'; exit 0 ;;
    *) echo "unknown option: $1 (--help)" >&2; exit 2 ;;
  esac
done
[ -n "$dir" ] || dir="$(mktemp -d "${TMPDIR:-/tmp}/one-turn.XXXXXX")"
mkdir -p "$dir"
dir="$(cd "$dir" && pwd)"
[ "$mode" = score-one ] || rm -f "$dir"/*/verdict
if [ -n "${ONE_TURN_HOME:-}" ]; then home="$ONE_TURN_HOME"   # a --score-one child shares its parent's
else home="$(mktemp -d)"; mkdir -p "$home/.cache"; trap 'rm -rf "$home"' EXIT; fi

check() {  # check <dir> <file>: writes <dir>/<file>.out, prints the exit code
  local code=0
  (cd "$1" && HOME="$home" "$bin" --check "$2" > "$2.out" 2>&1) || code=$?
  echo "$code"
}

selected() {  # selected <case>
  [ -z "$only" ] && return 0
  local p
  for p in ${only//,/ }; do case "$1" in "$p"*) return 0 ;; esac; done
  return 1
}

prepare() {
  local f name d code
  for f in test/errors/*.march; do
    name="$(basename "$f" .march)"
    selected "$name" || continue
    d="$dir/$name"; mkdir -p "$d"
    grep -v -E '^[[:space:]]*--' "$f" > "$d/main.march" || true
    code="$(check "$d" main.march)"
    if [ "$code" = 0 ] && ! grep -q -E '^-- (ERROR|WARNING)' "$d/main.march.out"; then
      cp "$f" "$d/main.march"   # the comments carried the error (a doc-comment case); keep them
      code="$(check "$d" main.march)"
    fi
    echo "$code" > "$d/orig.code"
    grep -o -E -- '-- EXPECT-FIXED-BY: .*' "$f" | sed 's/^-- EXPECT-FIXED-BY: //' > "$d/fixed-by" || true
    {
      echo "The March compiler reports a problem with this program. Here is the program and the"
      echo "compiler's output. Reply with the complete corrected program in one \`\`\`march code"
      echo "block. Keep what the program is meant to do; change only what the report requires."
      echo
      echo '```march'
      cat "$d/main.march"
      echo '```'
      echo
      echo "Compiler output of \`march --check main.march\`:"
      echo
      echo '```'
      cat "$d/main.march.out"
      echo '```'
    } > "$d/prompt.txt"
  done
}

ask() {
  local cmd="${ONE_TURN_CMD:-claude -p --model $model}"
  find "$dir" -mindepth 2 -maxdepth 2 -name prompt.txt | sort | while read -r p; do
    [ -s "$(dirname "$p")/answer.txt" ] || echo "$p"
  done | xargs -P "$jobs" -I{} sh -c '
    d=$(dirname "$1")
    $2 < "$1" > "$d/answer.tmp" 2> "$d/answer.err" && mv "$d/answer.tmp" "$d/answer.txt"
    printf "." >&2' _ {} "$cmd"
  echo >&2
}

decls() {  # the top-level names a program declares
  grep -o -E '^[[:space:]]*(fn|pfn|type|actor|mod|interface|protocol|extern)[[:space:]]+[A-Za-z_][A-Za-z0-9_]*' "$1" \
    | awk '{print $2}' | sort -u
}

score_one() {  # score_one <case dir>: prints the verdict
  local d="$1" orig_code code ans="$1/answer.txt" n changed limit name frag
  [ -s "$ans" ] || { echo noanswer; return; }
  # The last ```march (or bare ```) block; the whole answer if there is none.
  awk '/^```/{ if (inb) { inb=0; last=buf; found=1 } else { inb=1; buf="" } next }
       inb { buf = buf $0 "\n" }
       END { if (found) printf "%s", last; else exit 1 }' "$ans" > "$d/fixed.march" \
    || cp "$ans" "$d/fixed.march"
  [ -s "$d/fixed.march" ] || { echo noanswer; return; }
  code="$(check "$d" fixed.march)"
  orig_code="$(cat "$d/orig.code")"
  name="$(basename "$d")"
  if [ "$orig_code" = 0 ]; then
    # A warning-only case: fixed when its own code is gone.
    if grep -q -E "\[${name%_*}(:[^]]*)?\]\$" "$d/fixed.march.out"; then echo rejected; return; fi
  elif [ "$code" != 0 ]; then
    echo rejected; return
  fi
  diff "$d/main.march" "$d/fixed.march" > "$d/diff" || true
  if [ -n "$(comm -23 <(decls "$d/main.march") <(decls "$d/fixed.march"))" ]; then echo intent; return; fi
  n="$(grep -c -v -E '^[[:space:]]*$' "$d/main.march" || true)"
  changed="$(grep -c -E '^< *[^ ]' "$d/diff" || true)"
  limit=$(( n / 4 > 4 ? n / 4 : 4 ))
  if [ "$changed" -gt "$limit" ]; then echo intent; return; fi
  while IFS= read -r frag; do
    [ -z "$frag" ] || grep -q -F -- "$frag" "$d/fixed.march" || { echo intent; return; }
  done < "$d/fixed-by"
  echo fixed
}

score() {
  local d name
  for d in "$dir"/*/; do
    d="${d%/}"; name="$(basename "$d")"
    [ -f "$d/prompt.txt" ] || continue
    if selected "$name"; then echo "$d"; fi
  done | xargs -P "$jobs" -I{} env MARCH_BIN="$bin" ONE_TURN_HOME="$home" "$0" --score-one {}
  : > "$dir/results.tsv"
  for d in "$dir"/*/; do
    d="${d%/}"; name="$(basename "$d")"
    if [ ! -f "$d/verdict" ] || ! selected "$name"; then continue; fi
    printf '%s\t%s\t%s\n' "$name" "${name%_*}" "$(cat "$d/verdict")" >> "$dir/results.tsv"
  done
  awk -F'\t' '
    { n[$2]++; if ($3 == "fixed") ok[$2]++; v[$3]++; total++ }
    END {
      for (c in n) printf "%5.0f%%  %3d/%-3d  %s\n", 100 * ok[c] / n[c], ok[c], n[c], c | "sort -n"
      close("sort -n")
      printf "\nfixed %d/%d (%.1f%%)   intent %d   rejected %d   noanswer %d\n",
        v["fixed"], total, total ? 100 * v["fixed"] / total : 0, v["intent"], v["rejected"], v["noanswer"]
    }' "$dir/results.tsv"
  echo "per-case verdicts: $dir/results.tsv" >&2
}

case "$mode" in
  prepare) prepare; echo "prompts in $dir/<case>/prompt.txt; write answer.txt beside each, then --score $dir" >&2 ;;
  score) score ;;
  score-one) rm -f "$dir/verdict"; score_one "$dir" > "$dir/verdict.tmp" && mv "$dir/verdict.tmp" "$dir/verdict" ;;
  all) prepare; ask; score ;;
esac
