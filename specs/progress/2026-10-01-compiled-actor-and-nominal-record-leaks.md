# Compiled actors leaked every message; nominal records leaked when only read

**Date:** 2026-10-01
**Closes:** `specs/todos/2026-09-29-discarded-send-result-leaks.md` (filed from the
observe quick wins; removed in this change), which named only the smallest of the
leaks below.
**Regression guard:** `test/native/actor_message_record_leak_probe.march`
(`flat: false` on every leg before the fix).

## What leaked

Compiled, `--opt 2`, objects per iteration (`live_allocs()` deltas; the
interpreter was flat on every leg):

| Leg | Before | After |
|---|---|---|
| send; handler returns `state` unchanged | 1 | 0 |
| send; handler builds a new state record | 2 | 0 |
| `send(p, m)` as a bare statement | 3 | 0 |
| message with a `String` field | 2 | 0 |
| nominal record `{ n : Int }`, one field read | 1 | 0 |
| nominal record with two `String` fields, both read | 3 | 0 |
| impure call returning a list, as a statement | 1 | 0 |

Every message delivered to a live compiled actor leaked, with every heap value it
carried, for as long as the program ran. The same numbers on `216f45fba`
(2026-09-24) show it is long-standing, not a recent regression.

## Causes and fixes

1. **The dispatch function never released its message.** `<Actor>_dispatch($actor,
   $msg)` is called only by the C actor loop (`actor_green_thread`), which hands
   over its reference to the message and frees a message itself only when the
   actor is already dead. Borrow inference left `$msg` borrowed (the body only
   scrutinises it), so nobody released it. `lib/tir/borrow.ml`'s `init` now pins
   param 1 of an actor dispatch fn named `$msg` as owned, beside the apply-fn pin
   and for the same reason (callers must see the final answer during the fixpoint).
   `$actor` stays borrowed.
2. **Nominal records were invisible to aggregate RC.** Three places matched only
   the structural `TRecord`/`TTuple`, never a `TCon` naming a `TDRecord`
   (a user `type St = { ... }`, an actor's `Name_State`):
   - Perceus's scope-end drop (`Perceus_core.is_aggregate_ty`): such a value had
     no drop site at all;
   - the drop pass's deep drop (`Drop.aggregate_fields`): a `dec_rc` on it stayed
     shallow, orphaning heap fields;
   - the `EField` no-dup rule: a projection of a still-live nominal record took an
     increment nothing undid.
   `Kind` now keeps the module's nominal records (`is_record_type`,
   `record_fields`; actor structs excluded, the runtime owns those) and all three
   consult it.
3. **The scope-end drop refused scopes it could not type.** It rebinds the scope's
   value to a typed temporary and refused when `tir_expr_ty` returned `None`: an
   actor handler ends in the `:unit` atom literal, and a helper often ends in a
   primitive operator (`+`) whose callee carries no `TFn`. Now a scope ending in a
   literal gets the drop just before the literal (no temporary needed), and
   `tir_expr_ty` types primitive arithmetic, comparison and boolean operators from
   their operands (`Perceus_core.builtin_op_result_ty`), refusing whatever is still
   unknown.
4. **A statement's call result was dropped on the floor.** A block statement
   lowers to `ESeq (call, rest)`. A pure call was deleted by the optimiser, so this
   only showed for impure calls such as `send`, whose `Some(())` leaked every time.
   Perceus's `ESeq` case now rebinds an owned, RC-typed call result to a fresh
   unused `let`, which the dead-binding branch releases, the same release
   `let _ = send(p, m)` already got.

5. **Keeping a dropped record from costing an allocation.** Before, an actor
   handler's rebuilt `state` record (`let state = { n = $sf_n }`) was folded away
   entirely: `Cprop` (P13) forwarded its field reads and DCE deleted the then-dead
   binding. The new scope-end `dec_rc state` kept the binding alive, so every
   message paid an extra allocate-and-free. `Dce.dce_expr` now treats a record or
   tuple literal whose fields are all scalars, and whose only remaining uses are its
   own `dec_rc`/`free`, as dead and removes the binding with those releases.
   Scalar-only, because a heap field's release is a deep drop that must still run.
   The handler is back to one allocation per message (the returned state), which
   is now freed.

6. **Freeing what leaked cost +16% on a send-heavy benchmark; a shared `Some(())`
   recovers it.** With messages and discarded `send` results now released,
   `bench/actors/fanin_flood.march` paid two frees per message it used to skip.
   `march_send` allocated a fresh `Some(())` on every successful send only for the
   caller to free it. It now returns one static immortal cell, and every decrement
   entry point (`march_decrc`, `march_decrc_local`, `march_decrc_freed`,
   `march_decrc_local_freed`) returns early on an immortal cell. Previously
   immortal cells (string literals) were still atomically decremented; they were
   simply never expected to reach zero. Skipping the decrement keeps every
   sender off one shared cache line and makes immortality exact.

## Benchmarks

Same-box interleaved A/B, `--opt 2`, n = 40 per arm, load < 10, base = `main`'s
compiler (`086a577e5`) built in a separate worktree:

| Benchmark | Schedulers | Leak fix alone | Leak fix + shared `Some(())` |
|---|---|---|---|
| `bench/actors/fanin_flood.march` | 1 | +16.3% | −2.2%, then +1.5% |
| `bench/actors/fanin_flood.march` | 8 | +14.2% | −14.2%, then −13.7% |
| `bench/actors/call_storm.march` | 1 / 8 | +0.6% / −0.7% | not rerun |
| `bench/tree_transform.march` | 1 | −0.4% | +0.2% |
| `bench/binary_trees.march` | 1 | −0.6% | +0.1% |
| `bench/list_ops.march` | 1 | −0.8% | −0.0% |

The second `fanin_flood` run is the final runtime (the first was the same change
in a scratch copy, without the guard on the two `_freed` siblings). At one
scheduler the two runs straddle zero inside the base arm's own half-IQR (±3.0%):
indistinguishable from `main` at this box's resolution. Every other delta is
inside its base arm's half-IQR (0.7–1.7%).

## Verification

- `scripts/run-tests.sh` full run: the only failures were `hcr stdlib actors` cases
  3 and 4, which fail identically on `main`'s own build (`086a577e5`, run in a
  separate worktree), so they are pre-existing and unrelated; and
  `audit-baseline`, whose only diff was the two lines for the new native probe
  (regenerated).
- TIR snapshots: every existing golden unchanged; new fixture
  `test/snapshots/src/nominal_record_actor_drops.march` pins the new drops.
- The new native probe, red before / green after.
- `dune build --root . @test/runtest` (every native golden plus the Alcotest
  suites), on the final runtime: only the two pre-existing `hcr stdlib actors`
  failures; no golden differs.
- Linux ASAN sweep (Docker, arm64 glibc, `MARCH_SANITIZE=1`, leaks off) over the
  72 native tests that declare an actor or a record type and use no network: 69
  exit 0 with no ASAN, UBSan or RC-underflow report; 3 FFI fixtures do not link
  without their `--ffi-link` flags. Run before and after the shared `Some(())`.
