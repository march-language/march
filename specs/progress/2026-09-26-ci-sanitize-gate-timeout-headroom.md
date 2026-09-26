# CI: headroom for the sanitize-gate ASan sweep

`sanitize-gate` in `.github/workflows/ci.yml` hit its 45 min step timeout on
main runs 36218685305 (job 108339687224, 8b541c44b) and 36221645823 (job
108347905453, 7b56b9e0e), and on PR #665. Both runs were killed during the
second-to-last two-node scenario (`topology_move`, with only `wrong_secret`
still to run), and every program before that was reported CLEAN.

## Diagnosis: no hang, no regression

I compared per-program times (the gaps between the `[golden/…]`, `[native/…]`,
`[two-node/…]` lines) against green main runs, using
`gh api --allow-escape-sequences repos/march-language/march/actions/jobs/<id>/logs`:

| run | commit | golden+native (s, excl. g01) | two-node (s, excl. hcr) | step |
|---|---|---|---|---|
| 36201991990 | 335d6e379 | 230 | 1476 | 29 min |
| 36151363227 | d39d1d454 | 255 | 1563 | 31 min |
| 36205920026 | 5bfa708d6 (last green before #663) | 248 | 1747 | 34 min |
| 36168897522 | ee0413cf4 | 308 | 1939 | 38 min |
| 36186395205 | ad217215a | 307 | 1993 | 39 min |
| 36194939239 | 8d5381eaf | 309 | 2003 | 39 min |
| 36209646384 | 1877afc22 (green, after #663) | 278 | 1925 | 40 min |
| 36218685305 | 8b541c44b (red) | 315 | 2173 | >45 min |
| 36221645823 | 7b56b9e0e (red) | 314 | 2173 | >45 min |

- The slowdown is **uniform**: every program in a red run is 20-30% slower
  than in the fast green run. No single program jumps. The same code has
  already run at both speeds (fast ~230-255 s, slow ~305-310 s golden+native
  on the day before), so the ubuntu runners come in two speeds. The red runs
  landed on slow ones.
- #663 (a6cafa213) added `two-node/hcr_new_code_session`. It compiles four
  ASan artifacts (two nodes and two patch `.so`s) and takes about 150 s. It is
  the only change to the sweep's contents in the window.
- On a slow runner, that scenario plus the list's earlier growth comes to
  about 46 min, just past 45. 1877afc22 (the first run with the new scenario)
  passed at 40 min on a medium-speed runner.

No bisect was needed: no program regressed, and the two commits in the red
range (#667, #666) show the same uniform ratio as the pre-#667 runs on
similar runners.

## Fix

- Step timeout **45 → 65**, job **65 → 80** (step + setup 12, rounded up).
  65 is about 40% over the worst projected slow-runner sweep, leaving room for
  the scenario list to keep growing. The workflow comment records why.

Not done, deliberately:

- **No shard.** `sanitize-gate` finishes well before the long pole,
  `test (macos-15, all)` at ~60 min. A second shard would buy no wall time and
  would add another toolchain setup + build to every run's Linux job-minutes
  (20 Linux runners org-wide; see `.github/workflows/README.md`, "Runner
  budget", and
  `specs/progress/2026-09-25-ci-macos-test-and-two-node-timeout-headroom.md`
  for the same trade-off on the two-node job). A longer timeout costs nothing
  while the sweep passes.

`.github/workflows/README.md` doesn't quote timeout values, so it needs no
edit. No CHANGELOG bullet: this is a CI-only change with no user-visible
effect.
