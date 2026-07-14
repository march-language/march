# Uniform apply-fn ABI (stage 2) — implementation plan

**Goal:** make every closure apply function take its args in the UNIFORM
(erased) convention — i64-family scalars tagged `(n<<1)|1`, Floats as raw
IEEE-754 bits in the ptr slot, heap ptrs raw — so the calling convention no
longer depends on whether the lambda's TIR params are concrete or erased.
Then lift the monomorphism restriction (the stage-1 stopgap, commit
`b84ae429`, `STAGED DECISION` comment in `lib/typecheck/typecheck.ml`) and
re-enable unannotated let-polymorphic lambdas.

**Why:** today an apply fn's LLVM parameter types come from the lambda's TIR
param types (`llvm_param_ty v.v_ty`, `lib/tir/llvm_toplevel.ml:175-178`).
A let-generalized lambda (params still `TVar`) gets `(ptr $clo, ptr, ptr)`
— erased — while a monomorphic lambda gets `(ptr $clo, i64, i64)`. The
ECallPtr call site meanwhile derives its arg slot types from the
*call-site's* view of the closure's `TFn` type
(`lib/tir/llvm_emit.ml:2186-2212`). When generalize-then-instantiate makes
those two views disagree, scalar args mis-decode: odd ints mis-untag, even
ints deref as heap ptrs (SIGBUS) — the curried-comparator bench-sort class.
Returns do NOT have this problem: apply returns are already forced to the
`ptr` ABI on both sides (`llvm_toplevel.ml:157-159`,
`llvm_emit.ml:1804-1808`/`2177-2185`). **Stage 2 is an args-only change.**

**Non-goals:** no TIR type changes, no Perceus/ownership changes (apply
consumes `$clo` — `perceus.ml:639`, `bin/main.ml:1902-1912` — RC decisions
are TIR-type-driven and must not see this ABI at all), no js_emit change
(JS closure calls `f._0(f, args)` are uniformly dynamic already,
`js_emit.ml:719-744` — verify only), no change to non-apply direct calls
(the ECallPtr no-var-slot catch-all that resolves to direct calls,
`llvm_emit.ml:2027-2087`, keeps concrete conventions).

## Design decisions

1. **Args-only, emit-layer-only.** The flip lives entirely at the LLVM
   emission boundary: apply signatures become all-`ptr`; a prologue decode
   writes each param into the fn's EXISTING concretely-typed alloca
   (conditional untag for Int/Bool/Unit/Atom, bitcast for Float, raw for
   ptr). TCO and mutual-TCO back-edges store into those same allocas
   (`llvm_toplevel.ml:223-230`), so loop bodies stay raw — the decode cost
   is paid once per call, not per iteration.
2. **Floats stay raw bits, untagged.** The existing erased-slot convention
   for `double` is a raw bitcast into the ptr slot (`coerce` double↔ptr,
   `llvm_ctx.ml:477-489`; `clo_wrap_define`'s double arm,
   `llvm_calls.ml:148-153`; `march_make_float` "bitcast, untagged",
   `runtime/march_ffi.h:48`). Tagging would be lossy; boxing would change
   RC behavior. Decode is static-type-directed, same as today.
3. **Plain `ptr` params, no attributes.** `llvm_param_ty` emits
   `nonnull dereferenceable(16)` — UB-feeding metadata on a slot that
   carries a tagged scalar (already latently wrong for TVar params today).
   Uniform apply params are bare `ptr`.
4. **Atomic flip.** Producer (apply signature + prologue decode) and every
   consumer (ECallPtr args, known_call'd direct EApp args, all three
   clo_wrap trampoline producers) land in ONE commit — the
   2026-04-16-uniform-integer-tagging plan's lesson ("tag only in coerce"
   failed) is that partial coverage of producer/consumer pairs is the
   failure mode.
5. **ABI is a cross-fragment/cross-time contract.** JIT/REPL fragments (5
   finalizers in `llvm_repl.ml`), the CAS-cached precompiled stdlib prelude
   (`emit_fns_fragment`, `Defun.set_lambda_counter`), and hot-reload `.so`
   patches can mix old-convention closures with new-convention callers in
   one process. Every such cache must be invalidated/keyed on the ABI
   version in the same commit as the flip.
6. **known_call stays, dual-entry only if measured.** known_call rewrites
   `ECallPtr` → direct `EApp(apply, clo :: args)` (`known_call.ml:58-88`)
   and inline.ml can then erase the call entirely. Under the uniform ABI
   those direct calls tag args too; TIR inlining and LLVM -O2 tag/untag
   folding are expected to absorb it. Only if bench/list_ops regresses
   beyond noise do we add the dual-entry scheme (uniform `foo$apply$N` as
   a shim over a concrete `foo$apply$N$direct` that known_call targets).

