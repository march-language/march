# Two "pre-existing test failures" that were one stale `_build` copy

Filed and fixed 2026-08-06.

## What was observed

A full `scripts/run-tests.sh` reported two failures that looked like real
compiler bugs:

| Suite | Failure |
|---|---|
| `cap_strip` 3 | `--cap-sandbox` pure binary does not embed a deny-default SBPL profile |
| `blocking_extern` 2 | `march --compile` fails: undefined `_march_test_blocking_nap`, `_march_blocking_calls`, `_march_blocking_threads_spawned` |

Both reproduced under `run-tests.sh` and neither reproduced when the same test
was run on its own — the classic shape of a build-staging problem rather than a
code one. `cap_strip` 3 additionally passed when run as `test cap_strip 3`, and
passed paired with each of its predecessors (`0,3`, `1,3`, `2,3`), which ruled
out in-suite ordering and the CAS (`MARCH_DEBUG_CASFLAGS` confirmed `capsandbox`
is in the cache key, and a plain compile followed by a sandbox compile of the
same source produced a profile-bearing binary).

## Root cause — one cause, two symptoms

Tests that shell out to the built compiler for a NATIVE compile link
`_build/default/runtime/*.c` and read `_build/default/stdlib` — dune COPIES of
the source trees. `run-tests.sh` built only `test/run_*.exe`, which does not
refresh those copies, so a runtime edit was simply absent from what the tests
compiled:

- `runtime/march_ffi.c` had `march_test_blocking_nap`; the staged copy did not
  → undefined symbol at link.
- `-DMARCH_CAP_PROFILE=...` is only referenced by `march_runtime.c`'s
  `MARCH_CAP_PROFILE` block, so against a staged copy predating that block the
  define expands nowhere and the profile string never lands in the binary
  → "no deny-default profile".

`diff -q runtime/march_ffi.c _build/default/runtime/march_ffi.c` showed the
divergence directly. Both tests pass after
`dune build @test/cas-runtime-dir` (which has the `source_tree` deps and so
restages as a side effect).

Note the repo already had a regression test for this exact divergence
(`@test/cas-runtime-dir`, added when the CAS key digested the wrong runtime
directory) — but it is in its own alias, so a `run-tests.sh` run never triggered
the staging it depends on.

## Fix

A staging-only rule in `test/dune`:

```
(rule
 (alias stage-source-trees)
 (deps (source_tree ../runtime) (source_tree ../stdlib))
 (action (progn)))
```

`scripts/run-tests.sh` now builds `@test/stage-source-trees` alongside the test
executables. The rule has no action; its only effect is making dune refresh the
copies, so the cost is a directory copy. Verified by deleting
`_build/default/runtime/march_ffi.c` and re-running `run-tests.sh -q stdlib`:
the file is restored and the suite is green.

`dune build runtime stdlib` does NOT restage (no such targets); `dune build
@install` does not either. The `source_tree` dep is what does it.

## Not a March bug: the third failure

`adversarial-regressions` 40 (MARCH_SANITIZE=1 hello-world must exit 0) timed
out. The test's own comment said to first rule out a machine-wide ASAN problem
by compiling and running a trivial unrelated `clang -fsanitize=address` C
program. Measured: that probe spins at ~98% CPU indefinitely on this machine
(macOS 26 / arm64), so no March change can be the cause.

Rather than leave that as a red suite forever, or paper it over, the test now
runs that discriminator itself — but ONLY after a timeout has already happened,
so a passing run pays nothing. A wedged probe (no March code in it at all)
downgrades the result to a counted `Alcotest.skip` with the reason logged; a
probe that exits keeps the failure and now says so explicitly ("this is not an
ASAN environment issue — treat it as a real March hang"). Verified both the skip
and the logged reason.
