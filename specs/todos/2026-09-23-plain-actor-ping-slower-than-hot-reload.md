# `[P2]` A plain (non-hot-reload) actor ping-pong runs 2.7× slower than the `--hot-reload` build

Found by the G1 boundary-cost measurement
(`specs/progress/2026-09-23-hot-reload-boundary-cost.md`), 2026-09-23, macOS arm64,
compiler at `12c062761`.

`bench/actor_ping.march` (two actors exchanging 1,000,000 messages), compiled `--opt 2`:

| build | wall (median of 5) | user | system |
|---|---:|---:|---:|
| plain | 3.57 s | 0.82 s | 2.30 s |
| `--hot-reload Game` | 1.31 s | 0.61 s | 0.96 s |

Reproduced in three more alternating pairs at load ~6 (plain 2.74–3.14 s, hot-reload
1.31–1.58 s). An instrumented copy shows both builds leave the benchmark's `wait_done`
loop after one iteration, so the gap is inside message handling, not the wait loop.

The extra time is almost all system time, which points at scheduler parking and waking,
not the handler's own code. The one known difference on the per-message path: in
`actor_green_thread` (runtime/march_runtime.c) a hot-reload actor's dispatch function is
called directly as `dispatch_fn(actor, msg)`, while a plain actor is called through a
closure wrapper (three arguments). Whether that, a difference in how the two lowerings
send or reply, or something in the handler's allocation changes how often the partner
proc parks is not known.

Every plain actor program pays this, so it is worth more than the hot-reload question it
was found under.

**Acceptance.** The cause identified (e.g. `sample`/`dtruss` on both builds, or a
per-message count of park/wake events), and plain within ~10 % of the hot-reload build on
`actor_ping`, or a recorded reason why it cannot be.
