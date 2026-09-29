# `run_until_idle()` no longer returns mid ping-pong (fixed 2026-09-28)

**Reproduced.** Two actors bounce one message 200000 times, and `main` calls
`run_until_idle()` and then reads both hit counts with `get_actor_field`
(`test/native/run_until_idle_ping_pong.march`). Compiled `--opt 2` and run
directly, 8 at a time, with `MARCH_NUM_SCHEDULERS=14`, at host load 30-45 on a
14-core Mac, origin/main's runtime printed a short total (`total 7733`,
`total 97747`, ...):

| runtime | runs | short totals |
|---|---|---|
| origin/main | 320 | 3 |
| origin/main | 800 | 8 |
| origin/main, 2 schedulers | 320 | 0 |
| origin/main, default count | 400 | 0 |
| fixed | 800 | 0 |
| fixed | 800 | 0 |

**Mechanism (confirmed by the fix, which was the only change).**
`march_sched_wait_idle` (`runtime/march_scheduler.c`) scans the process
registry one slot at a time with relaxed loads. That scan is not a snapshot.
It can read B as WAITING with an empty mailbox, then A (still RUNNING a
moment earlier) sends to B and goes WAITING. The scan then reads A as idle
too. Every proc looked idle, so it returned with the ball in flight. This is
the reading the report suggested.

**Fix.** Add a global `g_sched_activity` counter, incremented `seq_cst` after
every event that creates work for another proc:
- a message push (`mbox_push_node` and the batch requeue);
- a proc being published (`sched_spawn_common`).

`wait_idle` reads the counter before the scan and again after an idle
verdict. It returns only if the counter is unchanged; otherwise it scans
again. Because the increment comes after the push, a scan that starts after
the increment sees the message itself, and one that starts before it sees
the counter move. A same-box interleaved A/B of `bench/actor_ping.march`
(6 runs each, load ~30) shows no measurable cost: medians of about 1.21 s
for both.

**Guarantee, documented.** `specs/lang/actors.md` ("Running Until Idle"),
with `docs/actors.md` regenerated, now states what `run_until_idle()`
waits for:
- no runnable or running process;
- no deliverable message;
- no live timer wake;
- no send or spawn during the check.

It also states what it does not wait for: a pending `send_after` delivery,
and work in other OS processes or on other nodes.

**Test.** `native_run_until_idle_ping_pong` runs the ping-pong once at
`MARCH_NUM_SCHEDULERS=14`. That is a weak guard for a ~1% race, as the dune
comment says; the soak numbers above are the real evidence.

---

Original report:

# `[P3]` `run_until_idle()` once returned while two actors were still exchanging messages

Seen once, 2026-09-22, not reproduced since. An early `bench/actor_ping.march` (two
actors bouncing one message 1,000,000 times; `main` called `run_until_idle()` and then
asked both actors for their counts with `Actor.call`) printed `730492` instead of
`1000000` on its first run, compiled `--opt 2`, at load average ~35 on a 14-core Mac.
The next ten runs printed `1000000`.

A plausible reading: `run_until_idle` observed no runnable process in the window
between one actor's send and the other's wake-up. That would make it return with
messages in flight. Not confirmed from the code.

The benchmark now loops until the total reaches `n`, so it no longer depends on this.

**Acceptance.** Either a statement of `run_until_idle`'s guarantee in
`specs/lang/actors.md` that excludes this case, or a repro (run the ping-pong without
the loop a few hundred times under load) and a fix.
