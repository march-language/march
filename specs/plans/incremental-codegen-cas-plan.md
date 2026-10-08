# Compiler Observability and Incremental Compilation — Plan

**Date:** 2026-10-04
**Status:** Proposed. Part A and B1 recommended regardless. B3–B5: B0 **passes** go criterion 1
(2026-10-07, `incremental-codegen-cas-baseline-2.md`); they now wait on criteria 2 and 3 (§3). Every section has been source-checked once by an independent read; see §19.

---

## 1. Why one plan

Incremental compilation caches machine code keyed on what the compiler *believes* that code
depends on. Every such belief is an invariant, and the project's bug history says invariants
between passes are what break. A rough count over `specs/progress/` filenames puts RC/Perceus
leaks and double frees, JIT parity, codegen repr/niche/TCO, typecheck and stale caches as the
largest classes (doc-lint:ignore-count); since July 2026, 26 commits fix a leak or
use-after-free and 12 fix a cache or staleness bug. The September 2026 leak fixes all read the
same way: two passes disagreed about ownership, a hand-written delta test caught it, and someone
read IR to root-cause it.

A per-unit object cache multiplies the cost of that class: a stale object is a silent miscompile
that reproduces only with a particular edit history. So:

- **Part A — Observability foundations.** A TIR verifier, source provenance that survives to the
  binary, RC event tracing (extending what the runtime already has), pass bisection and
  reduction, a determinism oracle, per-pass metrics, and a query interface over compiler facts.
  Each pays for itself on today's bugs. Together they are the preconditions for trusting a cache.
- **Part B — Incremental compilation.** The CAS work, with each phase naming the foundation it
  consumes and the guard that catches it being wrong, and a decision gate in front of the
  expensive phases.
- **Queryability** cuts across both: a query *interface* (A7) is the debugging front door for A;
  a coarse query *layer* with recorded dependencies (§12) is what B6 should be built on. §12 also
  records why a full query-based rewrite is not.

Part A items are independent of each other and can start now. Part B's critical path is
B0 ∥ B1 ∥ B3a → B2 → B3b → B4 → B5.

---

## 2. Problem (incremental compilation)

The CAS speeds up a compile only when nothing changed. Three caches exist today:

| Layer | Where | Key | A hit skips |
|---|---|---|---|
| Source-level | `bin/main.ml` (~1988–2092, `source_cas_state`) | MD5 of entry file + stdlib hash + every `.march` under the entry's directory and each `MARCH_LIB_PATH` dir | everything (copies the binary, `exit 0`), **before parsing** |
| Post-TIR | `bin/main.ml` (~3310–3395) | concatenation of every SCC's Merkle `impl_hash` from `Pipeline.hash_module`, through `build_cas_key` | `llvm-emit` + clang only |
| Runtime objects | `lib/cas/runtime_archive.ml` | runtime `*.{c,h}` digest + compiler identity + `cc --version` + exact cflags | recompiling the ~20-file C runtime |

Any real edit misses both whole-program keys and pays the full pipeline: parse → desugar →
resolve → stdlib-load → typecheck → lower → mono/fusion/defun/Perceus/drop/escape/opt → LLVM
emission of the **whole** program → one clang invocation over one `.ll`. "Whole program" is
dominated by stdlib specialisations: `examples/` totals ~5 600 lines against a ~52 000-line
stdlib, and `examples/topology_app`'s `--compile-so` manifest lists ~13 000 functions. So an edit
to user code mostly re-emits code that did not change.

`Pipeline.compile_scc` (`lib/cas/pipeline.ml`) is a tested per-SCC cache nothing calls. Its doc
comment names the blocker: codegen emits one LLVM module and links one binary. This plan does
**not** revive it; its key is the transitive Merkle hash, which §15 explains is wrong for objects.

### Terms
- **Symbol**: the LLVM function name a TIR `fn_def` is emitted under.
- **`impl_hash`**: `Hash.hash_fn_def`'s hash of signature + body, alpha-normalised locals,
  callees referenced **by name**.
- **Merkle `impl_hash`**: `Pipeline.hash_module`'s fold with callees' Merkle hashes and the
  type-layout closure. Computed on `pipe.Contract_pipeline.final`, i.e. **post-optimisation**
  TIR (`bin/main.ml:3313`).
- **Unit**: a set of `fn_def`s emitted into one `.ll` / compiled to one `.o` (B3).
- **Provenance table**: the side table A2 introduces, `fn_name → origin` (TIR has no spans).

## 3. The decision: is Part B worth it?

