# `[P1]` `let pid_of_int = pid_of_int` switches the stdlib-only gate off for its module

Filed 2026-09-24 by the distributed-deploys review (step 2, PR #594). Plan: II.1.

## Defect

A module-level `DLet` of a gated name counts as a local declaration that
shadows the builtin, so the gate skips the whole module
(`lib/typecheck/typecheck_caps.ml:212-213` with
`lib/typecheck/typecheck_builtins.ml:334-356`). That includes the `let`'s own
right-hand side, which is the builtin itself.

## Confirmed

```march
let pid_of_int = pid_of_int

fn main(_c : Cap(IO.Console)) do
  let v = spawn(Victim)
  let p = pid_of_int(pid_to_int(v))
  let _ = send(p, Bump())
  ...
```

`--check` exits 0 (re-checked at d3396f743). Interpreted and compiled, it
prints `forged hits=2`.

## Fix I would make

The resolution-based check in
`2026-09-24-dd-review-stdlib-only-gate-skips-impl-interface-test.md`. At
minimum, a `DLet` must not count as shadowing its own right-hand side, and
that right-hand side must still be scanned.
