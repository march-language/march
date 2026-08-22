# ECallPtr caller/callee ownership mismatch: a fresh heap argument through a closure call leaks — Float was just one instance

Filed 2026-08-21, found while root-causing the Float-box ABI leak
(`specs/progress/2026-08-21-float-box-uniform-abi-call-site-release.md`).
The Float fix landed there closes the *boxes the emitter itself creates*;
this item is the underlying, type-independent accounting gap.

**STILL OPEN. Re-confirmed and scoped 2026-08-22** while closing the other two
items in this family (`specs/progress/2026-08-22-erased-slot-ownership-leaks.md`,
`specs/progress/2026-08-22-task-handle-and-ok-wrapper-leak.md`). Not attempted:
the survey below is why. **It does NOT share a root with those two** — they are
"a value crossing into an erased slot has no named owner", each fixable at one
site; this is "two sides of one ABI implement different conventions", which
cannot be fixed on one side alone.

Re-measured on `origin/main` 8897bb1a, Darwin arm64, `--compile --opt 2`:
200,000 calls with a fresh heap `String` argument → `live_allocs` delta =
**200,000**, exactly 1 leaked String per call. Unchanged by either fix above,
as expected.

## Measured (Darwin arm64, `--compile --opt 2`)

```march
pfn call_n(f : (String) -> Int, n : Int, acc : Int) : Int do
  if n <= 0 do acc else call_n(f, n - 1, acc + f(int_to_string(n))) end
end
-- f from a list (genuine ECallPtr): fn (s : String) -> string_length(s)
```

1,000,000 calls with a FRESH heap String argument (dead after the call):
**live_allocs delta = 1,000,001** — one leaked String per call. A
long-lived argument doesn't show in live_allocs but its refcount grows by 1
per call (caller pre-incs, nobody ever decs), making the object immortal.

## Why

The two sides of an indirect closure call implement different conventions:

* **Caller** (perceus.ml's general `ECallPtr` case, the "audit P5" comment):
  every arg is treated as OWNED — "the closure-apply ABI used for ECallPtr
  always consumes args". Live-after args get a balancing `EIncRC`;
  dead-after args transfer the caller's reference.
* **Callee** (borrow.ml `infer_module`): only `$clo` (param 0) is pinned
  owned. Every other apply-fn param goes through per-body borrow inference,
  initialised BORROWED — and a param whose body only reads it (the
  overwhelmingly common case: `string_length(s)`, a comparator) stays
  borrow-classified and **never consumes the transferred reference**.

The P5 comment already names the real fix ("attaching per-call-site borrow
modes to closures at EAlloc time and plumbing them through the call
dispatch — a sizeable architectural change") and deliberately deferred it;
what it did not record is that the deferral is an unbounded OBJECT leak for
fresh args, not just "extra Inc/Dec pairs". This is the same disease as the
fold-heap-accumulator borrowed-return item
(`specs/todos/2026-08-20-fold-heap-accumulator-borrowed-return-leak.md`),
seen from the argument side.

## Constraints on any fix, learned the hard way (read the progress file above)

* A callee-side "always consume" pin must migrate the C runtime's closure
  call sites in the same change — they assume BORROWED args (e.g.
  `native_float_arr_fold` releases its own element boxes; the 6-site audit
  in memory/`specs/progress` maps them).
* A caller-side "treat as borrowed" flip is unsound alone: some apply-fn
  params legitimately infer OWNED (body stores/returns them) and would
  underflow. Normalising the external ABI to borrowed requires the callee to
  self-inc at entry when its body wants ownership.
* Either normalisation would also subsume the Float alias guard and the
  self-tail-call exemption
  (`specs/todos/2026-08-21-selfrec-closure-float-tail-call.md`).

## Why there is no narrow fix — established 2026-08-22

Worth writing down, because "just release the dead-after arg at the call site"
is the obvious move and it is a use-after-free.

The leak needs the callee's mode, and an `ECallPtr` callee is dynamic:

* caller emits `march_decrc(arg)` after the call → correct iff the callee
  BORROWS; an underflow the moment it consumes;
* caller emits `march_incrc` before and `march_decrc` after → net zero for a
  consuming callee, and still leaks for a borrowing one;
* nothing keyed on the argument's TYPE helps: the mode is a property of the
  callee's body, not of the value.

So the mode has to be made uniform, and the two ways to do that are exactly the
two the constraints above rule out one-sidedly. Note also which params actually
bite: `Rc_types.borrow_eligible` is FALSE for `TVar` and `TFn`, so an apply fn
with an erased or closure param already infers OWNED and is already balanced.
The mismatch is confined to params whose type is borrow-eligible AND whose body
only reads them — `String`, `List`, records, comparators. That is the common
case, not a corner.

**Pinning apply-fn params owned (mirroring `$clo`) is the coherent design**, and
it is a bigger change than the one-line pin suggests, because it must land
together with:

1. `borrow.ml` `infer_module`: extend the `i = 0 && is_apply_fn` pin to every
   param, so `owned_in`'s fixpoint stops reclassifying them;
2. the 6 C-runtime closure call sites (the audit in memory /
   `specs/progress`): each currently passes a value it still owns and releases
   it itself (`native_float_arr_fold`'s `march_decrc(elem)`). Each needs an
   `march_incrc` before `call_closure_*` — a smaller edit than removing their
   releases, and it keeps their own allocation accounting intact;
3. **#321's caller-side Float releases must be DELETED**
   (`specs/progress/2026-08-21-float-box-uniform-abi-call-site-release.md`):
   those boxes are created by the emitter's own `coerce`, are invisible to
   Perceus, and a consuming callee would release them too — the release plus
   the callee's consume is a double free. Their alias guard and the
   self-tail-call exemption go with them, which also closes
   `specs/todos/2026-08-21-selfrec-closure-float-tail-call.md`.

That is one coordinated change across `perceus.ml`, `borrow.ml`,
`llvm_emit.ml`, `llvm_toplevel.ml` and `runtime/march_runtime.c`, undoing a
fix that itself took three attempts. It wants its own branch and its own
verification cycle, not a ride along with two unrelated leaks.

## Verification bar

The fresh-String probe above RED→GREEN; the #313 acc probe and
`native_float_box_abi_leak_probe` stay green (they pin the C-runtime-caller
and emitted-caller conventions respectively); full ASAN corpus — an
ownership-convention change is exactly the kind that passes unit tests and
double-frees in the corpus.
