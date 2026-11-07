`[P2]` Bounded systematic exploration of actor interleavings on the real code.

Rung 3 of the distributed-proof ladder (2026-11-06 discussion).

## What it gives

For a small configuration (a test's actors, a bound on messages per actor), every delivery
order the semantics allows is run, and each run is checked against the program's own
assertions, refinements, `@invariant`s and (once it lands) the protocol monitors of
`2026-11-06-protocol-runtime-monitors`. A failure is reported with the exact schedule, which
replays deterministically. This is Concuerror (Erlang), CHESS and the P language's checker,
but on unmodified March code: no separate model to write or keep in sync.

## Builds on

- The interpreter's cooperative, reduction-counted scheduler (`lib/scheduler/scheduler.ml`,
  `lib/eval/eval_runtime.ml`): the place where the next runnable actor and the next message to
  deliver are chosen. Exploration replaces that choice with an enumerated one.
- Refinements and `@invariant` checks, and the witness executor's machinery for running a
  program to a stated input (`lib/refinecheck/witness.ml`).
- `march test` / `forge test` as the entry point (a property-test-like case).

## Shape

1. A choice point abstraction in the interpreter scheduler: at each step the set of enabled
   events (deliver message m to actor a, run task t), and a strategy that picks one.
2. Strategies: random with a seed (cheap, replayable), and exhaustive with dynamic partial-order
   reduction (DPOR: only reorder events on the same actor's mailbox or shared state), bounded
   by depth and by preemptions (preemption bounding finds most bugs within 2-3 preemptions).
3. `test "…" explore(max_messages: 8, preemptions: 2) do … end` in the test DSL; on failure,
   print the schedule as a list of deliveries and accept it back as `replay: [...]`.
4. Report: runs explored, states pruned by DPOR, and whether the bound was exhausted (a clean
   result says "no violation within the bound", never "verified").

## Done when

- A seeded bug (a lost-update race between two actors writing a third) is found with a
  schedule that replays; the fixed program explores clean within the same bound.
- The exhaustive mode on a 3-actor ping-pong-relay finishes in seconds with DPOR and reports
  how many interleavings it covered.
- Compiled code is unaffected (interpreter only).

## Not here

The native (C) scheduler; distribution across real nodes (that is
`2026-11-06-deterministic-cluster-simulation`); liveness.
