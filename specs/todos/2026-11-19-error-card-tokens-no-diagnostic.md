# The `tokens` diagnostic card no longer produces a diagnostic (2026-11-19)

Found by the ocap phase 4 PR B final review fix wave. `scripts/error-cards/src/tokens.march`
is meant to show a missing capability with the call chain from `main`
(scripts/error-cards/README.md), but it declares `needs IO.Random` and `main` takes
`Cap(IO.Random)`, so `march --check` accepts it (exit 0, no output) on origin/main as
on this branch; `render.py` then fails, as designed, on a sample that demonstrates
nothing. (This wave only moved its raw `random_bytes` call to
`Authority.must(Crypto.random_bytes(16))`.)

What to do: drop the `needs IO.Random` line and the `Cap(IO.Random)` parameter so
the sample shows the missing capability again, re-render the cards, and update the
README's description of what the card shows to match the diagnostic printed now.
