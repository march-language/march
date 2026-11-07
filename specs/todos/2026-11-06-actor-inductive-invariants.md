`[P2]` Inductive actor invariants: an `@invariant` proved for every message, not sampled.

Rung 4 of the distributed-proof ladder (2026-11-06 discussion). Split out of phase F of
`2026-11-04-lemmas-hcr-actors-choreography` ("handlers reflected as `<Actor>.step`"), which keeps
the migration-specific parts.

## What it gives

An actor's `@invariant` is shown to hold after `init` and to be preserved by every handler on
every message its type admits (with the message's refinement as a hypothesis). That makes the
invariant a theorem about every reachable state, so callers, migrations and monitors may assume
it; today it is checked where it is cheap and otherwise trusted at deploy.

## Builds on

- Handler contracts and message refinements obliged per actor (G4, progress
  `2026-11-04-interp-actor-dispatch-by-name`), the actor state as a record sort (phase 4 of the
  actor-state plan: `state.value` reflects through record selectors), and reflection of
  record-typed bodies (#1147; record-typed predicate variables in progress on
  `claude/reflect-record-predicate-vars`).
- `@invariant` grammar checks (phase A: an unsupported expression is an error).

## Shape

1. Reflect each handler as `<Actor>.step(state, msg) : state` (one arm per message
   constructor), and `init` as the initial state.
2. Obligations: `inv(init)`; for each message constructor M with refinement R,
   `inv(s) && R(m) ==> inv(step(s, M(m)))`. Each is an ordinary VC (unfolding the handler body
   once), filed under `cap verified` like any other obligation.
3. A handler that sends or calls: its effects are ignored for the invariant (they are other
   actors' messages), but its reply refinements (once `2026-11-04-actor-call-reply-untyped`
   lands) become obligations too.
4. `--guarantees` prints `proved (inductive)` per actor.

## Done when

- A counter actor with `@invariant(state.count >= 0)` and `Inc(n : {Int | _ > 0})` /
  `Dec`-guarded-by-`count > 0` handlers is proved; a `Dec` without the guard is refused with the
  message and state that break it (executed counterexample).
- The migration-simulation law of phase F can take the proved invariant as its hypothesis.
