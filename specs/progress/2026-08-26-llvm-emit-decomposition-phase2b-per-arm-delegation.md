# llvm_emit.ml decomposition — Phase 2b: per-arm delegation

**Date:** 2026-08-26
**Plan:** `specs/plans/2026-08-19-compiler-file-decomposition.md`, Phase 2
(the plan file is owned by another agent right now — this entry is the record;
reconcile the plan from here)
**Follows:** `specs/progress/2026-08-26-llvm-emit-decomposition-phase2.md`
**Branch:** `claude/emit-expr-carve-out`

Phase 2 shrank `llvm_emit.ml` by deleting dead code and lifting two topic
modules, but left `emit_expr`'s arm bodies inline: 3,878 lines, 81% of its
file. Its closing note named the remaining work — "the arith / task / record
arm bodies are still inline… extracting them is per-arm delegation, a larger
mechanical job". This is that job.

## What landed

Seven commits, one topic module each.

| | before | after |
|---|---|---|
| `llvm_emit.ml` | 4,798 | **2,271** (−53%) |
| `emit_expr` | 3,878 | **1,394** (−64%) |
| `emit_expr` share of its file | 81% | **61%** |

| New module | `.ml` | arm bodies |
|---|---|---|
| `llvm_emit_arith.ml` | 287 | `+ - * / %`, `== != < <= > >=`, `+. -. *. /.` |
| `llvm_emit_alloc.ml` | 840 | `EAlloc` ×3, `EAllocHole`, `EStackAlloc` ×2, `EReuse` ×2 |
| `llvm_emit_call.ml` | 809 | general `EApp`, five `ECallPtr` arms |
| `llvm_emit_data.ml` | 298 | 5 record-introspection builtins, `ETuple`/`ERecord`/`EField`/`EUpdate` |
| `llvm_emit_html.ml` | 209 | the four `~H` sigil arms |
| `llvm_emit_tcoarm.ml` | 278 | 4 Perceus-wrapped TCO arms + the `$fv` load arm |
| `llvm_emit_task.ml` | 200 | `task_await_unwrap`, `task_await`, `remote_ref_hashes` |

Every module has an `.mli`, and every one was added to `lib/tir/dune`'s
explicit `(modules …)` list in the same commit that created it.

**38 arm bodies delegated. 90 of `emit_expr`'s 133 top-level arms are still
inline** (43 delegate, counting the SIMD arm and the four NativeArray arms
Phase 2 already did). The ones left inline are left on purpose: each is three
to ten lines, shorter than the call that would replace it — the bitwise
integer family, `int_to_string`/`bool_to_string`/`float_to_string`, ~15 small
task arms, the ~20 vault/actor/channel/MPST coercion arms, the `EIncRC`
family, `ESetField`, the two `ECallPtr` redirect arms, `to_string`, `ECase`,
`ELetRec`. The two genuinely substantial ones that remain are the
`Dispatch_registry.is_sentinel` arm (~65 lines) and `to_string` (~40).

## What was NOT done, and why

**No arm moved, no guard changed, no arm reordered.** This is the constraint
Phase 2 identified and it is worth restating, because it is what makes the
oracle's verdict meaningful. Non-builtin arms interleave with builtin arms:
`is_int_bitwise` sits above `int_mod`, `vault_get` and `chan_send`, and the
self- and mutual-TCO arms and the sentinel arm sit in that same span. Grouping
arms by topic would change two things no corpus program exercises — fall-through
for unhandled arities, and TCO precedence for every builtin dispatched below
the TCO arms — so the IR oracle **could not see** the breakage. Only bodies
moved; the dispatch structure is untouched in shape and in order.

Destination modules are grouped by topic even though the arms are not. That is
safe: which file a body lives in has no bearing on which arm matches.

## Convention

Each moved body becomes one function whose header is the only new text; the
body itself is byte-identical, indentation included. `~emit_atom` and (where
the body recurses) `~emit_expr` are threaded as labelled callbacks — the shape
`llvm_emit_simd.ml` and `llvm_emit_nmap.ml` already established. Where a body
used `emit_atom_as` (defined in terms of `emit_atom`, so unreachable from a
module that comes first in dependency order) it gets it back as a local shadow
with the same definition, which is what keeps the moved text byte-identical.

Helpers whose last caller moved out went with the bodies:
`int_arith_op`/`int_cmp_pred`/`float_arith_op` → `Llvm_emit_arith`;
`release_temp_boxes` and `fn_ret_tir` → `Llvm_emit_call` (`fn_ret_tir` is
re-exported bare — `emit_atom` still has three call sites). **Seventeen re-export
aliases** in `llvm_emit.ml` lost their last caller and were deleted:
`repr_audit_record`, `emit_tag_scalar`, `emit_untag_scalar`, `intern_string`,
`module_of_name`, `is_apply_fn`, `emit_store_tag`, `emit_stack_alloc`,
`emit_load_field`, `get_record_fields`, `field_index_for`, `shape_kind_char`,
`emit_set_shape`, `mangle_ty_for_eq`, `ensure_adt_eq_fn`,
`emit_raises_wrapper`, `fail_if_unresolved_iface_method`, plus the `simd_ty`
type re-export. Each deletion was forced by `warning 32`, not guessed.

## Verification

- **IR oracle run 7 times, once after every commit: `IR IDENTICAL across 240
  programs` every time.** This is pure code motion; anything else would have
  been a defect.
- **Verbatim-ness is machine-checked, not asserted.** The carve tool builds the
  new source and the new module together, then *reassembles*: it substitutes
  each moved body — read back out of the destination file, not out of memory —
  at its call line in the new source, and requires the result to equal the
  original file **byte-for-byte**. Nothing can be dropped (the trailing-blank-line
  trap), duplicated, or reordered without that check failing. It also asserts
  each range is comment-balanced outside string literals, and that every call
  line is unique in the file. Each run's input is the previous run's verified
  output, so the seven runs chain into one proof against the pre-Phase-2b file.
- Full suite **3,161 tests across 11 suites, exit 0** — unchanged from the
  baseline recorded before any edit (judged by `$?`, not by tail output).
  `run_snapshots` 33 tests, exit 0.
- `dune build --root . @check` at its **17 pre-existing** `forge/test` + `js`
  errors (missing optional opam dep), identical set to the baseline.

## Notes for whoever continues

- The `Dispatch_registry.is_sentinel` arm (~65 lines) belongs in
  `Llvm_emit_call`; `to_string` (~40) wants a home of its own or `Llvm_emit_data`.
  Both are straightforward with the same tool.
- Every line number in Phase 2's note was stale, and every line number here
  will be too. Re-derive by grep at the moment of use.
- `open` does not re-export. `dune build @check` is the only reliable oracle
  for that class; baseline its 17 pre-existing errors first.
