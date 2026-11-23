# ocap p6: the grant check picks a package impl by the first argument's type only

Logged 2026-11-23 by ocap phase 6, Task 3 (fix round 2).

When code outside a granted package calls an interface method that the package implements,
`Typecheck.check_dep_grants` decides which package impl the call reaches from the solved type
of the call's FIRST argument (its head constructor, from `env.type_map`). Only that impl
becomes a root of the static check. This under-approximates:

- a method whose dispatch type is not its first parameter (`tag(1, x)`, with `x` of the
  package's type) counts no package impl;
- a call whose first argument's type is a type variable, or a method used as a value, counts
  none either;
- two types with the same short name in different modules, each with an impl of the same
  method name, can be confused (impl keys carry only the short type name).

The run-time grant frame still holds in every case: such an impl is either unproven or reaches
beyond the grant, so it keeps its frame (plan decision 7), and its violation is a run-time
refusal instead of a `dep_grant_exceeded` at compile time.

What to do: take the dispatch position from the interface's declaration (the parameter whose
type is the interface's type variable), and key impls by the full type path.
