# `[P2]` Linearity: a lambda's or local fn's parameter is never checked for "must be used"

Found 2026-09-10 while reviewing
`2026-09-03-protocol-projector-typed-endpoints.md`, whose generated API hands a
linear session state to a user callback on every step. **Specced 2026-09-13**;
part of `specs/plans/2026-09-13-linearity-holes-plan.md` (step 2), which has
the full measured matrix.

## The hole

A value of an `always_linear` type bound to a **lambda** parameter, or to a
parameter of a **local `fn … end`** inside a block, and never used, is
accepted with no error and no warning. The same parameter on a top-level
`fn` or an actor handler is rejected.

```march
mod PB1 do
  needs IO.Console
  always_linear type S1 = S1(Int)
  fn run(k : S1 -> ()) : () do k(S1(1)) end
  fn main(c : Cap(IO.Console)) do
    run(fn st -> print_line("st abandoned"))   -- accepted, silently
  end
end
```

## Measured (main `8eb0d7ee`, 2026-09-13)

| binder | never used | used twice |
|---|---|---|
| top-level `fn` param | rejected | rejected |
| actor handler param | rejected | rejected |
| lambda, check mode: `run(fn st -> …)` | **accepted** | rejected |
| lambda, infer mode, annotated: `let f = fn (st : S1) -> …` | **accepted** | rejected |
| lambda, `linear` keyword: `fn (linear t : T) -> …` | **accepted** | — |
| lambda, two params, second unused: `run(fn (a, b) -> sink(a))` | **accepted** | — |
| local `fn g(st : S1) : Int do 0 end` | **accepted** | rejected |

Out of scope here and filed separately, because the cause is different:

- **Unannotated** infer-mode lambda params miss the used-twice check too.
  The type is still a variable when the param is bound, so it is never
  promoted: [[2026-09-13-linear-unannotated-parameter-never-promoted]].
- `fn _ -> …` discarding a linear argument:
  [[2026-09-13-linear-wildcard-discards-a-linear-value]].
- A value consumed on only one branch of the body:
  [[2026-09-13-linear-consumed-on-one-branch-only]].

## Cause

Parameter **binding** is already right: all three sites go through
`bind_lam_param`, which promotes `always_linear` types and `linear`/`affine`
keywords to tracked entries. That is why used-twice is caught. What is
missing is the scope **close**. `check_fn` (l.3417) and the actor handler
(l.4331) call `check_linear_all_consumed` after the body; none of these
three do:

- `infer_expr`'s `Ast.ELam` arm (l.1776): binds, infers the body, runs the
  capture check, returns the arrow. No must-use.
- `check_expr`'s `Ast.ELam` peel (l.2386): binds params one arrow at a time,
  checks the body in the innermost call, returns unit. No must-use.
- `infer_block`'s `Ast.ELetFn` (l.2955): `bind_lam_params`, then
  `infer_block env_inner [body]`. No must-use.

## Design

### A scope-close helper keyed on entry identity, not name

`check_linear_all_consumed env ~scope_span names` checks every entry in
`env.lin` whose `le_name` is in `names`. That is correct for `check_fn` and
handlers, which have no enclosing linear binders. It is **wrong for a
lambda**, because `env.lin` there also holds the enclosing scope's entries,
and a lambda parameter can shadow one:

```march
let s = S1(1)
let f = fn (s : S1) -> sink(s)        -- inner s consumed
println(int_to_string(f(S1(2)) + sink(s)))   -- outer s consumed LATER
```

This is accepted today, correctly (probe `Y1`). A name-filtered check at the
lambda's close would see the outer `s` still unused and report it at the
lambda's span: a false positive on correct code.

Add, beside `check_linear_all_consumed`:

