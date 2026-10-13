# Hot code reload chapter restructured for first readers (2026-10-13)

`docs/hot-code-reload.md` (hand-maintained) got the frame treatment used for the
refinement-types chapter the same day: section bodies kept, the frame and order changed.

- a three-paragraph opener: what a hot deploy keeps, the mechanism in one paragraph
  (signed patch of changed functions, epochs, per-unit epoch routing, the two gates,
  sequenced releases), and the practical payoff; then an **On this page** index grouping
  every section into Start here, One server, Many hosts, What happens to running work,
  and Trust and durability;
- **When to use it**: a table from the kind of change to how it ships (hot patch,
  patch + `migrate_state`/`migrate_msg`, same-batch callers, receivers-before-chooser,
  restart, gated widening), and when a plain restart is the better tool;
- **How it fits with the rest of March**: actors and supervision, capabilities (the two
  gates), choreography (epoch-pinned sessions, drains at loop boundaries), refinement
  types (`@invariant` via the SMT checker), topology and clustering, observe (`EPOCHS`,
  `WHICH`, `SOURCE`), tooling;
- sections regrouped: the single-server `[hot-reload]` reference now sits next to
  "Configuring forge.toml" instead of near the end; the topology push follows the
  multi-host section; migration, compatibility, `@invariant`, signature changes and
  epoch-tagged dispatch are contiguous; capability-safe deploys, sequenced releases,
  artifact integrity and restart durability form the trust group;
- eight small phrase edits in the bodies ("That gap is real", "just means", "In other
  words", "It's easy to read the previous section and assume", "Note the diagnostic",
  the sprint aside); `Next Steps` became `See also` with choreography, observe and
  topology added.

All four inbound anchors (`#capability-safe-deploys`, `#protocol-changes`, `#drains`,
`#pushing-a-topology-the-topology-verb`) are unchanged; every in-page and cross-chapter
anchor was checked; every "above/below" phrase still points the right way; no inline-code
token was dropped; `scripts/check-docs.sh` passes.
