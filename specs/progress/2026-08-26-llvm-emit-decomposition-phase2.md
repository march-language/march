# llvm_emit.ml decomposition — Phase 2

**Date:** 2026-08-26
**Plan:** `specs/plans/2026-08-19-compiler-file-decomposition.md`, Phase 2
**Branch:** `claude/llvm-emit-phase2`

## What landed

Four commits, code motion and semantic change kept strictly separate.

| | |
|---|---|
| `llvm_emit.ml` | **5,719 → 4,798** lines (−16%) |
| `emit_expr` | **4,319 → 3,878** lines (−10%); still 81% of its file |
| `llvm_emit.mli` | **44 → 12** `val`s |
| new modules | `builtin_name.ml/.mli`, `llvm_emit_simd.ml/.mli` (585), `llvm_emit_nmap.ml/.mli` (433) |

1. **`feat(tir): add Builtin_name variant`** — a closed variant naming the 57
   builtins `emit_expr` dispatches, derived from the source rather than copied
   from the plan. Round-trip test in `test_codegen.ml` pins the count.
2. **`refactor(tir): dispatch emit_expr builtins through Builtin_name`** — all
   63 `f.Tir.v_name = "<builtin>"` guards become
   `Builtin_name.is Builtin_name.X f.Tir.v_name`.
3. **`refactor(tir): split SIMD and NativeArray-inline codegen out`** — pure
   code motion into two sibling modules.
4. **`refactor(tir): delete llvm_emit's 33 dead re-export bindings`**.

## Facts the plan got wrong (corrected in place)

- The builtin count is **57**, not the 50 / 58 the plan states in two places.
- `root_cap` is dispatched in `emit_atom`, not `emit_expr`, so it gets **no**
  constructor — including it would make the set lie about what it covers.
- `task_await` has **one** emit arm, not two. The plan's imagined second arity
  would have been unreachable dead codegen.
- `emit_expr` has **no external caller**; the seven sibling emitters receive it
  as a threaded `~emit_expr` callback.
- Every line number in Phase 2 is stale. Re-derive by grep.

## Deviation: the arms were NOT consolidated into `emit_builtin`

Task 2.2 Step 2 asks for a single guarded arm covering every arity of all 57
names, placed where the `not` arm sits, with unhandled arities escaping to the
generic `EApp` arm via `emit_generic_app`. **That is not behaviour-preserving.**
Six non-builtin arms sit *between* the first and the last builtin arm:

    is_int_bitwise [a;b]              record_keys/values/entries [r]
    mutual-TCO EApp                   self-TCO EApp
    Dispatch_registry.is_sentinel     the four SIMD arms

Hoisting the builtins above those changes two things:

1. A builtin-named `EApp` at an arity no arm handles currently falls through to
   those six arms; under the plan's shape it jumps straight to the generic arm.
2. A user function whose name collides with a builtin dispatched *below* the
   TCO arms — every `vault_*`, `actor_*`, `chan_*`, `mpst_send`, `send`,
   `record_*`, `int_mod`/`int_div`/`int_pow`/`int_abs`/`int_max_value`/
   `int_min_value` — currently wins the TCO arm and would stop doing so.

No corpus program exercises either case, so the IR oracle **cannot see** the
difference: consolidating would have been an unverifiable change sold as a
verified one. (Which builtins sit above vs. below the TCO arms is itself
accidental — worth a separate look, filed as a todo.)

Guards were therefore converted **in place**, preserving arm order exactly.
The exhaustiveness the consolidation was for is delivered instead by
`Llvm_emit.builtin_group`: a wildcard-free match classifying every
`Builtin_name.t` by the topic section that emits it. Verified to fire by adding
a `Probe_unused` constructor — the build fails in both `builtin_name.ml`
(`to_string`) and `llvm_emit.ml` (`builtin_group`) — then reverted.

Task 2.3 followed from that: with no `emit_builtin` to carve, the split took
the seam that *is* order-preserving — the SIMD intercept arm's 444-line body
plus its shape table, and the two NativeArray inline-loop emitters. Each moved
arm keeps its exact position and its guard; only bodies moved, with
`emit_atom` threaded in as a labelled callback (the `~emit_expr` convention).

## Still open

The **arith / task / record arm bodies** are still inline in `emit_expr`.
Extracting them is per-arm delegation (57 arms, one function each), a larger
mechanical job than this phase. `emit_expr` is 3,878 lines.

## Verification

- **IR oracle run 5 times** (after each commit plus one mid-Task-2.3):
  **IDENTICAL across 240 programs every time**, including after the two
  "semantic hardening" commits the plan predicted would legitimately change IR.
  They do not: converting string-guard dispatch to a variant changes how the
  compiler decides, not what it writes.
- Full suite **2,763 tests, all runners exit 0** (baseline 2,761 + the two new
  `test_codegen` cases). `run_snapshots` exit 0.
- `dune build @check` at its 17 pre-existing `forge/test` + `js` errors
  (missing optional opam dep), unchanged from baseline.
