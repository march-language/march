# `[P2]` Linearity: an unannotated parameter is never tracked, even when its body fixes it to a linear type

Filed 2026-09-13 from the probe sweep in
`specs/plans/2026-09-13-linearity-holes-plan.md` (step 5).

## The hole

A parameter's linearity is decided **when it is bound**, from its type at
that moment. An unannotated parameter's type is then a fresh type variable,
so it is bound unrestricted and never entered into `env.lin`. The body can
fix the type to an `always_linear` one a line later; the parameter still
isn't tracked, and a double use goes through:

```march
mod U do
  needs IO.Console
  always_linear type S1 = S1(Int)
  fn sink(s : S1) : Int do match s do S1(e) -> e end end
  fn g(st) : Int do sink(st) + sink(st) end          -- accepted; st used twice
  fn main(c : Cap(IO.Console)) do
    let f = fn st -> sink(st) + sink(st)             -- accepted
    println(int_to_string(g(S1(1)) + f(S1(2))))
  end
end
```

Annotate either parameter as `st : S1` and it is rejected.

## Measured (main `8eb0d7ee`)

| binder, unannotated | type fixed by | used twice |
|---|---|---|
| top-level `fn g(st)` | the body (`sink(st)`) | **accepted** |
| lambda `fn st -> …`, infer mode | the body | **accepted** |
| actor handler `on Take(s)` | the body | **accepted** |
| any of the above, annotated | the annotation | rejected |

## Scope: only types fixed inside the scope

This item covers a parameter whose type is resolved to a linear type **by
the time its own scope closes**, which in practice means by its uses in the
body. It does **not** cover a parameter that is still a type variable at the
close and is generalised, like `fn drop_it(x) : Int do 0 end` called with
`drop_it(S1(1))`, or `fn dup(x) do (x, x) end`. Those functions are
polymorphic, and whether a type variable may be instantiated with a linear
type is a property of the function's scheme, not of any single scope. That
is [[2026-09-13-linear-generic-code-and-containers]], and no scope-close rule
can fix it.

So the must-use half of this item rarely fires: an unused parameter's type
is almost never fixed by its own body. The at-most-once half is the one that
matters.

## Cause

Three binding sites decide linearity from `repr t` at bind time:

- `bind_lam_param` (`typecheck.ml` l.3035): lambdas, local `fn … end`, and,
  since 2026-09-12, actor handler params;
- `check_fn`'s `FPNamed` parameter loop (~l.3270), a near-verbatim copy of
  the same promotion;
- `check_fn`'s `FPPat (PatVar _)` arm, which uses a plain `bind_var` with a
  fresh variable and no promotion at all. A top-level unannotated `fn g(st)`
  lands here: the parser's `FPNamed` forms all carry a type.

With a fresh variable, `resolves_always_linear` sees no `TCon` and returns
`Unrestricted`.

## Design: pending entries, decided at scope close

Track every parameter whose type is an **unbound type variable at bind time**
as a *pending* linear entry. Uses are recorded but not judged. At the
scope's close, resolve the type and judge them.

1. **Entry shape.** Extend the linear entry (the record with
   `le_name`/`le_lin`/`le_used`/`le_first_use`, declared in
   `typecheck_env.ml` and repeated in `typecheck_env.mli` and
   `typecheck.mli`) with
   - `le_pending : ty option`: `Some t` for a pending binder, holding its type;
   - `le_dup : Ast.span option ref`: the first use that happened while
     `le_used` was already set.

   A pending entry has `le_lin = Unrestricted`, so nothing that reads
   `le_lin` (`bind_pattern_bindings`'s inheritance, the capture check,
   `check_linear_all_consumed`) treats it as linear before it is judged.
2. **`record_use`.** For a pending entry: if `le_used` is already set and
   `le_dup` is `None`, set `le_dup := Some span`. Otherwise set `le_used` and
   `le_first_use` as usual. Never report.
3. **Paths.** `iter_paths_linear` already saves and resets `le_used` and
   `le_first_use` per path, which is what makes `le_dup` exact: a use in the
   second arm is not a duplicate of one in the first. `le_dup` itself is
   **not** reset between paths, because a duplicate inside any one path is
   real.
4. **Scope close.** At every close that judges parameters, over the entries
   the scope added (the identity-based `lin_entries_added` from
   [[2026-09-10-linear-lambda-parameter-not-must-use]]), for each pending
   entry resolve `repr t`:
   - `TCon` that `resolves_always_linear`, or `TLin (Linear, _)`: report
     `le_dup` as "The linear value `st` is used more than once here."
     (label: first use at `le_first_use`), and report never-used exactly as
     for a declared linear binder;
   - `TLin (Affine, _)`: report `le_dup` only;
   - anything else, including a still-unbound variable: nothing.

   The closes are the three `check_scope_consumed` sites from the lambda item
   (lambda infer, lambda check peel, `ELetFn`), plus `check_fn` (l.3417) and
   the actor handler (l.4331).
5. **One promotion helper.** Fold `check_fn`'s copied promotion and its
   `FPPat (PatVar _)` arm onto `bind_lam_param`, so the pending rule lives in
   one place. That is a refactor with no behaviour change of its own; land it
   as the first commit and run `scripts/types-oracle.sh` to prove it.

**Check mode needs nothing.** `check_expr`'s peel passes the known arrow
component to `bind_lam_param`, so the type is already resolved and the
parameter is promoted eagerly, as now.

**Capture.** A pending outer entry captured by a closure: the capture check
runs after the closure body, so resolve the pending type there too, and
report if it is linear by then. If it only resolves later, it is missed.
Record that as a known limit, since it belongs to the generics item.

### Cost

Every unannotated parameter in the program becomes an `env.lin` entry for
its scope's lifetime, and `record_use` does `List.find_opt` over `env.lin` on
every variable reference. Entries die with their scope, so the list stays
bounded by nesting depth times arity, but stdlib is dense with
`fn x -> …` lambdas. **Measure it:** time `march --check` over the largest
stdlib-heavy program in the corpus and over `~/code/bastion_todos`, before
and after, same box, same load (`uptime` first). A slowdown past noise means
`env.lin` needs an index, and that is a separate change.

## Tests

Reject witnesses (RED on `main` first), expected `is used more than once`:

- top-level `fn g(st) : Int do sink(st) + sink(st) end`;
- infer-mode `let f = fn st -> sink(st) + sink(st)`;
- actor handler `on Take(s) do { state with n: sink(s) + sink(s) } end`.

Accept witnesses:

- `fn g(b : Bool, st) : Int do if b do sink(st) else sink(st) end end`: one
  use per path, and the guard on step 3;
- `List.map(xs, fn x -> x + 1)`, and `fn id(x) do x end` used at `Int` and
  at `S1`: nothing pending ever resolves linear;
- an unannotated parameter that resolves to a session endpoint and is used
  once;
- the full `specs/lang/types/` corpus unchanged apart from the new rows.
