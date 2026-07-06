# March Language Reference

**v1 (in progress) · 2026-07-05 · core fragment complete, topic chapters migrating**

---

## How this reference is organized

This is the umbrella index over `specs/lang/` — the versioned, structured
*set* of documents that together form the normative March language
reference. It replaces ~21 scattered current-truth docs (spread across
`specs/features/*.md`, `docs/*.md`, and root guides) with one coherent
structure, organized by altitude:

- **Two conformance-tested core references** sit at the foundation:
  [`core-march.md`](core-march.md) (operational semantics — "what programs
  mean," grounded arm-for-arm in `eval.ml` and checked against a golden
  interpreter-vs-compiled corpus in [`golden/`](golden/)) and
  [`core-march-types.md`](core-march-types.md) (static semantics — "which
  programs are well-typed," grounded in `typecheck.ml` and checked against
  an accept/reject corpus in [`types/`](types/)). These cover the core
  expression fragment only; each is versioned and cites the implementation
  by line.
- **[`surface-syntax.md`](surface-syntax.md)** is the grammar quick-reference
  chapter — a terse cheatsheet over nearly the entire surface grammar (the
  layer above the core fragment: pipe, multi-head fn surface form, `let?`,
  sigils, etc.), plus a "Semantics notes" appendix of verified non-obvious
  behaviors. It explicitly defers to `lib/parser/parser.mly` as the
  authoritative grammar.
- **Per-topic chapters** — one canonical chapter per language topic
  (modules, pattern matching, interfaces, actors, capabilities, and so on),
  migrating in from `docs/` and `specs/features/` per the chapter map below.

For **compiler internals** (value representation, Perceus/RC, TIR, the
scheduler, the content-addressed build cache, the C runtime, the compiler
pipeline), see the implementation reference `specs/impl/index.md` — **pending
(Task 5)**. That reference is a sibling, not a merge: compiler-internal
material is referenced from language chapters where relevant, not duplicated
into them.

For a gentler, narrative introduction to the language, see README's
["Language tour"](../../README.md) section — it stays in README by design
(the survey judged it low-value to merge verbatim) and is a good starting
point before diving into this reference.

### How it's kept honest

- The two core references are checked against their conformance corpora
  (`golden/` for `core-march.md`, `types/` for `core-march-types.md`) —
  every rule in those documents is exercised by a runnable program, not
  merely asserted.
- `scripts/check-docs.sh` (run in CI) lints every file under `specs/lang/`
  (via a `find specs/lang -name '*.md'` glob) for dead compiler-source
  pointers and stale stdlib-module-count claims, the same freshness
  discipline already applied to `README.md`, `CLAUDE.md`, `docs/*.md`, and
  `specs/features/*.md`.

---

## Chapter map

Status legend: **canonical** = the authoritative chapter exists at this path
today. **pending (Task N)** = not yet migrated; still lives at its pre-
consolidation location until the named task lands.

| Topic | Chapter file | Status |
|---|---|---|
| Operational semantics (core fragment) | [`core-march.md`](core-march.md) | canonical |
| Static semantics / typing (core fragment) | [`core-march-types.md`](core-march-types.md) | canonical |
| Surface syntax (grammar quick-reference) | [`surface-syntax.md`](surface-syntax.md) | canonical |
| Modules, visibility, imports | [`modules.md`](modules.md) | canonical |
| `let?` / Result propagation | [`let-propagation.md`](let-propagation.md) | canonical |
| Pattern matching | [`pattern-matching.md`](pattern-matching.md) | canonical |
| Interfaces (typeclasses) | [`interfaces.md`](interfaces.md) | canonical |
| Type system (tutorial companion to core-march-types.md) | [`type-system.md`](type-system.md) | canonical |
| Linear types | `linear-types.md` | pending (Task 3) |
| Refinement types | `refinement-types.md` | pending (Task 3) |
| Session types | `session-types.md` | pending (Task 3) |
| Capabilities | `capabilities.md` | pending (Task 3) |
| Memory model (Perceus/FBIP, user-facing) | `memory-model.md` | pending (Task 3) |
| Safety by construction | `safety-by-construction.md` | pending (Task 3) |
| Actors | `actors.md` | pending (Task 4) |
| Supervision | `supervision.md` | pending (Task 4) |
| Parallelism | `parallelism.md` | pending (Task 4) |
| Clustering | `clustering.md` | pending (Task 4) |
| Standard library (overview/pointer chapter) | `standard-library.md` | pending (Task 5) |
| Implementation reference (compiler internals, sibling) | `specs/impl/index.md` | pending (Task 5) |

---

## Conformance corpora

- [`golden/`](golden/) — differential interpreter-vs-compiled programs
  backing `core-march.md`.
- [`types/`](types/) — `accept/`/`reject`-split typechecking programs backing
  `core-march-types.md`.

Future chapters that make specific, checkable claims should grow their own
corpus directory alongside them, following this same pattern.
