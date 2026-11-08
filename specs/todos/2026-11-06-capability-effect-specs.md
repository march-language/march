`[P3]` Specifications for effects: pre/postconditions per capability operation over a pure model.

Large step 12 of `2026-11-06-verification-ladder-roadmap`. The F* idea (effects carry
specifications) in March's capability form. Overlaps phase D of
`2026-11-04-lemmas-hcr-actors-choreography` (`stdlib/actor_theory.march`).

## Wanted

Each capability operation gets a contract over a pure model of the world it touches: `File.write`
appends to the file's model content, `File.read` returns it; `Actor.send` appends to the target's
mailbox model (per-sender FIFO); `Actor.call` correlates the reply. A function's contract can then
talk about effects (`ensures file_content(path) == old(file_content(path)) ++ data`).

## Builds on

Capabilities (`Cap(IO.File)`, per-function `needs` bounds), `actor_theory.march`'s model (phase
D), two-state specs (`2026-11-06-two-state-specs`).

## Risks

The model must match the runtime (phase D's trace conformance is the evidence for actors; files
need an equivalent). Start with one capability (`IO.File`, single-threaded) and a test that runs
the model and the real operation side by side.

## Done when

A small program that writes, appends and reads a file has its final content proved, and a
deliberate bug (truncating write) is refused with the model's counterexample.

## Effect semantics before surface syntax (2026-11-07)

[F*, POPL 2016](https://fstar-lang.org/papers/mumon/paper.pdf) gives effects predicate-transformer
semantics. Borrow composition of pre/postconditions; do not import full dependent types.

- Define operations as transitions of a pure model, with explicit normal and error results.
  Distinguish overwriting `write` from `append`; specify partial IO/error behavior rather than
  declaring every write to append. State frames: which paths/handles may change, and which
  facts survive the operation. Compose contracts in sequence and across error branches.
- Initial scope: one exclusively owned file handle, no external writers, no aliases changing
  its state. A capability permits an operation; it does not prove exclusive access or that the
  filesystem remained unchanged between reads. Specify when model facts become invalid.
- `old` denotes an immutable logical snapshot, not a retained runtime reference. Do not infer
  snapshot isolation for files or other actors from handler-local state specifications.
- For actors, separate send attempted, accepted/enqueued, dropped, received and processed.
  Queue limits, cancellation, crashes and partitions must not be hidden by a postcondition that
  every send appends to a mailbox. Model call IDs, late replies and timeouts before stating
  correlation; use the actor trace-conformance work to test the chosen observable boundary.

Acceptance extends the write/append/read example with an unrelated-file frame check, a failed
operation and an alias/interference rejection. Report `proved against model` with assumptions;
conformance tests add evidence but do not turn the runtime implementation into a proved one.
