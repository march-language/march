#!/usr/bin/env bash
# Regression test for scripts/affected.sh's path -> plan mapping.
#
# The dangerous failure of a test selector is a rule that is too narrow: a
# path that silently selects nothing.  These cases pin both directions: the
# narrow plans the script exists to produce, and the FULL fallback for paths
# it has no rule for.  Pure text, no build: runs in well under a second.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
fails=0
n=0

# expect <field> <substring|!substring> -- <paths...>
expect() {
  local field="$1" want="$2"; shift 3
  local line
  n=$((n + 1))
  line="$(MARCH_AFFECTED_QUIET=1 bash "$ROOT/scripts/affected.sh" --files "$@" | grep "^  $field:")"
  case "$want" in
    !*) if printf '%s' "$line" | grep -qF -- "${want#!}"; then
          echo "FAIL: [$*] $field should NOT contain '${want#!}': $line"; fails=$((fails + 1)); fi ;;
    *)  if ! printf '%s' "$line" | grep -qF -- "$want"; then
          echo "FAIL: [$*] $field should contain '$want': $line"; fails=$((fails + 1)); fi ;;
  esac
}

# Narrow plans.
expect suites "lsp utf16 jsonrpc incremental query_cli" -- lsp/lib/analysis.ml
expect suites "!codegen" -- lsp/lib/analysis.ml
expect oracles "(none)" -- lsp/lib/analysis.ml
expect suites "(none)" -- docs/types.md specs/todos/2026-01-01-x.md
expect checks "scripts/check-docs.sh" -- docs/types.md
expect suites "refinecheck" -- lib/refinecheck/refine_check.ml
expect suites "!ALL" -- lib/refinecheck/refine_check.ml
expect oracles "refine" -- lib/refinecheck/refine_check.ml
expect oracles "ir" -- lib/tir/perceus.ml
expect dune "@test/runtest-run_snapshots" -- lib/tir/perceus.ml
expect suites "!eval" -- lib/tir/perceus.ml
expect suites "eval" -- lib/eval/eval.ml
expect oracles "!ir" -- lib/eval/eval.ml
expect checks "scripts/check-runtime-sources.sh" -- runtime/march_runtime.c
expect checks "scripts/check-tree-sitter.sh" -- lib/parser/parser.mly
expect oracles "types" -- lib/typecheck/typecheck.ml
expect suites "stdlib_march" -- test/stdlib/test_list.march
expect suites "errors" -- test/errors/foo_1.expected
expect dune "@forge/test/runtest" -- forge/lib/cmd_add.ml
expect dune "@test/types-check" -- specs/lang/types/accept/t01_literals.march
expect dune "@test/bench_gate" -- bench/list_ops.march
expect dune "@test/bench_gate" -- test/test_bench_gate.ml

# Test modules resolve to the stanza that lists them in test/dune.
expect suites "codegen" -- test/test_trmc.ml
expect suites "compiler" -- test/test_cap_scope.ml
expect suites "test_jit" -- test/test_jit.ml

# The FULL fallback: no rule, shared helpers, test wiring, the language corpus.
expect suites "ALL" -- lib/some_new_library/x.ml
expect suites "ALL" -- test/test_helpers.ml
expect suites "ALL" -- test/test_properties.ml
expect suites "ALL" -- test/dune
expect suites "ALL" -- dune-project
expect suites "ALL" -- specs/lang/golden/foo.march
expect oracles "ir refine types" -- dune-project
# One FULL file makes the whole plan FULL, however narrow the others are.
expect suites "ALL" -- lsp/lib/analysis.ml lib/some_new_library/x.ml

if [ "$fails" -eq 0 ]; then
  echo "test-affected: all $n cases passed."
  exit 0
fi
echo "test-affected: $fails of $n cases FAILED."
exit 1
