# Current State (as of 2026-07-30, `forge test` resolves transitive deps)


**`forge test` built `MARCH_LIB_PATH` from DIRECT deps only**, while
`forge build`/`forge check` walk the graph transitively. `Cmd_build.lib_path_env`
(`forge/lib/cmd_build.ml:244`) calls `collect_transitive_deps` — a breadth-first,
nearest-wins walk that pulls in each dep's own prod `deps` recursively —
but `Cmd_test.project_env` (`forge/lib/cmd_test.ml:105`) mapped
`dep_to_lib_paths` straight over `deps @ dev_deps @ test_deps`. Consequence: a
project depending on `B`, where `B` depends on `C`, saw `C`'s modules from
`lib/` under `forge check` and NOT from `test/` under `forge test` — the test
compile failed with "Unknown module ..." for a call that typechecks two
directories away. This is the same class of bug as the earlier
`scroll`→`bastion`→`depot` failure, just on the one code path that never got
the fix.

`project_env` now uses `Cmd_build.collect_transitive_deps` over the test scope
(`deps` + `dev-deps` + `test-deps`, still excluding `dev-only-deps`), so it
inherits the same breadth-first nearest-wins shadowing — a project's own direct
path dep still beats a same-named dep reached through a sibling.

Pinned by a new unit regression in `forge/test/test_build_check.ml`
("project_env walks transitive path deps"): A path-deps `midb`, `midb`
path-deps `leafc`, assert `leafc/lib` is in `project_env`'s returned lib paths.
Fails on the old code, passes on the new. All seven other forge suites green
(242 tests); `test_build_check` has one PRE-EXISTING unrelated failure
("check: stdlib shadow does not corrupt an unrelated module"), confirmed by
reverting the change and reproducing it.
