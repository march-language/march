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
