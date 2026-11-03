# Choreography chapter rewritten for first readers (2026-10-13)

`specs/lang/choreography.md` (rendered as `docs/choreography.md`) was a correct but
dense reference that opened with a "how to read this page" paragraph and buried the
"when should I use this" question. It is now organised as:

- a three-paragraph introduction, then an **On this page** index with anchors to every
  section;
- **When to use it**: the shapes a choreography fits, and a table of what to reach for
  instead (two-party `Chan`, actors / `Node.send`, `Actor.call` / remote calls, HTTP);
- **How it fits with the rest of March**: one row each for session types, actors and
  supervision, capabilities, clustering, and hot code reload, each linking to its chapter;
- a six-step walkthrough (protocol, generated code, roles, running, addressing, in-process
  testing) using the same `Fan` example;
- then the reference sections (protocol syntax, generated names, entry points, cluster
  node, access points, hosting in an actor, per-role grants, ordering, session end,
  failure, crash branches, draining, changing a protocol, configuration, limits).

Every fact, code token, identifier and environment variable from the old page is present
in the new one (checked by diffing the inline-code token sets). The three inbound anchors
other chapters link to (`#per-role-grants`,
`#access-points-many-sessions-and-starting-again`, `#changing-a-protocol`) are unchanged.
Every in-page and cross-chapter anchor was checked against the target headings.
