# DONE 2026-09-24: A zero-parameter lambda is `Unit -> T` everywhere

**Cause.** `() -> T` is `TArrow(Unit, T)`, and `check_expr`'s ELam arm already
gave `fn () -> e` that type when checked against a declared `Unit -> T` (a
parameter). But `infer_expr`'s ELam arm folded an EMPTY parameter list into
plain `T`, so any zero-parameter lambda typed WITHOUT an expected arrow in hand
(a record-literal field: blocks and record literals are inferred and then
unified, never checked; an unannotated `let`) was its body's result, and
`Int` never unifies with `() -> Int`. The same collapse happened when a lambda
was checked against a still-unknown type variable (`id(fn -> 3)`), and a
generic `fn apply(f) do f() end` typed as `a -> a` (an empty-parens call of an
unknown value returned the value's own type), which only worked because the
lambda it received was collapsed too.

**Fix** (`lib/typecheck/typecheck.ml`):
- `infer_expr` ELam: an empty parameter list infers to `TArrow(Unit, body)`.
- `check_expr` ELam: a zero-parameter lambda checked against an unbound type
  variable binds it to `Unit -> fresh` before checking the body.
- `EApp`: an empty-parens call `f()` of a LOCAL, monomorphic, still-unknown
  value (an unannotated parameter; not a named fn in `fn_arities`, not a
  qualified name) binds it to `Unit -> r`, so `apply(fn -> 7) : Int`. Named
  zero-arg fns keep their "typed as the return type" convention, and their
  forward/self-reference placeholders stay free.

Consequence: passing a zero-arg NAMED fn by bare name to such a generic
(`apply(answer)`) is now a type error. It used to typecheck and run
interpreted, but the compiled program called the returned integer as a
closure and died with SIGSEGV.

The change exposed a latent desugar bug (`lib/desugar/desugar.ml`,
`expand_defaults_decl`): a short-arity default-arg variant forwarded
`required @ defaults` instead of the original parameter order, so
`fn f(a, b \\ "x", c)` called as `f(1, 2)` became `f$3(1, 2, "x")`. It only
typechecked in `test/native/zero_arg_closure_default.march` because its
misplaced zero-arg lambda was collapsed to `String`, the default's type. Fixed
to forward in declaration order.

`stdlib/topology.march`: `TopoRole.open` is now `() -> Result(...)` with no
dummy argument.

**Evidence.**
- `test/test_compiler.ml`, group `zero_arg_unit_callback`, 4 new cases (record
  field, let-bound thunk into field and param, generic `apply`/`id`,
  default-before-required forwarding): all 4 FAIL with origin/main's
  `typecheck.ml` + `desugar.ml` swapped in, all pass with the fix.
- Both repros plus `r.go()`, `(r.go)()`, `{ r with go: fn -> 10 }`, a list of
  thunks, Float/String-returning thunks in record fields, `id(fn -> 41)()`,
  `Some(fn () -> "opt")`: identical output interpreted and `--compile`d.
  `test/native/unit_callback_zero_arg.march` and
  `zero_arg_closure_default.march` also agree on both backends.
- `--check` of all 125 `stdlib/*.march` with the pre- and post-change compilers
  (separate HOMEs, `MARCH_STDLIB` set): byte-identical output.

---

Original report:

Found while writing `stdlib/topology.march` (build step 3). Minimal repro:

```march
mod Z do
  type R = { name : String, go : () -> Int }
  fn mk(name : String) : R do
    { name: name, go: fn () -> 3 }      -- error: expected `() -> Int` but got `Int`
  end
  fn mk2(name : String) : R do
    let g = fn () -> 4                  -- same error, reported at this `let`
    { name: name, go: g }
  end
end
```

`go : Unit -> Int` fails the same way. Passing `fn () -> 3` as an ARGUMENT to a
parameter declared `() -> Int` works (`Signal.watch`, `Topology.hook`), so the
checking-mode path for a record field / let-bound zero-parameter lambda is the
suspect. Workaround in use: `Topology.TopoRole.open` is `Int -> ...` called with a
dummy argument.

**Acceptance:** the repro typechecks and `(r.go)()` returns 3 on both backends; then
`Topology.TopoRole.open` can drop its dummy argument.