**Evidence on value.** No `specs/todos/` or `specs/progress/` entry complains about compile
time. The one measured number (`runtime_archive.ml`: ~6.5 s per compile on CI, "essentially all
of it clang" on the C runtime) was already fixed by the runtime object cache. What remains is
unmeasured.

**Evidence on cost.** Two active contributors (482 + 173 commits since July); review bandwidth
is the scarce resource. B3a is a refactor of an 1 809-line emitter that must be byte-identical.
The two bug classes B3–B4 add surface to (codegen, cache staleness) are the two the project
already fights most, and a stale unit object is a silent miscompile in a language that advertises
capability-by-absence and a checked runtime. The first review of this plan found four blockers
from reading alone.

**Pieces, separately:**

| Piece | Risk | Value depends on compile-time numbers? | Verdict |
|---|---|---|---|
| Part A | low: additive, test-time or opt-in, no codegen change | no: pays on bugs already happening | **do** |
| B1 structural names, B7 quick wins | moderate; every change is a rename checked by `ir-oracle` | no: fixes the open HCR P2 and a live cache-key gap | **do** |
| B3–B5 unit split, object cache, ThinLTO | **high** | **entirely** | criterion 1 **met** (B0, 2026-10-07); waits on criteria 2 and 3; start with **B3-lite** |
| Memo layer / B6 | high, speculative | yes, and only if the front end dominates | **defer** until B0 and a quarter of Part A in use |

**Go criteria for B3–B5, all three required:**
1. B0 shows a warm leaf-edit compile of `examples/topology_app` at `--opt 2` over ~10 s with the
   back-end bucket above 60% of it.
2. Someone actually sits in an edit-compile loop (`forge watch` exists; is its latency the
   complaint?). If compiles mostly happen in CI, job parallelism already hides latency.
3. A1 and A5 are green in CI first.

**Criterion 1: met** (`specs/plans/incremental-codegen-cas-baseline-2.md`, 2026-10-07, after
#807 removed two quadratic post-opt name scans). The topology leaf edit at `--opt 2` is 14.5 s
wall, and `llvm-emit` + `clang` is 11.1 s of it, 76%. clang at `-O2` over the whole program
(~8.2 s) is the largest single cost. B3–B5 now wait on criteria 2 and 3 only. When they are
met, the baseline recommends **B3-lite** (the two-object seam below and in §16) before the full
N-unit split. Small programs show a ~2.4 s whole-program floor per edit, mostly TIR work over the
stdlib with only ~0.4 s of back end, and per-function units would not remove it.

**If B0 is borderline: the two-object seam (B3-lite).** Split at exactly one stable boundary,
stdlib specialisations vs user code, into two objects. The stdlib object is keyed on the set of
specialisations the program requests, so any edit that introduces no new generic use is a hit;
the user object is small. It needs B1, the `linkonce_odr` rule and the atom-table fix from B3b,
but no partitioning, no eviction policy and no ThinLTO decision, roughly a third of B3b + B4.
Generalise to N units only if that is still too slow.

## 4. Goals and non-goals

**Goals.**
1. An inter-pass invariant violation is reported at the pass that violated it, naming the
   function, not three stages later as a wrong value or a leak delta.
2. A compiled crash, leak or divergence names the March source line and the passes that produced
   the code, without reading IR.
3. (If B3–B5 go.) After editing one function, the native `--compile` path re-emits and
   re-compiles roughly the unit containing it, then links. A cached object is never used when a
   clean build would have produced different machine code for it.

**Non-goals.**
- WASM, JS, cross-compiled and `--compile-so`/`--hot-reload` builds keep the monolithic path
  (same reasons as `Runtime_archive`'s eligibility check, `bin/main.ml` ~4039–4046).
- Windows (nothing supports it today).
- Incremental *type checking* of user modules (B6; separate plan).
- A TIR interpreter as a second oracle backend: considered and deferred (§11).

## 5. Dependency map

```
A1 TIR verifier ─────────────┬──► B2 unit keys (verifier runs before hashing)
                             ├──► B3a emitter refactor (verifier on every pass under test)
                             └──► B4 verify mode (TIR-level check on cache hits)
A2 provenance table ─────────┬──► B1 structural names (host of a lambda = provenance)
                             ├──► B3b partition by source module
                             └──► B4 .meta sidecars, build manifest
A3 RC tracing (site ids) ────┬──► B4 differential-test triage
                             └──► today's leak hunts
A4 bisection + reducer ──────┬──► B4 edit-sequence differential test (minimal repros)
                             └──► today's oracle divergences
A5 determinism oracle ───────┬──► B1 acceptance
                             └──► B2 (tm_fns order question)
A6 metrics + idempotence ────┬──► B0 bench harness (same stamps)
                             └──► B3a byte-identity (second signal)        (A6 idempotence needs B1)
A7 query interface ──────────┬──► B4 `why-miss` over .meta sidecars
                             └──► today's "which input changed?" cache hunts
Memo layer (§12) ────────────┬──► B6 (per-module typecheck/lower queries)
                             └──► B2 globals_digest → recorded deps, over time
```

Everything in A ships alone and is useful alone. Nothing in B after B0 lands before the A item it
consumes.

---

# Part A — Observability foundations

## 6. A1 — TIR verifier

**Problem.** No *whole-TIR* well-formedness checker exists; passes trust each other. The
tuple-destructure leak (`specs/progress/2026-09-30-compiled-tuple-destructure-leaks-moved-fields.md`)
was Perceus treating a scrutinee as borrowed while codegen made the binders own the fields;
nothing between them could say so. Three *targeted* checks already exist and are the precedents
to build on, not re-derive: `MARCH_REPR_AUDIT=1` (`llvm_ctx.ml:1031–1053`, a codegen-time
recorder of representation decisions that reports mixed families), `Mono.check_repr_disagreement`
(`mono.ml:70`), and the pass-contract checks `Policy_dce.audit : tir_module -> (string * string)
list` (`policy_dce.ml:192`) and `Vectorize_check.check` (`vectorize_check.ml:195`).
`Policy_dce.audit`'s shape is the one `Tir_verify.check` wants.

**Hook point.** `Contract_pipeline.run` already calls `snap "tir-<stage>" tir` after every pass
(`contract_pipeline.ml:97, 131, 135, …, 241`) and `Opt.run` calls `snap "tir-opt-<iter>-<pass>"`
after each inner pass (`opt.ml:55–57`). The verifier is installed as that `snap` observer; no new
state record. Add one `snap "tir-trmc"`: `Trmc.transform_module` (`:70`) and the `tm_exports`
rewrites (`:73–123`) run before the first snap today.

**Call sites that do not go through `Contract_pipeline`** and must call the verifier explicitly:
`test/test_snapshots.ml:200–202`, `test/test_codegen.ml:343–348, 371–374, 1735–1737, 1815–1817`,
and `lib/jit/repl_jit.ml:495–517`, each of which hand-rolls `Mono → Defun → Perceus → Escape`.
`test_oracle` drives the `march` binary as a subprocess and gets it via `MARCH_VERIFY_TIR=1`. The
REPL/JIT sequence differs (no `Borrow.infer_module`, `Kind.of_module ~unboxing:false`,
`~repl:true`), so checks that need a borrow map or repr table take them as options and skip when
absent.

**Design.** `lib/tir/tir_verify.ml`, `Tir_verify.check : stage:string -> ?borrow_map ->
?k_table -> tir_module -> error list`, on under `--verify-tir` / `MARCH_VERIFY_TIR=1` and always
in the drivers above. An error names the stage, function, construct and invariant. Checks, in
bug-yield order, each its own PR:

1. **Scoping and references.** Every `AVar` is bound; every `EApp` callee is in `tm_fns`,
   `tm_externs`, **or the builtin set**. Builtins are plain `EApp`s on a bare runtime name
   (`tir.ml:42`); the emitter's "known callee" test is three places
   (`Llvm_builtins.builtin_ret_ty`, `Builtin_name`, and a hard-coded I/O list at
   `llvm_emit_call.ml:655–662`), and an unknown callee is silently `declare`d
   (`:663–682`). **First deliverable: one enumerable builtin table** that both the emitter and the
   verifier use. `ADefRef` resolves by `did_hash` matching a `tm_fns` entry's impl hash (content
   hash, not a name, `tir.ml:28–31`). `ECallPtr` is indirect: check only that the callee atom has
   a function/pointer type. No two `fn_def`s share a name.
2. **Type consistency.** `EApp` argument types unify with the callee's `fn_params`; `ECase`
   branches bind the constructor's arity; `EField` names exist in the record type; after mono, no
   `TVar` reaches a position where codegen must pick a concrete repr (the
   `Array.from_list$..$Float` wrong-value bug, `llvm_ctx.ml` `top_fn_param_tys` comment).
3. **RC balance (post-Perceus).** Perceus is dup/drop (Koka-style), not linear-consume: an owned
   var gets `EIncRC` at every non-last use and `EDecRC` where it dies (`perceus_core.ml:836–895`,
   `find_inc_vars`). The invariant is a **count balance** on every path:
   `1 + #EIncRC/EAtomicIncRC = #consuming uses + #EDecRC/EAtomicDecRC/EFree`. Exemptions the
   check must know or it false-positives: `needs_rc env ty = false` (scalars, unboxed per
   `k_table`; `perceus_core.ml:354` via `Kind.needs_rc_of`); `borrowed_field_vars` (fields
   projected from a borrowed param, `:138–176`); closure free variables in the `borrowed` set
   (`:663–665`); borrowed callee positions via `Borrow.is_borrowed` (`:869, 895`); `Lin`/`Aff`
   bindings, which get `EFree` not `EDecRC` (`march_runtime.c:545–552`); immortal literals
   (`:490–495`); `Perceus_elide` cancelling adjacent pairs (`perceus_elide.ml:24–39`), which
   changes counts but not balance. Take `~borrow_map` from `Contract_pipeline.run`, which
   already computes it once for Perceus, Drop and Escape (`contract_pipeline.ml:170–178`;
   `Borrow.infer_module`, `borrow.ml:1020`). Liveness can reuse the pure
   `Perceus_liveness.live_before` (`perceus_liveness.ml:41`, exported via `Perceus`); the balance
   invariant does not require an independent dataflow. Whether this check would have caught the
   September leaks is to be re-derived from each fixed bug's shape as the check's red tests, not
   assumed.
4. **Repr invariants (pre-codegen).** Promote the `MARCH_REPR_AUDIT` recorder to a check over
   `k_table`: niche/unboxed decisions consistent with every `EAlloc`/`ECase` on the type;
   `collision_set` tags agree across all uses.
5. **Pass contracts.** Post-defun: no lambda-bearing `ELetRec`. Post-mono: no polymorphic
   `fn_def`. Post-join-points: every `$jp` defined once. Post-escape: `EStackAlloc` values do not
   escape (`Escape.escape_analysis` is a transform, `escape.ml:624`; add a checking mode).

**Prove it red.** Each check lands with a test feeding it hand-broken TIR (for check 3: the
pre-fix Perceus output of a fixed September leak, reconstructed) and asserting the error.

**Cost.** O(program) per pass, opt-in outside tests. ~1 500 lines across the five.
**Effort.** 1–2 sessions per check; the builtin table and check 3 are the largest.

## 7. A2 — Source provenance that survives to the binary

**Status (2026-10-06):** table, seeding/rename hooks, pass recording, `--debug-info`
(function-level `!dbg`, plus a per-call location the verifier forces) and
`!march.provenance` landed; see `specs/progress/2026-10-06-provenance-table-debug-info.md`
for the two deviations (reset at the start of lowering, not of the pipeline; `!dbg` on every
call). Manifest sidecar still open.

**Problem.** TIR `fn_def` has no span (`tir.ml:158–164`); `lib/tir`, `lib/jit` and `bin` emit no
`DILocation`/`!dbg`/`DISubprogram` at all. A compiled crash, ASan report or `perf` profile names
`Foo.bar$Int$String+0x4c`; mapping it back is manual. `js_emit.ml:35, 57` already carries an
`fn_lines` side table for exactly this reason.

**Design: a provenance side table, not a TIR field** (TIR snapshots don't churn; same reasoning
as the `fn_kind` printer caveat in `tir.ml`).

```
Provenance.t : (string, origin) Hashtbl.t      (* fn_name → origin *)
origin = {
  src_span : span option;        (* from lowering, for user and stdlib fns *)
  host     : string option;      (* enclosing top-level fn for $lam/apply/jp/fused helpers *)
  derived  : derivation list;    (* Mono of (generic, tyargs) | Fusion of (f, g) |
                                    HofSpec of (g, arg) | Defun of lam | Inlined_from fn | ... *)
  passes   : string list;        (* passes that rewrote this fn's body *)
}
```
- **Seeding.** Lowering has the span at creation (`lower_decls.ml:312` builds the `fn_def` from
  `def.fn_name : Ast.name = {txt; span}`), **but renames fn_defs afterwards**
  (`lower_decls.ml:223, 380`; `lower.ml:666, 796, 883`). So seed at the *end* of `lower_module`
  by walking final `tm_fns` against a side map from original name to span, rather than at each
  creation site; and every later rename site calls `Provenance.rename`.
- **Where it lives.** `Contract_pipeline.run` threads nothing through passes (passes are
  `tir_module -> tir_module`; `k_table` is a local rebound at the end,
  `contract_pipeline.ml:143–148, 254`). Decision: `Provenance` is a module-level table **reset
  at the start of each `Contract_pipeline.run`**, the pattern every pass already uses
  (`Mono.repr_table`, `Fusion.gensym_ctr`, …), with B1's pass-by-pass work threading it properly
  where it touches a pass anyway. For the REPL, which runs many fragment compiles per process,
  the table is per-fragment and keyed with the fragment's host name (B1).
- **Consumers:**
  - **`DILocation` under a new `--debug-info` flag with its own CAS tag.** There is no `-g`
    option today: `--debug`/`--debug-tui` are the interpreter's time-travel debugger
    (`bin/main.ml:5311`, `:2541–2551`), and the compiled path passes clang `-g` and the `dbg` CAS
    tag only under that flag (`:3636, 3454, 1110`). Function-granularity `!dbg` is a one-site
    change on the `define` line (`llvm_toplevel.ml:268`) plus a `!llvm.dbg.cu` /
    `!llvm.module.flags` block in the header (`llvm_builtins.ml:1968`). Platform notes: ld64 needs
    `"Dwarf Version"`/`"Debug Info Version"` module flags and `dsymutil` for symbolised crashes;
    lld reads DWARF from the object. `Llvm_rc_inline` rewrites the module **text** after
    emission (`llvm_rc_inline.ml:18–21`, regexes on `call … @march_incrc(`): a trailing
    `, !dbg !N` on those lines is new text the regexes must tolerate; test that first.
    Function granularity is enough for ASan and `perf` to name March functions; per-instruction
    `!dbg` is open question §18.6.
  - **`!march.provenance` named metadata** on every function: the `derived` chain as a string.
  - **Build manifest as a sidecar**, not a section: `forge cap inspect` does not read sections,
    it shells out to `nm` for `__march_cap_*` symbol names (`forge/lib/cap_binary.ml:26`), so a
    section would need a new reader. `--compile-so` outputs already carry sidecars
    (`.hcr_manifest`, `.schemas.json`; `Cas.store_sidecars/restore_sidecars`, `cas.ml:338, 350`).
    `<out>.march_build` holds compiler identity, `build_cas_key` flags, source hash and (after
    B4) unit ids and keys, and rides the existing sidecar machinery.
  - The `--explain-fn` idea folds into A7's `origin` query.
- **Keeping it complete.** A5 diffs the table across two compiles and B3b fails loudly on a
  function with no host, which together catch a pass that forgets to record.

**Effort.** Table + seeding + `DILocation` + flag: 2–3 sessions. Manifest sidecar: ½ session.

## 8. A3 — RC tracing: site ids on top of `MARCH_TRACE_GC`

**What exists (and the first draft missed).** `MARCH_TRACE_GC=1` (`march_runtime.c:80–125`)
already writes JSONL `alloc`/`inc_ref`/`dec_ref`/`free` events with address, rc, tag and
timestamp to `trace/gc/gc.jsonl`, from `march_alloc` (`:458`), `march_incrc` (`:484`),
`march_decrc` (`:498`), `march_decrc_freed` (`:526`), `march_free` (`:559`) and
`march_incrc_local` (`:660`). RC underflow already aborts (`:507–513, 535–541`). The inline RC
fast path (`llvm_rc_inline.ml:8–16`) tests `march_gc_trace_state` and calls the out-of-line
function whenever tracing is on (`:27–29`; runtime `:98–104`), so the trace is complete with
inlining enabled. `march_live_allocs` is always on (`:304–312`); `str_alloc_count`/
`obj_alloc_count` are runtime-gated by `MARCH_STRING_STATS=1` (`:221–226`).

**What is missing.** *Who* did each inc/dec: the trace has addresses and counts, not the
emitting function. Per-object history is reconstructable offline from the JSONL but nothing does
it. No live-object dump on demand. No `EAllocHole` fill check.

**Design: extend, don't replace.**
- **Site ids out-of-band.** Adding a parameter to `march_incrc`/`march_decrc` would break the
  text-rewriting inline twins (`entries` table `llvm_rc_inline.ml:68–75` and the call-site
  regexes). Instead, under `--rc-trace` (own CAS tag), the emitter stores a dense site id into a
  thread-local `march_rc_site` immediately before each RC call, and the runtime's `gc_emit`
  adds a `site` field. The site table `(fn symbol, ordinal within fn)` is emitted into the module
  (the shared unit after B3). Release emission and the rewriter are untouched.
- **`scripts/gc-trace-report.py`**: folds `gc.jsonl` into per-object histories; prints live
  objects at exit with type tag, allocation site and full inc/dec history with sites, and any
  object that went negative. `SIGUSR1` → runtime flushes the trace so the script can run on a
  live process.
- **Checked runtime extras** in `MARCH_SANITIZE` builds (which already disable mimalloc and the
  inline fast path, `bin/main.ml:1085–1093`, `llvm_rc_inline.ml:46–48`): `EAllocHole` fills
  assert the slot is still null; `march_free` on a live object aborts with history.
- **Test integration.** The "delta: N" tests re-run under `MARCH_TRACE_GC=1 --rc-trace` on
  failure and attach the report to the alcotest message.

**Effort.** Site ids (emitter + runtime field): 1 session. Report script + `SIGUSR1`: ½.
Checked extras + test integration: ½.

## 9. A4 — Pass bisection and program reduction

**Facts.** The optional-pass switches that exist are `MARCH_NO_HOF_SPEC` and `MARCH_NO_UNBOX`
(`contract_pipeline.ml:32–44`), `MARCH_NO_INLINE_RC` (`llvm_rc_inline.ml:52`) and the CLI
`--no-opt` (`bin/main.ml:5302`). `MARCH_NO_TRMC` was **removed** 2026-09-21 (`bin/main.ml:5324–5328`;
the stdlib's list producers depend on TRMC). Mono, Defun, Perceus, Drop, Escape, TRMC,
`Dce.prune_unreachable` and `Native_map_inline` are unconditional (`contract_pipeline.ml:70, 96,
133, 171–179, 218, 238`); fusion, known-call, beta-ADT, join points and simplify are all under the
single `opt` boolean, and `Opt.run`'s inner passes (`opt.ml:33–43`, the `named_passes` table) have
no switches. `test/test_oracle.ml` enumerates real files (`bench/`, `examples/`,
`specs/lang/golden/`, ~135 today, plus a 15-entry native allowlist, `:11–20, 273–293`), has no
generator and no shrinker.

**Design.**
- **`disabled : string list` parameters** on `Contract_pipeline.run` and `Opt.run`, exposed as
  `--disable-pass NAME,…`, instead of more env vars; `named_passes` is already a name → pass list.
  Only the optional passes are disableable; the plan says so.
- **`march --bisect-pass FILE [--expect OUT]`**: re-runs with each optional pass disabled in
  pipeline order and reports the first whose removal fixes the output (vs the interpreter by
  default). A bug in a mandatory pass surfaces as "no removal fixes it" and goes to A1 (or §11).
- **`march --reduce FILE --oracle CMD`**: delta-debugging on the **AST** (drop a declaration;
  replace an expression with a literal of its inferred type; inline a `let`; drop an unused
  match arm) while `CMD` still fails, re-running parse/desugar/typecheck to keep candidates
  well-typed. Output: a minimal `.march`. (The stdlib's PBT shrinking is value shrinking in
  March; it is a precedent in spirit only.)
- `test_oracle` calls both on failure and attaches the minimal program and blamed pass.

**Effort.** `--disable-pass` + bisect: 1 session. Reducer: 2–3 sessions.

## 10. A5 — Determinism oracle; A6 — metrics and idempotence

**A5.** `scripts/ir-oracle.sh` already hashes `--emit-llvm` over ~240 programs and its header
(`:4–13`) states and relies on byte-identical output across runs and renamed copies;
`test/test_snapshots.ml:46–58` documents the counter-reset discipline and a 3-run determinism
check. A5 is `ir-oracle` run against **itself** under two private `HOME`s, cold then warm, from
two cwds, plus a `--dump-impl-hashes` flag (one line per fn: `symbol impl_hash sig_hash`) and the
provenance table (A2) added to the comparison. Store location differs by cwd
(`Cas.create ~project_root:(Sys.getcwd ())`) and is not compared. **Prove it red first** (add a
lambda to a stdlib module in one run). B1 needs this green; §12's memo layer needs it to audit
module-level state leakage between queries.

**A6.** Per-pass counts in `--timings` output (functions, allocs, `EIncRC`/`EDecRC`, reuse
tokens, join points), pinned for a handful of snapshot programs. **Idempotence**: `Opt.run` is a
fixed-point loop capped at 5 iterations (`opt.ml:60–66`), so the test asserts `changed = false`
after the last iteration on the snapshot corpus, not "second run is a no-op" (which would flag
the cap). Perceus is **not** idempotent by design (it inserts RC ops on RC-free TIR) and is not
run twice. Any second-run comparison also needs B1's counter removal first
(`Defun.lambda_counter`, `Fusion.gensym_ctr`, `Join_points.jp_counter`, `Mono.repr_table`,
`Lower_state`'s 18 module-level tables), which is why A6's idempotence half depends on B1.

**Effort.** A5 1 session; A6 ½ + ½.

## 11. Deferred: a TIR interpreter

A TIR interpreter would split the oracle in two (AST-eval vs TIR-eval isolates lowering through
Perceus; TIR-eval vs compiled isolates codegen) and is the most precise localiser for silent
wrong values, including bugs in the mandatory passes A4 cannot bisect. It is also a third backend
to keep in parity, and JIT parity is already a recurring bug class. **Defer** until A1 + A4 have
run for a quarter; revisit with the list of divergences they left un-localised.

## 12. A7 — A query interface; and the feasibility of a query-based compiler

### A7 — the interface
**What exists.** `lsp/lib/query.ml` is a facade over `Analysis` and `lsp/lib/query_cli.ml`
exposes it as `march-lsp query hover|type|symbols|definition|references|diagnostics|completions|
inlay|format FILE [--line --col]` → hand-rolled JSON (`:27–49`), tested in
`lsp/test/test_query_cli.ml`. It stops at the front end. **It is not reusable from `march`**:
`bin/dune` does not link `march_lsp_lib`, and `query.ml:7` depends on `Linol_lsp` types. There is
no pipeline state record either: `bin/main.ml` keeps everything as locals, and `--dump-phases`
converts each stage to a JSON string immediately (`Dump.tir_phase`, `lib/dump/dump.ml:475–560`),
so no TIR is retained in memory.

**Design.** A new `lib/query/` depending on `march_tir` + `march_cas` only, linked by both
binaries; the LSP proxies. Pipeline access via a **`snap`-based collector** that retains
`(label, tir_module)` pairs plus an early-exit hook, rather than refactoring the ~2 600-line
compile path into a resumable record.

| Query | Answers | Source |
|---|---|---|
| `fn NAME [--at PASS]` | TIR body at a pass; final symbol | snap collector, `Pp` |
| `origin NAME` | span, host, derivation chain, passes | provenance (A2) |
| `callers` / `callees NAME` | post-opt call graph | `Scc.deps_of` |
| `owners NAME` | per-variable borrow/RC verdicts | `borrow_map` + A1 check 3 |
| `repr TYPE` | niche/unboxed/boxed decision and why | `k_table` / `Kind` |
| `key FILE` / `key --unit ID` | whole-binary / unit keys and **every input** that fed them | `build_cas_key`, `unit_keys` |
| `why-miss FILE` | which key input changed since the last build | `.march_build` sidecar (A2/B4) vs current inputs |
| `verify [--stage S]` | A1 findings | `Tir_verify` |
| `bisect` / `reduce` | A4 | A4 |

`why-miss` pays first: the stale-cache fixes in `specs/progress/` were "which input changed?"
questions answered by hand with `MARCH_DEBUG_CASFLAGS`.

**Effort.** `lib/query/` + collector + `fn`/`origin`/`callers`/`key`: 2 sessions once A2 exists.

**Status (2026-10-07):** landed as `march query` with `fn`, `origin`, `callers`,
`callees`, `repr`, `verify`, `key` and `why-miss`
(`specs/progress/2026-10-07-a7-query-interface.md`). `owners`, `bisect`/`reduce`
and `key --unit` wait on A1 check 3, A4 and B3/B4.

### Feasibility of a query-*based* architecture
Salsa/rustc-style: every fact a pure function of recorded inputs, dependencies recorded as read,
re-run recomputes only what changed. Assessment:

**Against a full rewrite.**
- `typecheck.ml` is 9 346 lines of whole-module inference. The module-level refs the second draft
  named are mostly benign: `deferred_pending` (`:543`) and `wildcard_sink` (`:613`) are
  dynamically scoped with `Fun.protect`; `last_with_env_final` (`:9021`) is a return channel;
  `Typecheck_env.ctor_index_cache` (`typecheck_env.ml:1276`) is a content-keyed memo.
  **The real hazard for per-module memoisation** is that the seed `env` carries *mutable*
  `errors : Err.ctx` and `type_map : (span, ty) Hashtbl.t` that every layer writes into
  (`:9030–9031`): a "result" is a mutation of a shared table, not a value, so memoising it needs
  per-layer snapshotting. Also `check_module_core` resets `Json_dispatch` and `record_names_load`
  (`:8603–8620`) but `check_module_with_env` resets only the latter (`:9029`).
- `lower_state.ml` holds 18 module-level tables; defun, mono, fusion have global counters (B1
  removes those) and tables (`Mono.repr_table`, `Mono.stdlib_impl_syms`).
- Mono, defun, Perceus, escape and opt are whole-program **algorithms** (demand-driven from
  `main`, `k_table`/`collision_set` over all types). Per-declaration queries over them is a
  different algorithm, not a refactor.
- A rewrite of the pass structure before A1 exists would be done blind.

**For it, already there.** `Typecheck_reorder` computes per-declaration and per-module
dependency order (`typecheck_reorder.ml:1–5, 537`). `check_module_with_env_full` is env-in /
env-out, so per-layer in shape (though marked REPL-only via `root_cap_allowed = true`,
`:9024–9028`, so a generalised entry point is needed), and `lsp/lib/typecheck_cache.ml` already
memoises the stdlib+deps prefix keyed on `Cas.compiler_identity`. Every cache in the project is
"fact = f(inputs), memoised by hash"; what's missing is a shared mechanism and *recorded*
dependencies instead of hand-listed keys.

**Verdict: coarse query layer yes; fine-grained query architecture no.**
1. `lib/cas/memo.ml`: `Memo.query : name -> key -> (unit -> 'a) -> 'a`, in-process and on-disk
   tiers, **recording** which queries a computation read and persisting
   `(name, key, dep keys, result hash)`. Validity = all recorded deps unchanged.
2. Coarse nodes, least invasive first: `parse_desugar(file)` (pure already) →
   `typecheck_module(module, import_interfaces)` (generalised env layering, with `type_map`
   segmented per layer) → `lower_module` (after `lower_state.ml`'s tables move into an explicit
   state record) → `whole_program` (mono through opt, **one** node) → `unit_object` (B4) → `link`.
3. A7 reads the same memo tables, so `why-miss` is "which recorded dep changed".

**Risk specific to this.** Recording is sound only if every input is read through the API; a
pass reading a global ref or env var directly is an unrecorded dependency and a stale result.
`MARCH_NO_UNBOX` missing from `codegen_cas_tags` today (B7.4) is that failure in miniature.
Mitigation: a strict test mode that fails on unregistered `Sys.getenv`/module-ref reads, plus
A5 comparing memoised vs fresh across the corpus.

**Effort.** `Memo` + first two nodes: 1–2 weeks, as B6's first milestone. Blocks nothing in B1–B5.

---

# Part B — Incremental compilation

## 13. B0 — Measure before building

`--timings` exists (`stamp` in `bin/main.ml`; finer `mono`/`fusion`/`defun`/`perceus`/`drop`/
`escape`/`opt` stamps in `contract_pipeline.ml:88–249`); A6 adds counts to the same lines.

- `scripts/compile-time-bench.sh [--opt N] [--corpus small|bench|topology|all]`, private `HOME`;
  corpus: a `test/snapshots/src/` pick, `bench/tree_transform.march`, `examples/topology_app`;
  scenarios, 3× median: cold; warm no change; comment-only edit; leaf body edit; signature edit
  with many callers; record field added to a common type.
- Three buckets: **front end** (`parse`…`typecheck`), **whole-program TIR** (`lower`…`opt`),
  **back end** (`llvm-emit` + `clang`).
- Results committed once as `specs/plans/incremental-codegen-cas-baseline.md`; a "compile time"
  row in `specs/benchmarks.md`.

**Gate** is §3's criterion 1. Below it: B3–B5 do not start; B6 is reconsidered on the front-end
bucket. Part A, B1, B2 and B3a proceed either way (B3a only if someone wants the emitter
refactor for its own sake; otherwise it waits too).

## 14. B1 — Deterministic symbols (every counter that reaches a name)

The driver's HCR hashing comment (`bin/main.ml:947–951`) lists the problem: symbols like
`$lam39788$apply$4781` carry two global counters. Inventory (verified):

| Name shape | Generator | Counter |
|---|---|---|
| `$lam<n>` | `Lower_expr` (`lower_expr.ml:900`) | `Lower_state._lower_counter`, reset per `lower_module` |
| `<lam>$apply$<n>`, `$Clo_<lam>$<n>` | `Defun` via `Tir_names` (`defun.ml:518–519, 585, 590`) | `Defun.lambda_counter`, never reset |
| `$fused_<p>_<n>` | `Fusion` (`fusion.ml:35–38`) | module-level, never reset |
| `<g>$hspec$<n>` | `Hof_spec` (`hof_spec.ml:184`) | per-run `st.counter` |
| `$V__<n>` | `Mono.mangle_ty` (`mono.ml:167, 1129`) | typecheck fresh-var ids |
| `$jp<n>` | `Join_points` (`join_points.ml:140`) | module-level; check it never reaches a symbol |
| `$t<n>`, `_i<n>` | lowering/inliner temps | locals only; alpha-normalised by `Serialize` |

Why the hash can't absorb this: a cached `.o` binds to callees **by symbol**; a renumbered helper
is an undefined symbol (loud) or the wrong function (silent).

**Design: host-scoped ordinals, minted at lowering, recorded in provenance (A2).**
- `Lower_expr` names a lambda `<host>$lam<i>` (`i` = index in a deterministic traversal of the
  host's body; nested → `<host>$lam<i>$lam<j>`) and records `host`.
- `Defun` keeps the **lambda's own name** as the apply prefix (`<lam>$apply$0`, `$Clo_<lam>$0`);
  `lam_uid` is removed. The prefix must stay the lambda's self-binding name:
  `Tir_names.apply_fn_base` (`tir_names.ml:151–170`) feeds `llvm_emit_call.ml:830–833`'s
  self-tail-call recognition (a measured 20k-depth stack overflow otherwise).
- `Fusion`: fused callees + call-site ordinal in the host. `Hof_spec`: `g` + the specialised
  argument's symbol. `Mono`: `$V_` suffix from canonical position in the specialisation's
  type-argument list. Each records a `derived` entry. Collision arguments per generator: open
  question §18.1.
- REPL/JIT: counter persistence in `lib/jit/repl_jit.ml:1657–1767` (`lambda_counter=N`
  sentinel) and `test/test_snapshots.ml:49–55, 187, 197` go away; a fragment's host is
  `$repl<n>`; remove the `Lower_state.reset_counter` interplay (`lower_state.ml:30–36`).
- **Consumers** (grep `$apply$`, `$Clo_`, `lam_uid`, `apply_fn_base`, `$lam`): `drop.ml:709–722`,
  `borrow.ml:679, 1064`, `perceus.ml:702, 772`, `perceus_core.ml:886`, `known_call.ml:41, 176`,
  `alloc_contract.ml:412, 461`, `hof_spec.ml:287`, `llvm_emit_call.ml:194, 244, 364, 545, 830`,
  `llvm_toplevel.ml:200, 222`, `native_map_inline.ml:108`, `llvm_emit_alloc.ml:46`,
  `js_emit.ml:6`, `llvm_emit.ml:2364–2374`, `test/test_codegen.ml:130–144, 5700–5785,
  15066–15243`, `test/snapshots/`. Retire `hr_slot_hashes`'s `counter_re` (`bin/main.ml:982`):
  it becoming a no-op is the check that nothing counter-shaped is left.
- Also fix `specs/todos/2026-10-01-cold-stdlib-cache-changes-specializations.md`; its repro and
  byte-identical `--emit-llvm` acceptance are reused here.

**Acceptance.** A5 green with a recorded red run; `ir-oracle` shows only renames; snapshots
regenerated (renames only); the P2 repro gives identical manifests; `forge deploy hot` lists zero
spurious functions between cold and warm builds.

**Effort.** ~1 week.

## 15. B2 — A per-function object key that doesn't cascade

`hash_module` folds each callee's **full** Merkle hash into its caller's: right for the
whole-binary key, wrong for objects (a leaf edit misses everything up to `main`; the HCR code
already works around this at `bin/main.ml` ~3320).

**A function's `.o` depends on:**
1. its post-opt TIR body with real symbols (TIR-level inlining is already in it);
2. each callee's symbol and **ABI**: `Serialize.write_fn_sig` (`serialize.ml:371–375`) is name +
   param types + return type only, but call sites also read `native_vec_params` (from the
   callee's **body**, `native_vec_param_idxs`, **off for mutual-TCO members**,
   `llvm_toplevel.ml:1183–1189`). Define
   `abi_hash fd = BLAKE3(sig_hash ++ native_vec_param_idxs fd ++ in_mutual_tco_group fd)`;
3. the transitive type-layout closure (`type_closure_hashes`);
4. program-wide emitter inputs: `globals_digest` below;
5. toolchain: `Cas.compiler_identity`, `Runtime_archive.cc_identity`, exact cflags.

```
Pipeline.unit_keys : tir_module -> globals_digest:string -> partition:(fn_def -> unit_id)
                     -> (unit_id * string * fn_def list) list
fn_key fd  = BLAKE3(impl_hash fd ++ sorted [callee symbol ++ callee abi_hash] ++ sorted type-closure hashes)
unit_key   = BLAKE3(sorted member fn_keys ++ globals_digest ++ "unit-format-v1")
```
**`globals_digest`, coarse in v1** (any change misses every unit; accepted): every `emit_module`
argument (`fast_math`, `pmap_threshold`, `target`, `hot_reload`, `impl_hashes`,
`remote_impl_hashes`, `remote_sig_hashes`, `emit_main`, `cap_attrib`, `cap_decls`, `k_table`);
`Serialize.serialize_type_def` of **all** `tm_types` in order (feeds `type_defs`,
`collision_set` which changes constructor tags, `poly_ctors`, `type_params`, `field_map`,
`ctor_info`, descriptors); `tm_externs`, `tm_tests`, `tm_exports`, `tm_io_fns`, `tm_name`; the
**order of `tm_fns` names** (`unqualified_fns` first-wins at `llvm_toplevel.ml:1136–1160`,
`main` last-wins at `1377–1385`; A5 shows whether stable, else sort at registration);
`build_cas_key`'s flag list verbatim (which already carries `noinlinerc`/`nohofspec`,
`bin/main.ml:1125–1131`) **plus `MARCH_NO_UNBOX`** (B7.4); `Llvm_toplevel.pin_main`;
`Llvm_builtins.called_syms`.

Per-unit dedup tables (`emitted_eq_fns`, `emitted_dispatch_fns`, `emitted_wraps`,
`unknown_decls`, `str_ctr`, `ctor_desc_ids`, `rec_shape_globals`, `call_tag_globals`) are
per-unit after the split and not in the digest. Constructor descriptors are declaration-ordered
and already per-unit (`llvm_ctor_desc.ml:80–96`; runtime interns by content).

**A1 runs before hashing.** `unit_keys` refuses (hard error under `--incremental`) if the
verifier reports anything on the post-opt TIR.

**Tests** (`test/test_cas.ml`): leaf body edit → only leaf's `fn_key`; leaf param-type edit →
leaf + direct callers; native-vec eligibility change → `abi_hash` + callers; record layout edit →
transitive users only; `fast_math` → every `unit_key`; mutual-recursion group edits move together.

**Effort.** ~3–4 days.

## 16. B3 — Split LLVM emission into units

### B3a — refactor, `--codegen-units=1` byte-identical (no dependency on B1)
`Llvm_emit.emit_module` → `Llvm_toplevel.emit_module ~emit_expr` (`llvm_toplevel.ml:976`) builds
one ctx (`buf`, `preamble`, `extra_fns`), runs a pre-pass (`top_fns`, `top_fn_*`,
`native_vec_params`, `unqualified_fns`, mutual-TCO groups via `Llvm_tco.find_mutual_tco_groups`,
`llvm_tco.ml:409`), emits every function, finalises program-wide pieces. Split into:

```
Llvm_toplevel.emit_shared : prepass -> tir_module -> string
Llvm_toplevel.emit_unit   : prepass -> unit_id -> fn_def list -> string
```
- **Pre-pass** once over the whole module (no emission): the tables above plus `collision_set`,
  the atom-literal scan, the `called_syms` union, provenance lookups.
- **Shared unit**: type/struct declarations, record-shape globals, the atom show-table (external
  linkage, below), HCR epoch + dispatch publish, cap declarations and markers, `@.rpc_impl_*`
  (indexed by `tm_fns` position, `llvm_toplevel.ml:1355–1373`), `@.hr_hash*`, module init,
  `main`, the A3 site table under `--rc-trace`.
- **Per-unit ctx**: fresh `buf`, `preamble`, `extra_fns`, counters, dedup tables, own ctor
  descriptor; `declare`s for every external reference, generated from the pre-pass.
- **Guard**: `scripts/ir-oracle.sh` zero-diff at `N=1` (prove red first); full suite; A6 counts
  unchanged.

### B3b — `N>1` (depends on B1 for host recovery, A2 for module partition)
What must stay together or be made link-safe (verified):
- **SCCs and mutual-TCO groups** are atomic; membership comes from the shared pre-pass.
- **On-demand helpers with external linkage**, duplicate-symbol link errors otherwise:
  `$clo_wrap` trampolines (`llvm_calls.ml:465–483`, `emitted_wraps`), structural equality
  `__eq$…` (`llvm_eq.ml:126, 186, 345, 546`), interface dispatch `__march_ifdispatch$…`
  (`llvm_dispatch.ml:60`). Under `N>1` every helper in `extra_fns` is **`linkonce_odr`**; under
  `N=1` unchanged.
- **`internal` helpers** (`Llvm_rc_inline` twins, `@.str*`/`@.strcell*`): duplicated per unit.
- **Aliases** `__migrate_<Actor>`/`__migrate_msg_<Actor>` (`llvm_toplevel.ml:1222–1280`) in the
  aliasee's unit.
- **Atom show-table**: `atom_names` fills during emission (`llvm_emit.ml:371`,
  `llvm_case.ml:945`) and `@march_atom_to_string`/`@march_atom_name_or_null` are **`internal`**
  (`llvm_toplevel.ml:573, 596`); split naively, `show(:x)` silently renders `:<atom>` across
  units. The shared unit scans all `fn_def`s for atom literals and defines the table externally;
  units `declare` it; the `buffer_contains … "define internal ptr @march_atom_to_string"` check
  (`:541`) goes.
- **Partition**: by **source module** of the base function from provenance (mono specialisations
  with their generic's module; `$lam`/apply/fused helpers with their host); a module over ~400
  fns splits into `BLAKE3(base_name) mod k` buckets; unit ids are stable strings. **B3-lite**
  (§3) is this with exactly two partitions, stdlib and user.
- **`.ll` publication**: `write_ll_tmp`/`publish_ll` run on **every** compile
  (`bin/main.ml:3221–3238`) and ~20 `test/dune` rules grep `native/*.ll`. Under `N>1`,
  `<basename>.ll` is the concatenation (shared first, then units in id order) and
  `<basename>.<unit>.ll` are published alongside.
- **Guard**: per-unit `llvm-as` over the `test/native` corpus (no general IR-validity gate exists;
  `test/dune:5023` has one local `check_ir`); link every `bench/*.march` and `test/native` fixture
  at `N=8` (the duplicate/undefined-symbol catcher); program output `N=1` vs `N=8` at `--opt 0`;
  full suite.

**Effort.** B3a 1–2 weeks (`llvm_toplevel.ml` is 1 809 lines; the boundary cuts the finaliser);
B3b ~1 week; B3-lite ~3 days on top of B3a.

## 17. B4 — Object store, parallel compile, link; B5; B6; B7

### B4
- **Store**: `<project>/.march/cas/objects-v1/<aa>/<rest>.o` + `.meta` (unit id, member symbols,
  provenance summary, cflags), write-through to `~/.march/cas/objects-v1/`; temp + `Unix.rename`
  as `Cas.copy_file_exec` already does (`cas.ml:283–297`). Key = B2 `unit_key` with the
  toolchain facet as `Runtime_archive.ensure` folds it.
- **Flow**: `unit_keys` → lookup per unit → emit + `clang -c` the misses in parallel
  (`Unix.create_process`, `-j ncpu`, `MARCH_JOBS`) → link runtime objects, shared, units, user
  FFI, `ffi_link` (order as today; `-Wl,--gc-sections` + `-ffunction-sections` apply to unit
  cflags) → store under both whole-binary keys as today.
- **Eligibility**: `Runtime_archive`'s predicate and `--incremental`/`MARCH_INCREMENTAL=1`;
  `MARCH_NO_RUNTIME_CACHE=1` also disables the object store. `MARCH_ECHO_CC` prints per-unit
  commands. `MARCH_DEBUG_UNITS=1` prints id, key, hit/miss, members.
- **Verify mode** `MARCH_INCREMENTAL_VERIFY=1`: on every hit, recompile and byte-compare the `.o`
  (keep `-grecord-command-line` off under `--debug-info`), **and** run A1 on the TIR behind the
  key. One CI job runs the native `test/dune` rules this way. The `.march_build` sidecar lets a
  failing binary be checked against the entries it was linked from.
- **Edit-sequence differential test** (`test/test_incremental.ml`, Slow): the `test_oracle`
  corpus plus `bench/`; seeded random sequences of 10 edits (rename a local, change a literal,
  add/remove a lambda, change a param type and fix callers, add a record field, add/remove a
  function, add an atom literal in one module and `show` it in another); after each edit compare
  incremental vs clean monolithic output and exit code. On failure, A4 minimises and bisects, and
  A3 reports live objects if the divergence is a leak delta.
- **Forge**: `forge build` passes `--incremental` (`forge/lib/cmd_build.ml:144` picks
  `--opt 0/2`); `forge watch` is the first consumer; `forge clean --cas` (`cmd_clean.ml:16–21`)
  already removes the store; add `forge clean --objects` and `forge cache gc [--max-size 2G]`
  (LRU by atime, both stores; `march cache gc` for non-forge users), default bound applied after
  a build.

**Acceptance.** Leaf-edit scenario ≥ 3× faster than the B0 baseline at **both** `--opt 0` and
`--opt 2`; comment-edit scenario unchanged (post-TIR hit); verify-mode job green; differential
test green. **Effort.** ~1 week.

### B5 — optimised builds and default-on
Units as ThinLTO bitcode (`-flto=thin -c`), link with `-flto=thin
-Wl,--thinlto-cache-dir=<store>/thinlto` (lld; `-Wl,-cache_path_lto,<dir>` on ld64; the `zig cc`
driver bundles lld). Detect at link time; fall back to plain objects at `--opt 0/1` and monolithic
at `--opt 2/3`. **Gate**: `bench/tree_transform`, `bench/list_ops`, `bench/binary_trees`,
`bench/fib` at `--opt 2`, 5× median, monolithic vs incremental+ThinLTO; no regression over 3%, or
`--opt 2/3` stays monolithic. Then `--incremental` default on, `--no-incremental` to opt out,
`--codegen-units=1` kept for bisecting. **Effort.** 3–5 days plus benchmark time.

### B6 — front end (separate plan)
Design is §12's memo layer: `parse_desugar` → `typecheck_module` (per module, keyed on source +
import **interface** hashes, generalising `check_module_with_env_full` / `typecheck_cache.ml`,
with `type_map` segmented per layer) → `lower_module`, mono-through-opt one node. Only if B0 shows
that node dominating: a per-specialisation mono cache keyed on (generic `impl_hash`, type args).
A stale typecheck result is a soundness hole; own plan, own oracle (`types-oracle.sh` plus
`Memo`'s strict mode).

### B7 — independent quick wins, each its own todo → progress entry
1. **Replay stored diagnostics on a cache hit.** `Errors.diagnostic` is structured
   (`errors.ml:21–29`, `render_diagnostic` `:185`, `render_diagnostic_json` `:308`), but JSON is
   one-way and rendering re-reads source; store the **rendered text** as a sidecar via
   `Cas.store_sidecars`. This removes the `no_alloc` text bailout (`bin/main.ml` ~2037) for
   warnings-only runs; runs whose *output* is a report (`--refine-*`, `--report-contracts`,
   `--dump-role-authority`, `--emit-protocols`, `:1977–1988`) stay bypassed.
2. **Key the source-level cache on the previous build's load set, ccache depend-mode style.** The
   check runs **before parsing** (`:1988–2092`, then `t_compile_start` at `:2098`), so the
   resolver's actual set is not knowable there. But `resolve_imports` returns `user_files`
   ("every file loaded as user code", `resolver.ml:650–655`): store it as a sidecar and on the
   next run hash only those files, falling back to today's directory walk if any listed file is
   missing or a **new** `.march` appears in a walked directory (a new sibling can become
   reachable). A pre-filter via `referenced_name_tokens` on the entry alone is unsound
   (reachability is transitive) and is not the plan.
3. **Write-through to the global store**; delete `Runtime_archive`'s stale sentence claiming
   `Cas.store_artifact` writes directly (`runtime_archive.ml:52–55`; `copy_file_exec` has done
   temp+rename since).
4. **Add `MARCH_NO_UNBOX` to `codegen_cas_tags`.** It changes emitted code
   (`contract_pipeline.ml:146`) and is absent from the key, so an A/B run reuses whichever
   variant was cached first. (`noinlinerc`/`nohofspec` were added 2026-10-01, f49c43b6; this is
   the remaining one.)

---

## 18. Correctness strategy, risks, open questions

| Guard | Lands in | Catches |
|---|---|---|
| TIR verifier on every `snap` in tests and the JIT | A1 | inter-pass invariant violations at the violating pass |
| Determinism oracle (`ir-oracle` × two HOMEs/cwds + hashes + provenance) | A5 | unstable symbols/hashes; passes that forget provenance |
| `Opt` fixed-point assertion | A6 | non-converging / order-dependent opt passes |
| `ir-oracle` zero-diff at `N=1` | B3a | emitter refactor changing output |
| Per-unit `llvm-as` + `N=8` link of bench + `test/native` | B3b | missing `declare`s, duplicate helpers, alias placement |
| `MARCH_INCREMENTAL_VERIFY=1` (byte-compare + A1) in CI | B4 | a key that under-approximates a dependency |
| Edit-sequence differential test, with A3/A4 on failure | B4 | everything above, end to end, with a minimal repro |
| Benchmark gate ≤ 3% | B5 | perf loss from splitting |

**Risks.**

| Risk | Likelihood | Mitigation |
|---|---|---|
| Program-wide emitter input missing from `globals_digest` → stale object | medium | coarse digest from a field-by-field audit; verify mode; narrow only with a test per narrowing |
| A counter-derived name B1 missed | medium | A5; `counter_re` retirement; link errors loud; differential test for the silent case |
| B3a refactor changes codegen | high (large diff) | `N=1` byte-identity; lands behind default `N=1`; A6 counts as second signal |
| Duplicate-symbol link errors from on-demand helpers | high without `linkonce_odr` | §16 rule + `N=8` link guard |
| Verifier false positives (esp. check 3's exemption list) block `--incremental` | medium early | verifier ships in tests first; false positives fixed before B2 depends on it |
| Provenance table incomplete (rename sites, passes that forget) | medium | seed at end of lowering; A5 diffs; B3b fails loudly on a missing host |
| `!dbg` text breaks `Llvm_rc_inline`'s regex rewrite | medium | test first; `--debug-info` is a separate CAS tag |
| `-O2` perf loss | medium | ThinLTO; 3% gate; else dev-builds only |
| `tm_fns` order unstable | low | sort at registration; A5 detects |
| B0 shows no compile-time problem worth B3–B5 | **plausible** | §3: B3–B5 don't start; Part A, B1, B7 still pay |

**Open questions.**
1. Structural-naming schemes for `Fusion`/`Hof_spec`/`Mono` helpers with a collision argument
   each (two fusions of the same callees in one host → ordinal; two `hspec`s of `g` on the same
   argument symbol → one function; dedupe).
2. Is `tm_fns` order already deterministic given deterministic input? A5 answers.
3. ThinLTO availability on every CI image and macOS developer setup.
4. `.ll` publication under `N>1`: concatenate (assumed) or update the ~20 `test/dune` rules.
5. A1 check 3: is the exemption list complete? Each false positive found while running it over
   the snapshot corpus is either a new exemption or a real bug; the PR must say which for each.
6. A2 `DILocation` granularity: function-level first; is per-instruction worth span plumbing
   through mono/defun/fusion?
7. A2 provenance as a module-level table vs. threading through pass signatures: the plan picks
   the former for now; B6's memo layer argues for the latter. Decide when B6 starts.

## 19. Review record

### First draft (CAS-only), reviewed 2026-10-04 against the source
Four blockers, eleven should-fixes; all folded in.
- **Blockers:** stabilised one counter (`lam_uid`) when six generators reach symbols (§14 table);
  the naming scheme would have broken self-tail-call recognition (`apply_fn_base` must keep the
  lambda's self-binding name); three helper families have external linkage and would have
  produced duplicate-symbol link errors (`linkonce_odr`); the atom show-table is `internal` and
  would have silently degraded across units.
- **Should-fixes:** `globals_digest` missed `type_defs`, `collision_set`, `unqualified_fns`
  order, `tm_externs`/`tm_tests`/`tm_exports`/`tm_io_fns`, `pin_main`, `called_syms`;
  `ctor_desc_ids` is declaration-ordered and already per-unit; `sig_hash` narrower than assumed
  (→ `abi_hash`); `Cas.store_artifact` already does temp+rename; finer `Contract_pipeline`
  stamps; `.ll` publication on every compile; REPL counter persistence is in `lib/jit/`; forge
  integration; Windows out of scope; B3a independent of B1.

### Second draft (Part A, queryability), reviewed 2026-10-04 against the source
Four blockers, ~20 should-fixes; all folded in.
- **Blockers:** A1's "callee in `tm_fns` or `tm_externs`" was false (builtins are bare `EApp`s,
  known-callee test is three places, unknown callees silently `declare`d → the builtin table is
  now A1's first deliverable); A3 proposed a tracing mode the runtime **already has**
  (`MARCH_TRACE_GC`, with RC-underflow abort; the inline fast path already defers to it) → A3 is
  now "site ids on top of it", out-of-band so the inline rewriter is untouched; A4's switch
  inventory was wrong (`MARCH_NO_TRMC` removed 2026-09-21; mandatory passes listed; `test_oracle`
  has ~135 real files, no generator); A7 assumed `march` could link `lsp/lib/query.ml` (it
  can't: `Linol_lsp` dependency, not in `bin/dune`) and that `--dump-phases` retained TIR (it
  serialises to JSON immediately) → `lib/query/` + `snap` collector.
- **A claimed "live cache bug" was already fixed.** `noinlinerc` has been in `codegen_cas_tags`
  since f49c43b6 (2026-10-01). The real gap is `MARCH_NO_UNBOX`; B7.4 and §12 now say so.
- **Should-fixes:** three existing targeted checks (`MARCH_REPR_AUDIT`,
  `Mono.check_repr_disagreement`, `Policy_dce.audit`) are the precedents; `snap` is the hook;
  five non-`Contract_pipeline` call sites listed; Perceus invariant is a count balance with a
  nine-item exemption list, not linear consumption; `borrow_map` already threaded; lowering
  renames fn_defs after creation (seed at end); no pipeline state record exists (module-level
  table, decided); no `-g` flag exists (`--debug-info`); `forge cap inspect` uses `nm`, not
  sections (sidecar); `!dbg` text vs `Llvm_rc_inline` regexes; `Opt` is a capped fixed point and
  Perceus is not idempotent; `ir-oracle` already asserts determinism; the second draft's list of
  "global" typecheck refs was mostly benign and missed the real hazard (shared mutable
  `type_map`/`errors` in the seed env); B7.2 impossible as written (check precedes parse →
  depend-mode sidecar); B7.1 diagnostics are structured but JSON is one-way.

### Third draft (this one), 2026-10-04
Structural: clean numbering; §3 decision gate and B3-lite added; stale cross-references fixed;
hand counts marked or removed per CLAUDE.md. **Not yet reviewed independently:** §3's decision
framing and the B3-lite design, A3's out-of-band site-id mechanism, and B7.2's depend-mode
fallback rule.

### Still unverified
Everything about *time* (no build was possible in the authoring environment; B0 exists for
this); ThinLTO on CI images; `tm_fns` order stability; A1 check 3's exemption list completeness.
