# Stack promotion through a non-retaining callee

**Landed:** 2026-09-03. Companion to
`specs/progress/2026-09-03-unboxed-small-scalar-aggregates.md`; the two came
from the same brief.

## The problem

`lib/tir/escape.ml`'s verdict stopped at every call boundary: an [`EApp`]
argument was an escaping position, full stop. A value whose only use is a
callee that reads its fields and returns a scalar therefore stayed on the heap,
even though its address never left the frame.

## What landed

Two changes, one in each of the two passes involved.

### 1. `Escape`: a callee-retention analysis

`escaping_vars`'s `EApp` arm now clears an argument when the callee is defined
in this module AND either

- `Borrow.is_borrowed` says the parameter is borrowed (the criterion the brief
  named), or
- `may_retain_table` — a new, purpose-built least fixpoint — says the callee
  cannot put the POINTER anywhere that outlives the call.

The second answer is the one that fires. `Borrow` answers an OWNERSHIP question
("who releases the reference"), which is strictly stronger than the one stack
promotion needs. Measured over the 43 programs in `bench/`, the borrow verdict
alone promotes **nothing** — 0 additional stack cells, the same as before the
extension — because `field_escape_owns` marks a parameter owned as soon as any
extracted field is used in an owning position, and `is_borrowed` has no entry
for `+`. The retention answer is about where the pointer went, and `a + b` on
two `Int` fields is not an aliasing question at all.

Retaining shapes: returned; stored into `EAlloc`/`EStackAlloc`/`ETuple`/
`ERecord`/`EUpdate`/`EAllocHole`/`ESetField` (a closure capture is an `EAlloc`
of a `$Clo_` struct and rides the same arm); `ECallPtr` in either position; an
`EApp` to anything not defined in this module (an extern or a runtime builtin —
`send`, `task_spawn`, a `Vault` write); an `EApp` to a local function at an
already-retaining parameter; and any `EIncRC`/`EDecRC`/`EFree` on it. That last
one is not merely retention: a stack cell's header says `rc = 0`
(`Llvm_data.emit_stack_alloc` zeroes it), so a decrement would underflow and
hand a stack address to `free`.

Not retaining, and the point of the analysis: an `ECase` scrutinee, an `EField`
source, an `EReuse` token. A field read out of the cell is a COPY; where that
copy goes is a question about the FIELD's lifetime, not the cell's address.

Three restrictions, each with its own reason in the module doc:

1. **Never a closure struct through a call.** `Borrow.infer_module` PINS an
   apply function's `$clo` parameter owned and
   `Perceus.insert_apply_fn_clo_drop` emits a `dec_rc $clo` on the strength of
   that pin. Measured before this restriction existed: 36 stack cells appeared
   across `bench/`, and every one of them was a capture-free `$Clo_` handed to
   its own apply function — a cell the callee decrements and that `Llvm_emit`
   already turns into one immortal global. With the restriction the same sweep
   promotes only what it should.
2. **March-defined callees only.** `Borrow.is_borrowed` falls back to a
   hardcoded ABI table for C externs, where "borrowed" is a declaration about
   code this pass cannot read.
3. **A borrow map must be supplied**, and it must be the one `Perceus`
   consumed (computed pre-Perceus). `Contract_pipeline` now computes it once
   and hands it to both; a caller that assembles its own pass list and passes
   none keeps the old, narrower verdict.

### 2. `Borrow`: scalar-only variants stop being force-owned

`field_escape_owns` exists to stop an extracted HEAP field from escaping
without an inc — the "second read returns None" / local RC underflow class. For
a variant whose every constructor's every declared field is a scalar (`Int`,
`Float`, `Bool`, `Unit`, `Atom`) no extracted field can be a pointer and the
hazard cannot arise, so the rule no longer fires for those types
(`Borrow._scalar_only`, a per-module table set by `infer_module`).

This is what makes the extension reach the motivating shape. Before it,
`sum5(b : Big) : Int` (five `Int` fields, summed) was inferred `b:own`, which
made Perceus emit `dec_rc b` inside the callee — and a callee that frees the
cell can never be given a stack one.

## Verification

- `test/test_eval.ml`, group `escape_analysis`: promoted through a reading
  callee (with `has_heap_alloc` asserted false, so it is a real replacement,
  not an addition); not promoted through a callee that stores the pointer; not
  through an extern; not for a closure passed to its own apply function.
- `test/test_alloc_contract.ml`: `@[no_alloc]` accepts a function whose cell is
  promoted through such a call.
- The 43 `bench/` programs compile and run byte-identically to the base
  compiler (timing lines excepted), and `dune build @test/oracle` is at parity.

## Not done

`field_escape_owns` is still conservative for a variant that mixes scalar and
heap fields: an `Int` field extracted from `Node(Int, Tree)` and handed to `+`
still marks the whole parameter owned. Making that per-FIELD rather than
per-TYPE needs `Lower` to give `br_vars` their concrete types (today they are
`TVar "_"`, which is exactly why the rule does not gate on them). Filed as
`specs/todos/2026-09-03-field-escape-owns-is-per-type-not-per-field.md`.
