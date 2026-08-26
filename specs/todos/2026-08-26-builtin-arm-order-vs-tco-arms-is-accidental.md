# `emit_expr`: which builtins win over the TCO arms is accidental

**Filed:** 2026-08-26 (from Phase 2 of the file-decomposition plan)
**File:** `lib/tir/llvm_emit.ml`

`emit_expr`'s flat match interleaves builtin-name arms with two arms that
match on *context* rather than on name:

- the mutual-TCO arm — `EApp (f, args) when ctx.mutual_tco_group <> [] && List.mem f.v_name ctx.mutual_tco_group`
- the self-TCO arm — `EApp (f, args) when ctx.tco_in_tail && ctx.tco_fn_name = Some f.v_name && …`

Roughly half the 57 dispatched builtins sit *above* those two arms and half sit
*below*. Nothing chose that split: arms were appended over time.

The consequence is only visible for a user-defined function whose name collides
with a builtin. For a colliding name **above** the TCO arms (`not`, `negate`,
`to_string`, `int_to_string`, `int_popcount`, all `task_*`, `signal_*`,
`record_keys/values/entries`, …) the builtin arm wins and the TCO arm never
fires. For one **below** (`record_get`/`put`/`has_key`/`from_list`, `send`,
every `vault_*`, `actor_*`, `chan_*`, `mpst_send`, `int_mod`/`int_div`/
`int_pow`/`int_abs`/`int_max_value`/`int_min_value`) the TCO arm wins.

Two questions worth answering:

1. **Can a user function even reach `emit_expr` as an `EApp` carrying one of
   these names?** If shadowing/defun makes that impossible, the ordering is
   moot and a comment saying so is the whole fix. If it is possible, one side
   of the split is emitting a call to the wrong thing.
2. If it is reachable, decide the intended precedence *deliberately* and make
   the arms agree, rather than inheriting whatever append order produced.

This is why Phase 2 declined the plan's proposal to consolidate all 57 name
arms into one arm placed above the TCO arms: doing so would have silently
picked answer "builtin always wins" for the whole set. No corpus program
exercises the case, so the IR oracle cannot see the difference — which is
exactly why it needs a real answer rather than a refactor's side effect.

See `specs/progress/2026-08-26-llvm-emit-decomposition-phase2.md`.
