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
