# `[P2]` Linearity: a record's linear field can be consumed while the record keeps it (actor state is the sharpest case)

Found 2026-09-10 while reviewing
`2026-09-03-protocol-projector-typed-endpoints.md`, whose first draft proposed
keeping a linear session state in an actor's state. **Specced 2026-09-13**,
and widened: the probe sweep in
`specs/plans/2026-09-13-linearity-holes-plan.md` (step 6) showed the actor is
one instance of a general record hole, not a special case.

## The hole

An `always_linear` field of an actor's state, consumed inside a handler and
then retained by the `{ state with … }` update, is accepted with no error and
no warning. The value now exists twice: once consumed, once still in the
state for the next turn.

```march
mod PCN do
  needs IO.Console
  always_linear type S1 = S1(Int)
  fn sink(s : S1) : Int do match s do S1(e) -> e end end
  actor Ep do
    state { st : S1, n : Int }
    init  { st: S1(0), n: 0 }
    on Tick() do
      let k = sink(state.st)          -- consumes state.st ...
      { state with n: state.n + k }   -- ... and retains the old st: duplicate
    end
  end
  fn main(c : Cap(IO.Console)) do
    let p = spawn(Ep)
    send(p, Tick())
    run_until_idle()
  end
end
```

## Measured (main `8eb0d7ee`, 2026-09-13)

| shape | result |
|---|---|
| actor: `sink(state.st)` then `{ state with n: … }` | **accepted** |
| actor: `sink(state.st) + sink(state.st)` | **accepted** |
| actor: `linear st : T` field (plain `T`), consume then retain | **accepted, not even a warning** |
| actor: `linear st : T` field, `tsink(state.st) + tsink(state.st)` | **accepted** |
| actor: `{ state with st: bump(state.st) }` | accepted (correct) |
| actor: `st` untouched, `{ state with n: … }` | accepted (correct) |
| actor: `let x = state.st`, `x` never used | rejected (correct: `x` is let-bound) |
| let-bound record, `always_linear` field accessed twice | **accepted** |
| let-bound record, `linear` field accessed twice | rejected, "`r.st` is used more than once" |
| let-bound record, `linear` field consumed, then record passed whole | **accepted** |
| let-bound record, `always_linear` field consumed, then `{ r with n: … }` | **accepted** |
| param-bound record, same | **accepted** |
| let-bound record holding an `always_linear` field, never touched | **accepted** |
| same record passed whole to a consuming fn twice | **accepted** |

Three separate defects produce that table.

## Cause

1. **Only `linear`-qualified fields get sentinels.** Field tracking works by
   registering a phantom entry `"r#st"` per linear field when `r` is bound
   (`bind_linear_field_sentinels`, `typecheck_unify.ml` l.893). It matches
   `TLin (lin, _)` field types only. A field whose type is an
   `always_linear` type (`st : S1`) has no `TLin` wrapper, gets no sentinel,
   and the `EField` arm (`typecheck.ml` l.1881) likewise only looks at
   `TLin`. So an `always_linear` field is untracked in every record,
   everywhere.
2. **A field use and a whole-record use don't know about each other.**
   Accessing `r.st` marks `r#st`. Using `r` itself (passing it, returning
   it, or as the base of `{ r with … }`) marks nothing about its fields. So
   "consume a field, then keep the record" is invisible even for
   `linear`-qualified fields, where sentinels do exist. Nor does anything
   check a sentinel at scope close: the let path's must-use
   (`infer_block`, ~l.2922) runs only when the binding itself is linear.
3. **Actor state drops the `linear` qualifier and gets no sentinels.** The
   `DActor` arm builds `state_ty` from each field's `fld_ty` alone (~l.4254)
   and never reads `fld_lin`, unlike the record-type arm just above it,
   which wraps the type in `TLin`. So `state { linear st : T }` is a plain
   `T` field: `tsink(state.st) + tsink(state.st)` is accepted with no
   warning (measured). The handler also binds `state` with a plain
   `bind_var` (~l.4300), so no sentinel would exist for it even if the
   qualifier survived.

