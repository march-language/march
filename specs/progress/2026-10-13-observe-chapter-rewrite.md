# Observe chapter restructured for the person on call (2026-10-13)

`docs/observe.md` (hand-maintained; not a `specs/lang/` chapter) was reorganised the same
way as the choreography chapter the same day:

- an introduction that names the four forge commands and the three tiers (observe, debug,
  shell) in plain terms, then an **On this page** index covering every section (the old
  index omitted the debug tier, tracing, WHICH/SOURCE and the remote shell);
- **Which tool answers which question**: a question-to-command table and a table of what
  each tier reveals and what unlocks it;
- **How it fits with the rest of March**: actors and supervision, capabilities
  (`Actor.Introspect` / `Actor.Debug` as the in-process equivalent of signature + policy),
  hot code reload (epochs, WHICH/SOURCE, the deploy key, deploy-ends-shell), topology and
  release bundles, and clustering (not yet);
- the slow-node walkthrough moved up to follow "Turning it on", with a fifth step pointing
  at the debug tier and the shell;
- the forge commands and diagnose findings now come before the raw socket protocol and
  verbs, and the remote shell got sub-headings (how values print, what the node checks,
  what happens when, line editing).

**Stale claims corrected** in "What is not there yet", checked against `specs/todos/` and
`specs/progress/`: the TUI (R7), tracing (R8) and actor events (`Sent`/`Received`/…,
2026-10-12) all shipped and were still listed as not built; the Trace panel was listed
twice. The list now names what is open: type names without `--hot-reload`, the cluster
section, `MESSAGES`, per-actor heap bytes, STATE/MESSAGES/Trace in the TUI, the tracing
follow-ups (arity, `Recon.trace_*`, interpreter, payloads), `forge observe --which/--source`,
the shell's security review, and dumps on fatal signals (by design).

Every other fact and code token is retained (set-diffed). Every in-page and cross-chapter
anchor and every cited `specs/` path was checked. `scripts/check-docs.sh` passes.
