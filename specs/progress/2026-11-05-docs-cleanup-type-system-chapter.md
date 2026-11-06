# Docs cleanup; Type System chapter restructured for first readers (2026-11-05)

**Removed.** The four 1.0 claim chapters (`specs/lang/claim-{deploys,capabilities,performance,refinements}.md`
and their generated `docs/` copies, dropped from `scripts/gen-lang-docs.py` and
`specs/lang/index.md`); `docs/upgrading-to-0-{3,4,5}-0.md`; the Findings section of
`docs/lab.md`. Inbound links were removed or reworded in `capability-threat-model`,
`compatibility`, `lemmas`, `platforms` (the tier table's "1.0 claims apply" row is gone; moving
to tier 1 now names `--cap-sandbox` directly) and `docs/index.md` (its "What 1.0 promises"
heading is now "Compatibility & platforms"; the Upgrading table lists only 0.6.0, which it
previously omitted). `docs/lab.md`'s two "see the findings" pointers now state the fact
inline. `scripts/bump-version.sh`'s release reminder no longer mentions the 0.3.0 guide. The
dated design specs and plans that mention the claim pages are historical and left as they are.

**Type System chapter** (`specs/lang/type-system.md`, rendered as `docs/types.md`) got the
treatment the pattern-matching, interfaces and capabilities chapters had:

- a plain opener (what static types rule out, the types you write, what the page covers),
  replacing the HM one-liner, the "New here?" blockquote and the long tutorial-companion
  banner; the pointer to `core-march-types.md` is one sentence in the opener and a See also
  entry;
- **On this page**, grouped: Start here, Everyday types, Built-in types, Beyond the basics,
  Reference;
- **Which type do I need?** and **How it fits with the rest of March** tables;
- sections reordered to match the groups (Opaque and Qualified Types move up beside the other
  user-defined types; Atoms joins the built-in types; Operator Reference follows Function
  Types); "Working with Records" became the subsection "Updating and destructuring records"
  of the ADT section;
- Type Annotations no longer says recursive functions need an annotation (checked: an
  unannotated recursive `len` infers); the Atoms "verified live 2026-07-22" aside and the
  signature-type-variable changelog sentence became plain facts / a short *History* note;
  the hierarchy diagram lists `Char` and `Atom`; Next Steps became See also.

Section bodies otherwise kept. Inbound anchors other pages use (`#int-width-and-overflow`,
`#int-on-the-javascript-target`) are unchanged; every in-page anchor resolves.
`scripts/gen-lang-docs.py --check` and `scripts/check-docs.sh` pass.
