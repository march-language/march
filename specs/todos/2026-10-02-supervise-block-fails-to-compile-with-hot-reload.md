`[P1]` **Any `supervise` block fails to compile with `--hot-reload`.**

Found 2026-10-02 (origin/main 88397fbdb) while building the observe R1 tests:

    MARCH_RUNTIME_DIR=$PWD/runtime ./_build/default/bin/main.exe --compile \
      --hot-reload Main -o /tmp/t test/native/actor_on_stop_tree.march
    ... error: use of undefined value '@$sup_child_ptr_a'
      %gl = call ptr @$sup_child_ptr_a()

The same file compiles without `--hot-reload`. `$sup_child_ptr_<field>` is a
local introduced by supervisor spawn lowering (`lib/tir/lower_actor.ml`, around
lines 430-540; also `lib/tir/cap_passing.ml:221`); under `--hot-reload` a
reference to it becomes a call to a global that does not exist. Deployed nodes
are `--hot-reload` builds, so a supervised app cannot be built for hot deploys.

Acceptance: a native rule compiling a supervisor program with `--hot-reload
Main` and running it; the observe R1 fixture
(`test/native/observe_snapshot.march`) can then also run as a hot-reload build.
