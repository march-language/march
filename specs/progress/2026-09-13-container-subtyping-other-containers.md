# `[P3]` Container subtyping covers `List` and `Option` only

Filed 2026-09-13 when container subtyping landed
(`specs/progress/2026-09-13-container-subtyping.md`).

`Refine_scope.elem_refinement` is the single test of "does the checker
model this container", and it admits exactly `List(…)` and `Option(…)` with
a refinement one layer down. Still unenforced, and reported so by
`--refine-audit` (position `Type_arg`, nesting `Nested`):

- a refinement inside any other container's type argument — `Map(k, {Int |
  p})`, `Set({Int | p})`, `Result({Int | p}, e)`, a user ADT's argument;
- two layers of nesting: `List(List({Int | p}))` (the pinned audit fixture
  in `test/test_refinecheck.ml`'s `audit-flag` group uses this shape for
  exactly that reason);
- elements reached through a stdlib function rather than a `match`:
  `List.head(xs)` on `xs : List({Int | p})` returns an `Option(Int)` as far
  as the checker knows, so the element fact is lost there. Carrying it
  needs the stdlib signature to be polymorphic in the element refinement,
  which is the parametric half of container subtyping.

Each is an extension of the same three sites (`check_elements`'s literal
arms, `contenv`, the `EMatch` element facts); none needs a new mechanism.

## Design (2026-09-13)

`specs/2026-09-13-refinement-p3-designs.md` §2: the full design, soundness
argument, test list and effort estimate for this item.

## Landed 2026-09-13 (P3 design §2)

**§2a, other containers.** `Refine_encode.ctor_param_fields` records, per
constructor, which field carries which type parameter (`Param i`), the
container itself (`Self`), or something else — by hand for the builtins
(`Cons : [Param 0; Self]`, `Some`, `Ok : [Param 0]`, `Err : [Param 1]`),
from the type's own parameter list for every user variant. `elem_refinement`
admits any registered ADT with a refined type argument; `check_elements`
and the `EMatch` element facts are table-driven from the same registry, so
`Cons`/`Some` became the general case: `Ok(0)` under `Result({Int | _ > 0},
String)` is rejected, `Node(Leaf, 0, Leaf)` under a user `Tree({Int | _ >
0})` is rejected and `Node(_, x, right)` hands `x` the fact and `right` the
container entry. A stdlib type defined as a variant (`Map` is) is modelled
too; a tuple, an arrow, or an unregistered name is not, and the audit says
so (`test/refine_audit/holes/tuple_element.march` keeps the non-vacuity set
non-empty).

**§2b, two layers.** A container-env entry is `(container, slot list)` with
one slot per type parameter, each a refinement or a nested container entry;
`check_elements` recurses on a literal's nested container, and a `PatVar` at
a nested position takes the nested entry. `[[1], [0]]` under
`List(List({Int | _ > 0}))` is rejected; `Cons(inner, _)` hands `inner` the
inner entry. Variable-to-variable implication at a nested slot is a
recorded skip (no scalar stand-in for a symbolic nested element).

**§2c, elements reached through a polymorphic call.** `fn_sig.ret_ty` (the
declared return type) and `Refine_check.parametric_return`: `let h =
first(xs)` with `first : List(a) -> Option(a)` puts `h` in the env with slot
`a` = `xs`'s; `let x = hd(xs)` with `hd : {List(a) | …} -> a` gives `x` the
element refinement as a scope fact. `entry_of_sig` now keeps EVERY
signature (an unrefined one obliges and assumes nothing), so a stdlib
signature is resolvable. **Soundness, condition (i) enforced:** the rule
fires only if the callee cannot manufacture an element — every occurrence
of the type variable in the parameter types must be a direct argument of a
container parameter whose actual is a container-env variable. `put(xs :
List(a), v : a) : List(a)` has `a` bare, so `put(xs, 0 - 1)`'s result
inherits nothing (pinned). This was caught by a driver probe on `Map`, not
by the first draft of the tests.

Tests: `test/test_refinecheck.ml`, group `container-subtyping-2` (6 cases).
