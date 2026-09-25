# `[P1]` `check_role_grants` does not check a role body passed through a local `let`, a parameter, or a `let`-aliased function

Filed 2026-09-24 by the distributed-deploys review (step 4, PR #596, commit
320fbb217). Plan: section 2 ("everything reachable from the closure, including
captured functions"), II.2. The progress entry does not restrict roots to
literal lambdas or top-level names.

## Defect

`lib/typecheck/typecheck.ml:7482` records the runner call's last argument as
the root, whatever it is. `:7558-7568` sets the root's refs to that argument's
free variables. A local `let` name or a parameter matches no key in
`own_cap_closures`/`fn_refs`, so it is dropped and the root is charged nothing.
`--dump-role-authority` then reports `reaches: nothing`.

## Confirmed

In each probe `role Cons needs IO.Console`, `save` calls `file_write`, and
`main(c : Cap(IO))`. Every one should be rejected:

| Probe | Body | `--check` |
|---|---|---|
| control | lambda literal calling `save` inside the nested `recv` lambda | rc 1, "body → save" |
| let-bound body | `let body = fn (s, con, st) -> … save(n) …`, then `run_Cons(…, body)` | rc 0 |
| parameter | `pfn go(c, b) do run_Cons(c, …, b) end`, and `main` calls `go(c, fn … save(n) …)` | rc 0 |
| aliased fn | `let sv = save`, then the body lambda calls `sv(n)` | rc 0 |
| local fn | a local `fn sv(n) do file_write(…) end` in `main`, called by the body | rc 0 |

The let-bound and aliased cases were re-checked at d3396f743 (rc 0, and rc 1
for the control).

## Fix I would make

- When the root is a local bound by `let`/`ELetFn` in the owner's body,
  substitute its right-hand side, repeatedly.
- When a free variable of the root is such a local, charge its right-hand
  side's builtin caps and free variables, transitively.
- When the root is a parameter of the owner, emit "cannot see the body passed
  to `run_R`; pass a lambda or a named function" rather than passing silently.
- Add each probe as a reject case.

## Fixed 2026-09-24

The root of the walk is now the VALUE that flows into the runner's body parameter.
`find_role_roots` walks each function body with the lexical scope the typechecker bound
it under (`iter_expr_scoped`: block `let`s and local `fn`s extend the scope, lambda /
match / `let?` binders shadow as opaque), and `resolve_root_value` follows the argument:

- a lambda literal, as before;
- a `let`-bound name: its right-hand side, repeatedly (a lambda, an alias of a name, a
  call result);
- a parameter of the calling function: every argument in that position at every call of
  the function in the same module (the stdlib is not searched, so its many local `go`s
  never match a user function of that name), each resolved in ITS caller's scope, to a
  bounded depth;
- a name not bound locally: a top-level function, as before, when it is a known key;
- a value BUILT by a call (`let b = pick()`): the callee and every non-literal argument
  are charged, since the result can reach only what they reach (the row solver's
  `CCharged`); the chain reads `body → pick → save`.

A lambda's free variables are expanded against the scope at its definition: a captured
local closure gets its own synthetic row (`<root>/<name>:<line>`), is charged (a
captured function is part of the body's code, plan section 2), and renders in the chain by
its local name (`body → sv → save`). A captured pid the enclosing function spawned is
HELD, not charged (D1: delegation), and listed by the report. A captured value with no
traceable origin is reported when the body invokes it.

What cannot be resolved — the argument itself (a record field, a match binder, a value
from a data structure), an invoked captured local of unknown origin, or (the row solver's
`unknown`, now computed with `with_rows:true` over seeds for every non-stdlib function) an
untraceable head invoked anywhere in the reach — is a WARNING at the call, not an error:
"cannot verify role grant for the body passed to `Stream_Run.run_Cons` at <file>:<line>:
value not statically known (...)", because under D14 a received closure is its creator's
authority. The grant is reported as unverifiable rather than passed silently.

D34 seeding: a named body's own `Cap(P)` parameters are read from its declaration; when
they differ from the role line the runner call is already a type error ("expected
`IO.Console` but got `IO.FileWrite`"), and the walk stays silent for that root rather than
reporting a second violation against a grant the body never claimed.

Witnesses (`test/test_endpoints.ml`): `cli_role_grant_let_bound_body` (a `let`-bound body
reaching `file_delete` under `IO.NetConnect`, rejected with `body → wipe`),
`cli_role_grant_parameter_body`, `cli_role_grant_aliased_fn`, `cli_role_grant_local_closure`
(`body → sv → save`), `cli_role_grant_call_built_body` (`body → pick → cons → save`),
`cli_role_grant_unresolvable_body_warns` (exit 0, the warning, no violation),
`cli_role_grant_wrong_cap_type`; corpus `reject/t295`. Each of the five probes above went
from `--check` rc 0 to rc 1 with the chain; the control stayed rc 1.
