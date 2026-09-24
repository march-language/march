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
