# An unused, owned closure parameter of a named function leaks on a direct call

Filed 2026-10-12 from the TIR verifier's leak sweep
(`specs/progress/2026-10-12-verifier-leak-sweep.md`; the finding is `need` in
`specs/lang/types/accept/t312_refine_abstract_shorthand_user_combinator.march`).

```march
pfn need(xs : List(Int), keep : Int -> Bool) : Int do List.length(xs) end

pfn spin(n : Int, acc : Int) : Int do
  if n <= 0 do acc else
    let k = n % 7
    let f = fn y -> y > k
    let l = [f]
    spin(n - 1, acc + need([1, 2], f) + List.length(l))
  end
end
```

Compiled, 3000 iterations leave 3000 live objects, one closure per call. Interpreted, the count
stays flat. If the closure is not also stored in `l`, Escape stack-promotes it and nothing
leaks, which hides the bug in simpler programs.

`keep` is a `TFn`, which `Kind.borrowable_of` never borrows, so it is owned and the caller hands
it a reference. But only an apply fn gets a drop for a parameter its body never mentions
(`insert_dead_apply_param_drops`). A named function keeps that reference. Erased (`TVar`)
parameters have the same gap. For those, the `$clo_wrap` trampoline path was patched instead:
`Clo_flags` registers an unused erased parameter as borrowed
(`test/native/generic_fn_closure_unused_param_leak_probe.march`). A direct call is still
uncovered.

This is not a one-line fix. A callee-side drop of unused owned parameters must agree with that
trampoline registration, or the trampoline and the callee both release the value. The fix
should either drop in the callee and stop registering such parameters as borrowed for
`$clo_wrap`, or make the borrow map itself say borrowed for unused non-borrowable parameters,
so that callers release them. The verifier currently reports `kfst`/`ksnd` in that fixture as
leaks because it reads only the borrow map, so the second option also clears that false
positive.
