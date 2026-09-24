# `[P3]` Flake: `test_dispatch`'s reclaim race test sometimes never exercises the race

Seen 2026-09-24 on the `test (macos-15, all)` CI leg of PR #617 (a change to one
unrelated native test fixture; run 36014086206, job 107681985040).

```
PASS: test_reclaim_race_threads (publishes=1000000 pins=27748 blocked_publishes=0 overlap=0)
  FAIL [test_reclaim_race_threads:436]: some publishes found the candidate pinned (else no race exercised)
test_dispatch: 1 check(s) failed
```

`test/test_dispatch.c`'s `test_reclaim_race_threads` (from #551, the HCR reclaim TOCTOU
fix) has a vacuity guard: it requires at least one publish to find its reclaim candidate
pinned by a reader (`blocked > 0`), otherwise the race was never exercised and the pass
proves nothing. That guard is right. Here readers pinned 27,748 times but no publish
ever overlapped a pin: the correctness check (`overlap=0`) passed, only the "did we test
anything" check failed. On a busy shared runner the reader threads and the publisher
evidently did not interleave.

## Fix direction

Keep the guard (a test that can pass without exercising the race is worse than a flaky
one). Make the overlap happen deterministically instead of by chance: for example, have
the publisher loop until `blocked > 0` or a generous iteration cap, or add a handshake
so a reader holds its pin until a publish has observed it at least once. Then the guard
only fails if the mechanism genuinely prevents overlap.
