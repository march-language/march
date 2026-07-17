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

## Stage 1 — runtime box API (ADDITIVE, non-breaking) — ✅ DONE (2026-07-15)

Ported the reference implementation (`b7140673`, originally on
`docs/core-march-types-skeleton`) onto the trunk — it cherry-picked clean
(additive; 6 files, +231). Delivered: `MARCH_FLOAT_TAG=-3` +
`march_float_box {hdr; double val}` (24 B); `march_alloc_float`/
`march_unbox_float`; `march_poly_eq` float-box arm; new `march_poly_compare`
(odd→int / float-box→`march_compare_float` / string→`march_compare_string`);
`march_value_to_string` float-box arm; `march_message.c` `copy_value` copies the
box opaquely; `test/test_float_box.c` (linked against the core runtime set).
**Gate PASSED:** `main.exe` builds; `test_float_box_runner` "all checks passed"
(round-trip + eq + the negative-float ordering `-9.0 < -1.25`); full suite
UNCHANGED (809 + all drivers, exit 0 — nothing emits the tag yet). Landed as
commit `ec899b1e`.

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

## Reconnaissance re-anchor (2026-07-16, trunk `9c97391a`)

Bounded read-only recon (no flip). **Two findings materially shrink Stage 2 and
retire Stage 3.**

**Stage 1 — on trunk, green.** `MARCH_FLOAT_TAG=-3` (`march_runtime.h:116`);
`march_float_box {rc;tag;pad;val}` 24 B (`:117`); `march_alloc_float`
(`march_runtime.c:465`) / `march_unbox_float` (`:472`); `march_poly_eq` float arm
(`:544`); `march_poly_compare` (`:551`, float arm `:564`); `march_value_to_string`
float arm (`:3784`); `test_float_box_runner` → "all checks passed". (Landed via a
different commit than `ec899b1e`; the symbols are what matter and they're present.)

**Live P0 reconfirmed.** Erased Float comparator (`fn a -> fn b -> a < b`) through
`Sort.mergesort_by([3.5,-1.25,2.75,0.5,-9.0,4.5], cmp)` → **SIGSEGV 139, 3/3
runs** (interp: `-9.`). Mechanism 1 (RC on raw float bits).

**FINDING 1 — the Perceus flag-day is ALREADY DONE.** The old
`refine_occurrence_ty` / `resolve_case_field_ty` float suppressions are gone AND
not replaced (swept `lower*/mono/defun/perceus*` — nothing recovers `TFloat` at
an occurrence to skip RC). The float RC contract now lives solely in
`lib/tir/rc_types.ml`: `needs_rc (TVar _) = true` (`:117`), `needs_rc TFloat =
false` (concrete, `:121`). So erased floats **already** get RC ops emitted — which
is exactly why the bug is a loud crash, not silent-wrong. Boxing makes those
already-emitted ops land on a real cell. **Stage 2 needs NO Perceus inversion —
only encode/decode boxing + the compare hook.**

**FINDING 2 — Stage 3 (lift the MR) is a no-op.** No monomorphism-restriction
gate exists on trunk. `accept/t03_let_poly.march` (unannotated `let id = fn x ->
x` used at Int AND String) is ACCEPTED; no `reject/t79*` witness exists. The only
"value restriction" (`demote_to_monomorphic`, `typecheck.ml:685-710`) is
capability-producer-specific (`cap_narrow`/`mint_cap`) and unrelated. **Skip
Stage 3.**

**`llvm_case.ml:347 TFloat -> false` does NOT need flipping** (sub-plan step 4 is
obsolete): that arm classifies CONCRETE `TFloat` scrutinees (raw `double`,
correctly non-heap). Erased floats arrive as `TVar` scrutinees, handled by the
adjacent `TVar _ -> scrut_ty = "ptr"` arm (`:355`), which already treats a boxed
float ptr as heap.

### Re-anchored Stage 2 — the atomic flip (encode + decode + compare, one commit)

1. **`coerce` erased arms** (`lib/tir/llvm_ctx.ml`): `("ptr","double")` decode
   `:476-481` → `march_unbox_float`; `("double","ptr")` encode `:483-488` →
   `march_alloc_float`. **Leave `("i64","double")` `:522-525` alone** — that's the
   raw REPL-slot path (`march_repl_get`, `llvm_repl.ml`), stays raw.
2. **Bypass encode/decode sites:**
   - `clo_wrap_define` double-return: `lib/tir/llvm_calls.ml:148-151`.
   - Ok-Float raises-wrapper: `lib/tir/llvm_calls.ml:74-78` (currently
     `march_make_float(double)→i64`) → box.
   - `llvm_eq` erased-Float arm: `lib/tir/llvm_eq.ml:132-143` (bitcast i64→double
     + fcmp) → unbox.
   - record `kind='f'`: `runtime/march_extras.c` (raw bits `:1891`; Option(Float)
     get already boxes via `rec_box_some_float`/`none_float` `:357/:362` —
     reconcile to the new box repr) + emit site `llvm_emit.ml:1421`.
3. **Compare hook (mechanism 2):** `fallback_cmp` else branch,
   `lib/tir/llvm_emit.ml:1040-1044` — when operands are erased-ptr (`ty_a="ptr"`
   / `TVar` `v_ty`), route ORDERING through `march_poly_compare(ptr,ptr)` instead
   of `coerce→i64` + `icmp`; keep `icmp` for concrete `i64`. **EQ already routes
   through `march_poly_eq` at `:1090` — no change.**
4. **CAS/JIT cache-key bump (`abi3`):** `bin/main.ml` `cas_flags` + the JIT
   prelude version.

**Gate:** the `-9.` repro interp==compiled; `Stats.median`; the five float sort
benches; oracle divergence-free; full suite green.

### FFI contract (`march_make_float`) — sweep list (unchanged risk)
`march_make_float` (bitcast, untagged) used by: `llvm_calls.ml:78` (Ok-Float —
changes), `llvm_toplevel.ml:776` (declare), `runtime/march_ffi.c:36/167/394/407`,
and the Rust layer `rust/march/src/{sys.rs:33, value.rs:75/81/147/160}`. Decide:
keep `march_make_float` as the raw-bits FFI primitive and box only at the erased
boundary (`coerce`) — do NOT double-box. Audit each `march_ffi.c` caller for
whether its Float result reaches an erased slot.

### Net
Stage 2 is ~8-10 mechanical encode/decode sites + one compare hook, all atomic.
Its scariest advertised step (Perceus inversion) is already in place, and Stage 3
is gone. Residual risk = the FFI/Rust `march_make_float` contract and cross-time
ABI skew (cache-key bump) — both well-understood. Still a flag-day (encode +
decode + compare must land together), but no longer a Perceus-semantics gamble.

## Risk register (unchanged from the design doc, re-emphasized)

Runtime ABI + public FFI-contract break (`march_make_float` meaning changes for
erased slots — sweep `rust/` + `march_ffi.c`); Perceus flag-day (encode+decode+
RC+compare together); compare must ship with boxing (box-only = silent wrong
pointer-compare); cross-time ABI skew (cache-key bump). **Multi-day. Decision
gate before Stage 2.**