## Design: move-out semantics for a record's linear fields

A record's linear fields are owned by the record. Moving one out (accessing
it) leaves the record **partially moved**. A partially moved record can
only be used again by an update that puts a value back into every moved-out
field.

### Rules

For a record-typed binder `r` (let, pattern, function or lambda param,
handler param, and the handler's `state`) whose type has linear fields,
where a linear field is either `TLin (Linear|Affine, _)` or a `TCon` that
`resolves_always_linear`:

- **R1, field use.** `r.f` on a linear field `f` uses sentinel `r#f`, as
  today. A second use is "used more than once".
- **R2, whole use.** Any other occurrence of `r` (an argument, a return
  value, a tuple or list element, the scrutinee of a `match`, the RHS of
  `let r2 = r`) uses **every** sentinel `r#f`. So consuming a field then
  using the record, using the record twice, and using the record then a
  field are all "used more than once".
- **R3, update base.** In `{ r with g1: e1, …, gk: ek }` with base `r`, `r`
  uses the sentinels of the linear fields **not** among `g1…gk`. A replaced
  field's old value is not retained, so that field is neither used nor
  required. (Its old value must still be consumed somewhere, and R4 checks
  that, like any other field.)
- **R4, must-use.** At the scope close that judges `r`, every `Linear`
  sentinel of `r` must be used, by R1, R2 or R3. Otherwise report "The linear
  value `r.f` was never used." (the display name is already rendered
  `r.f`).
- **R5, non-linear fields.** `r.n` on an unrestricted field is not a whole
  use and marks nothing. Reading `state.n` must never consume `state.st`.

Under these rules the actor cases fall out without an actor special case:

| handler body | R-rules | result |
|---|---|---|
| `let k = sink(state.st)` / `{ state with n: k }` | R1 then R3 on `st` | **error**, used more than once |
| `{ state with st: bump(state.st) }` | R1 on `st`; R3 skips `st` | ok |
| `{ state with n: 1 }`, `st` untouched | R3 uses `st` once | ok (it moves into the new state) |
| `{ st: S1(0), n: 0 }` (fresh record, old `st` ignored) | nothing uses `state#st` | **error**, `state.st` never used (the old state leaks) |
| `sink(state.st) + sink(state.st)` | R1 twice | **error** |

`accept/t197` (a handler storing its linear **parameter** into the state)
stays green: that is a use of the parameter, and R3 on `state`.

### Implementation

1. **`bind_linear_field_sentinels`** takes the env it already has and also
   registers `TCon` fields that `resolves_always_linear`, as `Linear`.
2. **`EField`** treats those fields exactly like `TLin` fields: sentinel
   lookup, the "complex expression" error for a non-variable base.
3. **Whole use (R2).** In `infer_expr`'s `EVar` arm, after `record_use`, if
   `env.lin` holds any `name#…` sentinels, `record_use` each one. Two call
   sites must **not** count as whole uses, and need a way to look the
   variable up without it:
   - `EField`'s base, when it is `EVar v`;
   - `ERecordUpdate`'s base, when it is `EVar v`. That site does R3
     instead.

   Use an explicit `infer_var ~whole_use:false` helper rather than
   re-matching `EVar` inline at both sites. The EVar arm carries a lot of
   module-path and import-tracking logic that must stay shared.
4. **R3.** In `ERecordUpdate`, when the base is `EVar v` with sentinels,
   `record_use` the sentinels of the fields not in `updates`.
5. **R4.** Every scope close includes the closed binders' sentinels:
   - `check_fn`: add `p#f` names for each record-typed param;
   - `infer_block`'s let close: run for a binding that has sentinels even
     when `auto_lin` is `Unrestricted`;
   - lambda and `ELetFn` closes: automatic, if the identity-based helper from
     [[2026-09-10-linear-lambda-parameter-not-must-use]] has landed (the
     sentinels are consed in the same scope). Remove that item's "skip `#`
     names" exclusion in this change;
   - actor handler: include `state#f` for every linear field of the state.
