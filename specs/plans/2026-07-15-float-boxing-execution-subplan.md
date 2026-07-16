# Float-boxing — execution sub-plan (re-anchored to `origin/main` `e1977f12`)

**Companion to** `specs/plans/2026-07-13-float-boxing-design.md` (the decision
doc — Option A settled). That doc's `file:line` anchors are from HEAD
`91e97b4a` and are **~196 commits stale**; this sub-plan re-verifies them
against the current trunk and records the gaps. **Open-items plan Phase 2.**

## Ground truth on the trunk (verified 2026-07-15)

- Both target P0s are LIVE compiled: the annotated generalized-Float comparator
  through `Sort.mergesort_by([3.5,-1.25,2.75,0.5,-9.0,4.5], cmp)` → **SIGSEGV
  139** (interp prints `-9.`); the sort-RC bench family (`mergesort` etc.) →
  **138/139**.
- **Stage 1 is NOT landed on the trunk** (no `march_alloc_float` /
  `MARCH_FLOAT_TAG` anywhere). The design doc's `[LANDED]` was true only on the
  old-main lineage. Building Stage 1 from scratch (in progress).
- Precedents present: `rec_box_some_float`/`rec_box_none_float`
  (`runtime/march_extras.c:346-362`, boxes Option(Float) at the record_get
  boundary); `march_make_float` (`runtime/march_ffi.c:36`, the "bitcast,
  untagged" FFI float constructor — this is the public-contract break in the
  risk register).

## Re-anchored targets (trunk)

| Design-doc target | Old anchor | Trunk anchor (verify before editing) |
|---|---|---|
| `march_hdr` struct | — | `runtime/march_runtime.h:11` (`{rc; tag; pad}`, 16 B) |
| tags in use (so FLOAT=-3 free) | — | STRING=-1 `runtime.h:101`, RESOURCE=-2 `:105` |
| `IS_HEAP_PTR` | `march_runtime.c:155-157` | `runtime/march_runtime.c:189` |
| `march_poly_eq` | `:480-487` | `runtime/march_runtime.c:517` |
| `march_value_to_string` float arm | `:3890` | near `runtime/march_runtime.c:359` |
| `coerce` / `llvm_ty_of` | `llvm_ctx.ml:473-527` | `llvm_ctx.ml:332` (TFloat→double), `:342` (TVar→ptr); the bitcast `coerce` helper is nearby — RE-LOCATE |
| `fallback_cmp` erased branch | `llvm_emit.ml:1013-1035` | `lib/tir/llvm_emit.ml:1025` (def), int branch `:1044`, callers `:1079/:1097` |
| `llvm_case` float-heap predicate | `:742-754` | `lib/tir/llvm_case.ml:347` (`TFloat -> false`) |
| `needs_rc (TVar _) = true` | `rc_types.ml:127` | `lib/tir/rc_types.ml` (documented `:31`), re-exported `perceus.ml:346` |
| `clo_wrap` double-return bypass | — | `lib/tir/llvm_calls.ml` (`clo_wrap_define`), trampoline `llvm_emit.ml:370/502` |
| **Perceus float suppressions** | `refine_occurrence_ty` / `resolve_case_field_ty` | **NOT FOUND BY NAME on trunk — refactored. MUST re-discover the current suppression sites before Stage 2.** |
| MR gate (Stage 3) | `typecheck.ml:5028-5058` | **Unclear on trunk** — no `t79_let_poly_unannotated_mr` in the corpus; verify whether the MR gate exists here at all before planning Stage 3 |

## Stage 1 — runtime box API (ADDITIVE, non-breaking) — IN PROGRESS

Dispatched to a focused agent. Deliverables: `MARCH_FLOAT_TAG=-3` +
`march_float_box {hdr; double val}` (24 B); `march_alloc_float`/
`march_unbox_float`; `march_poly_eq` float-box arm; new `march_poly_compare`
(odd→int / float-box→double / string→string-compare); `march_value_to_string`
float-box arm; `copy_value` float-box arm; `test/test_float_box.c` proving the
**negative-float ordering `-9.0 < -1.25`** a hardened guard can't fix. **Gate:
builds; full suite byte-identically unchanged (nothing emits the tag yet).**

## Stage 2 — the atomic compiler flip (ONE commit) — GATED, NEEDS SIGN-OFF

**Do NOT start until (a) Stage 1 is green and (b) the human decision gate is
passed.** This is the flag-day; encode + decode + RC + compare MUST move
together (the design doc's central lesson; both prior `lower_match` attempts
were reverted for splitting them).

Concrete work on the trunk:
1. `coerce` double↔ptr arms → `march_alloc_float`/`march_unbox_float` (split the
   static REPL-slot caller from the erased-slot caller).
2. The ~6 bypass encode sites: `clo_wrap` double-return, `emit_raises_wrapper`
   Ok-Float, `record_put`/`EUpdate` kind-`'f'`, the `llvm_eq` newtype-over-Float
   arm. RE-GREP each on the trunk.
3. `fallback_cmp`'s integer branch (`llvm_emit.ml:1044`) → call
   `march_poly_compare` for erased TVar operands.
4. **Perceus inversion (riskiest, needs re-discovery):** find the current
   float-suppression sites (the old `refine_occurrence_ty`/
   `resolve_case_field_ty` are gone), retire them, and flip
   `llvm_case.ml:347`'s `TFloat -> false` so an erased float box counts as a
   heap field for IncRC. `needs_rc (TVar _)` already = true; boxing makes that
   unconditionally sound.
5. JIT-prelude / CAS cache-key bump (`abi3`).

**Gate:** `fcu`/`fcu_ann`/`fcu_neg` repros interp==compiled; `Stats.median`;
the five float sort benches; oracle divergence-free; `MARCH_REPR_AUDIT` clean;
full suite green.

## Stage 3 — lift the MR (verify it exists on the trunk first)

Remove the typecheck MR gate (if present), restore `accept/t03_let_poly`
unannotated, retire the reject witness, add the unannotated-curried-Float
compiled regression. **First establish whether the trunk even has the MR gate**
(the corpus witness is absent here).

## Stage 4 — perf pass

`bench/array_numeric`, `bench/dataframe_bench`, `stdlib/stats.march` folds.
Add FBIP `EReuse` on the float box / unbox-on-entry only if the erased-float
box+RC cost bites. Keep `niche_payload_ok TFloat` = Boxed.

## Risk register (unchanged from the design doc, re-emphasized)

Runtime ABI + public FFI-contract break (`march_make_float` meaning changes for
erased slots — sweep `rust/` + `march_ffi.c`); Perceus flag-day (encode+decode+
RC+compare together); compare must ship with boxing (box-only = silent wrong
pointer-compare); cross-time ABI skew (cache-key bump). **Multi-day. Decision
gate before Stage 2.**
