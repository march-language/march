# `Session.hold_epoch`/`release_epoch` expose the stdlib-only epoch builtins to any code, with no capability

**DONE 2026-09-24.** Both wrappers take a `Cap(Session.Live)`, so only code holding a
session can pin or unpin an actor's epoch. Generated code no longer calls
`hold_epoch` at all (the transport holds at `register`; see
[2026-09-24-dd-review-hosted-register-path-takes-no-hold.md](2026-09-24-dd-review-hosted-register-path-takes-no-hold.md))
and calls `release_epoch(s)` only from `cancel(s, p)`, which gained the cap; the
raw builtins stay stdlib-only. `Session.epoch_holds_here()` is a new read-only count
for tests. Filed 2026-09-24; the text below is the finding as filed.

Filed 2026-09-24 by the distributed-deploys review (step 6, PR #612, commit
753336d36). Plan: II.4.4 says the builtins are stdlib-only. This is not listed
as a deviation.

## Defect

`stdlib/session.march:104-118` defines public `Session.hold_epoch()` and
`Session.release_epoch()` that take no cap and call `epoch_hold()` and
`epoch_release()`. They exist because generated `@[endpoints]` code lives in
user modules. Any code can therefore:

- pin its actor to an old epoch and block retirement. The hard deadline is off
  by default, so this lasts until someone sends `DRAIN`;
- release a hold that `SessionNode` or a generated endpoint took, so the actor
  advances in the middle of a session.

## Confirmed

```march
fn main(_c : Cap(IO.Console)) do
  Session.hold_epoch()
  Session.hold_epoch()
  Session.release_epoch()
  println("held without any cap")
end
```

`--check` exits 0 (re-checked at d3396f743). It runs interpreted and compiled.

## Fix I would make

Make the wrappers take `Cap(Session.Live)`, which every generated call site
already has in scope as `s`. Or accept the call only from desugar-generated
spans. See also `2026-09-24-dd-review-hosted-register-path-takes-no-hold.md`:
an unbalanced release is already reachable from generated code alone.
