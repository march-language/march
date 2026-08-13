# `[P2]` `Parse`: the "lost deeper error" was commit placement, not the success channel

**Status:** Root-caused and fixed by adding `then_commit` (2026-08-12). The
filed premise was wrong, and the real cause is a grammar-authoring trap worth
naming.

## The claim

The combinator JSON parser produced a worse message than the hand-written one:

    input:  {"a":}
    hand:   unexpected character: '}'
    comb:   1:2: I was expecting `}` in the object that started at 1:1

The user's mistake is a missing **value** after `:`. This was filed against the
Int-only success channel — `ROk` carries the furthest failure *position* but
not its *expected-set*, so a deeper failure that is later abandoned loses its
detail — with the proposed fix being to widen the channel to `(pos, expected)`
and pay an allocation on the success path.

## The measurement

The two commit placements, isolated, same grammar and input:

| Placement | `{a:}` | `{}` |
|---|---|---|
| `commit(lit(":"))` — commit the delimiter | `1:2: I was expecting \`}\`` | accepted |
| `commit(skip_first(lit(":"), value))` — commit the tail | `1:4: I was expecting a value in the member that started at 1:2` | accepted |

Committing the tail produces exactly the right message: the correct position,
the right expectation, and the enclosing construct named. **No change to the
reply type was needed.** The success channel was never the problem.

## The real cause, which is a trap

`commit(p)` makes **`p`'s own** failure hard. Everything sequenced *after* `p`
stays soft. So `commit(lit(":"))` hardens the colon and leaves the value
parser soft — the enclosing `sep_by` then backtracks over the whole member,
its empty alternative succeeds, and the closing-brace parser reports a shallow
error at a position the user never typed anything wrong at.

The design sketch in the plan had this right all along —
`keyword("if") |> then_commit(if_tail())` commits the **tail**, not the
keyword — and the JSON grammar simply did not follow it.

What makes it a trap rather than a mistake: **both placements accept every
valid input.** The difference appears only on malformed input, which is
exactly where nobody is looking when they write the grammar, and exactly where
the message was supposed to be the product.

## The fix

`Parse.then_commit(p, q) = and_then(p, commit(q))` — so the correct shape is
also the short one — with the two messages written into its doc comment side
by side, and two tests pinning them: the good message on `{a:}`, and `{}`
still parsing (a commit that fires too early breaks the genuinely-empty case).

## Status of the original concern

The Int-only success channel *can* still lose a deeper expected-set in
principle, when a soft failure is abandoned and nothing commits. But the one
case that was supposed to demonstrate it does not: with correct commit
placement the detail survives. There is currently **no evidence** the
limitation matters in practice, so widening the channel — which would add an
allocation to the hot path, and the hot path is where the 16.5× lives
(`2026-08-12-parse-rebuild-cost-measured.md`) — is not justified. Re-open if a
grammar produces a bad message that correct commit placement cannot fix.
