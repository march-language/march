# Boxing floats at erasure boundaries — design + recommendation

**Status:** design / decision-needed. Unblocks the monomorphism-restriction
lift (uniform-apply-ABI stage 5, `specs/plans/2026-07-13-uniform-apply-abi.md`)
and retires the sort-RC patch family (`specs/todos.md`). Survey provenance:
full surface inventory at HEAD `91e97b4a`, 2026-07-13.

## The bug (two mechanisms, both verified)

An erased (`ptr`) slot holds heap ptrs raw (even), i64-family scalars tagged
`(n<<1)|1` (odd), and **Floats as raw IEEE-754 bits bitcast into the slot**
(untagged; decode is static-type-directed via `coerce`,
`lib/tir/llvm_ctx.ml:473-527`). Raw float bits are even and usually in the
canonical user-space range, so they pass every `IS_HEAP_PTR` guard
(`runtime/march_runtime.c:155-157`). When such a slot meets GENERIC code:

1. **RC-on-raw-bits → SIGSEGV.** Perceus emits `march_incrc`/`march_decrc`
   on erased slots; the guard admits the float bits and the RC write lands
   in `*(3.5)`. Only positive floats reach this — negative floats have bit 63
   set, so guard 3 (`(intptr_t)(p) > 0`) already rejects them.
2. **Generic `<=`/`<` integer-compares the bits → silent wrong answer.**
   `fallback_cmp` (`llvm_emit.ml:1013-1035`) takes the integer branch for
   erased operands: conditional-untag then `icmp`. IEEE positive floats
   happen to order correctly as signed int64; **negatives order in REVERSE
   magnitude** (more-negative float = larger unsigned bits). `==`/`!=` route
   through `march_poly_eq` (`march_runtime.c:480-487`), which dereferences
   the "pointer" for two distinct float-bit patterns.

**Experimental confirmation that hardening the guard is insufficient.**
I temporarily narrowed `IS_HEAP_PTR` to the canonical user-space bound
(`< 2^47`) and compiled the annotated repro over
`[3.5, -1.25, 2.75, 0.5, -9.0, 4.5]`. The crash was gone — but the compiled
binary printed head `-1.25` where the interpreter prints `-9.0`: the
signed-int compare of `-9.0`'s bits (`0xC022…`) vs `-1.25`'s (`0xBFF4…`)
ranks the larger magnitude *higher*, so `-9.0` never sorts to the front.
**A runtime-guard fix (option B) cannot fix mechanism 2** — boxing and the
generic-compare hook must land in the same change.

Pre-existing severity: at pre-flip `3c8826a0` the annotated form did not
crash but SILENTLY MIS-SORTED (positive-float head `4.5` where the
interpreter says `0.5`). The uniform-ABI flip converted silent-wrong to
loud-crash; neither is acceptable.

## Options

| | what | closes mech 1 | closes mech 2 | closes sort-RC family + Task/dyn-record/Result float | site count | perf cost |
|---|---|---|---|---|---|---|
| **A** | box floats when they enter erased slots | ✅ | ✅ (with compare hook) | ✅ | ~18–20 (≈10 funnel through `coerce`) | 1 alloc + RC per float crossing an erasure boundary |
| **B** | harden `IS_HEAP_PTR` | ✅ | ❌ (proven above) | ❌ | 1 | none |
| **D** | monomorphize let-bound lambdas by duplication (mono.ml) | only where uses are concrete | only there | ❌ | ~5–6 | none, but keeps Perceus special cases forever |

Option D structurally cannot reach escaping/abstract-typed closures (a
comparator returned from a generic fn or stashed in a `TFn(TVar)` record has
no per-occurrence concrete type to duplicate on) and fixes none of the other
erased-float surfaces (`Stats.median`, dyn-record floats, `Result`-Ok
floats, Task-await Float). It reintroduces the generalize-vs-instantiate
disagreement the uniform ABI just eliminated, one layer down.

**Recommendation: option A, staged, with the generic-compare hook in the
same atomic stage as the encode/decode/RC flip.** It is the only candidate
that closes both verified mechanisms and the open sort-RC family; it makes
`needs_rc (TVar _) = true` unconditionally sound (retiring
`refine_occurrence_ty`/`resolve_case_field_ty`'s float suppressions — the
patch-accretion the todos already flag for retirement); it incidentally
fixes the Task-await Float ABI break (`llvm_emit.ml:1230`) and the
`to_string`-on-erased-float divergence; and it is the already-written
direction of `specs/plans/2026-04-16-uniform-integer-tagging.md` Phase 3
(`:51`, `:96-151`) and the stage-5 blocker text. Keep B only as
defense-in-depth (harden the guard so a stray raw-bits slot faults instead
of corrupting silently). Revisit D later as a perf optimization (fewer
erased closures → fewer boxes), not a correctness fix.

## Box representation

