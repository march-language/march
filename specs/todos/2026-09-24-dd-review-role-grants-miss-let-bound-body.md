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
