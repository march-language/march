# Observe R8: tracing with mandatory limits, and boundary call tracing

**Date:** 2026-10-11
**Plan:** [`plans/2026-09-28-observe-recon-shell-plan.md`](../plans/2026-09-28-observe-recon-shell-plan.md), item R8.
**Design:** [`2026-09-23-per-actor-introspection-design.md`](../2026-09-23-per-actor-introspection-design.md) section 5, stages C1/C2, narrowed (below).
**Builds on:** [`2026-10-05-observe-r4b-signed-debug-verbs.md`](2026-10-05-observe-r4b-signed-debug-verbs.md).
**Left open:** [`todos/2026-10-11-observe-trace-actor-events.md`](../todos/2026-10-11-observe-trace-actor-events.md).

## Decision: the smallest safe slice

C1/C2 as specced trace *actor events* (`Sent`, `Received`, ...) by hooking
`march_send`, the actor loop, spawn and death, behind `g_introspect_armed` and
per-proc flags. R8 as planned wants something narrower and different: a
`traced` bit per dispatch slot and boundary calls. Options:

1. Build both. Touches the send path and the actor loop; the acceptance
   ("disarmed cost nil" on `call_storm`) is about the dispatch path.
2. Boundary calls only, with the session machinery (ring, mandatory limits,
   pull delivery, lifetime) written so actor events can reuse it. **Chosen.**
3. Actor events only. Does not meet the plan's item 3.

Deferred: the actor events and PAYLOAD/INHERIT (C2), arity per event (the
dispatch table has none), `Recon.trace_*` wrappers, the TUI panel (R7's
agent), interpreter support. All in the todo above.

## What exists now

- **`runtime/march_trace.c`/`.h`** (role `hcr`): up to 4 sessions, each with
  a ring of 40-byte slots and a lock-free producer path.
  - `Count(n)`: ring of exactly `n` slots, a compare-and-swap on `head` that
    refuses past `n`, so exactly `n` events are recorded; the producer that
    takes slot `n-1` marks the session done and clears the slots' `traced`
    bits, so the dispatch path is back to a never-taken branch.
  - `Rate(n, s)`: a window counter (`n` per `s` seconds, the excess counted
    in `rate_dropped`) in front of a ring of 1024 (`ring:` up to 16384). A full
    ring drops and counts (`dropped`); producers never wait.
  - A producer announces itself (`inflight`), then checks `state`; stop
    sets the state and waits for `inflight` to reach 0 before freeing the
    ring (a seq_cst Dekker pair), so the ring is never freed under a writer.
    Slots are published with a per-slot sequence word, so a drain never reads
    a slot that is reserved and not yet written.
  - Lifetime: 600 s, or 60 s without a drain, whichever first; checked by
    the producer (it already reads the clock) and by drain. No timer thread.
