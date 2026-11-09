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

## Status

2026-11-08: steps 2 and 4 landed in today's vocabulary, without reflecting the handlers
(progress `2026-11-08-invariant-unchecked-on-init-and-handlers`): `inv(init)` and
`inv(s) && R(m) ==> inv(handler result)` are obliged per actor on every build, and
`--guarantees` reads them (labelled `proved`, not yet `proved (inductive)`). Open: step 1
(`<Actor>.step`), the `proved (inductive)` label with its boundaries, reply refinements
(step 3), and the restart/migration boundary statements below.

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

## Sound induction boundary (2026-11-07)

[Horn Clause Solvers for Program Verification](https://www.microsoft.com/en-us/research/wp-content/uploads/2016/02/nbjorner-yurifest.pdf)
provides the init/transition/safety decomposition. Check user-supplied invariants first; discovering
an invariant is separate work (`2026-11-07-local-refinement-inference-experiment`).

- The inductive argument assumes serialized handler transitions. State whether panic,
  cancellation, restart and hot migration are transitions, termination of an actor, or outside
  the claim. Each way to install a live state must establish the invariant (including HCR);
  non-returning handlers do not establish progress or eventual reply.
- A handler-local invariant proves a safety property of local state. Ignoring sends is valid
  only for that scope; it cannot prove mailbox bounds, delivery, another actor's state, or
  cross-actor conservation. Explicitly reject treating those as local invariants.
- Preserve message-refinement admission requirements across local and remote send paths.
  Model reply contracts only once typed replies and their actual dispatch path are covered.
- Acceptance includes bad initialization, an unguarded decrement, two actors sharing message
  constructor names, an unsupported/effectful guard, restart and migration boundaries, and an
  undecidable preservation obligation. Label `proved (inductive)` only when all required
  obligations prove; retain assumptions and skipped boundaries in `--guarantees`.
