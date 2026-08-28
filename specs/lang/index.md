# March Language Reference

**v1 · 2026-07-06 · core language reference consolidated (core fragment conformance-tested; topic chapters canonical)**

---

## How this reference is organized

This is the umbrella index over `specs/lang/`: the versioned, structured
*set* of documents that together form the normative March language
reference. It replaces ~21 scattered current-truth docs (spread across
`specs/features/*.md`, `docs/*.md`, and root guides) with one coherent
structure, organized by altitude:

- **Two conformance-tested core references** sit at the foundation:
  [`core-march.md`](core-march.md) (operational semantics, "what programs
  mean," grounded arm-for-arm in `eval.ml` and checked against a golden
  interpreter-vs-compiled corpus in [`golden/`](golden/)) and
  [`core-march-types.md`](core-march-types.md) (static semantics, "which
  programs are well-typed," grounded in `typecheck.ml` and checked against
  an accept/reject corpus in [`types/`](types/)). These cover the core
  expression fragment only; each is versioned and cites the implementation
  by line.
- **[`surface-syntax.md`](surface-syntax.md)** is the grammar quick-reference
  chapter: a terse cheatsheet over nearly the entire surface grammar (the
  layer above the core fragment: pipe, multi-head fn surface form, `let?`,
  sigils, etc.), plus a "Semantics notes" appendix of verified non-obvious
  behaviors. It explicitly defers to `lib/parser/parser.mly` as the
  authoritative grammar.
- **Per-topic chapters**: one canonical chapter per language topic
  (modules, pattern matching, interfaces, actors, capabilities, and so on),
  migrating in from `docs/` and `specs/features/` per the chapter map below.

For **compiler internals** (value representation, Perceus/RC, TIR, the
scheduler, the content-addressed build cache, the C runtime, the compiler
pipeline), see the implementation reference
[`specs/impl/index.md`](../impl/index.md). That reference is a sibling, not a
merge: compiler-internal material is referenced from language chapters where
relevant, not duplicated into them.

For a gentler, narrative introduction to the language, see README's
["Language tour"](../../README.md) section; it stays in README by design
(the survey assessed it as low-value to merge verbatim) and is a good starting
point before diving into this reference.

### How it's kept accurate

- The two core references are checked against their conformance corpora
  (`golden/` for `core-march.md`, `types/` for `core-march-types.md`):
  every rule in those documents is exercised by a runnable program, not
  just stated.
- `scripts/check-docs.sh` (run in CI) lints every file under `specs/lang/`
  (via a `find specs/lang -name '*.md'` glob) for dead compiler-source
  pointers and stale stdlib-module-count claims, the same freshness
  discipline already applied to `README.md`, `CLAUDE.md`, `docs/*.md`, and
  `specs/features/*.md`.

---

## Chapter map

Status legend: **canonical** = the authoritative chapter lives at this path
under `specs/lang/` (including the two conformance-tested core references).
**external (sibling)** = the implementation reference, maintained as its own
document outside `specs/lang/` and linked from here rather than duplicated.

| Topic | Chapter file | Status |
|---|---|---|
| Operational semantics (core fragment) | [`core-march.md`](core-march.md) | canonical |
| Static semantics / typing (core fragment) | [`core-march-types.md`](core-march-types.md) | canonical |
| Surface syntax (grammar quick-reference) | [`surface-syntax.md`](surface-syntax.md) | canonical |
| Grammar (resolved, normative) | [`grammar.md`](grammar.md) | canonical |
| Modules, visibility, imports | [`modules.md`](modules.md) | canonical |
| `let?` / Result propagation | [`let-propagation.md`](let-propagation.md) | canonical |
| `let*` / generalized monadic bind | [`let-star-generalized-bind.md`](let-star-generalized-bind.md) | canonical |
| Pattern matching | [`pattern-matching.md`](pattern-matching.md) | canonical |
| Interfaces (typeclasses) | [`interfaces.md`](interfaces.md) | canonical |
| Type system (tutorial companion to core-march-types.md) | [`type-system.md`](type-system.md) | canonical |
| Linear types | [`linear-types.md`](linear-types.md) | canonical |
| Refinement types | [`refinement-types.md`](refinement-types.md) | canonical |
| Session types | [`session-types.md`](session-types.md) | canonical |
| Capabilities | [`capabilities.md`](capabilities.md) | canonical |
| Memory model (Perceus/FBIP, user-facing) | [`memory-model.md`](memory-model.md) | canonical |
| Safety by construction | [`safety-by-construction.md`](safety-by-construction.md) | canonical |
| Actors | [`actors.md`](actors.md) | canonical |
| Supervision | [`supervision.md`](supervision.md) | canonical |
| Parallelism | [`parallelism.md`](parallelism.md) | canonical |
| Clustering | [`clustering.md`](clustering.md) | canonical |
| Standard library (overview/pointer chapter) | [`standard-library.md`](standard-library.md) | canonical |
| Implementation reference (compiler internals, sibling) | [`specs/impl/index.md`](../impl/index.md) | external (sibling) |

---

## Conformance corpora

- [`golden/`](golden/): differential interpreter-vs-compiled programs
  backing `core-march.md`.
- [`types/`](types/): `accept/`/`reject`-split typechecking programs backing
  `core-march-types.md`.
- [`grammar/`](grammar/): `parse/`/`reject`-split parsing programs (41
  total) backing `grammar.md`'s core-grammar chapters (§2–§8: preprocessing
  layers, expressions, blocks, patterns, types, declarations), wired into CI
  as its own `grammar-check` dune alias (`dune build @grammar-check`,
  mirroring `types/`'s `types-check`).

Future chapters that make specific, checkable claims should grow their own
corpus directory alongside them, following this same pattern.
