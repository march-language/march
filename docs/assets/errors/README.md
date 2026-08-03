# Diagnostic cards

Rendered examples of March's compiler diagnostics, for use on the site.

Each `*.html` here is a self-contained card showing **the compiler's real
output** — captured by running `march --check` over the matching source in
`src/` with `MARCH_COLOR=always`, then converting the ANSI it emitted. None of
the text is written by hand, and the colours are the compiler's own, so a card
can be trusted as a screenshot rather than as an illustration.

## Regenerating

```
python3 docs/assets/errors/render.py path/to/march
```

Do this whenever a diagnostic's wording changes. The script fails loudly if a
sample stops producing a diagnostic at all — a source that no longer
demonstrates anything is worse than a stale card, because it looks fine.

Sources are compiled from inside `src/`, so the filename in each header stays
short (`session.march`) instead of an absolute path.

## The cards

| File | Shows |
|---|---|
| `session.html` | A linear value used twice, labelling the earlier consumption site |
| `divide.html` | A refinement violation naming the parameter and callee, underlining the argument |
| `scale.html` | A contract the solver could not decide, and the `cap verified` escalation |
| `tokens.html` | A missing capability with the call chain from `main` that forced it |

`tokens.html` deliberately shows both diagnostics the compiler emits for one
missing capability (a Warning carrying the mechanical `needs` fix, and a Hint
carrying the chain). They overlap in their first line; see
`specs/todos/2026-08-03-capability-diagnostic-duplication.md`.

## Turning these into images

The cards are HTML rather than PNG on purpose: text stays selectable and
searchable, and re-rendering after a message change costs nothing. If the site
needs raster images, screenshot a card at a viewport of about 1240×620 — wide
enough that the capability card's longest line does not scroll.
