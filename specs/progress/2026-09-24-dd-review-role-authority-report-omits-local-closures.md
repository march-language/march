# `[P2]` `--dump-role-authority` omits the local closures a role body captures

Filed 2026-09-24 by the distributed-deploys review (step 4, PR #596). Plan:
section 2 and II.2 (the report lists "the pids and closures the body
captures").

## Defect

A body that captures `let sv = fn n -> save(n)` or `let sv = fn n ->
file_write(…)` is accepted. Under D14 that is defensible, since a closure
`main` created is delegated authority charged to `main`. But the report prints
`values: none`, so it hides exactly the delegation it exists to show. Same root
cause as `2026-09-24-dd-review-role-grants-miss-let-bound-body.md`: locals are
not resolved.

## Confirmed

Both variants give `--check` rc 0, and `--dump-role-authority` prints
`values: none`.

## Fix I would make

Resolve locals as in the sibling todo and list them in `values`, whether or
not the plan decides to charge them.

## Fixed 2026-09-24

With locals resolved (see `2026-09-24-dd-review-role-grants-miss-let-bound-body.md`), the
report gained two lines per root:

- `closures: sv (closure in `main`, line 23) -> IO.FileWrite` — every local closure the
  body captures, transitively, with the function that made it, the line, and the IO caps
  its own row reaches. These ARE charged to the role (a captured function is part of the
  body's code), so a violation through one also appears in the check's chain.
- `holds: h -> Keeper -> IO.FileWrite` — every pid the body captures that the enclosing
  function spawned (`let h = spawn(Keeper)`), with the actor and its capabilities. These
  are NOT charged (D1: messaging a pid you hold is delegation); the line exists so the
  delegation is visible.

Plus, when the solver's `unknown` or an unresolved local applies, an `unverified:` line
with the reasons, and `invokes parameters:` when the root's row has `deps`. Both
variants from the finding now print the closure instead of `values: none`. Witness:
`cli_dump_role_authority_local_closures`; the original `cli_dump_role_authority` still
holds (`values: none`, `actors: none`, and now `closures: none`, `holds: none`).
