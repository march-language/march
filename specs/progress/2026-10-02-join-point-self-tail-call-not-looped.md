`[P2]` A self tail call inside a nested-pattern match arm is not turned into a loop

Found 2026-10-01 while working on the inline refcount fast path, when
`test/native/array_sort_by.march` overflowed its 1 MiB green-thread stack.

```march
pfn ordered(xs : List((Int, Int))) : Bool do
  match xs do
    Nil -> true
    Cons(_, Nil) -> true
    Cons(a, Cons(b, rest)) ->
      let ok = key_of(a) < key_of(b) || (key_of(a) == key_of(b) && pos_of(a) < pos_of(b))
      if ok do ordered(Cons(b, rest)) else false end
  end
end
```

The recursive call is in tail position, but the nested pattern is lowered through a
join-point closure (`$jp…$apply`, `FnJoinPoint`), so after Defun the call is
`ordered` -> `$jp$apply` -> `ordered`: a mutual call, not a self call. `Llvm_tco`
only loops self tail calls, and LLVM does not sibcall it (the functions use
dynamic stack slots), so the function recurses once per element and overflows at
about 8,000 elements even with `MARCH_NO_INLINE_RC=1`. TIR after Opt:

```
fn ordered(xs) = case xs of
  Cons($f1, $f2) -> let $jp_clo = alloc $Clo_$jp…($jp…$apply, $f1, $f2) in
                    case $f2 of Nil() -> true
                                _ -> $jp…$apply($jp_clo)
```

Fix direction: inline a join point whose closure has a single call site back into
its caller before TCO runs (it is only a closure because the match compiler shares
an arm), or teach the TCO pass to loop through a join-point apply fn that tail
calls its creator.

---

# DONE 2026-10-02

## The fix

`lib/tir/jp_inline.ml`, run in `lib/tir/contract_pipeline.ml` right after
`Known_call` (which makes the join-point call direct) and before Perceus:

1. Drop every unused join-point closure allocation. The match compiler mints a
   fallback closure for each leaf that might need one; an unused one still
   captures the closures it would have called, which made the live join point in
   `ordered` look used twice. An allocation has no effect, and before Perceus
   there is no ownership to account for.
2. For a join point whose closure is allocated once and called once in the same
   function, and whose apply function is referenced nowhere else, put its body
   back at the call site: alpha-renamed, each `$clo.$fvK` load replaced by the
   captured atom, the remaining parameters bound to the call's arguments. The
   call to the creator becomes a plain self tail call, which `Llvm_tco` loops.
   It backs off if the body uses `$clo` other than to load a field, or if a
   captured name is rebound between the allocation and the call.

## Verification

- `test/native/jp_self_tail_call.march`: the original `ordered` shape, a nested
  pattern with an accumulator, a guard, and a join point whose result is used in
  a non-tail position, at 1,000,000 elements; output matches the interpreter.
  With the pass disabled the compiled fixture overflows (SIGBUS in the stack
  guard page); with it, it passes.
- `ordered` now compiles to a loop with no join-point calls; it handles
  1,000,000 elements where it overflowed at 8,000.
- `dune build --root . @test/runtest`: the only failure was the refinement audit
  baseline gaining the new fixture's two lines; regenerated.
- ASAN (Linux container, `MARCH_SANITIZE=1`) over 252 `test/native` programs (all
  but network-bound ones): no memory-safety reports. `sched_stress` ran ASAN out of
  memory (FakeStack for its many green threads), `topology_hook_timeout` exits 1 by
  design, and `foreign_actor_http` needs the network.
- Benchmarks, same source with the pass disabled and enabled, 15 interleaved
  rounds: `list_ops` 1.05×, `binary_trees` 0.99×, `tree_transform` 1.02×, all
  noise. The pass changes about 2,250 functions per program, almost all of them
  stdlib functions losing dead join-point allocations.

## Not fixed here

`specs/todos/2026-10-01-dead-join-point-closure-leaks-captures.md` stays open: its
join point is reached from more than one leaf of the match, so it has several call
sites and is not inlined, and the closure is still dropped shallowly on the paths
that do not call it.
