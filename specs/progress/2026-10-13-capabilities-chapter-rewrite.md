# Capabilities chapter restructured for first readers (2026-10-13)

`specs/lang/capabilities.md` (rendered as `docs/capabilities.md`) got the same treatment as
the choreography and observe chapters the same day:

- a plain-language introduction naming the three checks (manifest, upper limit, grant) and
  the other things `cap`/`Cap(X)` carry (behavioral caps, proof caps, typestate), then an
  **On this page** index with anchors to every section;
- **Which tool do I need?**: the old top table and the old closing "Quick decision guide"
  merged into one table (union of rows, plus the grant and runtime dictionaries);
- **How it fits with the rest of March**: modules, actors, linear types, refinement types,
  choreography (per-role grants), hot code reload (capability-safe deploys), enforcement and
  audit, safety by construction, each linking to its chapter; a **See also** at the end;
- the "effect vs effect system" blockquote is now a plain paragraph; the dated
  "since 2026-08-06 / 2026-08-17" asides are kept as facts but no longer interrupt the
  sentence they qualify; the two changelog-style blocks ("Resolved (widening slice 6)" and
  "A fix landed in this reference's widening slice") are short *History* notes at the end
  of their sections; the compiler-internals detail of demand-driven propagation
  (`record_fn_caps`, keying, dispatch nodes) is one clearly labelled sub-block;
- the behavioral-caps heading got an explicit id (`behavioral-caps`) because its slug
  contains underscores, which Markdown engines treat differently.

Every inbound anchor other chapters use (`#capability-hierarchy`, `#cap-strict`, `#grant`,
`#ioforeign--calling-unverified-c`, `#tag--zero-arg-phantom-label-types`,
`#typestate-tracking-resource-lifecycle`, `#mocking-an-io-capability-in-tests`) is
unchanged. Every in-page and cross-chapter anchor was checked. Inline-code tokens were
set-diffed old vs new: nothing dropped beyond backtick-parsing artifacts and the generic
spellings `Tagged(X, Realtime)` / `proof cap`, which the merged table now shows concretely.
`scripts/check-docs.sh` passes.
