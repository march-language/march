# `[P2]` `Session.hold_epoch`/`release_epoch` expose the stdlib-only epoch builtins to any code, with no capability

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