## Stages (each independently verifiable; do not start N+1 with N red)

**Stage 1 — pin baselines.** Add IR-inspection tests asserting the CURRENT
apply signatures and ECallPtr call shapes (so the flip shows up as a
deliberate diff, not an accident); record compiled bench numbers for
`bench/list_ops.march` (the canary — 1M-element indirect `f(h)` dispatch,
`specs/benchmarks.md:76-93`) and the five bench sorts; confirm the oracle
is divergence-free. Gate: full suite green, numbers recorded in the PR.

**Stage 2 — refactor-only consolidation.** Funnel the three clo_wrap
producers (`llvm_emit.ml:368-394`, `:501-516`, `llvm_repl.ml:315-335`)
through one helper (extend `Llvm_calls.clo_wrap_define` to take TIR param
types). Gate: byte-identical IR on goldens + TIR snapshots (this is a
pure-refactor check; any diff is a bug).

**Stage 3 — the atomic ABI flip (one commit).**
(a) `llvm_toplevel.ml emit_fn`: FnApply signature all-plain-`ptr` + entry
decode into the existing allocas; (b) `llvm_emit.ml` ECallPtr arm
(`:2110-2223`): `fn_ty_str` all-`ptr`, args `coerce → "ptr"`; (c)
`llvm_emit.ml` general EApp (`:1763-1927`): when `is_apply_fn
resolved_name`, coerce args to `ptr` (symmetric to the existing
return-side special case); (d) clo_wrap wrappers: `ptr` params +
in-wrapper decode before forwarding to the concrete target. Gate: full
suite, goldens 50/50, types harness, five bench sorts,
`test_compiled_curried_comparator_mergesort`, a MARCH_REPR_AUDIT run.

**Stage 4 — C runtime + caches.** Update the seven raw closure-call sites
in `runtime/march_runtime.c` (`__try_call` :984-1047 dummy arg,
`__try_call_val` :1069-1116, actor dispatch :1477-1483 — verify-only,
args already uniform —, `do_actor_death` cleanup :1659-1682,
`march_respawn_child` spawn_clo :1542-1551, `march_thunk_trampoline`
:1840-1876 dummy arg) — normalize dummy args to tagged (`(1<<1)|1`),
update each site's convention comment. Bump the stdlib-prelude/CAS cache
key. Add a REPL cross-fragment closure test (define a lambda in fragment
N, call it in fragment N+2) and a hot-reload patch test with a
first-class closure crossing the `.so` boundary. Gate: task/actor/
supervision suites, JIT parity tests, REPL suite.

**Stage 5 — lift the monomorphism restriction.** Remove the typecheck.ml
gate (`:4997-5026`); flip `reject/t79_let_poly_unannotated_mr` back to an
accept test; restore `accept/t03_let_poly` to the unannotated form (+ its
`.ll` golden); update `core-march-types.md` §4.1 finding 1 + §5 table +
the `:269` cross-ref; update the todos STAGED-DECISION entry. Add the
float re-exposure regression: an UNANNOTATED curried Float comparator
through `Sort.mergesort_by`/`List.sort_by` (lifting the MR re-widens the
raw-float-bits-in-erased-slots surface the sort-RC fixes guard —
`resolve_case_field_ty`/`refine_occurrence_ty`). Gate: types harness,
differential oracle divergence-free, mergesort witness green on both the
annotated and newly-unannotated forms.

**Stage 6 — perf validation.** Rerun list_ops + the sorts against stage-1
baselines (compiled, `--opt 2`, per the benchmarks discipline). If
list_ops regresses beyond noise: implement the dual-entry `$direct`
scheme for known_call as a follow-up (touches `tir_names.is_apply_fn`
consumers, perceus, inline — scoped separately).

## Risk register

- Cross-time ABI skew (JIT fragments / prelude cache / hot-reload `.so`)
  — mitigated by stage 4's cache-key bump + cross-fragment tests.
- Silent C-side mis-decode (no verifier on the seven raw call sites) —
  mitigated by same-commit comment+code updates and the actor/task suites.
- Perceus float-bits re-exposure on lifting the MR — mitigated by the
  stage-5 unannotated-Float-comparator regression tests.
- TCO back-edges bypassing the prologue decode — mitigated by decoding
  into the existing param allocas (design decision 1); pinned by the TIR
  snapshots + B18 TCO regression tests.
- Perf on hot indirect dispatch — bounded (~3 ALU tag + ~4 conditional
  untag per scalar arg per call); measured in stage 6 with a named
  fallback.

Survey provenance: full surface map with file:line pointers produced
2026-07-13 (session worktree hopeful-kapitsa); key anchors re-verified at
head `1a547481`.
