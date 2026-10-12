# Trace: arity, a Recon wrapper, the TUI panel, the interpreter, message payloads

**Filed:** 2026-10-11, from R8 of `plans/2026-09-28-observe-recon-shell-plan.md`.
R8 shipped boundary-call tracing (`Trace`, `TRACE_START/DRAIN/STOP`; see
`progress/2026-10-11-observe-r8-tracing.md`), and `progress/2026-10-12-observe-trace-actor-events.md`
added the actor events (`Sent`, `Received`, `Spawned`, `Exited`, `Dropped`)
with a mandatory pid filter. What is still open:

1. **Arity.** The plan says "arity but no arguments". The dispatch table has
   no arity per slot, so an event carries the name and `name_id` only.
2. **`Recon.trace_*` wrappers.** `Recon` is `needs Actor.Introspect` for the
   whole module; the debug-tier calls live in `Trace` (`Cap(Actor.Debug)`).
   Add wrappers only if the shell wants one name.
3. **The Trace panel in `forge observe`'s TUI** (R7): consume
   `TRACE_DRAIN`'s JSON as documented in `docs/observe.md`.
4. **Interpreter.** `Trace` answers `Unavailable` there: it has no dispatch
   table. A function-entry hook in `lib/eval` could serve it.
5. **Payload rendering (C2 of the introspection design).** Rendering a message's
   contents needs its own security review; the actor events carry the
   constructor tag only. Also the design's INHERIT (children of a traced actor
   traced) and an actor-event `Dropped` for `Actor.call` to a dead actor
   (reported only through `send` today).
