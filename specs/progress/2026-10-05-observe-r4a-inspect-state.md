# Observe R4a: `Actor.inspect_state`

**Date:** 2026-10-05
**Plan:** [`plans/2026-09-28-observe-recon-shell-plan.md`](../plans/2026-09-28-observe-recon-shell-plan.md), item R4, part a.
**Tracking todos:** [`todos/2026-09-24-observe-recon-shell.md`](../todos/2026-09-24-observe-recon-shell.md),
[`todos/2026-08-12-per-actor-introspection-and-alarms.md`](../todos/2026-08-12-per-actor-introspection-and-alarms.md) (state-inspection item closed).

## What exists now

- **`Actor.inspect_state(d : Cap(Actor.Debug), pid, timeout_ms) : Result(String, InspectError)`**
  (`stdlib/actor.march`), with `proof cap Debug`, `Actor.debug(io)` minting it,
  and `type InspectError = InspectTimeout | InspectDead | InspectSelf | InspectFailed(String)`.
  The builtin underneath, `actor_inspect`, is stdlib-only (gate hint names
  `Actor.debug`).
- **Rendering.** Lowering (`lib/tir/lower_actor.ml`) generates one
  `Name_inspect` fn per actor through the handler glue: it reads each state
  field, renders it with `to_string` at the field's own static type (so mono
  picks the field's `Show`; e.g. `Some(3)` for a niche-encoded Option), joins
  them in declaration order as `{ f1: v1, f2: v2 }` (`{}` for no fields;
  a field whose declared type mentions a function, type variable or channel
  prints `<opaque>`, decided by `Ast.inspect_field_placeholder` on both
  backends, since `to_string` has no `Show` to pick for it) and
  hands the string to `actor_inspect_store`. The interpreter
  (`lib/eval/eval.ml`, `$sys_inspect`) prints exactly the same text. The
  whole record is never handed to `to_string`: the erased record renderer
  sorts fields and cannot see a niche Option.
- **Registration.** Spawn glue calls `register_actor_inspect(Name_dispatch,
  Name_inspect)`; the runtime keeps a lock-free 1024-slot table keyed by the
  dispatch closure, with the code epoch the renderer belongs to (the
  spawner's epoch, or the current one when the spawner is unpinned, e.g.
  `main`).
- **Request path (compiled).** `march_actor_inspect` builds a call-reply ref
  and a request message with the reserved tag `MARCH_SYS_INSPECT_TAG`
  (`0x7F000004`), pushes it with the new `march_sched_send_unlimited` (ignores
  the mailbox limit and policy, counts no `msgs_out`), and waits through
  `actor_call_wait`, now shared with `march_actor_call`. The actor loop
  intercepts the tag before hot-reload routing, undoes the `msgs_in` bump,
  runs the renderer under the actor's crash trap, and replies `Ok(s)` or
  `Err("render failed: …")`. Under `--hot-reload`, a renderer whose epoch no
  longer matches the actor's code answers an error instead of reading a
  layout it may not match.
- **Nested `receive`.** A request popped by an in-handler `receive` is
  answered `Err("busy")` (`InspectTimeout`) on both backends, so the request
  never wedges the actor or reaches user code.

## Tests

`test/native/actor_inspect_state.march`, compiled, compiled with
`--hot-reload Main`, and interpreted against one `.expected`: a five-field
record (Int, List, Option, ADT, String, a list of functions), a full `drop_new` mailbox that still
answers, self-inspection, a field whose `Show` panics (the actor survives), a
nested `receive`, and a dead actor. `test/native/actor_inspect_block.march`
(compiled only): a full BLOCK-limit mailbox answers. `test/test_stdlib_only.ml`
gates `actor_inspect`. The TIR snapshot `nominal_record_actor_drops` now shows
`Bump_inspect` and the registration.

The `<opaque>` rule came from the LLVM IR validity gate: stdlib actors
(`NodeQueue.Writer`, `SessionNode.Endpoint`) hold lists of callbacks, and the
first cut failed to compile `session_node_fan_loopback.march` with an
ambiguous `show`.

Red controls: removing the nested-receive guard wedges the actor (the later
lines never print); a limited push in place of `march_sched_send_unlimited`
turns "drop_new full: answered" into an error.

## Deviations from the plan

1. **String, not a structured value.** The state comes back as text; a typed
   reply would need a per-actor schema the caller cannot name.
2. **Busy is a timeout.** A request arriving during a nested `receive` is
   answered at once with `InspectTimeout` rather than deferred, so a
   handler blocked in `receive` cannot be inspected until it returns.
3. **External access (signed `STATE` / `MESSAGES` socket verbs, forge
   flags) is R4b.**
