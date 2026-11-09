`[P3]` Actor protocol layer: a transition system across actors, carried by ghost linear tokens.

Source: `specs/2026-11-08-auto-active-verifier-lessons.md` (research survey, 2026-11-08), recommendation 13.

## Why

IronFleet proved distributed systems by refinement (spec → protocol → implementation). It had
to impose by hand the reduction that makes each host step atomic: receive, then compute, then
send. A March handler already has that shape, provided it does not block mid-step on another
actor. Verus's VerusSync turns a transition system into ghost linear tokens, which cut proof
size sharply and sped verification up by about two orders of magnitude on a concurrent library.
March's linear types and erased ghost code (step 6) could carry such tokens at no runtime
cost. Per-handler invariants (PR 1210) cover one actor; nothing yet relates several.

## Wanted

- A protocol declaration: global state, transitions, and an invariant over all actors, checked
  as an inductive invariant (Ivy-style). A model-checking tier comes first (bounded exploration
  before proofs, as with P at AWS).
- Ghost linear tokens generated per protocol field, moved in messages, consumed by handlers,
  and erased from compiled code.
- A rule, stated and checked, that a handler performing a protocol step does not block on a
  reply.

## Builds on

`2026-11-06-actor-inductive-invariants`, `2026-11-06-two-state-specs`, ghost code, and the
session-type work (`2026-11-04-protocol-claims-across-messages`).

## Done when

A two-actor protocol (a lock or leader token) is proved, with a negative control that
duplicates the token.
