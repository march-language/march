# ocap p6: the grant check picks a package impl by the first argument's type only

Logged 2026-11-23 by ocap phase 6, Task 3 (fix round 2). Corrected by the final whole-branch
review (I3, C1).

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

This is reachable from ordinary generic code, not only from contrived programs: an app
function `fn go(x) do peek(x) end` called with the package's type, a method passed as a
value to `List.map`, or generic stdlib code that calls `compare` or `hash` on a package type
all reach a package impl the static check never judged. Inside a package the reach walks
every resolved reference, but a generic call there (`show(x)` resolving to the stdlib's
`Show`, `peek(x)` naming another package's interface) does not follow into the impl either.

The static check is therefore not the guarantee. The run-time grant frame is the backstop,
and it holds in every case: such an impl is either unproven or reaches beyond the grant, so it
keeps its frame (plan decision 7), and every capability operation it attempts is checked
against the grant at run time. A violation is a run-time refusal instead of a
`dep_grant_exceeded` at compile time.

`IO.Foreign` used to be the exception, since no extern call was checked at run time (final
review C1: an app's `fn gopeek(x) do peek(x) end` ran a granted package's `extern getpid`
under a grant of `IO.Console`, `--check` clean). Closed two ways: an extern any function of a
granted package can reach needs `IO.Foreign` in the grant package-wide, whatever the reach
sees (`check_dep_grants`); and at run time every extern call of a program built with a
grant frame goes through `Authority.foreign_guard` (compiled: `Auth_rt.guard_externs`;
interpreter: the `VForeign` arm of `apply_inner`), which panics when a grant layer in force
does not admit `IO.Foreign`. That covers C in an ungranted package reached from a granted one
through generic code. Tests: test_dep_grants "an extern in a granted package needs
IO.Foreign, reached or not" and "an extern under a grant without IO.Foreign is refused at
run time"; test/errors/dep_grant_exceeded_4.

What to do: take the dispatch position from the interface's declaration (the parameter whose
type is the interface's type variable), key impls by the full type path, and count every
impl of the method for a call whose dispatch type is not known (sound, at the price of
false positives), so the static check is a guarantee rather than a best effort.
