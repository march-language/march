`[P1]` **A `use` in a NESTED module shadowing an ENCLOSING contract rejects correct code.**

This is the cardinal-sin direction — a false positive on a correct program — and
should be fixed ahead of any lost-proof item in this area.

```march
mod P do
  fn run(a : Int, k : {Int | k != 0}) : Int do a / k end
  mod Inner do
    use Other.{run}          -- Other.run has no refinement
    fn go() : Int do run(7, 0) end
  end
end
```

The call dispatches to the **import** (typecheck's `bind_var` gives an inner
`UseNames` priority over an enclosing definition), and running the program
proves it — it prints Other's result. But `resolve_call`
(`lib/refinecheck/refine_check.ml`) tries the lexical enclosing-module lookup
(step 1) *before* `use`-imported names (step 3), so the call is checked against
`P.run`'s `k != 0` — a contract it never touches — and rejected.

Reproduced end-to-end 2026-07-31 (two-file `MARCH_LIB_PATH` fixture) and
confirmed identical at the pre-2026-07-30 parent, so the `use`-competition work
of that date neither introduced nor widened it.

- Root cause is the **step ordering in `resolve_call`**, not
  `adoptable_impl_methods`.
- It reaches **plain `fn` contracts**, not only `impl` methods — the impl case
  is just where it was first noticed.
- Note the asymmetry that makes it possible: `rctx.uses` inherits into nested
  modules, while declaration-list competition does not.

The opposite nesting (an enclosing `use` over a nested `impl`) was probed at the
same time and is **not** a hole — there the call really does dispatch to the
impl, so adoption matches dispatch. An earlier version of this item named that
direction; it was wrong.
