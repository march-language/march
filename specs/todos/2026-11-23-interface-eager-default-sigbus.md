# Compiled: two pre-existing failures found while testing interpreter grants

Logged 2026-11-23 by ocap phase 6, Task 5 fix round 1. Neither involves grants: both fail
with no grants file. Two `test/test_dep_grants.ml` `frames` cases run interp only because of
them.

1. **An interface default method whose body does work before yielding its lambda** crashes the
   compiled program. `test/dep_grants/apps/eager_default` with `deps/eager` (no grants):
   `march --compile` builds, and running prints
   `march: fatal SIGSEGV si_code=2 ... fault outside its stack` (exit 139; SIGBUS on some runs).
   The interpreter prints `default body: eager:allowed`.
2. **An app actor sharing its name with a library module's actor** fails to compile.
   `test/dep_grants/apps/actor_name_clash` with `deps/lifecycle`, where both define `actor W`,
   fails with clang `invalid redefinition of function '$actordrop$W_Actor'`. The drop-glue
   name is not module-qualified.

When each is fixed, add native mode to the matching `frames` case
("an interface default body runs under the grant at load" and
"an app actor named like a dep actor keeps the app's authority").
