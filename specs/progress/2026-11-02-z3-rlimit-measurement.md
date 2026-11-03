# z3 rlimit: measured defaults

Part of the bundled-z3 work (`2026-11-02-bundled-z3.md`). The design asked for a default
`rlimit` about 10x the costliest proof, within the owner's budget (the refinecheck suite and
the stdlib build no more than ~25% slower than before), lowering the multiplier if needed but
never below the costliest proof + 50%.

## Measurement

`scripts/z3-rlimit-measure.sh` with z3 4.16.0 built by `scripts/install-z3.sh`, a private
HOME and cold caches, over the refinecheck suite and `march --check` of every
`specs/lang/types/{accept,reject}` fixture (each also checks the stdlib's own obligations).
Phase 1 ran at the then-default 3,000,000; phase 2 re-ran every query phase 1 left
`unknown` alone at 30,000,000.

| stage | queries | decided | max decided | p99 | p99.9 | unknown at 3M | of those, decided at 30M |
|---|---|---|---|---|---|---|---|
| main | 89,057 | 88,891 | 777,526 | 2,309 | 2,583 | 110 distinct | 0 (95 unknown, 15 past a 180 s cap) |
| stage 2 | 5,587 | 5,572 | 3,295 | 2,510 | 2,672 | 13 distinct | 0 |

Rejected (malformed) queries: 42, all from tests that send them on purpose.

Nothing undecided at 3M became decidable with 10x the budget: what is not proved is out of
z3's reach (quantifier loops, incomplete theories), not short of steps.

## Budget

Undecided queries use their whole limit, and they are 89–96% of all solver work, so cost
scales almost linearly with the main limit. Timed side by side with the merge-base build
(650206432, wall-clock 3 s / 1 s timeouts), same machine and load, cold caches, private HOME:

| | refinecheck suite (2088 cases) | `--check` hello (stdlib obligations), median of 3 |
|---|---|---|
| base, 3 s timeout | 1505 s (1 failure: `infer-apply` 5) | 3.27 s |
| rlimit 8,000,000 (10x) | 2053 s (+36%, over budget) | 3.38 s |
| base, 3 s timeout | 1715 s (1 failure: `infer-apply` 5) | 3.83 s |
| rlimit 3,000,000 (3.9x) | 1622 s (−5%) | 3.86 s |

The base's failure in both runs is the wall-clock timeout losing a proof on a loaded machine
(load average 25–90 from other work), which is the flakiness the rlimit removes; the rlimit
build passed all 2088 both times.

## Defaults

- **main: 3,000,000** — 3.9x the costliest decided query (floor: 1,166,289), within budget.
  10x (8,000,000) was 36% over.
- **stage 2: 50,000** — 15x the costliest decided stage-2 query (3,295); stage-2 queries
  were bounded by a 1 s timeout before.

Both are part of the VC and build cache keys. Override per project: `--refine-rlimit N`,
`MARCH_REFINE_RLIMIT`, or forge.toml `[refine] rlimit = N`.

## Oracle

`scripts/oracle-base.sh --base 650206432 refine` with these defaults: **IDENTICAL** (7968
`--refine-report` lines over 569 fixtures, 139,456 site verdicts recorded). No verdict moved.
