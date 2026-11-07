`[P3]` `reveal f` for `@[opaque]` functions, and a per-proof fuel override.

Quick win 4 of `2026-11-06-verification-ladder-roadmap`. Dafny's `reveal` and `{:fuel}`.

## Now

`@[opaque]` keeps a function's body out of the logic everywhere. Fuel (how deep a chain of
unfoldings through one function goes) is set per function with `@[reflect(fuel: N)]`
(`specs/lang/refinement-types.md`, "Steps the facts decide, up to the fuel"); a proof that needs one
more step through a common function has to raise it for every caller, which costs solve time
everywhere.

## Wanted

- `reveal f` (a statement, like a lemma call) makes an `@[opaque]` function's definition available
  to the obligations after it in the block (or inside an `assert … by`, scoped).
- `with fuel(f, 4) do … end` raises `f`'s fuel for the obligations inside only.

## Done when

- Both statements are erased; obligations inside see the definition / extra fuel; outside, the
  default applies (a test shows a proof that needs both, failing without).
- `reflect-fuel` skip details suggest `with fuel(f, N)` with the depth that was exhausted.
