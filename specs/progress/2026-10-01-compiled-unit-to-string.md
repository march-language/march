# Compiled `to_string(())` printed `0`

**Filed:** 2026-09-29 from the observe quick wins
(`specs/progress/2026-09-29-observe-quick-wins-results.md`, QW3).
**Fixed:** 2026-10-01.
**Regression guard:** `test/native/unit_to_string.march`, run compiled and
interpreted against one `.expected`.

## Symptom

`to_string(())`, `show(())`, `"${()}"` and any container holding a unit
(`(1, ())`, `[(), ()]`, `Some(())`) printed `0` in place of `()` when compiled. The
interpreter printed `()`.

## Cause

The todo guessed that the generic runtime formatter could not tell unit from an
Int, and that `to_string` should special-case a `Unit` static type at lowering.
That was half right: the formatter does read unit's raw word, but compiled code
should never have reached it. `lib/tir/lower.ml` already defines
`Show$Unit.show`, which returns `"()"`. It went unused because the unit VALUE is
typed as the empty tuple (`TTuple []`, printed `()` in TIR), not `TUnit`. Mono's
interface dispatch keyed the lookup by tuple arity, `"$Tuple0"`, found no impl,
and routed `show` to the generic `to_string` builtin
(`march_value_to_string`).

## Fix

`lib/tir/mono.ml`: the concrete-type key for interface dispatch maps
`TTuple []` to `"Unit"`, so `Show$Unit.show` resolves. One line.

## Verification

- The regression program printed `0` on every one of its seven legs under
  `main`'s compiler (`086a577e5`, built in a separate worktree) and `()` on every
  leg with the fix, matching the interpreter.
- `dune build --root . @test/runtest` (every native golden plus the Alcotest
  suites) and the TIR snapshots: no golden or snapshot changed; the only failures
  are `hcr stdlib actors` cases 3 and 4, which fail identically on `main`'s own
  build. `audit-baseline` gained the two lines for the new test (regenerated).
