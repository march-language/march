#!/usr/bin/env bash
# Pick the test suites, oracles and checks a change actually needs.
#
# Every alcotest runner links nearly every march_* library (test/dune), so dune
# cannot say which suites a change can reach: any lib edit relinks them all.
# This script maps changed PATHS to suites by hand instead, and treats any path
# it has no rule for as "run everything".  It is a dev-loop tool: CI still runs
# the whole matrix, and the full suite still runs before merge (CLAUDE.md).
#
#   scripts/affected.sh                  # print the plan for this branch
#   scripts/affected.sh --run            # ... and run it (quick suites, -q)
#   scripts/affected.sh --run --full     # ... without -q (Slow tests too)
#   scripts/affected.sh --run --no-oracles
#   scripts/affected.sh --base REF       # diff against merge-base(HEAD, REF); default origin/main
#   scripts/affected.sh --files a b ...  # plan for an explicit path list (scripts/test-affected.sh)
#
# Changed files = everything differing from the merge-base, committed or not,
# plus untracked files.  The plan is the UNION over files.
#
# Oracles run through scripts/oracle-base.sh, which caches the base baseline
# by commit, so only the check half runs on each iteration.
#
# Keep the rules below in step with what the suites test.  A rule that is too
# narrow is a silent hole, so when in doubt route the path to FULL.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BASE_REF=origin/main
RUN=0
QUICK=-q
ORACLES_ON=1
FILES=()
EXPLICIT=0
BASE_SHA=""

while [ $# -gt 0 ]; do
  case "$1" in
    --run) RUN=1; shift ;;
    --full) QUICK=""; shift ;;
    --no-oracles) ORACLES_ON=0; shift ;;
    --base) BASE_REF="${2:?--base needs a ref}"; shift 2 ;;
    --files) EXPLICIT=1; shift; while [ $# -gt 0 ]; do FILES+=("$1"); shift; done ;;
    -h|--help) sed -n '2,/^set -uo/p' "$0" | sed '$d' | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
  esac
done

if [ "$EXPLICIT" -eq 0 ]; then
  BASE_SHA="$(git -C "$ROOT" merge-base HEAD "$BASE_REF" 2>/dev/null)" \
    || { echo "FATAL: no merge-base between HEAD and $BASE_REF (git fetch?)" >&2; exit 2; }
  while IFS= read -r f; do [ -n "$f" ] && FILES+=("$f"); done < <(
    { git -C "$ROOT" diff --name-only "$BASE_SHA"
      git -C "$ROOT" ls-files --others --exclude-standard; } | sort -u)
fi

SUITES=""   # run-tests.sh suite names
DUNE=""     # dune aliases
ORACLES=""  # oracle-base.sh oracle names
CHECKS=""   # standalone check scripts
NOTES=""    # things this script will not run, said out loud
FULL=0
REASONS=""

add() { # <var> <words...>
  local var="$1"; shift
  eval "$var=\"\${$var} $*\""
}
note() { NOTES="${NOTES}$1"$'\n'; }
reason() { REASONS="${REASONS}  $1 -> $2"$'\n'; }

ALL_LSP="lsp utf16 jsonrpc incremental query_cli"

# Runner owning a test/<module>.ml: the (name ...) of the test/dune stanza whose
# (modules ...) lists it.  Prints a run-tests.sh suite name, a dune alias
# prefixed with @, or nothing.
owner_of_test_module() {
  local m="$1" stanza
  stanza="$(awk -v m="$m" '
    /^\((test|tests|executable|executables|library|rule)[ )]*/ { k = $1; sub(/^\(/, "", k) }
    /\(name [A-Za-z0-9_]+\)/ { match($0, /\(name [A-Za-z0-9_]+\)/); n = substr($0, RSTART + 6, RLENGTH - 7) }
    /\(modules / { line = " " $0 " "; gsub(/[()]/, " ", line); if (index(line, " " m " ") > 0) { print (k == "executable" ? "exe:" : "") n; exit } }
  ' "$ROOT/test/dune")"
  case "$stanza" in
    exe:test_bench_gate) echo @test/bench_gate ;;   # a plain executable, run by its own rule
    # Other plain executables are driven by rules and aliases this script does
    # not model (no runtest-<name> alias exists): run everything.
    exe:*) echo FULL ;;
    march_test_compiler) echo compiler ;;
    march_test_eval) echo eval ;;
    march_test_codegen) echo codegen ;;
    march_test_stdlib_suite) echo stdlib ;;
    march_test_snapshots|run_snapshots) echo @test/runtest-run_snapshots ;;
    march_test_helpers) echo FULL ;;
    run_compiler|run_eval|run_codegen|run_stdlib|run_errors|test_stdlib_march|test_jit|test_refinecheck)
      echo "${stanza#run_}" ;;
    "") ;;
    *) echo "@test/runtest-$stanza" ;;
  esac
}

