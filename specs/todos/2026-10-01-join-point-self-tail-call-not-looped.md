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
