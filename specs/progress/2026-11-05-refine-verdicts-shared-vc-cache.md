# refine-agreement: one verdict cache per run (x86 leg timeouts)

**Problem.** CI's `refine-agreement (ubuntu-24.04, linux-x86_64)` leg hit its 30-minute
"Refinement verdicts" step limit on main and on PRs alike (4 of ~25 runs, 2026-11-04/05;
passing runs took 19–29 min, while linux-aarch64 held at 15–17 and darwin-arm64 at 11–20
on the same work). Not a regression in any one PR: the x86 runners are slower and noisier,
and the step had no margin.

**Cause.** `scripts/refine-verdicts.sh` checks each of the ~930 fixtures from a fresh cwd,
and the verdict cache lives under the cwd (`.march/cas/vc`). Every fixture also re-reports
the stdlib's obligations, so a run asked z3 the same **1,406 distinct queries ~234,000
times**.

**Fix.** The fixtures of one run share one fresh cache directory (`OUT/vc.XXXXXX`, linked in
as each cwd's `.march/cas/vc`). Each fixture still gets a fresh cwd and the run a private
HOME, so nothing from before the run answers. The cache key carries the z3 identity, the
limits and the platform, so a hit is this run's own answer from this z3, and every distinct
query is still proved on every platform.

**Measured** (local, 14 cores, same tree): cold 240s / 231s, shared 117s / 127s / 114s.
Verdicts byte-identical to the cold run's (234,177 lines). The perturbation still goes red:
`--rlimit 2000` changes 7,441 lines.
