# ocap p6: granted-package code that gets no grant frame

Logged 2026-11-22 by ocap phase 6, Task 4 fix round 1 (review M4).

Two kinds of code written in a granted package are not tagged by the lowering, so they get no
grant frame of their own:
- a derived impl whose span is a dummy (no file, so no package);
- an interface default method written in the package but instantiated for an app type.

Both are pure today (derived show/eq/hash, no effectful default methods). An effectful default
method in a granted package would run ungranted when reached from outside it.

What to do: tag those by their declaring module, then add a test that reaches each kind from
outside the package under a scoped grant.
