`[P3]` A `choose` whose branches begin with a message from the other role is accepted

Found 2026-11-04 while writing the protocol `--explain` pages (§F3 mechanism 6). Without
`@[endpoints]`, `choose by A: x -> B -> A : Int | y -> B -> A : Bool` checks clean, although `B`
cannot know which branch `A` picked before it must send. `@[endpoints]` rejects the shape
(`endpoints_label_invalid`: "needs every branch of `choose by A` to begin with a message from
`A`"), but plain protocol checking does not. Decide whether the rule belongs to every protocol (it
is the usual MPST well-formedness condition) and, if so, report it as `protocol_invalid` on the
branch head.
