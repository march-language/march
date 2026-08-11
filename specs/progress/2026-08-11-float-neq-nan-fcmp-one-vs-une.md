# Compiled `!=` on NaN floats diverged from the interpreter

**Fixed:** 2026-08-11

## Bug

`lib/tir/llvm_emit.ml`'s float comparison codegen (the `fpred` match inside
the `is_int_cmp` fallback, around line 1556) mapped March's `!=` to LLVM's
`fcmp one` (ordered-and-not-equal). Per IEEE 754 and the LLVM LangRef, `one`
is `false` whenever either operand is NaN (it requires both operands to be
ordered, i.e. non-NaN).

`lib/eval/eval.ml` implements float `!=` via OCaml's polymorphic `<>`
(`cmp_op` at line 3921), under which `nan <> nan` is `true` — OCaml's
built-in comparison operators use a total order where NaN compares unequal
to everything, including itself, under `<>`/`=`, unlike `Stdlib.compare`.

Net effect: `nan != nan` printed `false` compiled, `true` interpreted — a
backend-observable, program-value-dependent divergence for any float that
could be NaN (parsed input, `0.0 /. 0.0`-shaped computations that escape the
runtime's checked-div-by-zero guard via other means, SIMD lane extraction,
etc).

## Fix

Changed the `"!="` arm of the float `fpred` match from `"one"` to `"une"`
(unordered-or-not-equal) — `une` is `true` whenever the operands differ OR
either is NaN, matching `<>`. `"=="` correctly stayed `"oeq"` (both sides
already agree: `nan == nan` is `false` on both backends, and `oeq` requires
ordered-and-equal).

## Verification

- Reproduced pre-fix: interpreted `println(x != x)` for `x` bound via
  `string_to_float("nan")` (avoids the checked-fdiv abort that `0.0 /. 0.0`
  hits on both backends) printed `true`; compiled printed `false`.
- Added `test_compiled_float_nan_neq_parity` in `test/test_codegen.ml`
  (`assert_compiled_interp_parity`), asserting `nan != nan` and `nan != 1.0`
  both print `true` on interpreted AND compiled output. Confirmed it fails
  pre-fix (compiled prints `false\ntrue`) and passes post-fix.
- Grepped `test/*.ml` for existing Float `!=`/NaN assertions before
  changing — none existed relying on the old (wrong) `one` behavior.
- Full `scripts/run-tests.sh -q` run: 797 stdlib + 564 codegen tests, all
  green except two pre-existing/unrelated items — the known-flaky compiled
  `Signal.watch` repeated-delivery RC test, and `testing_library`'s
  `run_tests: fail count` self-test (which deliberately triggers and counts
  a nested test failure; its embedded `FAIL: "bad"` stdout is the *expected*
  fixture, not an actual alcotest failure — confirmed by re-running the
  `stdlib` suite in isolation, which shows it `[OK]`).

## Files

- `lib/tir/llvm_emit.ml` — the one-line predicate fix.
- `test/test_codegen.ml` — new `test_compiled_float_nan_neq_parity` +
  registration.
- `CHANGELOG.md` — user-facing `### Fixed` entry.
