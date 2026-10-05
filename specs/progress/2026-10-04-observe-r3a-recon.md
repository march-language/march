# Observe R3a: `observe_query` and the `Recon` module

**Date:** 2026-10-04
**Plan:** [`plans/2026-09-28-observe-recon-shell-plan.md`](../plans/2026-09-28-observe-recon-shell-plan.md), item R3, parts 1-2.
**Tracking todo:** [`todos/2026-09-24-observe-recon-shell.md`](../todos/2026-09-24-observe-recon-shell.md).

R3 lands in stages: this one (the builtin and `Recon`), then `diagnose`
(March and OCaml over shared fixtures, `forge diagnose`), then `forge top` and
`forge status`, then remote-send counting.

## What exists now

- **`observe_query : String -> String`**, a stdlib-only builtin (the
  `Recon` module is its only caller; user code gets "use the `Recon` module").
  It answers one request line with the same envelope the observe socket
  serves.
  - Compiled: `march_observe_query` (`runtime/march_observe_snapshot.c`) runs
    the verb in-process through `march_observe_handle`, a new export of the
    server's request handler. Its string argument is borrowed
    (`lib/tir/borrow.ml`).
  - In-process callers are on a green thread, so a windowed `SCHED` or `TOP`
    (which `nanosleep`s the calling OS thread) is refused there with
    `windowed_in_process`, and an in-process `SCHED` defaults to lifetime
    figures. `TOP` gained an explicit window of `0`, meaning the cumulative
    counter, on both the socket and in-process.
  - Interpreted: `lib/eval/eval_observe.ml` builds the same envelope and field
    names from the interpreter's actor table for every verb. By design it has
    one "scheduler", no memory gauges (`null`), eager delivery (mailboxes
    usually 0), and a "crash ring" made of the dead actors whose death was a
    crash.
- **Interpreter counters** (R2's deferred parity): `actor_inst` gains
  `ai_slices`, `ai_msgs_in`, `ai_msgs_out`. Received and dispatched at the
  scheduler's pop (undone when a handler blocks in `receive` and the message
  goes back); sent in `mailbox_enqueue` when the message was actually
  enqueued, on the current actor.
- **`stdlib/recon.march`**, observe tier, every function taking a
  `Cap(Actor.Introspect)`: `info(c, pid) : Option(ActorInfo)`, `actors(c)`,
  `proc_count(c, attr, n)`, `proc_window(c, attr, n, window_ms)`,
  `tree(c) : List(SupNode)`, `node_stats(c) : NodeStats`,
  `crashes(c, n) : List(CrashReport)`, `epochs(c) : EpochReport`,
  `scheduler_usage(c, window_ms) : List((Int, Float))`. The windowed two
  take two samples and sleep the CALLING green thread in between. Decoding is
  by hand over `Json.get`: `derive Json` does not decode list fields reliably
  (`stdlib/control.march`'s note), and an eager stdlib `derive Json` would put
  a `from_json` in every program's scope.

## Tests

- `test/native/recon_basic.march`, run compiled AND interpreted, both diffed
  against one golden: every `Recon` function, with a registered worker, a
  2-child supervisor and a crashed child. Lines that differ by design are
  printed as properties (`rss_ok`, `schedulers_ok`, "in [0,1]"), so the two
  backends must agree on everything they print.

## Deviations from the plan

1. **The test is a native golden on both backends**, not
   `test/stdlib/recon_test.march`: that harness runs the interpreter only, and
   the point is that the two backends agree.
2. **No doctests**: every `Recon` function needs a live capability and
   actors, which a `march>` doctest cannot set up; the docs carry plain
   examples instead.
3. **`proc_count`'s counters are cumulative** (`TOP <attr> <n> 0`), since an
   in-process window is refused; `proc_window` is the rate.