`struct march_float_box { march_hdr hdr; double val; }` — 24 bytes,
`hdr.tag = MARCH_FLOAT_TAG (-3)` (joining `MARCH_STRING_TAG=-1`,
`MARCH_RESOURCE_TAG=-2`; ADT ctor tags are ≥0, F19 actor-msg tags start at
`0x0100_0000`, `MARCH_MIGRATE_TAG` is gated — no collision). Perceus treats
it as an ordinary heap value; `EReuse` box-reuse is a later perf option.
New runtime API `march_alloc_float(double) : ptr` / `march_unbox_float(ptr)
: double`. Micro-precedent already in tree: `rec_box_some_float`
(`runtime/march_extras.c:349-354`) boxes Option(Float) at the record_get
boundary. **Do NOT** flip `niche_payload_ok TFloat` in the same change — a
boxed float becomes non-null so Option(Float) *could* go niche, but that
reopens the three-site encode/decode/eq repr-audit problem; keep it Boxed.

## Staged plan (each gated; do not start N+1 with N red)

**Stage 1 — runtime box API + tag-dispatch arms (additive, non-breaking). [LANDED]**
`MARCH_FLOAT_TAG`, `march_alloc_float`/`march_unbox_float`
(`march_runtime.{c,h}`); `march_poly_eq` gains a float-box arm; new
`march_poly_compare(ptr,ptr)` dispatching odd→int / float-box→
`march_compare_float` / string→`march_compare_string`; `march_value_to_string`
float-box arm (also fixes the `#<tag:N>`-for-float cousin of the container
divergence); `copy_value` treats the float box like the string arm (opaque
payload, no raw-bits sniff). Gate: builds, existing suite unchanged (nothing
emits the tag yet). Landed — pinned by `test/test_float_box.c` (a C harness;
the box fns live in the `march_runtime.c` god-object, so it links the core
runtime set + `-lz`), which proves the negative-float ordering
`-9.0 < -1.25` that a hardened `IS_HEAP_PTR` cannot fix.

**Stage 2 — the atomic compiler flip (one commit).** `coerce` double↔ptr
arms box/unbox (splitting the `("i64","double")` arm from the static REPL-slot
caller); the 6 bypass encode sites (`clo_wrap_define` double-return,
`emit_raises_wrapper` Ok-Float, `record_put`/`EUpdate` kind-`'f'`) and the
`llvm_eq` newtype-over-Float arm; **`fallback_cmp`'s integer branch calls
`march_poly_compare` for erased TVar operands**; Perceus inversion (retire
the float suppressions in `refine_occurrence_ty`/`resolve_case_field_ty` and
flip `llvm_case.ml:742-754`'s IncRC predicate to count erased float boxes as
heap fields); JIT-prelude/CAS cache-key bump (abi3). Gate: `fcu_flt`/
`fcu_flt_ann`/`fcu_flt_neg` repros interp==compiled, `Stats.median([4.5,3.8,
4.9])`, five bench sorts over floats, oracle divergence-free, MARCH_REPR_AUDIT
0 flagged, full suite.

**Stage 3 — lift the MR (= uniform-ABI stage 5).** Remove the typecheck gate,
restore `accept/t03_let_poly` unannotated, retire
`reject/t79_let_poly_unannotated_mr`, update finding 1 + the todos entry, add
the unannotated-curried-Float-comparator compiled regression.

**Stage 4 — perf pass.** `bench/array_numeric`, `bench/dataframe_bench`,
`stdlib/stats.march` folds (3 boxes + 1 tuple/iteration). If the erased-float
box+RC cost bites, add FBIP `EReuse` on the float box and/or unbox-on-entry at
monomorphized boundaries (only *erased* slots box, so concrete numeric code is
already immune). NativeArray/typed-array halves never box.

## Risk register (option A)

- **Perceus inversion is a flag-day**, not a patch — the float RC suppressions
  become wrong the same commit boxing lands; both reverted lower_match attempts
  show how sensitive this family is. Encode+decode+RC+compare flip together
  (the 2026-04-16 plan's "tag only in coerce" lesson).
- **Compare must ship with boxing** — box-only turns wrong-int-compare into
  wrong-pointer-compare (still silent). `march_poly_compare` + the `poly_eq`
  float arm are part of the minimum viable change.
- **FFI public-contract break** — `march_make_float`'s "bitcast, untagged"
  meaning changes wherever the value feeds an erased slot
  (`march_ffi.h:48/76/103/146`); sweep `rust/` and the `march_ffi.c` examples.
- **Cross-time ABI skew** — JIT/REPL fragments, CAS-cached prelude, hot-reload
  `.so`s can mix box/raw; needs the stage-4-style cache-key bump + a
  cross-fragment float-closure test.
- **Perf on numeric-heavy erased code** — one alloc + atomic RC per erased
  float; quantify in stage 4 before deciding whether FBIP reuse is required.

## Cost

Multi-day. Runtime ABI change + public FFI-contract change + a Perceus
flag-day + a measurable (bounded) perf cost on float-heavy generic code.
This is a deliberate architectural change, not a bug-fix — hence the
decision gate before stage 2.