- **`runtime/march_dispatch.c`**: `MarchDispatchSlot.traced`, a `uint32`
  session-bit mask placed after `current` (it fills what was padding, so the
  slot does not grow and shares `current`'s cache line). `march_dispatch_enter`
  and `march_dispatch_enter_gen` (and so `_enter_unit`) load it relaxed after
  pinning and call `march_trace_hit(name_id, mask, epoch)` when non-zero.
  `march_trace_hit` is weak in `march_dispatch.c`, so C harnesses that link
  only the dispatch table still build.
- **Events** are `{pid, name_id, epoch, at_ns}`: the calling actor's pid
  index (`-1` for `main`/tasks), the slot, the epoch of the version entered,
  and time since the session started (an absolute monotonic clock passes
  2^53 ns after ~104 days, which a JSON double cannot hold). **No arguments.**
- **Verbs** in `runtime/march_observe_debug.c`: `TRACE_START`,
  `TRACE_DRAIN`, `TRACE_STOP`, debug tier, built on R4b's `admit()`
  (signature, freshness, `$MARCH_DEBUG_POLICY`, audit), plus the unsigned
  `HELLO`. A request with no limit is `limit_required`; `count:0`, over
  65536, `rate:0`, `per_s` outside 1..3600, `rate` over 100000 are
  `limit_out_of_range`. Function names are `[A-Za-z0-9_.$]`, at most 32,
  each must be a registered dispatch slot (`unknown_function`). Audit lines
  gain a `detail` (session, limit, function count).
- **`stdlib/trace.march`** (`Trace`, in the manifest): `start(c, names,
  limit)`, `drain`, `drain_max`, `stop`, `format`; `type Limit = Count(Int)
  | Rate(Int, Int)`; errors as a `TraceError` variant. `start` takes the
  function list because a session has to name something (the plan's
  `Trace.start(c, limit)` has no room for it). It reaches the runtime
  through `observe_query` on the in-process path: `Cap(Actor.Debug)` is the
  authority, so no signature (audited as `"signer":"in-process"`). The
  remote shell pre-binds `debug`, so `Trace.start(debug, ...)` works there
  (not exercised live; the shell's fragments run the same builtin).
- **forge**: `forge observe --trace-start FNS (--max-events N | --rate N/S)`,
  `--trace-drain ID`, `--trace-stop ID`.
- Interpreter: `HELLO` answers; `TRACE_*` answer `tracing_unavailable`.

## Replay protection (a finding, fixed here for all debug verbs)

R4b's verbs had the shell review's F1/F2 hole (`reviews/2026-10-07-shell-r5-review-packet.md`):
the nonce ring is in memory and a request names no node, so a line captured up
to 60 s before a restart replays after it, and replays against any other node
with the same key. The observe socket serves one request per connection, so a
per-connection challenge like the shell's `session:` is not possible. Instead
every signed request now carries `boot:<32 hex>`, the process's random id from
the unsigned `HELLO`; a mismatch is `wrong_boot`, checked after the signature
and before the nonce is spent. Applies to `STATE` and `CRASHES_FULL` too (a
protocol change: older `forge` cannot sign for a new node, newer forge for an
old one gets `bad_args` there; they ship together). Not covered: a replay
within one process inside the 60 s window is stopped by the nonce ring as before.

## Tests

- `test/native/trace_boundary.march` (`--hot-reload Main`, compiled):
  every refused limit, an unknown and a stdlib function, `Count(10)` yields
  exactly 10 of 25 calls then stops (later calls not recorded), `Rate(3, 60)`
  keeps 3 and counts 7, only the named function is watched, an actor's pid
  appears, at most 4 sessions, room again after stop.
  `test/native/trace_interp.march`: the interpreter's `Unavailable`.
- `test/observe_debug_check.ml` over `test/native/observe_debug.march`
  (a 20 ms `tick` loop): `HELLO`, `wrong_boot`, a request with no boot id,
  every refusal at the verb level, replay of a signed `TRACE_START`,
  `Count(10)` = exactly 10 events and `done`/`why=count`, no more afterwards,
  event shape (exactly the five fields, no arguments), `Rate(2,1)` over 2.5 s,
  four sessions then `too_many_sessions`, policy withdrawal, audit lines.
  `test/observe_snapshot_check.ml`'s pinned `HELP` list gained the four verbs.
- `forge/test/test_observe_client.ml`: the signed line includes `boot`.

- Red controls (by file copy, restored after): a `Count` that never marks
  itself done turns `done=true why=count` red in `trace_boundary` (4 lines);
  a `TRACE_START` that defaults a missing limit to `count:100` turns
  `limit_required`, `four sessions start` and the audit check red in
  `observe_debug`.
- ASAN (Linux arm64, `march-amdr-repro`, `MARCH_SANITIZE=1`): `trace_boundary`
  output identical; the signed `observe_debug` fixture passes all checks with
  no sanitizer report from the node. LeakSanitizer at exit reports only the
  float boxes `Json.parse_number` leaks
  ([`todos/2026-10-08-json-parse-number-float-leak.md`](../todos/2026-10-08-json-parse-number-float-leak.md)),
  on every `Trace`/`Recon` call that parses a number; nothing from `march_trace.c`.

## Cost: A/B on the dispatch path

Compiled `--opt 2 --hot-reload`, same machine, load average 82-108 (other
sessions), alternating A/B runs, CPU time (user+system) because wall time
under that load is noise. A is `origin/main` 8b6a4b7da, B is this branch with
tracing compiled in and disarmed.

| Program | n | A median | B median | median delta | min delta | A/A (A vs copy of A) |
|---|---|---|---|---|---|---|
| `bench/actors/call_storm.march` (`--hot-reload CallStorm`) | 60 | 153.5 ms | 155.3 ms | +1.1% | -3.0% | -1.0% median |
| 300M boundary calls (`tick` via `march_dispatch_enter_unit`), 4 runs | 25, 25, 25, 40 | 2065, 2055, 2108(A/A), 2014 ms | 2090, 2120, -, 2033 ms | +1.2%, +3.2%, -, +1.0% | -0.6%, +0.3%, -, +1.4% | +0.1%, -0.8% (n=40) |

Under this load the A/A control alone moves by about +-1% and single runs by up to +-3%, so a real cost of 1% or less on the pure-dispatch loop cannot be ruled out or in; nothing larger shows up in four runs. `call_storm` barely calls
boundary functions, so the second program makes the dispatch path dominate.
The only change on it is the one relaxed load and branch described above.

## Security notes

- No arguments in any event. Events carry pids, slots, epochs, times.
- Bounded: 4 sessions, 32 functions, rings 65536 / 16384 slots, drains 4096
  events, lifetime 600 s, idle 60 s. Out-of-range limits are refused, not clamped.
- Function names are validated to `[A-Za-z0-9_.$]` before they reach the audit
  log; only registered dispatch slots can be traced.
- A session outlives the request that made it (no connection to tie it to);
  the timers above bound it.
- Debug tier: signature, `boot`, nonce/expiry, then `$MARCH_DEBUG_POLICY`,
  every attempt audited.
