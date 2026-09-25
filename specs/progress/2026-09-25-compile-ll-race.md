# Concurrent `--compile` of one source raced on `<source>.ll` (fixed 2026-09-25)

Fixed on branch `fix/compile-ll-race`.

## Symptom

CI macOS, PR #652 run 36106735935: the `native_qctor_collision_opt0` rule in
`test/dune` failed with `Undefined symbols for architecture arm64: "_main"` and
`march: clang failed (exit 1)`. Compiled alone the fixture was fine (6/6).

## Mechanism

`march --compile` wrote its LLVM IR to `<source-without-ext>.ll` beside the source,
whatever `-o` said, and passed that path to clang (native and wasm paths in
`bin/main.ml`). `native_qctor_collision` and `native_qctor_collision_opt0` compile the
same `native/qctor_collision/entry.march` with different `-o`/`--opt`, so dune can run
them together. One compile's `Sys.remove` + `open_out` truncated the shared `.ll` while
the other's clang was opening it. clang then linked an empty or half-written module,
which has no `main`.

## Fix

`bin/main.ml` now writes the IR to a per-process temp beside it,
`<basename>.<pid>.tmp.ll`, and runs clang on that temp. When clang returns (success
or failure) it `Sys.rename`s the temp onto `<source>.ll`. rename(2) is atomic within a
directory and replaces a read-only target, which covers Dune's sandbox. An `at_exit`
hook does the same rename on every other way out: the `exit 1` paths between writing
the IR and clang, and uncaught exceptions. So a failed build still leaves its IR where
it used to, and no `*.tmp.ll` is ever left behind. `--emit-llvm` uses the same
temp-then-rename, so a concurrent reader never sees a partial file.

The final `<source>.ll` location did not change. `test/dune` greps,
`test/test_cap_markers.ml`, `test/test_tcenv_cli_cache.ml` and `scripts/ir-oracle.sh`
all read it there. When several compiles run at once, the last one to finish leaves its
IR there. A CAS hit still writes no IR, as before.

## Evidence

The natural race window is only microseconds long (between open_out and the write). An
unsynchronised stress run of the pre-fix compiler did not hit it on a dev Mac: 0
failures in about 350 compiles, run as 4–16 concurrent compiles with jittered starts
and per-process CWDs so the CAS could not short-circuit them.

`test/test_compile_ll_race.ml` (run_compiler, group `compile_ll_race`) makes the race
deterministic. A `clang` shim first on `PATH` parks the first compile's clang on its
`.ll` input. A second compile of the same source runs to completion in the meantime.
Then the parked clang checks that its input is unchanged (same inode, same `cksum`).

- `origin/main` compiler: **RED 5/5** (`race.ll was replaced while clang held it`).
- With the fix: **GREEN 5/5**.

The second case, 3 rounds × 4 unsynchronised concurrent compiles with one at
`--opt 0`, is a contract test. It passes on both compilers. It asserts that every binary
runs with the right output, that `<source>.ll` exists afterwards and that no
`*.tmp.ll` remains.

Checked by hand: a failing clang (shim `exit 1`) still leaves `race.ll` and no temp;
`--emit-llvm` writes `race.ll`; compiling over a read-only (`chmod 444`) `race.ll`
succeeds.
