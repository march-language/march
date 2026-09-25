# [P2] Sendability is a six-name denylist checked only on message payloads; closures, tasks and user ADTs bypass it

**Logged:** 2026-09-25
**Plan:** `specs/plans/2026-09-25-send-data-race-freedom-plan.md`

## Symptom

`check_sendable` (`lib/typecheck/typecheck_exhaustive.ml:831`) keeps the
mutable buffers (`RingBuf`, `Native*Arr`) owned by one thread, but it only runs
on actor-message constructor arguments. Found by reading the code; not yet
reproduced with a built compiler (Phase 0 of the plan does that):

- **H1:** `task_spawn`, `Task.*`, `Parallel.*` never check what their closure
  captures, so two tasks can mutate one `RingBuf` at once.
- **H2:** a closure's captures are invisible to the type walk
  (`send(s, Run(fn x -> RingBuf.push(rb, x)))` passes).
- **H3:** a user ADT hides its fields (`type Wrap = Wrap(RingBuf(Int))`).
- **H4:** type variables are skipped.
- **H5:** the HTTP server shares one handler closure across connection
  threads; nothing checks its captures.

## Known gap the plan leaves open

`spawn(A, rb)` moves a buffer into a new actor, but nothing stops the spawner
using `rb` afterwards. Closing that needs linear buffers (item C of the review)
or a narrower use-after-spawn check.

## Done when

Every phase of the plan has landed. H1–H5 each have a `reject/` fixture in
`specs/lang/types/`, and the warning-vs-error decision for unverifiable
closures is recorded in the progress entry.
