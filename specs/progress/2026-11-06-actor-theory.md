`[P2]` Actor.Theory: the mailbox model and its laws (lemmas phase D, part one)

Phase D of `specs/2026-11-04-lemmas-hcr-actors-choreography-design.md` (§4): the laws A1-A3
proved on a March model of the mailbox, the runtime tied to the model for A1 by a conformance
fixture (M8, first part), and the guarantee report's runtime block labelled accordingly.

## Fix

- **`stdlib/actor_theory.march` (`Actor.Theory`).** `ActorEnv` (`EnvMsg(sender, payload)`,
  `EnvDown(ref)`, `EnvReply(call id, value)`), `ActorQueue` (`QEnd`/`QThen`), `ActorMons`;
  `qcat`, `qenq`, `qlen`, `from_sender`, `payloads`, `replay` (deferral and stash put the held
  messages in front), `call_reply`, `without_reply`, `call_succeeds`, `downs`, `is_down`,
  `bounded_enq` (a full mailbox drops an ordinary message, never a `Down`), `monitored`,
  `unmonitor`, `death_q`. Every type and constructor is prefixed: March has one global type
  namespace (the `Session.Theory` lesson: a stdlib `Global` broke user records of that name).
- **Laws, in `stdlib/lemmas.verified`.** A1: `from_cat`, `qcat_end`, `enq_other`,
  `enq_self`, `replay_order` (A1b, deferral and stash, A1d), `call_keeps_others` (A1c). A2:
  `stale_reply_ignored`, `call_reply_cat`, `call_reply_later`, `deadline_law`. A3:
  `downs_cat`, `down_never_dropped`, `unmonitor_gone`, `down_at_most_once`. 14 lemmas.
- **M8, first part.** `test/native/actor_theory_conformance.march`: three senders each send 50
  numbered messages to one logger concurrently; the logger's handling order is built into an
  `ActorQueue` and `from_sender` applied: each sender's must be 1..50. RED on purpose:
  replaying the log newest-first makes all three false. A2 is tested by the existing
  `actor_call_late_reply`, A1c by `actor_call_in_handler_keeps_messages`.
- **Report.** New labels `proved (model)` and `proved (model) · tested (runtime)`; the runtime
  block's one `assumed` line becomes three: per-sender order and `Actor.call` replies
  `proved (model) · tested (runtime)` (naming the laws and the fixtures), `DOWN` delivery
  `proved (model)` (no fixture yet).

## Not covered

A runtime fixture for A3 (a full mailbox keeps a `Down`, delivered once), the A4 RC-trace
fixtures per send path, and conformance driven by the observe trace's `sent`/`received`
events instead of an application-level log: todo `2026-11-06-actor-theory-runtime-tests`.