classify() {
  local f="$1" o
  case "$f" in
    # ── docs and design records: lint only ───────────────────────────────
    *.md|docs/*|specs/progress/*|specs/todos/*|specs/plans/*|specs/impl/*|specs/features/*)
      add CHECKS scripts/check-docs.sh; reason "$f" "doc-lint" ;;
    specs/lang/types/*)
      add DUNE @test/types-check; add ORACLES types; reason "$f" "@types-check, types oracle" ;;
    specs/lang/*)
      FULL=1; reason "$f" "FULL (language corpus)" ;;

    # ── front end: reaches every suite ───────────────────────────────────
    lib/lexer/*|lib/parser/*)
      add SUITES compiler eval codegen stdlib stdlib_march errors $ALL_LSP
      add CHECKS scripts/check-tree-sitter.sh; add ORACLES types ir
      reason "$f" "front-end suites, tree-sitter, types+ir oracles" ;;
    lib/ast/*|lib/desugar/*)
      add SUITES compiler eval codegen stdlib stdlib_march errors $ALL_LSP; add ORACLES types ir
      reason "$f" "front-end suites, types+ir oracles" ;;
    lib/typecheck/*|lib/modules/*|lib/resolver/*)
      add SUITES compiler eval codegen stdlib stdlib_march errors refinecheck $ALL_LSP
      add ORACLES types refine
      reason "$f" "front-end suites + refinecheck, types+refine oracles" ;;
    lib/errors/*)
      add SUITES compiler errors $ALL_LSP; add ORACLES types
      reason "$f" "compiler, errors, lsp; types oracle" ;;

    # ── back end ──────────────────────────────────────────────────────────
    lib/tir/*|lib/codegen/*)
      add SUITES codegen stdlib compiler test_jit; add DUNE @test/runtest-run_snapshots
      add ORACLES ir; add CHECKS "scripts/determinism-oracle.sh"
      reason "$f" "codegen, stdlib, compiler, jit, snapshots; ir + determinism oracles" ;;
    runtime/*)
      add SUITES codegen stdlib test_jit
      add CHECKS scripts/check-runtime-sources.sh scripts/check-actor-rc-stores.sh
      note "runtime: two-node and sanitizer sweeps not run (scripts/two-node.sh, specs/lang/golden/sanitize.sh)"
      reason "$f" "codegen, stdlib, jit; runtime manifest + actor-rc checks" ;;
    lib/jit/*|lib/repl/*)
      add SUITES test_jit compiler eval; reason "$f" "jit, compiler, eval" ;;
    lib/eval/*)
      add SUITES eval stdlib stdlib_march compiler
      note "lib/eval: the ir oracle cannot see the interpreter; bench/run_interp_bench.sh --modes interp for perf"
      reason "$f" "eval, stdlib, stdlib_march, compiler" ;;

    # ── checkers and tooling libraries ────────────────────────────────────
    lib/refinecheck/*|lib/refine/*)
      add SUITES refinecheck compiler errors; add ORACLES refine
      reason "$f" "refinecheck, compiler, errors; refine oracle" ;;
    lib/caps/*|lib/ctxesc/*|lib/effects/*|lib/cas/*|lib/driver/*)
      add SUITES compiler codegen; reason "$f" "compiler, codegen" ;;
    lib/search/*|lib/query/*)
      add SUITES compiler query_cli lsp; reason "$f" "compiler, query_cli, lsp" ;;
    lib/format/*|lib/lint/*|lib/refactor/*)
      add SUITES compiler lsp; reason "$f" "compiler, lsp" ;;
    lib/forge/*|forge/*)
      add DUNE @forge/test/runtest; add SUITES compiler; reason "$f" "forge tests, compiler" ;;
    lsp/*)
      add SUITES $ALL_LSP; reason "$f" "lsp suites" ;;
    bin/*)
      add SUITES compiler codegen errors test_jit; reason "$f" "compiler, codegen, errors, jit" ;;

    # ── stdlib: every program reads it ────────────────────────────────────
    stdlib/*)
      add SUITES stdlib stdlib_march eval codegen compiler errors
      add ORACLES refine ir; add CHECKS scripts/check-docs.sh
      reason "$f" "stdlib, stdlib_march, eval, codegen, compiler, errors; refine+ir oracles" ;;

    # ── tests and fixtures: the runner that owns them ─────────────────────
    test/native/*|test/snapshots/*)
      add SUITES codegen; add DUNE @test/runtest-run_snapshots; add ORACLES ir
      reason "$f" "codegen, snapshots; ir oracle" ;;
    test/stdlib/*) add SUITES stdlib_march; reason "$f" "stdlib_march" ;;
    test/errors/*) add SUITES errors; reason "$f" "errors" ;;
    test/two_node/*)
      note "two-node: scripts/two-node.sh <scenario> (not run here)"; reason "$f" "two-node (note only)" ;;
    test/dune) FULL=1; reason "$f" "FULL (test wiring)" ;;
    test/*.ml)
      o="$(owner_of_test_module "$(basename "$f" .ml)")"
      case "$o" in
        "") FULL=1; reason "$f" "FULL (no owning stanza found)" ;;
        FULL) FULL=1; reason "$f" "FULL (shared test helper)" ;;
        @*) add DUNE "$o"; reason "$f" "$o" ;;
        *) add SUITES "$o"; reason "$f" "$o" ;;
      esac ;;
    bench/*)
      add DUNE @test/bench_gate
      note "bench: timing not checked; run it compiled (specs/benchmarks.md)"
      reason "$f" "bench gate" ;;

    # ── everything with its own check ─────────────────────────────────────
    tree-sitter-march/*|zed-march/*)
      add CHECKS scripts/check-tree-sitter.sh; reason "$f" "tree-sitter" ;;
    scripts/run-tests.sh|scripts/test-run-tests.sh)
      add CHECKS scripts/test-run-tests.sh; reason "$f" "test-run-tests.sh" ;;
    scripts/affected.sh|scripts/test-affected.sh)
      add CHECKS scripts/test-affected.sh; reason "$f" "test-affected.sh" ;;
    scripts/determinism-oracle.sh)
      add CHECKS "scripts/determinism-oracle.sh"; reason "$f" "determinism oracle" ;;
    scripts/ir-oracle.sh) add ORACLES ir; reason "$f" "ir oracle" ;;
    scripts/oracle-base.sh) add ORACLES ir; reason "$f" "ir oracle (exercises oracle-base.sh)" ;;
    scripts/refine-oracle.sh) add ORACLES refine; reason "$f" "refine oracle" ;;
    scripts/types-oracle.sh) add ORACLES types; reason "$f" "types oracle" ;;
    scripts/check-*.sh) add CHECKS "$f"; reason "$f" "itself" ;;
    scripts/*|.github/*|.claude/*|editors/*|tools/*|share/*|examples/*|demo/*|demo_app/*)
      note "$f: no local suite covers it; review by hand (CI covers .github/demo/examples)"
      reason "$f" "none (note)" ;;

    # ── anything else: run everything ─────────────────────────────────────
    *) FULL=1; reason "$f" "FULL (no rule)" ;;
  esac
}

for f in ${FILES[@]+"${FILES[@]}"}; do classify "$f"; done

uniq_words() { printf '%s\n' $1 | sed '/^$/d' | awk '!seen[$0]++' | tr '\n' ' ' | sed 's/ $//'; }

if [ "$FULL" -eq 1 ]; then
  SUITES="ALL"
  ORACLES="ir refine types"
fi
SUITES="$(uniq_words "$SUITES")"
DUNE="$(uniq_words "$DUNE")"
ORACLES="$(uniq_words "$ORACLES")"
CHECKS="$(uniq_words "$CHECKS")"

echo "affected: ${#FILES[@]} changed file(s)${BASE_SHA:+ vs merge-base ${BASE_SHA:0:10} ($BASE_REF)}"
echo "  suites:  ${SUITES:-(none)}"
echo "  dune:    ${DUNE:-(none)}"
echo "  oracles: ${ORACLES:-(none)}"
echo "  checks:  ${CHECKS:-(none)}"
if [ -n "$NOTES" ]; then
  echo "  not run:"
  printf '%s' "$NOTES" | sed '/^$/d' | awk '!seen[$0]++' | sed 's/^/    - /'
fi
if [ -n "$REASONS" ] && [ "${MARCH_AFFECTED_QUIET:-}" = "" ]; then
  echo "why:"
  printf '%s' "$REASONS" | head -40
  n=$(printf '%s' "$REASONS" | wc -l | tr -d ' ')
  [ "$n" -gt 40 ] && echo "  ... ($((n - 40)) more)"
fi

[ "$RUN" -eq 1 ] || exit 0

rc=0
step() { # <label> <cmd...>
  echo ""; echo "######## $1"
  shift
  "$@" || { echo "!! FAILED: $*" >&2; rc=1; }
}
cd "$ROOT" || exit 2
for c in $CHECKS; do
  case "$c" in
    scripts/determinism-oracle.sh) step "$c --corpus small" bash "$c" --corpus small ;;
    *) step "$c" bash "$c" ;;
  esac
done
if [ "$SUITES" = ALL ]; then
  step "run-tests.sh ${QUICK}" bash scripts/run-tests.sh $QUICK
elif [ -n "$SUITES" ]; then
  # shellcheck disable=SC2086
  step "run-tests.sh ${QUICK} $SUITES" bash scripts/run-tests.sh $QUICK $SUITES
fi
for a in $DUNE; do
  if [ "$a" = @test/types-check ]; then
    # Without --force this alias is an empty check that exits 0 (CLAUDE.md).
    step "dune build $a --force" dune build --root . "$a" --force
  else
    step "dune build $a" dune build --root . "$a"
  fi
done
if [ -n "$ORACLES" ] && [ "$ORACLES_ON" -eq 1 ]; then
  # shellcheck disable=SC2086
  step "oracle-base.sh $ORACLES" bash scripts/oracle-base.sh --base "$BASE_REF" $ORACLES
fi
echo ""
[ "$rc" -eq 0 ] && echo "affected: all selected steps passed." || echo "affected: one or more steps FAILED."
exit "$rc"
