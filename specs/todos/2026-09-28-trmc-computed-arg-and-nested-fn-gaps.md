# TRMC misses two natural-style shapes (OPEN, 2026-09-28)

**Filed:** 2026-09-28, while rewriting the stdlib list producers into natural
style (specs/progress/2026-09-28-rewrite-stdlib-list-producers-into-natural-style.md).
Both gaps were worked around in `stdlib/list.march`; neither is fixed in
`lib/tir/trmc.ml`.

## 1. A computed call argument hides the modulo-cons site

```march
@[no_warn_recursion]
fn r1(a : Int, b : Int) : List(Int) do
  if a >= b do Nil else Cons(a, r1(a + 1, b)) end        -- TRMC: non-trmc
end

@[no_warn_recursion]
fn r2(a : Int, b : Int) : List(Int) do
  if a >= b do Nil else do
    let n = a + 1
    Cons(a, r2(n, b))                                     -- TRMC: eligible
  end end
end
```

`MARCH_TRMC_REPORT=1` reports `r1` as `non-trmc tail=0 modcons=0 other=1`. The
two differ only in where `a + 1` is bound. The likely cause is that lowering
nests the argument's `let` inside the call's binding
(`ELet (t, ELet (n, a + 1, r1(n, b)), alloc Cons(a, t))`), so `sites_of` sees a
let RHS that is not an `EApp` and scans it as a value computation. A let-floating
normalisation (`ELet (x, ELet (y, e1, e2), k)` -> `ELet (y, e1, ELet (x, e2, k))`)
before the analysis would cover it; the transform's `seed_entry`/`returnify`
match the same shape, so it has to run before both.

This matters most because the non-trmc version is a plain non-tail recursion,
so it overflows the stack on long input. `List.range` was left in its
accumulator form (it is already single-pass: it builds from the end, no
`reverse`) because its natural form hits this gap.

## 2. Nested functions are analysed but never transformed

`analyze_module` reports every `ELetRec`-bound nested function, but
`transform_module` only rewrites `m.tm_fns`. A nested `fn go` in
natural style prints `TRMC eligible go ...` and then no `TRMCXFORM` line, so it
compiles to non-tail recursion. `List.flat_map` and `List.range_step` use
top-level `pfn` helpers for this reason.

Either transform nested functions too, or stop reporting them as `eligible` so
the report does not claim coverage that is not there.

## Test

For each gap: a `test/test_trmc.ml` unit on the TIR shape, and a compiled run
over 1,000,000 elements that would overflow without the transform (check the
exit code, not only the output).
