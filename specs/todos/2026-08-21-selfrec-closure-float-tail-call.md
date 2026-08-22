# Self-recursive local closures: Float boxes leak on the back-edge, and the loop itself is LLVM's, not ours

Filed 2026-08-21, split out of the call-site Float-box release work
(`specs/progress/2026-08-21-float-box-uniform-abi-call-site-release.md`).

## The shape

```march
pfn selfrec(n : Int) : Int do
  let f = fn (x : Float) -> x +. 3.0
  fn go(i : Int, acc : Float) : Float do
    if i <= 0 do acc else go(i - 1, f(acc)) end
  end
  float_to_int(go(n, 0.0))
end
```

`go` is a LOCAL recursive fn: defun lifts it to `go$apply$N` with a `$clo`
self-binding (`let go = $clo`), and the self-call is an `ECallPtr` through
that binding. TIR-level TCO (`Llvm_tco`) only recognises `EApp`-to-self, so
this recursion is **not** given a back-edge by us — it survives deep inputs
only because LLVM's tail-call elimination turns the emitted self-call into a
loop. Two consequences:

1. **Fragile stack behavior.** Any instruction emitted between the self-call
   and the merge/return defeats the elimination and the recursion becomes
   O(n) real frames. Measured during the call-site release work: a shape
   that ran 1,000,000 deep SIGBUSed (green-thread stack overflow) at 20,000
   once post-call releases were added. The emitter now EXEMPTS (potential)
   self-calls from those releases specifically to preserve eliminability —
   `Tir_names.apply_fn_base`-keyed in the ECallPtr arm,
   `resolved_name <> ctx.cur_emit_fn` in Boundary B.
2. **The exempted back-edge still leaks.** Each iteration allocates a
   `march_float_box` for the Float accumulator entering the erased self-call
   (plus, before the fix, f's own two boxes — those ARE fixed). Measured:
   1 box/iteration on the exempted edge, unbounded.

`test/native/native_float_box_abi_leak_probe.march`'s `selfrec_leg` pins the
stack half (1M deep, run OUTSIDE the leak-measurement window; a SIGBUS there
means a post-call instruction crept back onto the self-call path). Nothing
asserts the leak half — it is the open item here.

## The fix this wants

March-level TCO for self-recursive apply fns: teach the TCO analysis to
recognise the defun self-binding pattern (`let <name> = $clo` +
`ECallPtr(AVar <name>, args)` in tail position — defun already knows
`lam_is_recursive`) and give the apply fn the same back-edge + native
`double` slot treatment top-level fns get. That closes the per-iteration box
allocations entirely (coerce double→double is the identity), removes the
dependence on LLVM's optimizer for stack safety, and lets the self-call
exemption in the release machinery be deleted. Mutual recursion through
closures has the same fragility and is not covered by the exemption at all.
