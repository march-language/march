# forge test silently drops test modules that fail to compile

`forge/lib/cmd_test.ml` (compiled path, ~163-192) picks `List.hd test_files`
as the sole compile entry point and relies on `MARCH_LIB_PATH` (test/ dir
included) to auto-discover every other `*.march` file under `test/` as an
import. If one of those non-entry test modules fails to typecheck/compile,
`invoke_compiled` only sees the compiler's diagnostics for whatever import
graph it manages to resolve — in practice a broken test module can be
dropped from the run entirely rather than surfacing as a build failure, and
the suite reports `0 failures` with a silently lower test count than the
source actually contains.

Found while adding a compiled regression test for the `Vault.ns_get`
niche-encoding bug (see
`specs/progress/2026-08-17-vault-ns-get-missing-namespace-niche-encoding.md`)
— not itself blocking, since the test suite in question
(`test/test_stdlib_suite.ml`) is alcotest/OCaml-driven and doesn't go through
`forge test`, but worth hardening so a March-side `forge test` test suite
can't develop the same blind spot.

Fix direction: treat a non-zero/errored compile of *any* discovered test file
under `test/` as a hard failure of the `forge test` invocation, not just a
failure of files reachable from the chosen entry's import graph. Needs a
repro case first (a `test/` dir with two `*.march` test files, one of which
has a deliberate compile error) to confirm the current silent-skip behavior
before changing `cmd_test.ml`.
