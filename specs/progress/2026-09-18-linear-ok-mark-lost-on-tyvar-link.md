# `[P3]` Linearity: a `linear x : a` opt-in is lost when `a` is unified with another variable

Filed 2026-09-18 during the [[2026-09-18-linear-map]] survey. A false rejection, not a
soundness hole.

## Symptom

On `main` `b4252d39b`, with `always_linear type S1 = S1(Int)` and `fn g(x) do x end`:

| opted-in function, called at `S1` | result |
|---|---|
| `fn w(linear val : v) do Some(val) end` | accepted |
| `fn w(linear val : v) do g(val) end` | **rejected**: "`S1` is linear, but `w` is generic in a parameter of that type" |
| `fn w(linear val : v) do Some(g(val)) end` | accepted |
| `fn lm_put(m, key : Int, linear val : v) do match m do LM(inner) -> LM(Map.insert(inner, key, val, Map.int_cmp)) end end` | **rejected** |

## Cause

`mark_linear_ok` (`lib/typecheck/typecheck.ml`) records the parameter's type-variable
**id** in `env.linear_ok_ids` while the body is being checked. When unification later
links that variable to another unbound one (`r := Link t` in `typecheck_unify.ml`), the
representative is whichever variable the link points at, and the mark stays on the old
id. After generalisation `check_linear_instantiations` looks up the scheme's id, which is
then the unmarked one. Whether it fails depends on the direction of the link.

`cap_producer_ivars` has the same shape and handles it: the var-to-var arm of `unify`
propagates the tag to the variable being linked to. Do the same for `linear_ok_ids`, or
mark at generalisation by resolving the annotated parameter types through `repr`.

## Tests

Accept: the two rejected rows above. Keep `reject/t229`-`t231` (unmarked functions)
rejected.

---

## What shipped (2026-09-18)

The var-to-var arm of `unify` (`typecheck_unify.ml`) moves a `linear_ok_ids` mark to
the variable it links to, as it already did for `cap_producer_ivars`. Witness
`accept/t255` (fails with the propagation disabled). `types-oracle` moved no
pre-existing fixture. `@[trusted_linear]` marks the final representative directly,
so it never relied on this.

Following the mark exposed a related, older gap, filed as
[[2026-09-18-linear-shared-opt-in-tyvar-unchecked-param]]: any parameter whose type
is the opted-in variable can be passed a linear value, but only the one declared
`linear` is checked in the body.
