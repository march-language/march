# Interpreter's `Actor.call` now enforces `timeout_ms` (fixed 2026-09-08)

Filed while implementing correlation-checked replies for the compiled runtime
(`.superpowers/sdd/2026-08-11-actor-system-hardening/`, Task 4;
`specs/progress/2026-08-11-actor-call-correlation-checked-replies.md`).

## What's wrong

`lib/eval/eval.ml`'s `actor_call` builtin binds its third argument as
`VInt _timeout_ms` — underscore-prefixed, genuinely unused. The interpreter's
implementation is:

```
Queue.push (VCon (hname, [VInt ref_id])) inst.ai_mailbox;
!run_scheduler_hook ();
(match Hashtbl.find_opt pending_replies ref_id with
 | Some result -> ... VCon ("Ok", [result])
 | None -> VCon ("Err", [VString "no reply (timeout or unhandled Call)"]))
```

It runs the scheduler hook exactly once, synchronously, and checks whether a
reply landed. There is no wall-clock deadline: a handler that takes
arbitrarily long (but still replies within that one scheduler tick) is
treated as answering *before* any timeout, regardless of the `timeout_ms`
value passed in. Conversely a handler that doesn't reply within that single
tick is reported as a timeout even if `timeout_ms` was very large (e.g.
`10000`).

This means `test/native/actor_call_late_reply.march` — which relies on a
short (1ms) timeout genuinely elapsing before a slow handler replies, so a
second call can observe the correlation-check discarding the late reply —
cannot be given matching expected output for both backends. Compiled: the
first call legitimately times out (`first: timeout`). Interpreted: the first
call's handler runs to completion inside the single scheduler tick and
replies "in time" by construction, so the interpreter reports `first:
unexpected ok` regardless of loop size used to slow the handler down.

This is **not** a bug introduced by Task 4 — the correlation-checking fix
lives entirely in `runtime/march_runtime.c` (the compiled backend); the
interpreter's `actor_call`/`actor_reply` pair already correlates replies by
construction (a private `ref_id`/`pending_replies` hashtable per call, no
shared mailbox to misdeliver into) and was never at risk of the late-reply
hazard. The gap is narrower and pre-existing: the interpreter has never
implemented `Actor.call`'s timeout as a real deadline.

## Fix sketch

Give the interpreter's scheduler hook (or `actor_call` itself) a real
deadline: loop calling the scheduler hook (or an equivalent "run one step"
primitive) until either a reply lands in `pending_replies` or a wall-clock
deadline computed from `timeout_ms` passes, mirroring the compiled runtime's
`march_sched_recv_until` shape. Needs a scheduler-hook variant that yields
control back after a bounded slice of work rather than running one handler
dispatch to completion, since the current single-hook-call design can't
interleave a deadline check with a still-running handler.

## Workaround in place

`test/dune`'s `native_actor_call_late_reply` rule exercises the compiled
path only (dune golden `run`+`diff`, no interpreted counterpart). The
interpreted output for this fixture is `first: unexpected ok` / `second: 1`
and is expected to keep differing from `test/native/actor_call_late_reply.expected`
until this timeout gap is closed.


---

## Fixed 2026-09-08

`actor_reply` timestamps each reply into `pending_reply_times`; `actor_call`
computes a deadline from `timeout_ms` at entry and compares. A reply produced
after the deadline is discarded and the call returns `Err`.

**Why timestamping rather than the sketch's "loop until the deadline".** The
sketch above asks for a scheduler-hook variant that returns after a bounded
slice so a deadline check can interleave with a still-running handler. That is
a real change to the interpreter's execution model and it is not needed for the
actual defect: the interpreter's scheduler runs each handler to completion
inside one pass, so by the time control returns, either a reply exists or it
never will. What was missing was not the ability to interrupt — it was any
record of WHEN the reply happened. A handler that burned ten seconds and a
handler that returned instantly were indistinguishable, so `timeout_ms` had
nothing to compare against. With the timestamp, both directions are honest: a
slow handler misses a short deadline, and a slow handler comfortably makes a
long one.

The remaining gap is narrower and now documented rather than silent: the
interpreter still cannot ABORT a handler mid-run, so a call whose deadline
passes still waits for the handler to finish before returning `Err`. Wall-clock
enforcement of the RESULT is exact; pre-emption is not.

## The workaround is gone

`test/native/actor_call_late_reply.march` now runs on BOTH backends against one
`.expected` (`first: timeout` / `second: 1`), which was the todo's own
acceptance criterion.

Its burn loop shrank from 20,000,000 to 50,000 iterations, because the fixture
is now bounded from both sides: compiled, the handler must comfortably outlast
the 1ms deadline (50k takes ~4ms, a 4x margin, and CI load only pushes it
further past); interpreted, the same loop costs ~1.2s — about 300x — so the
original size would have taken hours, and at 3,000,000 it overflowed the
interpreter's stack outright. Checked stable over five consecutive compiled
runs.
