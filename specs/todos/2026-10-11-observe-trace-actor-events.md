# Trace: actor events (Sent, Received, Spawned, Exited, Dropped), arity, a Recon wrapper, the TUI panel

**Filed:** 2026-10-11, from R8 of `plans/2026-09-28-observe-recon-shell-plan.md`.
R8 shipped boundary-call tracing (`Trace`, `TRACE_START/DRAIN/STOP`; see
`progress/2026-10-11-observe-r8-tracing.md`). What it left out:

1. **Actor events** of the introspection design (`2026-09-23-per-actor-introspection-design.md`
   section 5.1): `Sent`, `Received`, `Spawned`, `Exited`, `Dropped`, with the
   per-proc `trace_flags`, `g_introspect_armed` and the check on `march_send`.
   These hook the lock-free send path and the actor loop, which R8's
   acceptance (a disarmed cost of nil on the call path) did not need to touch.
   The session machinery (`runtime/march_trace.c`: ring, limits, lifetime,
   `Trace.start/drain/stop`) is reusable as is: a session would gain an event
   kind and a pid filter. C2's PAYLOAD rendering needs its own security
   review (it renders message contents; R8 records no arguments by design).
2. **Arity.** The plan says "arity but no arguments". The dispatch table has
   no arity per slot, so an event carries the name and `name_id` only.
3. **`Recon.trace_*` wrappers.** `Recon` is `needs Actor.Introspect` for the
   whole module; the debug-tier calls live in `Trace` (`Cap(Actor.Debug)`).
   Add wrappers only if the shell wants one name.
4. **The Trace panel in `forge observe`'s TUI** (R7): consume
   `TRACE_DRAIN`'s JSON as documented in `docs/observe.md`.
5. **Interpreter.** `Trace` answers `Unavailable` there: it has no dispatch
   table. A function-entry hook in `lib/eval` could serve it.
