# `[P2]` Linearity: `_` over a container holding a linear value drops it

Filed 2026-09-18 during the [[2026-09-18-linear-map]] survey. A soundness hole, and a
prerequisite for `LinearMap`.

## The hole

The wildcard check ([[2026-09-13-linear-wildcard-discards-a-linear-value]]) shipped on the
same day as containment ([[2026-09-13-linear-generic-code-and-containers]]) and tests the
wildcard's own type with `is_linear_ty`. A wildcard whose type only **holds** a linear
value (`Option(S1)`, `(S1, Int)`, `List(S1)`) is not caught, so the value is dropped.
Measured on `main` `b4252d39b`, `always_linear type S1 = S1(Int)`:

| program | result |
|---|---|
| `let (_, n) = (S1(1), 2)` | rejected (correct) |
| `let (_, n) = (Some(S1(1)), 2)` | **accepted**; `S1(1)` is gone |
| `let _ = Some(S1(1))` | **accepted** |
| `match (Some(S1(1)), 2) do (_, n) -> … end` | **accepted** |

The `LinearMap` case: `let (_, m2) = LinearMap.put(m, k, v)` silently drops the displaced
value.

## Fix

`check_wildcard_discards` (`lib/typecheck/typecheck.ml`) tests `contains_linear env t`
instead of `is_linear_ty env t`. A record with a linear field should be included
(`contains_linear`'s default `~records:true`): `_` over such a record drops the field too.
The report message already prints the type.

Watch for `S1(_)` discarding an `Int` payload staying legal (the wildcard's type is
`Int`), and for generated code that uses `PatWild` over whole values (the endpoint
generator's `cancel` uses one arm per constructor precisely to avoid this).

## Tests

Reject: the three accepted rows above (RED on `main` first). Accept: `S1(_)` over an Int
payload; `(_, n)` over `(Int, Int)`. `types-oracle` must not move any existing fixture.

---

## What shipped (2026-09-18)

`check_wildcard_discards` tests `contains_linear` (records included). Witness
`reject/t253` (and `t248`, the LinearMap case); both fail with the check put back to
`is_linear_ty`. `types-oracle` moved no pre-existing fixture. Landed with
[[2026-09-18-linear-map]].
