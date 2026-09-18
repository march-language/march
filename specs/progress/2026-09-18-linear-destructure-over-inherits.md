# `[P3]` Linearity: destructuring a linear value with `let` makes every binder linear

Filed 2026-09-18 during the [[2026-09-18-linear-map]] survey. A false positive, not a
soundness hole, but it hits every "answer plus the map back" API.

## Symptom

On `main` `b4252d39b`, with `always_linear type S1 = S1(Int)`:

| program | result |
|---|---|
| `let (n, s) = (5, S1(1))`, then `n + n + sink(s)` | **rejected**: "`n` is used more than once" |
| `let (n, s) = pair()` with `pair : () -> (Int, S1)`, same | **rejected** |
| `match pair() do (n, s) -> n + n + sink(s) end` | accepted |
| `match T(5, S1(1)) do T(n, s) -> n + n + sink(s) end` (`always_linear type T`) | accepted |
| in `fn f(m : LM)` (`always_linear LM`), `match m do LM(n, inner) -> (n, LM(n, inner)) end` | **rejected**: `n` used twice |

So `let` and a match on a linear **variable** make every binder linear, while a match on
a fresh expression does not. For `LinearMap`, `let (count, m2) = LinearMap.size(m)` would
make `count` linear, and `let (ks, m2) = LinearMap.keys(m)` would make the key list
linear.

## Cause

`ELet`'s `auto_lin` computes one linearity for the whole right-hand side and applies it
to every binding of the pattern. Match arms inherit the scrutinee variable's linearity
(`inherited_lin`) in the same way.

## Fix

A binder gets linearity from its **own** type: linear if the type is linear, holds a
linear value, or mentions a type variable that is linear-ok in the enclosing function
(so an opted-in `linear x : (a, Int)` destructured as `let (y, n) = x` keeps `y`
tracked). A binder whose type is ground and holds nothing linear (`Int`, `List(Int)`,
`String`) is unrestricted. That is sound: destructuring consumes the container once, and
a component that is not linear can be copied freely.

## Tests

Accept: the three rejected rows. Reject: `let (a, b) = (S1(1), 2)` with `a` used twice
stays rejected, and so does a linear-ok type-variable component used twice.

---

## What shipped (2026-09-18)

`inherits_linearity` (`typecheck.ml`), used by `bind_pattern_bindings` (match on a
linear variable) and by `ELet` when the binding was promoted because of what the RHS
type holds. When the whole value is linear because of its type, a component inherits
only if its own type is linear, holds a linear value, or mentions a type variable.
When the whole was made linear by an explicit qualifier (`linear x : Int`, `linear
let`), every component still inherits, as before. Witness `accept/t254`, plus the
`n * n` in `accept/t244`; both fail with the rule off. `types-oracle` moved no
pre-existing fixture.
