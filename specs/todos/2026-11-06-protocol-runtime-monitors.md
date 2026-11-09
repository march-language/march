`[P2]` Runtime monitors generated from session protocols (trace conformance).

Rung 1 of the distributed-proof ladder (2026-11-06 discussion; the low-effort items are this
file, `2026-11-06-protocol-mixed-version-compatibility`, `2026-11-06-systematic-interleaving-exploration`).

## What it gives

Every message a running node sends or receives on a session is checked against the
projection of its protocol for that role. A violation (an unexpected label, a message out of
order, a payload outside its refinement) is reported with the session's trace so far, instead
of surfacing later as a stuck session or a wrong reply. Same idea as AWS P's runtime monitors
and TLA+ trace validation, but the spec is the protocol the program already declares, so
there is nothing to write and nothing to drift.

## Builds on

- The projections: `Typecheck_session` / `Desugar_endpoints` already compute each role's local
  type, and `stdlib/session_theory.march` proves projection and duality, with both projectors
  validated against it (progress `2026-11-06-session-theory-and-projection-validation`). A
  local type is a finite state machine; the monitor runs that machine over the message log.
- Message refinements are already obliged per actor (`<Actor>.<Msg>`, G4); the monitor checks
  the same predicates at runtime with the interpreter's evaluator (as `Reflect_parity` does).
- The send/receive paths in `runtime/` and `lib/eval/eval_session.ml`, and the RC-trace /
  GC-trace infrastructure for capture (`MARCH_TRACE_GC`, `scripts/gc-trace-report.py`).

## Shape

1. A `--protocol-monitor` build flag (off by default; on in `forge test` and the two-node
   scenarios) that emits one monitor state per live session endpoint and steps it on each
   send/receive.
2. An offline checker, `forge protocol check-trace FILE`, for traces captured in production
   (one line per message: session id, role, direction, label, payload digest).
3. On violation: a diagnostic naming the protocol, the role, the expected labels at this state
   and the last N messages; in tests, a failure.

## Done when

- A two-node scenario with a deliberately wrong reply label fails under the monitor and passes
  without the bug; a correct run of every `scripts/two-node.sh` scenario reports no violation.
- The offline checker accepts a trace captured from the `protocol` scenario and rejects one
  with a reordered message.
- Overhead with the monitor off is zero (no code emitted); with it on, measured and recorded.

## Not here

Crash branches (the theory is crash-free today), global properties across sessions (that is
`2026-11-06-systematic-interleaving-exploration` and, later, system-wide invariants).
