# ECallPtr caller/callee ownership mismatch: a fresh heap argument through a closure call leaks — Float was just one instance

Filed 2026-08-21, found while root-causing the Float-box ABI leak
(`specs/progress/2026-08-21-float-box-uniform-abi-call-site-release.md`).
The Float fix landed there closes the *boxes the emitter itself creates*;
this item is the underlying, type-independent accounting gap.

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

## Verification bar

The fresh-String probe above RED→GREEN; the #313 acc probe and
`native_float_box_abi_leak_probe` stay green (they pin the C-runtime-caller
and emitted-caller conventions respectively); full ASAN corpus — an
ownership-convention change is exactly the kind that passes unit tests and
double-frees in the corpus.
