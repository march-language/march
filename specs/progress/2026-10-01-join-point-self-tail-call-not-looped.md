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

## Fixed 2026-10-02

`lower_match.ml` now binds every hoisted join point through `bind_jp`, which
counts the fall-through sites in the decision tree it just built: a join point
with ONE site has its body substituted back in place (binding the join point's
parameters to the call's arguments), one with NO site (the inner matrix of a
nested pattern hoists its fallback before it knows every row matches) is dropped,
and only a join point with two or more sites, or one captured by a surviving
nested join point, stays a closure. The substitution is refused when a binder on
the path to the site rebinds a name the body reads (a guard-fail fall-through is
under the row's pattern variables).

With the body in place the tail call is a self call again and `Llvm_tco` loops
it. The snapshots lost 28 closures' worth of IR and every erased `inc_rc` on a
field that is now moved rather than captured.

Putting the fallback in place exposed a Perceus ordering bug and a leak that the
closure had masked; both are fixed in the same PR, see
[2026-10-01-dead-join-point-closure-leaks-captures.md](2026-10-01-dead-join-point-closure-leaks-captures.md).

Regression: `test/native/jp_self_tail_loop.march` (200,000 elements; SIGBUS in
the stack guard page before).
