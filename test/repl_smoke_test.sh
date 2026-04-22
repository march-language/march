#!/usr/bin/env bash
# test/repl_smoke_test.sh — REPL regression smoke test
#
# Run with: ./test/repl_smoke_test.sh
# Or: bash test/repl_smoke_test.sh [path/to/march.exe]
#
# Exit codes:
#   0 — all expected-pass tests passed
#   1 — at least one expected-pass test failed
#
# KNOWN ISSUES (tracked as expected-fail / xfail):
#
# 1. Cross-fragment stdlib function declarations (JIT limitation):
#    When a REPL session has 2+ expressions, the second fragment may call a
#    stdlib function (e.g. List.reverse$List_Int) that was compiled and
#    dlopen'd in the first fragment. LLVM IR requires all referenced functions
#    to be declared in the current module, even if they resolve at runtime via
#    RTLD_GLOBAL + "-undefined dynamic_lookup". Without `declare` stubs for
#    cross-fragment calls, clang rejects the IR with "use of undefined value".
#    Root cause: ctx.compiled_fns tracks which stdlib fns were compiled but
#    does NOT emit `declare` stubs in subsequent fragments that call them.
#    Fix needed: lib/jit/repl_jit.ml + lib/tir/llvm_emit.ml: track fn
#    signatures (fn_declare_str is already in llvm_emit.ml) and emit them as
#    declares when the fn is in compiled_fns but not new_fns.
#    Affects: any multi-expression REPL session where expr N+1 calls a stdlib
#    function that was monomorphized and compiled in fragment 0.
#
# 2. Heap-allocated REPL results print as '#<value at 0xADDR>' because the
#    pretty-printer (march_value_to_string) is not yet wired up in run_expr.
#    Affects: strings, lists, tuples, ADTs returned by expressions (not let bindings).

set -euo pipefail

MARCH="${1:-$(dirname "$0")/../_build/default/bin/main.exe}"

if [[ ! -x "$MARCH" ]]; then
  echo "ERROR: march binary not found at $MARCH"
  echo "Run 'dune build' first or pass path as first argument."
  exit 1
fi

PASS=0
FAIL=0
XFAIL=0

if [[ -t 1 ]]; then
  GREEN='\033[0;32m'; RED='\033[0;31m'; YELLOW='\033[0;33m'; RESET='\033[0m'
else
  GREEN=''; RED=''; YELLOW=''; RESET=''
fi

# run_test NAME INPUT EXPECTED_REGEX [xfail]
#
# EXPECTED_REGEX is matched against the full REPL output (including prompts).
# Use anchored patterns like "= 3" (REPL outputs "= VALUE" for expression results)
# or "val x = 3" for let bindings. Avoid short patterns that match in error messages.
run_test() {
  local name="$1" input="$2" pattern="$3" xfail="${4:-}"
  local output
  output=$(printf '%s\n' "$input" | "$MARCH" 2>&1 || true)
  if echo "$output" | grep -qE "$pattern"; then
    if [[ -z "$xfail" ]]; then
      echo -e "${GREEN}[PASS]${RESET} $name"
      PASS=$((PASS+1))
    else
      echo -e "${GREEN}[XPASS]${RESET} $name (expected to fail but passed — remove xfail?)"
      PASS=$((PASS+1))
    fi
  else
    if [[ -z "$xfail" ]]; then
      echo -e "${RED}[FAIL]${RESET} $name"
      echo "       input:    $(echo "$input" | head -1)"
      echo "       expected: $pattern"
      echo "       got:      $(echo "$output" | grep -v '^March REPL' | head -3)"
      FAIL=$((FAIL+1))
    else
      echo -e "${YELLOW}[XFAIL]${RESET} $name (known issue)"
      XFAIL=$((XFAIL+1))
    fi
  fi
}

echo "=== March REPL smoke tests ==="
echo "Binary: $MARCH"
echo ""

# ──────────────────────────────────────────────────────────────────────────────
echo "--- Basic expressions (single REPL fragment, stdlib compiled once) ---"
# ──────────────────────────────────────────────────────────────────────────────

# REPL prints "= VALUE" for expression results.
# Note: each test is a fresh REPL instance so the stdlib is compiled fresh each time.

run_test "int literal"       "42"         "= 42$"
run_test "int arithmetic"    "1 + 2"      "= 3$"
run_test "nested arithmetic" "2 * 3 + 1"  "= 7$"
run_test "subtraction"       "10 - 3"     "= 7$"
run_test "division"          "10 / 2"     "= 5$"
run_test "modulo"            "7 % 3"      "= 1$"
run_test "bool true"         "true"       "= true$"
run_test "bool false"        "false"      "= false$"
run_test "int comparison"    "3 > 2"      "= true$"
run_test "int equality"      "4 == 4"     "= true$"
run_test "float literal"     "3.14"       "= 3\.14$"
run_test "float arithmetic"  "1.5 +. 2.5" "= 4$"
run_test "if true"           "if true then 1 else 2"      "= 1$"
run_test "if false"          "if false then 1 else 2"     "= 2$"
run_test "if comparison"     "if 3 > 2 then 100 else 200" "= 100$"

