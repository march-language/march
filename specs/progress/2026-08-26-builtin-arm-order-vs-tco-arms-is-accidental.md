# `emit_expr`: which builtins win over the TCO arms is accidental — RESOLVED (real miscompile)

**Filed:** 2026-08-26 (from Phase 2 of the file-decomposition plan)
**Resolved:** 2026-08-27 — the suspicion was correct, and the bug was *wider*
than filed. **Demonstrated, fixed, regression-tested.**
**File:** `lib/tir/llvm_emit.ml`

## Original filing

`emit_expr`'s flat match interleaves builtin-name arms with two arms that
match on *context* rather than on name:

- the mutual-TCO arm — `EApp (f, args) when ctx.mutual_tco_group <> [] && List.mem f.v_name ctx.mutual_tco_group`
- the self-TCO arm — `EApp (f, args) when ctx.tco_in_tail && ctx.tco_fn_name = Some f.v_name && …`

Roughly half the 57 dispatched builtins sat *above* those two arms and half
*below*. Nothing chose that split: arms were appended over time.

Two questions were posed: (1) can a user function even reach `emit_expr` as an
`EApp` carrying one of these names? (2) if so, decide the precedence
deliberately.

## Answer to (1): yes — and it silently miscompiles

The front end **permits** the collision. `lib/modules/prelude_collision.ml`
rejects only the names Prelude's *own* bodies call unqualified (`to_string`,
`print`, `show`, `panic`, `reverse`, …); its header comment states explicitly
that general shadowing of a builtin name by an entry-module top-level `fn` is
"a documented, intentional, regression-tested feature" (fixtures
`t126_entry_module_shadows_list_length.march` shadows `head`,
`t168_module_fn_shadows_builtin_name.march` shadows `file_read` — both names
have no `emit_expr` arm, which is why they always passed).

`int_mod`, `int_not`, `int_and`, `int_abs`, `int_pow`, `record_get`,
`vault_*`, `chan_*`, `actor_*` … all have `emit_expr` arms and are **not**
rejected. `Llvm_emit_call.emit_generic_app` already does the right thing for
them (`if Hashtbl.mem ctx.top_fns f.v_name then f.v_name`) — but the builtin
arms fire first and it is never reached.

### Witness

`test/native/shadowed_builtin_name.march` (added as the regression test).
Three user fns shadow `int_mod` (a below-the-TCO-arms builtin), `int_not` (an
above-the-TCO-arms `Builtin_name` arm) and `int_and` (the above-the-arms
`is_int_bitwise` guard); each returns a value the real builtin cannot.

| | interpreted (reference) | compiled, before fix | compiled, after fix |
|---|---|---|---|
| `int_mod(17,5)` / `int_not(5)` / `int_and(12,10)` | `102 50 20` | `2 -6 8` | `102 50 20` |

Reading the pre-fix `--emit-llvm`: `@int_mod` **is** emitted (the user's body,
with a correct self-TCO loop) but every call site in `main` emits
`call i64 @march_checked_imod(i64 17, i64 5)`. The user's function is dead
code. Interpreted output was always correct — a compiled-only wrong-answer
miscompile, no crash, no diagnostic.

## Root cause

Every builtin arm in `emit_expr` dispatches on the callee's **bare
`v_name`** with no check that the name actually denotes a builtin.
`Defun.builtin_names` keeps these names as `EApp` (rather than `ECallPtr`)
precisely so the dedicated arms can catch them, and `Lower_state.resolve_use_alias`
leaves a same-module user fn's name unqualified, so a user `fn int_mod` reaches
`emit_expr` as `EApp {v_name = "int_mod"}` — indistinguishable, by name alone,
from the builtin.

Note this is **broader than the filing supposed**: the split relative to the
TCO arms was a red herring for the *primary* bug. Builtin arms on **both**
sides of the TCO arms beat the *general call* arm at the bottom, so
`int_not`/`int_and` (above) miscompiled exactly as `int_mod` (below) did. The
ordering question is real, but it only decides what happens to a *tail-
recursive* shadow.

## Fix (`lib/tir/llvm_emit.ml`, one arm + one predicate + a move)

1. New predicate `shadows_dispatched_builtin ctx name` =
   `Hashtbl.mem ctx.top_fns name && (Builtin_name.of_string name <> None || is_int_bitwise name)`.
   Builtins are never registered in `top_fns` (they have no March definition —
   the `ECallPtr` arm's own comment says so), so membership there is a sound
   discriminator: true means a user function owns that name.
2. New arm `| Tir.EApp (f, args) when shadows_dispatched_builtin ctx f.v_name
   -> Llvm_emit_call.emit_generic_app ~emit_atom ctx f args`, placed **above
   every builtin arm**.
3. The two bare-`EApp` TCO arms were **moved above the builtin arms**, so the
   deliberate precedence is now, top to bottom:

   1. the TCO arms — they only ever fire for the user function currently being
      emitted, so they are by construction always about a user fn;
   2. the shadow arm — a user top-level fn owns its name;
   3. the builtin name arms.

   The move is behaviour-neutral for every non-colliding program (the TCO
   guards test `ctx.tco_fn_name` / `ctx.mutual_tco_group`, which only ever hold
   user function names); it exists so a shadowed *tail-recursive* user fn keeps
   its loop instead of degrading to a real recursive call. A comment at the arm
   records the invariant so a future consolidation cannot silently re-pick it.

   Observed: with the move, the witness's `@int_mod` emits the `tco_loop1`
   back-edge (checked in `--emit-llvm`). Since the first matching arm wins,
   placing the shadow arm above the TCO arms instead would necessarily turn
   that back-edge into an ordinary recursive call — which is why the tiers are
   ordered this way and not the other.

## Adjacent, NOT fixed here (pre-existing, performance only)

`Llvm_toplevel.emit_fn` gates TCO on
`has_self_tail_call … && not (Llvm_builtins.is_builtin_fn fn_name)`, so a
shadow whose name is in `Llvm_builtins`' `is_builtin` set never gets a loop set
up at all — `int_not` and `int_and` in the witness emit real recursive calls
(`int_mod` is not in that set, which is why it keeps its loop). That costs
stack depth, not correctness, and lives outside `llvm_emit.ml`; left alone
deliberately to keep this diff to the correctness bug. If it is ever worth
fixing, the same `top_fns` discriminator applies there.

## Verification

- `scripts/ir-oracle.sh check`: `IR IDENTICAL across 240 programs`
  (240 emitted, 3 skipped; run under a private `HOME`, with the new fixture
  temporarily held out of `test/native/` so the corpus matched the baseline).
  The corpus contains no name collision, so the shadow arm never fires there
  and the TCO-arm move is a no-op — exactly the blindness the filing predicted,
  here repurposed as the safety net that the 82-line arm move changed nothing.
- `scripts/run-tests.sh`: full suite green.
- `test/native/shadowed_builtin_name.march` + `.expected` wired into `test/dune`
  as a native golden (compile → run → diff against the interpreter's output).
  It fails loudly on the pre-fix compiler.

## What would make this class live again

The predicate is keyed off `Builtin_name.of_string` and `is_int_bitwise` —
the two name sources `emit_expr`'s builtin arms actually dispatch on. **A new
builtin arm that guards on a raw string literal not in `Builtin_name`, or on a
new `is_*` name-set helper, is invisible to the predicate and re-opens the
hole for that name.** Add the constructor to `Builtin_name` (which is what
that module exists for) or extend `shadows_dispatched_builtin` alongside it.