6. **Actor `state`.** Build `state_ty` honouring `fld_lin`, the way the
   record-type arm above it does (wrap in `TLin` when not `Unrestricted`).
   Bind with `bind_var` followed by
   `bind_linear_field_sentinels "state" state_ty`, the same pair
   `bind_vars_with_linearity` uses. The `init` expression is then checked
   against a state type with `TLin` fields, which the record-type path
   already handles for record literals.
7. **Diagnostic.** When the second use of a sentinel comes from R2 or R3,
   the plain "used more than once" message is correct but hard to act on.
   Give `record_use` an optional `~via:(`Whole | `UpdateBase)` and, for the
   update base, say:

   ```
   `state.st` was already consumed, but `{ state with … }` keeps every field
   you don't replace, so the old value would survive into the new record.
   Replace it too: `{ state with st: … }`.
   ```

### Decision to confirm: R4 makes dropping such a record an error

R4 means `fn f(r : R) : Int do r.n end`, with `R` holding an `always_linear`
field, is rejected: `r.st` is never used. That is the linear rule applied
honestly (the handle leaks), and it is what makes the fresh-record handler
above an error. But it is the change most likely to reject existing code.
**Recommended: adopt R4**, and let the blast-radius run show the cost. If it
is too high, the fallback is R1–R3 without R4: the duplicate half is fixed,
and dropping a record stays a documented affine-like leak.

### Limits, stated

- **One level.** Sentinels are per direct field. `state.inner.st` still hits
  the "complex expression" error (for `TLin` today, and newly for
  `always_linear` fields), and `let i = state.inner` does not make `i`
  linear, because `Inner` is not itself a linear type. That is containment,
  and it belongs to [[2026-09-13-linear-generic-code-and-containers]].
- **Use after move of an unrestricted field.** `let r2 = r` then `r.n` stays
  legal. No linear value is duplicated, so it's not this item's concern.
- **Branches** follow `iter_paths_linear` (sentinels are ordinary `env.lin`
  entries), including its union rule; see
  [[2026-09-13-linear-consumed-on-one-branch-only]].

## Tests

Reject witnesses (RED on `main` first):

- the actor program above → `used more than once` (and the new update-base
  wording, if step 7 lands);
- actor `sink(state.st) + sink(state.st)`;
- actor with a `linear st : T` field, consume then retain;
- actor with a `linear st : T` field accessed twice (the dropped qualifier);
- let-bound record, `always_linear` field accessed twice;
- let-bound record, field consumed then record passed whole;
- param-bound record, field consumed then `{ r with n: k }` returned;
- record with an `always_linear` field passed whole twice;
- actor handler returning a fresh record that ignores the old `st` (R4);
- let-bound record with an `always_linear` field never touched (R4).

Accept witnesses:

- `{ state with st: bump(state.st) }`;
- a handler that never mentions `st`: `{ state with n: state.n + 1 }`;
- a handler that reads only `state.n` and returns `state` (R5 + R2 once);
- `accept/t197`, unchanged;
- a let-bound record whose linear field is consumed and then replaced:
  `let k = sink(r.st)` / `{ r with st: S1(k) }`.

Then: `scripts/types-oracle.sh` (every new diagnostic is a record holding a
linear field), `test/cap_mock/` and the actor suites (every handler now
binds `state` with sentinels), the session goldens, and
`~/code/bastion_todos`.

## When fixed

- Rewrite `specs/lang/linear-types.md`'s "Linear Record Fields" section to
  state R1–R5, and mirror it into `docs/linear-types.md`.
- The endpoint line no longer needs its "keep the session state out of actor
  state" workaround. The shipped actor-hosted endpoint
  (`specs/progress/2026-09-11-actor-hosted-session-endpoint.md`) keeps state
  in the transport's continuation for its own reasons, but the parked,
  handler-shaped `@[endpoints(actor)]` variant it lists as future work would
  hold states in actor state, and this item is its prerequisite. Note that
  there.
