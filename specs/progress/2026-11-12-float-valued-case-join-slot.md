# A Float-valued `if`/`match` joins in a `double` slot (done 2026-11-12)

Reported from Strata (a voxel engine in March): a profile of its island chunk
generator found 55% of CPU time in the allocator and the reference-count
runtime, almost all of it from Float-valued `if`s (`fmax`, `fmin`, `clamp01`,
`if e > 0.0 do e else 0.0 end`).

## Cause

`emit_case` (`lib/tir/llvm_case.ml`) emits the result slot's `alloca` before
any arm, so `predicted_unboxed_join` predicts its type from the TIR. It
predicted `i64` for Int/Bool arms and a struct for unboxed aggregates
(`specs/progress/2026-09-30-unbox-aware-case-join-slot.md`) but never
`double`. A Float-valued case therefore took the `ptr` slot: each arm boxed
its value with `march_alloc_float` and the merge unboxed it and freed the box
(`finish_ptr_merge`), a malloc and a free per evaluation. A nested
`else if` chain paid once per level.

## What changed

`predicted_unboxed_tail` answers `double` when the arm's tail, through
`ELet`/`ESeq` and nested cases, is a Float literal, a variable of type Float,
`+. -. *. /.` (or an overloaded `+ - * / %` whose first operand is a Float),
or a call of a builtin or top-level function whose return type is Float.
Diverging arms are ignored as before. Both slots use the prediction: the
ordinary one and the niche-encoded Option path (`slot_ty_n`). `coerce_arm`
stores `poison` for a diverging arm into a `double` slot, as it already did
for a struct slot.

A wrong `double` prediction is still well-typed and no worse for ownership
than the `ptr` slot was: an arm that turns out to hold a boxed Float is
unboxed by the store, and its box stays with whoever owned it, which is what
the mixed-arm `ptr` merge did.

Not covered, by choice: an arm that calls a closure (`f(x)` with `f` a
parameter) is not predicted, so such a join keeps the `ptr` slot, boxes in
each arm and frees the box at the merge, as before.

## Measured

Strata's reduced cases (`bench/march/float_if`, `stage_thermal`,
`stage_density` in that repository), `--opt 2`, CPU time and instructions
per unit of work. "Before" figures are Strata's own, recorded in those
directories on 12 November 2026 against an earlier origin/main; that
compiler also predates the inlined `NativeArray` reads, which is why the
rewritten rows moved too. Not re-measured here on one compiler.

| case | before | after |
|---|---:|---:|
| `float_if`, Float-valued `if` | 22.3 ns, 491 instr | 0.73 ns, 23 instr |
| `float_if`, same loop by arithmetic | 3.66 ns, 48 instr | 3.62 ns, 36 instr |
| `float_if`, C `?:` | 0.55 ns | 0.55 ns, 11 instr |
| `stage_thermal`, as it stands | 110 ns, 2370 instr | 9.18 ns, 229 instr |
| `stage_thermal`, rewritten without Float-valued `if` | 21.6 ns | 13.20 ns, 260 instr |
| `stage_thermal`, C | 3.2 ns | 3.24 ns, 75 instr |
| `stage_density`, as it stands | 71 to 85 ns, 1450 to 1700 instr | 6.10 ns, 160 instr |
| `stage_density`, rewritten without Float-valued `if` | 16.3 ns | 12.97 ns, 222 instr |
| `stage_density`, C | 2.7 ns | 2.75 ns, 57 instr |

The printed sums of both stage benchmarks are identical across the two March
variants and C. None of the three programs' IR calls `march_alloc_float`.
The benchmark sources call `Env.get_int` as a bare `Int`, which current main
rejects (`cap_result_unhandled`); they were run from a copy with
`Authority.must(...)` added.

## Tests (`test/test_codegen.ml`, group `unboxed_aggregates`)

- `test_float_case_join_slot_is_double`: a module with one function per arm
  shape has `alloca double` joins and no `march_alloc_float` or
  `march_unbox_float` call.
- `test_float_case_join_mixed_arms_keep_ptr_slot`: a closure-call arm keeps
  the boxed join, and the merge frees its box.
- `test_float_case_join_matches_interpreter_compiled`: compiled output equals
  the interpreter's.
- `test_float_case_join_no_leak_compiled`: `march_live_allocs` does not move
  over 20,000 iterations of both loops.
