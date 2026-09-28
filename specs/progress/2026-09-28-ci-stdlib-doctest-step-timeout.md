# CI: headroom for the stdlib `march>` doctest step

`conformance (ubuntu-24.04)` in `.github/workflows/ci.yml` killed PR #663's run
at 309 s, in the "Check stdlib `march>` doctests" step, which had a 5 min
timeout. No doctest failed. On main the same step took 195-251 s (for example
run 36265990806: 253 s; run 36254185021: 261 s), so 5 min left almost no room.

## Where the time goes

The step ran `dune build bin/main.exe` and then
`scripts/check-stdlib-doctests.py --check`. The build is not the cost:
`bin/main.exe` is already built earlier in the same job (the refinement
ratchet runs `dune build bin/main.exe`, and the scrollmd step runs it through
`dune exec`), so the build in this step is a no-op. The ~4 min is the doctest
script on the runner. The log prints nothing between the step start and the
final `N run, M skipped, 0 failed` line, so it can't show the split. The step
split below shows it directly.

A local same-box run of the script alone takes about 25 s cold. Why the
runner is ~10x slower is not investigated here.

## Fix

- The build moves to its own step ("Build compiler for stdlib doctests",
  10 min), so the doctest step's time is the script alone.
- Doctest step timeout **5 → 15** (about 3x the slowest observed pass).
- Job timeout stays **25**. The ubuntu job runs ~9 min end to end, ~4 of it
  this step. With every other step 30% slower on a slow runner and this step
  at its full 15 min, the job still ends around 21 min.

macOS skips both steps (`if: runner.os != 'macOS'`), so its leg is unchanged.
`.github/workflows/README.md` doesn't quote step timeouts, so it needs no edit.
No CHANGELOG bullet: CI-only, no user-visible effect.