```ocaml
(** Entries [after] added on top of [before]: the binders a scope introduced.
    [env.lin] is only ever consed onto, so these are a prefix of [after.lin];
    compare by the physical identity of [le_used] so a shadowed same-named
    outer entry is never mistaken for the inner one. *)
let lin_entries_added ~before ~after =
  let outer = List.map (fun le -> le.le_used) before.lin in
  List.filter (fun le -> not (List.exists (fun r -> r == le.le_used) outer))
    after.lin

let check_scope_consumed ~before ~after ~scope_span = …
  (* same message as check_linear_all_consumed, over lin_entries_added,
     Linear only, skipping the "#"-named field sentinels (the record item
     decides their must-use rule) *)
```

Then use it at all three sites, with `before` = the env on entry and `after`
= the env with every parameter bound:

- **`ELam` infer arm:** `env` / `env'`, after `infer_expr env' body`, span
  `lsp`.
- **`ELam` check peel:** restructure `peel` so its base cases return the
  innermost env (or run the check in place): after `check_expr env body …`
  in both base cases, `check_scope_consumed ~before:<peel's initial env>
  ~after:env`. **Do not** also check in the fallback `| _, _ -> infer_expr
  env (ELam …)` case: it re-enters the infer arm, which does its own check,
  and would double-report.
- **`ELetFn`:** `env_with_self` / `env_inner`, after the body, span `sp`.

Leave `check_fn` and the handler on the name-filtered helper. Moving them to
the identity helper is a harmless follow-up, but it would change two
known-good sites in a PR whose diff should show only the new ones.

### What stays exactly as it is

- **Affine binders.** The check fires only on `Ast.Linear`. Session-channel
  parameters resolve to `TLin` and `bind_lam_param` tracks them **affine**
  (the create-and-drop leniency), so a callback that receives an endpoint and
  doesn't drive it stays legal. Pin it with a witness.
- **Parameters named `_`.** `bind_lam_param` binds `_` as an ordinary name
  and it can't be referenced, so the new check would say "The linear value
  `_` was never used." Exclude `_` in this change and leave the rule to
  [[2026-09-13-linear-wildcard-discards-a-linear-value]], which owns that
  message. Both PRs must agree on the final behaviour.
- **The error text.** Same as a top-level fn: "The linear value `st` was
  never used." The span is the lambda (or local fn), matching the handler
  precedent of pointing at the scope rather than the binder.

## Tests

Reject witnesses, all accepted on `main` today (prove RED first):

- check-mode lambda, param never used (the program above);
- infer-mode lambda with annotated param, never used;
- infer-mode lambda with a `linear` keyword param on a plain type, never used;
- two-param lambda against `S1 -> S1 -> Int`, second param never used;
- local `fn g(st : S1) : Int do 0 end`, never used.

Expected text: `was never used`.

Accept witnesses:

- check-mode lambda consuming its param once;
- a lambda consuming its param by `match st do S1(e) -> e end`;
- nested callbacks, each consuming its own param:
  `with_s(fn s -> with_s(fn t -> sink(t)) + sink(s))`;
- **the shadowing program above**: guards against the name-filter false
  positive;
- an affine-keyword lambda param never used;
- a lambda receiving a `Chan(…)` endpoint and not driving it.

Unit cases for the same shapes in `test/test_compiler.ml`'s
`tag_and_typestate` group, beside `test_linear_actor_handler_param_*`. Add
the corpus rows to `specs/lang/types/INDEX.md`.

Before calling it done:

- `test/session/stream_endpoints.march`, `stream_actor.march`,
  `stream_actor_restart.march`, and `stream_replay.march` goldens unmoved. The
  generated `@[endpoints]` callbacks are exactly check-mode lambdas receiving
  `always_linear` states, so if they move, either the generator drops a state
  somewhere (a real bug the fix found: record it) or the check is wrong.
- `scripts/types-oracle.sh` diff shows only intended new diagnostics.
- `scripts/run-tests.sh` full, and `dune build --root . @types-check --force`
  with the log checked for the new count. Without `--force` the check is empty
  and exits 0.

## Docs

When fixed, add a row for lambda and local-fn parameters to
`specs/lang/linear-types.md`'s "Practical Rules" and mirror it into
`docs/linear-types.md`; both trees are served.
