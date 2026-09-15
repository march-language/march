# `[P2]` Linearity: an actor handler's parameters are not tracked at all

**Shipped 2026-09-12.** See "What shipped" at the end.

Found 2026-09-11 while designing the actor-hosted session endpoint
(`2026-09-11-actor-hosted-session-endpoint.md`), whose first design put the
session state in an actor message. Third hole in the same family as
[[2026-09-10-linear-lambda-parameter-not-must-use]] and
[[2026-09-10-linear-actor-state-field-retained-after-consume]], and the widest
of the three.

## The hole

A value of an `always_linear` type arriving as an actor handler's parameter is
tracked for **neither** use-at-most-once **nor** must-use. The lambda hole
loses only must-use; this one loses both.

```march
mod M2 do
  needs IO.Console
  always_linear type S = S(Int)
  fn sink(x : S) : Int do match x do S(v) -> v end end
  actor A do
    state { n : Int }
    init  { n: 0 }
    on Take(s : S) do
      let a = sink(s)
      let b = sink(s)          -- duplicated; accepted, no diagnostic
      { state with n: state.n + a + b }
    end
  end
  fn main(c : Cap(IO.Console)) do
    let p = spawn(A)
    send(p, Take(S(1)))
    run_until_idle()
  end
end
```

`march --check` exits 0. A handler that simply ignores `s` is likewise
accepted. Measured on `main` at `87101987`.

| shape | never used | used twice |
|---|---|---|
| named function parameter | rejected | rejected |
| `let`-bound, including a copy of a handler parameter | rejected | rejected |
| lambda parameter | **accepted** | rejected |
| **actor handler parameter** | **accepted** | **accepted** |

Two controls prove the probe is not vacuous:

- the handler body **is** typechecked — replacing `sink(s)` with `sink(42)`
  gives ``expected `S` but got `Int` `` and exit 1;
- `let t = s` followed by two `sink(t)` **is** rejected with "The linear value
  `t` is used more than once here", so the promotion machinery works on any
  binding derived from the parameter. Only the parameter's own binder is
  missed.

## Cause

Handler parameters are bound with a plain `bind_var`
(`lib/typecheck/typecheck.ml:4308-4314`):

```ocaml
List.fold_left (fun e p ->
    bind_var p.Ast.param_name.txt
      (Mono (match p.param_ty with
         | Some ann -> let tvars = ref [] in surface_ty env ~tvars ann
         | None     -> fresh_var env.level))
      e
  ) handler_env h.ah_params
```

No `bind_linear`, and none of the `always_linear` promotion that `ELet`'s
`auto_lin` and `bind_lam_param`'s `effective_lin` perform. The `state` and
`self` binders immediately above have the same shape, which is correct for
them.

## Why it matters

A linear value **can** be sent in an actor message — finding L6 in
`specs/lang/linear-types.md` records that deliberately, as a zero-copy move
whose sender is then prevented from touching it. The sender's half is
enforced; the receiver's half is not. So the one idiom the language documents
for handing a resource between actors drops every guarantee at the boundary.

It also undermines the shape the endpoint design recommended for actor-hosted
sessions ("it rides in each message and is `let`-bound inside the handler,
where tracking is real"): the `let`-binding is tracked, but nothing forces the
handler to write one, and the parameter can be dropped or duplicated first.
That recommendation is corrected in
`2026-09-11-actor-hosted-session-endpoint.md`.

## What to build

- Bind handler parameters through the same promotion path as a named
  function's parameters: an annotated parameter whose type resolves
  `always_linear` (via `resolves_always_linear`, not the raw registry — see
  [[2026-09-11-always-linear-registry-is-declaration-ordered]]) binds linear,
  and the handler body is subject to the same must-use check at its close as a
  function body is.
- Decide explicitly what "consumed" means for a handler whose body ends in a
  `{ state with … }` record update, and write the answer down: a linear
  parameter stored **into** the new state is consumed by that store; one
  neither stored nor passed on is dropped and must be an error.
- Check whether the lambda hole and this one share a fix. They are different
  binders (`bind_lam_param` vs. the handler fold) but the same missing step,
  and a single helper that binds a parameter with promotion would close both.
  If they are fixed separately, say so in each file.

## Tests

Reject witnesses (`specs/lang/types/reject/`, numbering after
[[2026-09-11-always-linear-registry-is-declaration-ordered]]'s):

- handler parameter used twice → `is used more than once`
- handler parameter never used → `was never used`

Accept witnesses:

- a handler that consumes its linear parameter exactly once;
- a handler that stores it into the returned state (whatever the decision
  above says, pinned as a test rather than left to fashion);
- the existing L6 witness (`accept/t68`) must stay green — the sender side is
  already correct and must not be double-reported.

Prove both rejects RED first: they are accepted today.

Re-run the actor suites and `test/cap_mock/` — handler binding is on the path
for every actor program, and a promotion that fires too eagerly turns ordinary
actor state into a linearity error.

---

## What shipped (2026-09-12)

Handler parameters are bound through `bind_lam_param`, the same helper a
lambda's parameters use, so they get the `always_linear` / `TLin` promotion
that a plain `bind_var` skipped; and `check_linear_all_consumed` now runs at
the handler body's close over the parameter names, the way `check_fn` runs it
over a function's.

The question the spec said to settle and pin: **storing the parameter into the
returned state counts as consuming it.** `{ state with held: s }` references
`s`, which marks it used, so an actor that HOLDS a resource is legal without
any special case. `accept/t197` pins both legal shapes, consumed-once and
stored-into-state.

Witnesses: `reject/t195`–`t196`, `accept/t197`, four unit cases. Both rejects
were silently accepted before. Full suite green, including the actor suites and
`test/cap_mock/`, which exercise handler binding on every actor program.

**Shared fix with the lambda hole: no.** `bind_lam_param` was already correct;
the handler fold simply did not call it. The lambda hole
(`2026-09-10-linear-lambda-parameter-not-must-use.md`) is that a lambda's body
close runs no `check_linear_all_consumed` at all, which is a different missing
step and stays open.
