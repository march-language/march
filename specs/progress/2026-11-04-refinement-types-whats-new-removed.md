# Refinement Types chapter: "What's new" box folded into the body (2026-11-04)

The dated "What's new (October 2026)" callout at the top of `specs/lang/refinement-types.md`
was removed. Every feature it listed already had its own section in the body; what was missing
was a way to reach them from the top of the page.

- "When to use refinements" gained rows for refinement messages, reflection, lemmas,
  relational element refinements, abstract refinements (one and two arguments), fold
  invariants, termination (`--termination-report`, `cap total`) and module-wide inference.
- "On this page" now lists the messages, containers/callbacks/folds, reflection, termination
  and `cap total` sections.
- The table's first row escaped its `|` inside code (`{Int \| …}`), which had split the row
  into an extra column on the site.

`docs/refinement-types.md` regenerated with `scripts/gen-lang-docs.py`.
