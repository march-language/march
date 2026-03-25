# Benchmark Report — 2026-03-25

Post-merge evaluation of:
- Borrow inference (P7) — `lib/tir/borrow.ml`, `lib/tir/perceus.ml`
- Known-call optimization — `lib/tir/known_call.ml`
- Struct update fusion — `lib/tir/fusion.ml`
- Escape analysis — (TIR pass)
- Mutual TCO — (LLVM emit)
- ESeq codegen fix — `lib/tir/llvm_emit.ml` (applied during this session)

---

## Test Suite

```
dune runtest (all suites):
  test_march.exe:   1088 tests run, 14 failures
  test_fmt.exe:     23 tests run, 17 failures (pre-existing formatter failures)
  forge tests:       25 tests run, 0 failures (search/forge suite)
```

**All 14 failures in test_march.exe are pre-existing JIT/clang-dependent tests** (`repl_jit_*`, `repl_compiler_parity`). No regressions from the new optimization passes.

**All optimization unit tests pass** (10 borrow_inference + 4 known_call + 4 struct_fusion + 6 escape_analysis + 5 mutual_tco_codegen = 29 tests, all green).

---

## Interpreter Mode Benchmarks

The March compiler is a tree-walking interpreter. Large benchmarks (fib(40), mutual_recursion N=10M, tree_transform depth=20×100 passes, binary_trees depth=15) require native compilation for practical timing.

| Benchmark        | Interpreter Time | Output  | Status |
|------------------|-----------------|---------|--------|
| string_build     | 14,218 ms        | 2888895 | ✅ OK  |
| string_pipeline  | 6,049 ms         | 644449  | ✅ OK  |
| fib(35)          | >300 s           | —       | TIMEOUT (expected; use native) |
| mutual_recursion | >30 s            | —       | TIMEOUT (N=10M, use native) |
| tree_transform   | >30 s            | —       | TIMEOUT (depth=20×100, use native) |
| binary_trees     | >30 s            | —       | TIMEOUT (depth=15, use native) |

string_build and string_pipeline produce correct outputs in interpreter mode, confirming the stdlib string functions work correctly.

---

## Native Compilation Benchmarks

Compiled with `march --compile --opt 2` (clang -O2).

### Working Benchmarks (with ESeq fix)

| Benchmark        | Min        | Median     | Max        | vs RESULTS.md (prev) |
|------------------|------------|------------|------------|----------------------|
| fib(40)          | — ms       | 263.5 ms   | 265.7 ms   | ↓ 287.7 ms → 263.5 ms (**−8.4%**) |
| binary_trees(15) | — ms       | 238.6 ms   | 240.5 ms   | ↓ 265.4 ms → 238.6 ms (**−10.1%**) |
| mutual_recursion | — ms       | 4.7 ms     | 4.9 ms     | ✅ new benchmark |
| string_build     | — ms       | 36.3 ms    | 39.2 ms    | — |
| string_pipeline  | — ms       | 21.5 ms    | 23.8 ms    | — |

> Note: "min" field not captured cleanly due to python timing script issue; median and max are reliable.

**Performance improvements vs 2026-03-24 (constant propagation baseline):**
- `fib(40)`: 287.7 ms → 263.5 ms (**−8.4%**) — likely borrow inference eliminating RC ops on Int arguments
- `binary_trees(15)`: 265.4 ms → 238.6 ms (**−10.1%**) — borrow inference + escape analysis reducing allocation overhead

### Crashing Benchmarks (Native Mode Only)

| Benchmark                  | Symptom       | Root Cause Hypothesis |
|---------------------------|---------------|-----------------------|
| tree_transform (100 passes, depth=20) | SIGSEGV at pass 100 | Stack overflow in alloca-in-TCO-loop pattern with deep tree recursion; exact trigger TBD |
| list_ops (1M)              | SIGSEGV       | Likely same alloca-in-loop stack accumulation |
| dataframe_bench            | Compile error | `HEntry.HLeaf` ctor_info collision (HAMT-related codegen bug) |

**Note:** `tree_transform` passes with ≤99 passes (depth=20) and passes with any passes at depth≤19. The crash at exactly 100 passes of depth=20 is suspicious and may be stack-related.

---

## LLVM Codegen Regression Found and Fixed

### Bug: `ESeq(call, dec_rc)` loses call result in ELet bindings

**File:** `lib/tir/llvm_emit.ml`, ESeq handler (was line 852-855)

**Root cause:** Perceus borrow inference generates post-call decrement patterns:
```
ELet($t, ESeq(EApp(f, borrowed_arg), EDecRC(borrowed_arg)), body)
```
`ESeq(e1, e2)` discards `e1` and returns `e2`. Since `EDecRC` returns `("i64", "0")`, the binding `$t` was set to `null` instead of the call result. This produced wrong outputs (e.g. `binary_trees` check=0) and segfaults in tree traversals.

**Fix applied:**
```ocaml
| Tir.ESeq (e1, e2) ->
  let result1 = emit_expr ctx e1 in
  (match e2 with
   | Tir.EDecRC _ | Tir.EIncRC _
   | Tir.EAtomicDecRC _ | Tir.EAtomicIncRC _ ->
     (* e2 is a pure side-effect. Return e1's value so that
        ELet(v, ESeq(call, dec_rc), body) binds the call result, not 0. *)
     ignore (emit_expr ctx e2);
     result1
   | _ ->
     ignore result1;
     emit_expr ctx e2)
```

After the fix: `binary_trees` and `fib` produce correct outputs. `tree_transform` and `list_ops` still crash (separate issue, filed below).

---

## Open Issues

### 1. `tree_transform` / `list_ops` SIGSEGV (native only)

- `tree_transform` crashes at 100 passes (depth=20) but works at 1–99 passes
- `list_ops` crashes with 1M items
- Hypothesis: alloca-in-loop stack accumulation in TCO'd functions that call deeply-recursive helpers (inc_leaves, check) is exhausting the stack at high iteration counts
- **Action:** Investigate clang's handling of alloca-hoisting with TCO loops; possible fix is to limit alloca depth or hoist explicitly

### 2. `dataframe_bench` Compile Error

```
Fatal error: Failure("LLVM emit: constructor HEntry.HLeaf has 2 field(s) but field index 2 was requested
  (arity mismatch — cascading from a ctor_info collision?)")
```
- `HEntry.HLeaf` has 3 fields (Int, k, v) but codegen sees 2
- Likely a ctor_info map collision when multiple HEntry definitions exist (the TIR shows duplicated HEntry types from different stdlib modules)
- **Action:** Deduplicate ctor_info entries in LLVM emit; or ensure unique names for polymorphic type instances

### 3. `binary_trees` check=0 (pre-fix)

Fixed by the ESeq change. Confirmed correct after fix via isolated reproduction.

---

## Summary

| Category | Result |
|----------|--------|
| Test suite regressions | None (14 pre-existing JIT failures) |
| Optimization unit tests | All 29 pass (borrow, known_call, struct_fusion, escape, mutual_tco) |
| Native fib(40) | **−8.4%** faster (new: 263.5ms vs 287.7ms) |
| Native binary_trees(15) | **−10.1%** faster (new: 238.6ms vs 265.4ms) |
| LLVM codegen fix | ESeq/dec_rc binding bug fixed |
| Open issues | tree_transform SIGSEGV, list_ops SIGSEGV, dataframe_bench compile error |
