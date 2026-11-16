# `[P3]` `hosted_protocol_change`: "served N, holds" off by one, under ASan

Found 2026-10-13 while looping the scenario under ASan for the
out-of-order-hello fix
(specs/progress/2026-10-05-hosted-protocol-change-unexpected-hello-under-asan.md).

**This is separate from that fix.** The out-of-order-hello panic was a delivery-order
bug in `SessionNode.deliver` and is fixed; this is a count in the scenario's expected
output read before a hold is released, seen in an UNFIXED run, and the per-sender
FIFO change neither causes nor fixes it.
One of 200 unfixed runs in the container (8 busy loops) printed
`host 1: served 1, holds 3` / `served 2, holds 2` / `served 3, holds 1`
instead of 2 / 1 / 0. Every served line was one hold higher than expected.

Likely cause: `Session.epoch_holds_here()` is read when the line prints,
and one hold was not yet released. The candidate is session 4's (its host's
`finish`, or its client's Endpoint, which releases on `ReleaseEpoch` in its
own turn, after `session(...)` has already returned in `main`). If so, the
golden asserts a count that races a release. Either `main` waits for the
holds to settle before `release(gate, ...)`, or the line prints the count
relative to this host. Not seen in plain runs.

## Cause found 2026-11-11: a stdlib bug, the hold really leaks. Not fixed yet.

The pre-1.0 plan (E3) took this for a scenario that prints a count too early. It is
not. `Session.epoch_holds_here()` counts the holds of the RUNNING actor, here the
hosting actor, and that actor both takes the hold (`register`, in its `Start` turn)
and releases it (`close`, inside `finish`, in its `Deliver` turn) before it prints.
No other actor's release (session 4's, a client Endpoint's `ReleaseEpoch`) can show
in this count. The line was right: host 1 did still hold three.

**The race** is in `SessionNode.ops`' `close` (`stdlib/session_node.march`):

    Vault.set(meta, "done", 1)
    match Vault.get(forward, "f") do      -- hosted? then release the hold
      None -> ()
      Some(_) -> epoch_release()
    end

"done" is what the session's runner is waiting for (`await_hosted_end` polls
`ep_done`). Once it is set, the runner goes on to `close_party`, which closes the
party's tables, `forward` among them, and a closed table reads empty. If the host is
descheduled between the two statements for long enough (the client has to read the
reply and close, its Bye has to arrive, the runner has to wake from a 10 ms sleep),
`Vault.get(forward, "f")` returns `None`, the release is skipped, and the host keeps
that hold for the rest of its life. In the sighting that happened to session 1 only,
which is exactly `holds 3 / 2 / 1`: one release lost, the next two fine.

**Forced, 1 of 1.** With a `sleep_ms(300)` between those two statements, in a private
copy of the stdlib (`MARCH_STDLIB=<copy> scripts/two-node.sh hosted_protocol_change`),
every hosted close loses its release:

    host 1: served 1, holds 3
    host 1: served 2, holds 3
    host 1: served 3, holds 3
    host 2: served 4, holds 1

**Why it matters outside the test.** A hosting actor with a leaked hold stays on the
code epoch its session formed under. After a hot deploy it is one of the "actor(s)
still on an old epoch" that only a hard drain deadline stops, and it pins that
epoch's code.

**The fix** (not made here: this was a test-harness package, and a stdlib change
needs its own test and CHANGELOG line). Decide "hosted" before anything can tear the
tables down, i.e. read `forward` at the top of `close`, or release the hold before
setting "done". The generated `cancel` path releases through
`Session.release_epoch` and does not read the table, so it is not affected. A
regression test can force the order without timing, the way "SessionNode delivery:
per-sender FIFO" does in `test/stdlib/test_session_node.march`: close the party's
tables after "done" is visible and before the release, and assert the host's count.
