# `[P3]` Flake: `test_scheduler_mbox`'s `test_drop_new` sends to a daemon that may already have exited

Seen once, 2026-09-24, on the `test (macos-15, all)` leg of PR #618 (a forge-only change):
CI run 36041334583, attempt 1, job 107773957020, head 4017a1d3f. Attempt 2 of the same run
passed. The dune rule is the `test_scheduler_mbox_runner` one in `test/dune`
(`MARCH_NUM_SCHEDULERS=""`).

```
Assertion failed: (march_sched_send(dn, (void *)0x1) == MARCH_SEND_OK),
  function test_drop_new, file test_scheduler_mbox.c, line 329.
```

That is the FIRST of the three sends expected to succeed, before any drop happens.

## Likely cause (not yet verified)

```c
march_proc *dn = march_sched_spawn_daemon(nop, NULL);
march_sched_set_mbox_limit(dn, 3, MARCH_MBOX_DROP_NEW);
assert(march_sched_send(dn, (void *)0x1) == MARCH_SEND_OK);
```

The daemon's body is `nop`. If a scheduler thread picks it up before the test's first send,
it runs, returns, and the proc is dead — and since the dead-proc reclamation work
(#592 / #609) a dead proc is retired and its sends report DEAD rather than OK. The test
assumes the daemon is still alive when it sends; nothing guarantees that. Also worth
checking whether the preceding test's scheduler run (`test_dead_reap_drain`) leaves
scheduler threads running that make the pickup more likely.

## Fix direction

Give the daemon a body that stays alive until the test is done with it (block on a flag
the test releases after its assertions, or park until a message it never receives), so
the mailbox assertions test the mailbox, not a race with the daemon's exit. Check the
sibling tests in the file (`test_drop_old`, …) that spawn the same `nop` daemon for the
same assumption. Verify by running the runner in a loop under load (and with
`MARCH_NUM_SCHEDULERS` set high), before and after.
