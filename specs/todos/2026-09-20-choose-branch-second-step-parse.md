# `[P2]` Protocol parser: a `choose` branch cannot hold a second message step on its own line

Filed 2026-09-20 while adding message labels
([[2026-09-20-choreography-message-labels]]).

```march
protocol P do
  choose by A:
    go -> A -> B : Int
          A -> B : Int
    no -> A -> B : Bool
  end
end
```

fails with "I got stuck here" pointing at the second step's `A`. The token filter's
arm-boundary scan (`lib/parser/token_filter.ml`, `lookahead_is_new_arm`) runs after the
newline inside a branch body and sees `A -> ...`: an `ARROW` at depth 0, which it reads as
the next arm's `pattern ->`, so it emits an arm separator and `choose_branch` then wants a
`lower_name ARROW` where the step is. A labelled second step (`tick: A -> B : Int`) fails
the same way. A `loop do ... end` or a nested `choose by X:` on that line parses, since
`DO` stops the scan and the nested choose's line has no arrow.

Independent of labels; it predates them. Nothing in the test corpus writes a branch with
two plain message steps, which is why it was not noticed. A fix needs the scan to know it
is inside a `protocol` (a step's `->` is never an arm), or the grammar to accept the
`do ... end` wrapper for a branch body as match arms do. Whichever, the menhir conflict
count must stay at 11 and a grammar-corpus fixture must pin the two-step branch.
