# Pin: a narrowed cap cannot reach a `Cap(IO)` signature

**DONE 2026-09-22.** G2 of
[specs/plans/2026-09-21-distributed-deploys-groundwork-plan.md](../plans/2026-09-21-distributed-deploys-groundwork-plan.md).

## What the plan assumed, and what is true

The groundwork plan (G2) and its parent (D31, II.1, II.3) say that
`Cap(IO.NetListen)` *unifies* with `Cap(IO)`, so a narrowed cap passes where
`Cap(IO)` is expected and only the grant walk stops it. That is not what the
checker does on main. `Cap` is an ordinary type constructor
(`TCon ("Cap", [inner])` in `lib/typecheck/typecheck_unify.ml`), so
`Cap(IO.NetListen)` and `Cap(IO)` do not unify:

```
fn narrow(c : Cap(IO.NetListen)) : () do
  wants_io(c)          -- wants_io(c : Cap(IO))
end
```

gives `expected IO but got IO.NetListen` at the call. The grant walk rejects
the program as well, independently, naming the chain:

```
`main` is granted `Cap(IO.NetListen)`, but the program reaches `IO`
(reached from `main`: main → narrow → wants_io).
```

A `main(c : Cap(IO))` that calls `narrow(c)` directly is also a type error in
the other direction. It has to write `narrow(cap_narrow(c))`.

So D31's conclusion holds, and more strongly than the plan says: amplifying a
cap is refused by the type checker, and a narrowed `main` that reaches a
`Cap(IO)` signature by any route that does type-check is still refused by
the grant walk. The plan's sentence "`Cap` types themselves unify across the
lattice, so this is the walk's doing" is wrong. The step-2 todo
(`specs/todos/2026-09-22-dd-step02-unforgeable-references.md`) says so.

## Tests

`test/test_compiler.ml`, in the `typecheck` group beside the other grant
tests:

- `narrowed cap cannot reach a Cap(IO) signature`: the plan's program. Asserts
  the type error, the grant error naming `IO`, and the chain
  `main → narrow → wants_io`.
- `Cap(IO) grant reaches a Cap(IO) signature`: `main(c : Cap(IO))` calls
  `wants_io(c)` and `narrow(cap_narrow(c))`. Asserts no errors at all.

The first version of the second test followed the plan (`main(c : Cap(IO))`
calling `narrow(c)`) and asserted only that the grant error was absent. It
passed while the program had two type errors. Checking both programs with
`march --check` exposed that; the test now asserts `has_errors = false`.

`scripts/run-tests.sh compiler`: 1180 tests, all passed, both cases included (678 s,
load ~40; run with G3's seven tests present).
