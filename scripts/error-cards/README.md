# Diagnostic cards

Renders March's compiler diagnostics as HTML cards, for use on the site.

Each card shows **the compiler's real output** — captured by running
`march --check` over the matching source in `src/` with `MARCH_COLOR=always`,
then converting the ANSI it emitted. None of the text is written by hand and the
colours are the compiler's own, so a card can be trusted as a screenshot rather
than as an illustration.

## Rendering

```
python3 scripts/error-cards/render.py --out /tmp/cards ./_build/default/bin/main.exe
```

Output defaults to a temp directory and **is not committed**, for two reasons:

- Anything tracked under `docs/` feeds the published site's Pagefind index
  (`scripts/gen-docs-search-index.sh`), so committed cards would put raw
  compiler-error text into site search results, and every regeneration would
  also require rebuilding and committing that index.
- A committed rendering drifts silently from the compiler that produced it,
  which is the exact failure this script exists to prevent.

When the site embeds these, render them as part of the site build and index them
deliberately.

The script fails loudly if a sample stops producing a diagnostic — a source that
no longer demonstrates anything looks fine and is worse than a stale card.

## The cards

| Source | Shows |
|---|---|
| `src/session.march` | A linear value used twice, labelling the earlier consumption site |
| `src/divide.march` | A refinement violation naming the parameter and callee, underlining the argument |
| `src/scale.march` | A contract the solver could not decide, and the `cap verified` escalation |
| `src/tokens.march` | A missing capability with the call chain from `main` that forced it |

`tokens.march` deliberately shows both diagnostics the compiler emits for one
missing capability (a Warning carrying the mechanical `needs` fix, and a Hint
carrying the chain). They overlap in their first line; see
`specs/todos/2026-08-03-capability-diagnostic-duplication.md`.

## Turning these into images

The cards are HTML rather than PNG on purpose: text stays selectable and
searchable, and re-rendering after a message change costs nothing. If the site
needs raster images, screenshot a card at a viewport of about 1240×620 — wide
enough that the capability card's longest line does not scroll.
