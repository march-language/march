# Supervision chapter restructured for first readers (2026-10-13)

`specs/lang/supervision.md` (rendered as `docs/supervision.md`) got the same treatment as
the other chapters the same day:

- a plain introduction (what a supervisor is, let-it-crash in two sentences, what the page
  covers), then an **On this page** index grouping every section into Start here, What
  happens when a child dies, Stopping and structure, and Putting it to work;
- **When to use a supervisor**: a situation-to-feature table (strategies, restart types,
  `init` arguments, graceful stop, `app`) and the cases a supervisor is not for;
- **How it fits with the rest of March**: actors (new Pid, names carried forward), hot code
  reload (hard-drain restarts, `on_stop` under a reload), observe (`TREE`, `crash.loop`),
  overload/resilience, parallel collections and Flow, clustering and topology;
- sections regrouped: the full example now follows "Declaring a Supervisor"; restart types,
  strategies (with the comparison diagram folded in as a subsection), escalation and
  backoff are contiguous; stopping and nesting follow; design strategies and the capstone
  close the page;
- **stale note corrected**: "Not yet supported: a `terminate`-style callback" was wrong
  since `on_stop` shipped (`test/native/actor_on_stop*`); the stopping section now lists
  `on_stop` as step 3 of a graceful stop and links the actors chapter, and the "still
  open" note is narrowed to draining across a hot reload;
- the example's `Cap(Actor.Introspect)` use is explained with a link; a "hold names, not
  Pids" design rule added; "Let's build something real" / "we'll" phrasing removed;
  `Next Steps` became `See also` with hot code reload, observe and overload added.

Both inbound anchors (`#declaring-a-supervisor`, `#app-level-entry-point`) are unchanged.
Every anchor checked; the only inline-code token not carried over is `terminate` from the
removed stale note. `scripts/check-docs.sh` passes.
