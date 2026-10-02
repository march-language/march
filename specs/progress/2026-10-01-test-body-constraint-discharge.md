# Test/setup body constraints are discharged at the test, not the next fn

**Date:** 2026-10-01

## Symptom

Adding any top-level `fn` between two `describe` blocks of
`test/stdlib/test_control.march` made `march --check` report five
"`CtlAction` / `CtlDecision` / `(Int, List(String))` … does not implement
interface `Eq`" errors, all pinned to the span of the new fn. Moving the fn
above the first `describe` made the file check cleanly.

Minimal repro:

```march
mod R do
  type Hue = Rood | Bloo
  describe "a" do
    test "x" do
      assert (Rood == Rood)
    end
  end
  fn helper() do 1 end          -- blamed for the `==` above
  describe "b" do
    test "y" do assert (helper() == 1) end
  end
end
```

## Cause

`==` raises a `CInterface ("Eq", t)` constraint into
`env.pending_constraints`. `check_decl` discharges that list only at `DFn` and
`DLet` boundaries (`discharge_constraints env sp`). The `DTest`, `DSetup` and
`DSetupAll` arms checked their bodies but never discharged, so the constraints
leaked forward:

- a later `fn`/`let` discharged them under its own span (the misattribution);
- with no later `fn`/`let`, they were dropped at the end of the module, so
  `==` on a type with no `Eq` impl was never checked inside tests at all.

## Fix

`lib/typecheck/typecheck.ml`: the `DTest`, `DSetup` and `DSetupAll` arms call
`discharge_constraints env sp` after checking their body, like `DFn`/`DLet`.

Closing the hole surfaced real, previously unchecked `==` on non-`Eq` types in
12 stdlib test files. The types are plain data, so they now `derive Eq` where
they are defined (`derive` on a foreign type does not parse): `Cli.FlagArity`;
`Control.CtlHosts`, `CtlAction`, `CtlGate`, `StepOrder`, `CtlDecision`;
`File.FileKind`; `Membership.MemberStatus`, `Member`; `NodeCert.Cert`;
`NodeIdentity.Identity`; `RemoteCall.CallError`, `Verdict`, `ReplyResult`,
`CallReply`; `Swim.Action`; `VectorClock.ClockOrder`. The two tuple
comparisons in `test_control.march` now destructure the tuple, since tuples
have no `Eq` (see `todos/2026-10-01-tuple-eq.md`).

## Tests

`test/test_compiler.ml`, group `test_body_constraints`:
- the error is pinned to the test's line, not the following fn's (RED on the
  pre-fix compiler: it reported line 8, the fn);
- a `setup` and a `test` body with no later fn are both checked (RED pre-fix:
  zero errors);
- with `derive Eq`, a fn between `describe` blocks is accepted.
