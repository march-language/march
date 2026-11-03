# Actors chapter restructured for first readers (2026-10-13)

`specs/lang/actors.md` (rendered as `docs/actors.md`) got the same treatment as the
choreography, observe, capabilities and refinement-types chapters the same day:

- a plain three-paragraph introduction (what an actor is, the shared scheduler, what the
  chapter covers), then an **On this page** index grouping every section into The core,
  Lifecycle and failure, Load and observation, Beyond one actor, and Reference;
- **Choosing a concurrency primitive** moved from near the end to directly after the index,
  as the "when to use an actor" section (its anchor is linked from four other pages);
- **How it fits with the rest of March**: supervision, capabilities, linear types, session
  types, observe, hot code reload, clustering, overload/resilience, each linking out;
- the large interpreted-vs-compiled status block that opened the old page moved to its own
  **Interpreted vs compiled** section near the end, with the backend differences listed in
  one place and the five dated blockquotes/asides (2026-07-08, -13, -18, -22, 09-22) folded
  into a dated **History** list there, every code token kept;
- sections reordered so `self()` sits with the messaging sections and the lifecycle sections
  (alive, stop, `on_stop`, monitor, names, caps) are contiguous; `Next Steps` became
  `See also` with choreography, observe and capabilities added;
- explicit ids on the two headings whose auto-slugs contain underscores.

All four inbound anchors (`#choosing-a-concurrency-primitive`, `#parameterised-init`,
`#app-entry-point`, `#mailbox-limits-and-backpressure`) are unchanged. Every in-page and
cross-chapter anchor was checked; the only inline-code tokens not carried over are
`Err(...)` and `call` from the folded blockquote. `scripts/check-docs.sh` passes.
