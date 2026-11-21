# `forge test FILE` compiles and runs only the named files (done 2026-11-20)

Reported from Strata: `forge test test/acoustics_test.march` ran all 55 of
Strata's test modules (about 25 minutes), and a loop over the test files ran
the whole suite once per file.

## Cause

The compiled path of `Cmd_test.run_files` (`forge/lib/cmd_test.ml`) used the
first named file as the entry but put the project's whole `test/` directory on
`MARCH_LIB_PATH`. The compiler loads every `.march` file on that path, and
`--test` runs every test block it loaded, so the files named on the command
line only chose the entry point.

## Fix

`Cmd_test.stage_selected_tests`: when the named files are a strict subset of
`test/`'s test files, it stages in `.march/build/test-selected` (emptied each
run) a symlink to each named test file and to every helper (a non-test
`.march` file such as a fixture), at its path relative to `test/`. The
compiled run puts that directory on `MARCH_LIB_PATH` and uses the staged first
file as the entry. Naming every test file, a file outside `test/`, or nothing
leaves `test/` as it was.

Strata: `forge test test/input_test.march` now builds and runs input_test's
11 tests in 18 s.

## Test

`forge/test/test_forge.ml`, "forge test FILE stages only the named test files":
one of two test files is staged with both helpers (one nested) and without the
other test; naming both, or a file outside `test/`, stages nothing.