# ──────────────────────────────────────────────────────────────────────────────
echo ""
echo "--- Let bindings (single fragment) ---"
# REPL prints "val NAME = VALUE" for let bindings.
# ──────────────────────────────────────────────────────────────────────────────

run_test "let int"    "let x = 42"             "val x = 42"
run_test "let bool"   "let b = true"           "val b = true"
run_test "let arith"  "let y = 3 * 7"          "val y = 21"
run_test "let fn"     "let f = fn x -> x + 1"  "val f = "

# ──────────────────────────────────────────────────────────────────────────────
echo ""
echo "--- Lambda and closures (single fragment) ---"
# ──────────────────────────────────────────────────────────────────────────────

run_test "immediate lambda"   "(fn x -> x + 1)(5)"        "= 6$"
run_test "lambda two args"    "(fn (a, b) -> a + b)(3, 4)" "= 7$"
# Match syntax in March: match EXPR do PATTERN -> BODY end (no 'with', no leading '|')
run_test "match option" \
  $'match Some(42) do\n  Some(x) -> x\n  None -> 0\nend' \
  "= 42$"
run_test "match int" \
  $'match 42 do\n  _ -> 1\nend' \
  "= 1$"

# ──────────────────────────────────────────────────────────────────────────────
echo ""
echo "--- Cross-line variable capture (the original bug: single REPL session) ---"
# These require multiple lines piped to ONE REPL instance.
# ──────────────────────────────────────────────────────────────────────────────

run_test "cross-line simple arithmetic" \
  $'let x = 10\nlet y = x + 5\ny' \
  "val y = 15"

run_test "cross-line fn as HOF arg (original bug)" \
  $'let f = fn x -> x * 2\nlet l = [1,2,3]\nList.map(l, f)' \
  "2, 4, 6"

run_test "cross-line fold with cross-line fn" \
  $'let add = fn (a, x) -> a + x\nList.fold_left([1,2,3,4,5], 0, add)' \
  "= 15$"

# ──────────────────────────────────────────────────────────────────────────────
echo ""
echo "--- Stdlib functions (single fragment — first expression in fresh REPL) ---"
# These all work as the first expression because stdlib is compiled once in frag 0.
# ──────────────────────────────────────────────────────────────────────────────

run_test "List.map"      "List.map([1,2,3], fn x -> x * 2)"            "= \[2, 4, 6\]$"
run_test "List.filter"   "List.filter([1,2,3,4], fn x -> x > 2)"      "= \[3, 4\]$"
# fold_left: list is first arg, accumulator second
run_test "List.fold_left" "List.fold_left([1,2,3], 0, fn (a, x) -> a + x)" "= 6$"
run_test "List.length"   "List.length([1,2,3])"                        "= 3$"
run_test "List.head"     "List.head([1,2,3])"                          "= 1$"
run_test "List.reverse"  "List.reverse([1,2,3])"                       "= \[3, 2, 1\]$"
run_test "List.any"      "List.any([1,2,3], fn x -> x > 2)"            "= true$"
run_test "List.all"      "List.all([1,2,3], fn x -> x > 0)"            "= true$"
# String.length is in the string module as string_byte_length, not String.length
run_test "string_byte_length" 'string_byte_length("hello")'            "= 5$"
run_test "String.concat"      '"hello" ++ " " ++ "world"'              '= "hello world"$'
run_test "int_to_string"      "int_to_string(42)"                      '= "42"$'
# println side-effects to stdout; march_println returns int (chars written), not Unit
# so the REPL shows "= 1" rather than "= ()".
run_test "println"       'println("hello")'                             "= 1$"

# ──────────────────────────────────────────────────────────────────────────────
echo ""
echo "--- Interface methods (Ord, Hash) ---"
# ──────────────────────────────────────────────────────────────────────────────

run_test "compare ints"    "compare(1, 2)"          "= -1$"
run_test "compare equal"   "compare(5, 5)"          "= 0$"
run_test "hash int"        "hash(42)"               "= "
run_test "show int"        "show(42)"               '= "42"$'
run_test "eq ints"         "eq(3, 3)"               "= true$"

# ──────────────────────────────────────────────────────────────────────────────
echo ""
echo "--- Map stdlib (uses Ord interface) ---"
# ──────────────────────────────────────────────────────────────────────────────

run_test "Map.empty"        "Map.empty()"                             "HamtMap|#<tag"
run_test "Map.insert"       'Map.insert(Map.empty(), "k", 1, fn a -> fn b -> a < b)' \
  "HamtMap|HLeaf"

# ──────────────────────────────────────────────────────────────────────────────
echo ""
echo "--- Summary ---"
echo -e "${GREEN}PASS: $PASS${RESET}  ${RED}FAIL: $FAIL${RESET}  ${YELLOW}XFAIL (known issues): $XFAIL${RESET}"

if [[ $FAIL -gt 0 ]]; then
  echo -e "${RED}FAILED${RESET} — $FAIL unexpected failure(s)."
  exit 1
else
  echo -e "${GREEN}OK${RESET} — all expected-pass tests passed."
  exit 0
fi
