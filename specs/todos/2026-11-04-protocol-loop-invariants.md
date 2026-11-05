`[P3]` Protocol claims across loop rounds: invariants and per-message conservation

Filed 2026-11-04 from a design conversation; not scheduled. Second phase after
`2026-11-04-protocol-claims-across-messages` (payload refinements that name earlier
messages), which it builds on.

## What is wanted

Claims about every message M that travels through a `loop`, not just one round.

1. **Per-round claims, every round.** When each M is answered within the round it arrives
   in, "every M ends in exactly one outcome" is already given by the session types (one
   round, one M, one `choose` branch), and the per-round value claim is the previous item
   applied each round. Nothing new beyond confirming labels inside a loop bind this round's
   values.
2. **Running invariants.** A value carried across rounds and an invariant re-proved each
   round: running totals, sequence numbers, "the balance never goes negative", "the sum of
   approved amounts `<=` the budget". Needs syntax for loop state the protocol can name
   (an accumulator over earlier rounds' labels, e.g. `sum(amount)`), and a proof by
   induction over rounds: the invariant holds at loop entry and each round preserves it.
   The lemma machinery (induction, IH) is the likely engine.
3. **Conservation with message identity (defer).** When M's outcome arrives in a later
   round (batching, pipelined requests, out-of-order replies): "no M dropped, none answered
   twice, none answered with another M's result", keyed by an id. This is a real
   conservation proof over the conversation's trace, and the largest piece; scope it only
   after 2 lands.

## Open questions

- Where accumulator state lives: in the protocol (each role tracks the ones its claims
  name) or as a ghost value only the checker sees.
- Which role proves preservation when the values of one round come from several roles.
- Draining during a deploy happens at loop boundaries (`specs/lang/choreography.md`,
  "Draining a session"): an invariant must hold there, and a protocol change must keep it
  (compare the HCR variance check, PR #1100).

## Out of scope

Liveness ("eventually responds", "no role is starved"), crash survival of an outcome,
timing and retries: these need runtime evidence or a model checker, not z3 over values.
