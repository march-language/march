# ocap p6: granted-package code that gets no grant frame

Logged 2026-11-22 by ocap phase 6, Task 4 fix round 1 (review M4). Narrowed by the final
whole-branch review (I2).

One kind of code written in a granted package is not tagged by the lowering (nor by the
interpreter), so it gets no grant frame of its own: a derived impl's methods (`derive Show`
and the like), whose spans are synthetic (file `<none>`), so they have no package.

They are pure today (derived show/eq/hash call only the field types' own methods, which are
framed if they are a package's). An effectful derived method would run ungranted.

Fixed by the final review (I2): an interface default method written in a granted package and
inherited by an impl outside it (an app's empty `impl Greet(Mine)`) ran ungranted, and
`--check` passed, because the method was tagged by the impl's file. Now an impl method's
package is the file its code is written in (`Dep_grants.impl_method_file`: the method name's
file, which for an injected default is the interface's), in the lowering
(`Lower_state.note_fn_grant`) and the interpreter (`impl_grant`), and the static reach
charges such a method to the interface's package (`check_dep_grants`, `body_pkg`). Tests:
test/cap_conformance/grant_default_method, test_dep_grants "an inherited interface default
is the package's", test/errors/dep_grant_exceeded_5.

What to do: tag a derived impl's methods by the module that holds the `derive` (the impl's
declaring module), then add a test that reaches one from outside the package under a scoped
grant.
