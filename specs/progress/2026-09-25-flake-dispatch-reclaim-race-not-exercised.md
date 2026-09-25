# `test_dispatch`'s reclaim race test: the blocked publish is now forced by a handshake, and the guard is back

Shipped 2026-09-25. Test-only fix; no runtime change. Closes the `[P3]` todo filed
2026-09-24 (`flake-dispatch-reclaim-race-not-exercised`, original report kept below).

## Cause

`test_reclaim_race_threads` (`test/test_dispatch.c`) relied on luck to get a publish that
finds its reclaim candidate pinned. The ring holds `MARCH_MAX_LIVE_VERSIONS` = 3
versions, and `pick_ring_slot` skips a pinned version when another non-current one is
reclaimable. So a publish is blocked only when **both** non-current versions are pinned
at the same moment, or when a pin lands in the narrow retire-then-recheck (Dekker)
window. Four free-running readers pinning one version each for a few dozen instructions
make that likely on an idle machine (locally 50–15,000 blocked publishes per run) but
not certain. On busy macOS runners it happened zero times in 1M publishes, twice.

Commit `7563085e0` (2026-09-24, "stabilize dispatch stress") had since removed the
`blocked > 0` vacuity guard and the loop's `blocked > 0` exit condition. That made the
test green, but it could then pass without ever exercising the race. This change puts
both back.

## Fix

A fifth thread, `recl_holder`, performs a handshake with the publisher:

1. It pins `enter_gen(k-1)` and `enter_gen(k-2)` and keeps them only if they are two
   distinct versions, neither of them current. Validated pins keep those slots from
   being recycled, and a publish only ever installs into a free or reclaimed slot, so
   neither can become current while held.
2. With current plus those two, all 3 ring slots are occupied and unreclaimable. The
   publisher's next attempt **must** return -1, through either the refs filter or the
   Dekker recheck. The publisher now publishes its blocked count (`g_recl_blocked`).
3. The holder waits (yielding) until that count moves or the publisher stops. It then
   checks neither of its versions was closed while pinned (the same overlap check the
   readers do) and lets go. One handshake per run.

The publisher loop again runs until `k > MIN_PUBS && blocked > 0 && pins >= MIN_PINS`,
capped by `MAX_PUBS` and the 10 s deadline. The deadline is now checked every 1024
**attempts**, not every 1024 values of `k`: a blocked attempt does not advance `k`, so
the old check could not fire while the publisher was stuck on a blocked slot. The
`blocked > 0` guard is restored beside `pins >= MIN_PINS`. Both are still skipped on
a 1-CPU machine.

## Evidence

Guard fails when the mechanism does (deliberate breaks, scratch copies of the test,
not committed):

| break | result |
|---|---|
| readers **and** holder never pin (`enter_gen` call replaced with NULL) | `FAIL ...: readers actually pinned ...` **and** `FAIL ...: some publishes found the candidate pinned (else no race exercised)`; `publishes=1000000 pins=0 blocked_publishes=0` |
| free readers never pin, holder does | blocked guard **passes** on the handshake alone: `pins=2 blocked_publishes=1 holder_handshakes=1` (the pins guard fails, as it should with only 2 pins) |

The second row shows the handshake alone produces the blocked publish, with no help
from chance.

Repeat runs (14-CPU machine, other sessions' load average 30–145):

| binary | runs | failures |
|---|---|---|
| guard restored, no handshake (the pre-`7563085e0` test) | 400 × 32 parallel + 300 × 48 parallel at background QoS | 0 (min `blocked_publishes` in a batch: 52) |
| fixed, direct `cc` build | 500 × 32 parallel + 300 × 48 parallel at background QoS | 0 |
| fixed, dune-built `test_dispatch_runner` | 500 × 32 parallel | 0 |

The original failure did not reproduce locally, so the "before" row shows only that the
old test is not flaky on this machine. The claim that the fix is deterministic rests on
the handshake argument and the second break above, not on repeat counts: every fixed
run reported `holder_handshakes=1`.

---

## Original report (filed 2026-09-24)

Seen 2026-09-24 on the `test (macos-15, all)` CI leg of PR #617 (a change to one
unrelated native test fixture; run 36014086206, job 107681985040).

```
PASS: test_reclaim_race_threads (publishes=1000000 pins=27748 blocked_publishes=0 overlap=0)
  FAIL [test_reclaim_race_threads:436]: some publishes found the candidate pinned (else no race exercised)
test_dispatch: 1 check(s) failed
```

The vacuity guard requires at least one publish to find its reclaim candidate pinned by
a reader (`blocked > 0`); otherwise the race was never exercised and the pass proves
nothing. Here readers pinned 27,748 times but no publish ever overlapped a pin: the
correctness check (`overlap=0`) passed, only the "did we test anything" check failed.
Fix direction was to keep the guard and make the overlap deterministic (loop until
`blocked > 0`, or a handshake where a reader holds its pin until a publish has observed
it).
