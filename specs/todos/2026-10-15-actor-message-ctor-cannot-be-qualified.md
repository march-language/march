`[P3]` An actor's message constructor cannot be qualified by its actor

Found 2026-10-15 while adding the `send_wrong_actor` check
(`specs/progress/2026-10-12-send-message-not-checked-against-pid-actor.md`).

When two actors declare a handler of the same name, a bare `Tally(1)` resolves to
one owner (`lookup_ctor`), and the `ambiguous_constructor` hint says to "use a
qualified form to disambiguate, e.g. `Labels_Msg.Tally`". That form, and
`Counter.Tally` and `Counter.Msg.Tally`, are all `unknown_constructor`. So there is
no way to send the other actor its own message except renaming a handler, and the
hint's advice is wrong for actor messages.

Before the `send_wrong_actor` check this was a silent backend split (the
interpreter dispatches by handler name and runs the target's handler; compiled
code builds the other actor's message, globally unique tag, and the target drops
it). The check now turns the differing-state case into an error, but the
same-state case still splits, and the user still cannot write the correct send.

Fix direction: register each actor message constructor under `<Actor>_Msg.<Name>`
(the spelling the hint already suggests) and make sure lowering builds the
qualified owner's tag. Alternatively, at a `send` whose pid type identifies a
single owner, resolve an ambiguous bare name to that owner. Add a test with two
actors sharing a handler name, run on both backends.
