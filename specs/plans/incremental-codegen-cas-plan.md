# Compiler Observability and Incremental Compilation — Plan

**Date:** 2026-10-04
**Status:** Proposed (not yet measured; see B0). Reviewed once against the source; see §17.

---

## 0. Why one plan

Incremental compilation caches machine code keyed on what the compiler *believes* that code
depends on. Every such belief is an invariant, and the project's bug history says invariants
between passes are exactly what break: of ~1 200 `specs/progress/` entries, the largest classes
are RC/Perceus leaks and double frees (~45), JIT parity (24), codegen repr/niche/TCO (~30),
typecheck (13), stale caches (~13) and silent wrong values (~10). The September 2026 leak fixes all
read the same way: two passes disagreed about ownership, a hand-written delta test caught it, and
someone read IR to root-cause it.

A per-unit object cache multiplies the cost of that class: a stale object is a silent miscompile
that reproduces only with a particular edit history. So this plan is in two parts:

- **Part A — Observability foundations.** A TIR verifier, source provenance that survives to the
  binary, RC event tracing, pass bisection and reduction, a determinism oracle, and per-pass
  metrics. Each pays for itself on today's bugs. Together they are the preconditions for trusting
  a cache.
- **Part B — Incremental compilation.** The CAS work, re-based so that every phase names the
  foundation it consumes and the guard that catches it being wrong.
- **Queryability** cuts across both: a query *interface* over compiler facts (A7) is the
  debugging front door for everything in A, and a coarse query *layer* with recorded
  dependencies (§8b) is what B6 should be built on. §8b records why a full query-based
  rewrite is not.

Part A items are independent of each other and can start now. Part B's critical path is
B0 ∥ B1 ∥ B3a → B2 → B3b → B4 → B5; the arrows from A into B are in §3.

---

## 1. Problem (incremental compilation)

The CAS speeds up a compile only when nothing changed. Three caches exist today:

| Layer | Where | Key | A hit skips |
|---|---|---|---|
| Source-level | `bin/main.ml` (~2029–2090, `source_cas_state`) | MD5 of entry file + stdlib hash + every `.march` under the entry's directory and each `MARCH_LIB_PATH` dir | everything (copies the binary, `exit 0`) |
| Post-TIR | `bin/main.ml` (~3310–3395) | concatenation of every SCC's Merkle `impl_hash` from `Pipeline.hash_module`, through `build_cas_key` | `llvm-emit` + clang only |
| Runtime objects | `lib/cas/runtime_archive.ml` | runtime `*.{c,h}` digest + compiler identity + `cc --version` + exact cflags | recompiling the ~20-file C runtime |

Any real edit misses both whole-program keys and pays the full pipeline: parse → desugar →
resolve → stdlib-load → typecheck → lower → mono/fusion/defun/Perceus/drop/escape/opt → LLVM
emission of the **whole** program (every monomorphised stdlib specialisation; `examples/topology_app`'s
`--compile-so` manifest lists ~13 000 functions) → one clang invocation over one `.ll`.

`Pipeline.compile_scc` (`lib/cas/pipeline.ml`) is a tested per-SCC cache nothing calls. Its doc
comment names the blocker: codegen emits one LLVM module and links one binary. This plan does
**not** revive it; its key is the transitive Merkle hash, which §10 explains is wrong for objects.

### Terms
- **Symbol**: the LLVM function name a TIR `fn_def` is emitted under.
- **`impl_hash`**: `Hash.hash_fn_def`'s hash of signature + body, alpha-normalised locals,
  callees referenced **by name**.
- **Merkle `impl_hash`**: `Pipeline.hash_module`'s fold with callees' Merkle hashes and the
  type-layout closure. Computed on `pipe.Contract_pipeline.final`, i.e. **post-optimisation**
  TIR (`bin/main.ml:3313`).
- **Unit**: a set of `fn_def`s emitted into one `.ll` / compiled to one `.o` (B3).
- **Provenance table**: the side table A2 introduces, `fn_name → origin` (TIR has no spans).

## 2. Goals and non-goals

**Goals.**
1. A compiler bug that is an inter-pass invariant violation is reported at the pass that violated
   it, naming the function, not three stages later as a wrong value or a leak delta.
2. A compiled crash, leak or divergence names the March source line and the passes that produced
   the code, without reading IR.
3. After editing one function, the native `--compile` path re-emits and re-compiles roughly the
   unit containing it, then links. A cached object is never used when a clean build would have
   produced different machine code for it.

**Non-goals.**
- WASM, JS, cross-compiled and `--compile-so`/`--hot-reload` builds keep the monolithic path
  (same reasons as `Runtime_archive`'s eligibility check, `bin/main.ml` ~4039–4046). HCR
  sidecars are therefore out of scope.
- Windows (nothing supports it today).
- Incremental *type checking* of user modules (B6 sketches it; separate plan).
- A TIR interpreter as a second oracle backend: considered and deferred, see §8.

## 3. Dependency map

```
A1 TIR verifier ─────────────┬──► B2 unit keys (verifier runs before hashing)
                             ├──► B3a emitter refactor (verifier on every pass under test)
                             └──► B4 verify mode (TIR-level check on cache hits)
A2 provenance table ─────────┬──► B1 structural names (host of a lambda = provenance)
                             ├──► B3b partition by source module
                             └──► B4 .meta sidecars, build manifest in the binary
A3 RC tracing ───────────────┬──► B4/B5 differential test triage
                             └──► today's leak hunts
A4 bisection + reducer ──────┬──► B4 edit-sequence differential test (minimal repros)
                             └──► today's oracle divergences
A5 determinism oracle ───────┬──► B1 acceptance
                             └──► B2 (tm_fns order question, §10)
A6 metrics + idempotence ────┬──► B0 bench harness (same stamps)
                             └──► B3a byte-identity (counts as a second signal)
A7 query interface ──────────┬──► B4 `why-miss` over .meta sidecars
                             └──► today's "which input changed?" cache hunts
Memo layer (§8b) ────────────┬──► B6 (its design: per-module typecheck/lower queries)
                             └──► B2 globals_digest → recorded deps, over time
```

Everything in A ships alone and is useful alone. Nothing in B after B0 should land before the A
item it consumes.

---

# Part A — Observability foundations

## 4. A1 — TIR verifier

**Problem.** No well-formedness checker exists for TIR; `grep invariant lib/tir/` finds comments.
Passes trust each other. The tuple-destructure leak
(`specs/progress/2026-09-30-compiled-tuple-destructure-leaks-moved-fields.md`) was Perceus
treating a scrutinee as borrowed while codegen made the binders own the fields; nothing between
them could say so.

**Design.** `lib/tir/tir_verify.ml`, `Tir_verify.check : stage:string -> tir_module -> error list`,
called by `Contract_pipeline.run` after every pass when `--verify-tir` is set or
`MARCH_VERIFY_TIR=1`, and **always** in the test drivers (`run_codegen`, `run_snapshots`,
`test_oracle`). An error names the stage, the function, the construct and the invariant. Checks,
in bug-yield order, each its own PR:

1. **Scoping and references.** Every `AVar` is bound in scope; every `EApp` callee is in `tm_fns`
   or `tm_externs`; `ADefRef` hashes resolve; no two `fn_def`s share a name.
2. **Type consistency.** `EApp` argument types unify with the callee's `fn_params`; `ECase`
   branches bind the constructor's arity; `EField` names exist in the record type; after mono, no
   `TVar` reaches a position where codegen must pick a concrete repr (the
   `Array.from_list$..$Float` wrong-value bug, `llvm_ctx.ml` `top_fn_param_tys` comment).
3. **Ownership discipline (post-Perceus).** A linear check over TIR: every owned variable is
   consumed exactly once on every path (`EDecRC`/`EFree`/moved into an alloc or call that
   consumes); no use after consumption; `EReuse`/`EAllocHole` tokens consumed exactly once;
   borrowed parameters (`Borrow`'s map) never dropped; scrutinee treatment matches what
   `llvm_case.ml`'s `strip_scrut_decrc` arm will assume. This check would have caught the
   September leaks at the Perceus stage.
4. **Repr invariants (pre-codegen).** `k_table` niche/unboxed decisions are consistent with every
   `EAlloc`/`ECase` on that type; `collision_set` tags agree across all uses.
5. **Pass contracts.** Post-defun: no lambda-bearing `ELetRec`. Post-mono: no polymorphic
   `fn_def`. Post-join-points: every `$jp` defined once. Post-escape: `EStackAlloc` values do not
   escape (reuse `Escape`'s own analysis in checking mode).

**Prove it red.** Each check lands with a test that feeds it a hand-broken TIR (e.g. the
pre-fix Perceus output from the tuple leak, reconstructed) and asserts the error.

**Cost.** O(program) per pass; under `--verify-tir` only. Expect ~1 500 lines across the five.

**Effort.** 1–2 sessions per check; ownership (3) is the largest.

## 5. A2 — Source provenance that survives to the binary

**Problem.** TIR `fn_def` has **no span field** (`tir.ml`); the LLVM emitters produce zero
`!dbg`/`DILocation` metadata. A compiled crash, an ASan report or a `perf` profile names
`Foo.bar$Int$String+0x4c`; mapping it back is manual. `js_emit.ml` already carries an `fn_lines`
side table for exactly this reason.

**Design: a provenance side table, not a TIR field** (so TIR snapshots don't churn, the same
reasoning as the `fn_kind` printer caveat in `tir.ml`).

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
- `Lower` seeds `src_span`; every pass that creates or renames a function records a
  `derivation` and its own name under `passes`. The table travels in `Contract_pipeline`'s
  state alongside `k_table`.
- **Consumers:**
  - **`DILocation` under `-g`**: `Llvm_toplevel.emit_fn` emits `!dbg` on the `define` from
    `src_span` (or the host's span for synthetic fns), and per-instruction `!dbg` only where TIR
    gives a position (initially: function granularity, which is already enough for ASan and
    `perf` to name March functions and lines). Gated on the existing `dbg` CAS tag.
  - **`!march.provenance` named metadata** on every function: the `derived` chain as a string.
    `--emit-llvm` output then explains where every `$fused_*`/`$hspec`/`$lam` came from.
  - **`--explain-fn NAME`**: prints the origin and, with `--dump-phases`, the body at each pass.
  - **Build manifest section** (`.march_build`, read the way `forge cap inspect` reads sections):
    compiler identity, `build_cas_key` flags, source hash, and (after B4) unit ids and keys. Every
    bug report becomes self-describing, and B4's verify mode can confirm a binary was built from
    the cache entries it claims.
- **Keeping spans attached.** Mono, fusion, defun and inlining create functions without spans
  today; each records `host`/`derived` instead, so a synthetic function always has a span to
  borrow from. The determinism oracle (A5) also diffs the provenance table, which catches a pass
  that forgets to record.

**Effort.** Table + lowering seed + `DILocation`: 2 sessions. Manifest section: 1 session.
Recording in each pass: small, folded into B1's pass-by-pass work.

## 6. A3 — RC event tracing and a checked debug runtime

**Problem.** `march_live_allocs` / `str_alloc_count` / `obj_alloc_count` (`march_runtime.c`
~138–233) say *that* and *how many*; not *which object* or *who held the last reference*.

**Design.**
- `MARCH_RC_TRACE=1` at **compile** time selects a runtime build (through `Runtime_archive`,
  which keys on cflags, so it's a separate cached object set) where `march_incrc`/`march_decrc`/
  `march_alloc` take a **site id**. The emitter passes one under this mode only: a dense id into
  a table of `(fn symbol, ordinal within fn)` emitted into the shared unit. The runtime keeps a
  per-object ring of `(event, site, thread)` and, at exit (or on `SIGUSR1`), prints every live
  object with its type tag, allocation site and full RC history, and every object whose count
  went negative. Release builds are byte-identical to today (no mode, no extra arguments).
- **Checked runtime asserts**, on in `MARCH_SANITIZE` and trace builds: `march_decrc` on a count
  of 0 aborts with the object's history; `march_free` on a live object likewise; `EAllocHole`
  fills check the slot is still null.
- Test integration: the existing "delta: N" tests gain `MARCH_RC_TRACE` on failure and attach the
  live-object dump to the alcotest failure message, so the first run of a failing leak test says
  which objects.

**Effort.** Runtime side 1 session; emitter side (site ids) 1 session; test integration ½.

## 7. A4 — Pass bisection and program reduction

**Problem.** The differential oracle (`test/test_oracle.ml`, ~1 090 generated programs,
interpreter vs compiled) reports "X vs Y" with the whole program; no shrinker exists; which pass
is wrong is a manual bisect.

**Design.**
- **`march --bisect-pass FILE`**: re-runs the compile disabling one optional pass at a time, in
  pipeline order, comparing compiled output against the interpreter (or against a `--expect`
  file), and reports the first pass whose removal fixes the output. The switches mostly exist
  (`MARCH_NO_HOF_SPEC`, `MARCH_NO_UNBOX`, `MARCH_NO_TRMC`, `MARCH_NO_INLINE_RC`); add the missing
  ones (fusion, join points, single-use inline, escape, native-map inline) under the same naming
  so the set is enumerable from one list in `Contract_pipeline`. Then run A1's verifier at the
  reported pass boundary for the invariant.
- **`march --reduce FILE --oracle CMD`**: delta-debugging on the **AST** (drop a top-level
  declaration; replace an expression with a literal of its inferred type; inline a `let`; drop a
  match arm whose constructor is unused) while `CMD` still fails. Reuses the parser, desugarer
  and typechecker to keep candidates well-typed; stdlib PBT already has integrated shrinking and
  the heuristics transfer. Output: a minimal `.march` that still exhibits the divergence.
- `test_oracle` calls both on failure and attaches the minimal program and blamed pass to the
  failure.

**Effort.** Bisect: 1 session. Reducer: 2–3 sessions.

## 8. Deferred: a TIR interpreter

A TIR interpreter would split the oracle in two (AST-eval vs TIR-eval isolates lowering through
Perceus; TIR-eval vs compiled isolates codegen) and is the most precise localiser for silent wrong
values. It is also a third backend to keep in parity; the JIT parity burden is already 24 progress
entries. Decision: **defer** until A1 + A4 have run for a quarter. If pass bisection plus the
verifier leave a class of divergences still un-localised, revisit with that evidence.

## 8a. A7 — A query interface over compiler facts

**What exists.** `lsp/lib/query.ml` is a transport-agnostic facade over `Analysis`, and
`lsp/lib/query_cli.ml` exposes it as `march-lsp query hover|type|symbols|definition|references|
diagnostics|completions|inlay|format FILE [--line --col]` → JSON, tested in
`lsp/test/test_query_cli.ml`. `forge search` (name/type search, `--callers`) covers declarations.
Both stop at the **front end**: nothing answers a question about TIR, a pass decision, a symbol's
origin, or a cache key. Those are exactly the questions a compiler-bug hunt asks, and today the
answers are `--dump-phases` JSON, `MARCH_DUMP_TXT` and reading IR.

**Design.** Extend the same facade downward rather than invent a second one. A `march query`
subcommand (in `bin/`, sharing `Query_cli`'s JSON conventions so the LSP can proxy it) over the
artefacts the pipeline already produces or Part A adds:

| Query | Answers | Source |
|---|---|---|
| `fn NAME [--at PASS]` | TIR body at a pass; final symbol | `--dump-phases` data, `Pp` |
| `origin NAME` | span, host, derivation chain, passes that rewrote it | provenance table (A2) |
| `why-symbol NAME` | why this symbol exists: which generic + tyargs, which fusion, which lambda | provenance `derived` |
| `callers NAME` / `callees NAME` | post-opt call graph edges | `Scc.deps_of` |
| `owners NAME` | per-variable ownership/borrow verdicts in a fn | `Borrow` map + A1 ownership check |
| `repr TYPE` | niche/unboxed/boxed decision and the reason | `k_table` / `Kind` |
| `key FILE` / `key --unit ID` | whole-binary and (after B2) unit keys, and **every input** that fed them | `build_cas_key`, `unit_keys`, `globals_digest` inputs |
| `why-miss FILE` | which key input changed since the last build of this file | `.meta` sidecars (B4) diffed against current inputs |
| `verify [--stage S]` | A1 findings | `Tir_verify` |
| `bisect FILE` / `reduce FILE --oracle CMD` | A4, under the same umbrella | A4 |

Implementation: each query is a function over a `Pipeline_state` record (AST, typed env, TIR per
pass, provenance, `k_table`, keys) that `Contract_pipeline.run` already threads most of; the
subcommand runs the pipeline to the needed stage, then answers. JSON output, `--text` for humans.
`why-miss` is the one that pays for itself first: the ~13 stale/missed-cache entries in
`specs/progress/` were all "which input changed?" questions answered by hand with
`MARCH_DEBUG_CASFLAGS`.

**Effort.** Facade + `fn`/`origin`/`callers`/`key`: 1–2 sessions once A2 exists. Each further
query ½ session; `why-miss` depends on B4's sidecars.

## 8b. Feasibility: a query-*based* compiler architecture

The other sense of "queryable": Salsa/rustc-style demand-driven memoisation, where every
compiler fact is a pure function of its inputs, dependencies are recorded as they are read, and
re-running after an edit recomputes only what transitively depends on changed inputs. It is how
serious incremental front ends are built, and it would make B6 principled rather than ad hoc.
Assessment against this codebase:

**What's against a full rewrite.**
- `lib/typecheck/typecheck.ml` is 9 346 lines of whole-module bidirectional inference with
  module-level mutable state (`deferred_pending`, `wildcard_sink`, `last_with_env_final`,
  `Typecheck_env.ctor_index_cache`, linearity tracked via aliased `bool ref`s). A query system
  requires every query to be a pure function of recorded inputs; this checker's state would all
  have to move into the query context first.
- Lowering keeps ~20 module-level tables in `lower_state.ml` (`_use_aliases`,
  `_protocol_roles`, `_actor_mailboxes`, `_builtin_shadows`, `_fns_ref`, …); defun, mono, fusion
  have global counters (B1 removes those) and tables (`Mono.repr_table`,
  `Mono.stdlib_impl_syms`).
- Mono, defun, Perceus, escape and opt are **whole-program** by design: demand-driven from
  `main`, with specialisation sets and representation decisions (`k_table`, `collision_set`) that
  depend on the whole set of types and call sites. A per-declaration query over them is not a
  refactor; it's a different algorithm.
- The project's bug history is dominated by inter-pass invariant breaks. A rewrite of the pass
  structure before A1 exists would be done blind.

**What's for it, and already there.**
- `Typecheck_reorder` computes per-declaration dependency order (SCCs of `DFn` runs, module
  dependency order for `DMod`). That is precisely the dependency graph a query system needs; it
  just isn't recorded or reused.
- `check_module_with_env_full` (the REPL JIT path) and `lsp/lib/typecheck_cache.ml` already
  implement "memoise the invariant prefix, re-check only the user layer", keyed by
  `Cas.compiler_identity` plus content hashes. That is a two-level query system with the levels
  fixed at (stdlib+deps, user file).
- The CAS, `Runtime_archive`, `stdlib_ast_*`/`stdlib_tcenv_*` caches and the B2 `unit_keys`
  design are all the same shape: a content-hash key over recorded inputs. The project already
  thinks in "fact = f(inputs), memoised by hash"; what it lacks is a shared mechanism and
  dependency *recording* instead of hand-listed keys.

**Verdict: feasible at coarse granularity, infeasible (and not worth it) at fine granularity.**
Recommend a **query layer, not a query architecture**:

1. **A memo primitive**, `lib/cas/memo.ml`: `Memo.query : name:string -> key:string ->
   (unit -> 'a) -> 'a` with on-disk (CAS) and in-process tiers, which **records** which other
   queries a computation read (a dynamic dependency trace, the way Salsa does) and persists
   `(name, key, dep keys, result hash)`. Correctness no longer rests on a hand-maintained key
   list like `build_cas_key`'s: a query's key is its declared inputs, and its validity is "all
   recorded deps still have the same result hash".
2. **Coarse query nodes**, in order of least invasive:
   - `parse_desugar(file)` — pure already;
   - `typecheck_module(module, import_interfaces)` — the existing env-layering path, generalised
     from two levels to per-module, keyed on the module's source plus the **interface hashes**
     (exported signatures + types) of its imports. `Typecheck_reorder`'s module order gives the
     evaluation order; the module-level refs in `Typecheck` get reset per query (they already are
     per `check_module` call) and audited by A5 for leakage between queries;
   - `lower_module(module, typed_env)` — after moving `lower_state.ml`'s tables into an explicit
     state record (a refactor B1 touches anyway);
   - `whole_program(tir_modules)` — mono through opt stays **one** query node, keyed on all
     lowered modules; it's whole-program and stays so;
   - `unit_object(unit_key)` — B4;
   - `link(objects)`.
3. **The query interface (A7) reads the same memo tables**, so `why-miss` is literally "which
   recorded dep's result hash changed", for free, and `key --unit ID` prints the recorded inputs
   rather than a reconstructed list.

This gives B6 its design (the first three nodes) and replaces B2's hand-listed `globals_digest`
with recorded dependencies over time, while leaving the whole-program middle untouched. What it
deliberately does **not** attempt: per-function typecheck queries, incremental mono, or
restructuring Perceus. If the `whole_program` node turns out to dominate (B0 will say), the next
step is per-specialisation mono caching inside it, not finer typecheck queries.

**Risks specific to this.** Dynamic dependency recording is only sound if every input is read
through the query API; a pass that reads a global `ref` or an env var directly is an unrecorded
dependency and a stale result. The `MARCH_NO_INLINE_RC` cache bug (B7.4) is exactly this failure
in miniature. Mitigation: `Memo` runs with a "strict" mode in tests that fails on any
`Sys.getenv` or module-level-ref read outside a registered input (wrap the handful of accessors),
and A5 compares memoised vs fresh results across the corpus.

**Effort.** `Memo` primitive + `parse_desugar` + `typecheck_module`: 1–2 weeks, as B6's first
milestone. It does not block any of B1–B5.

## 9. A5 — Determinism oracle, and A6 — metrics and idempotence

**A5.** `scripts/determinism-oracle.sh` + CI job: compile `test/snapshots/src/*.march`,
`bench/*.march`, `examples/topology_app` twice with `--emit-llvm` under two private `HOME`s, cold
then warm, from two cwds; compare `(symbol, impl_hash, sig_hash)` triples via a new
`--dump-impl-hashes` flag, the provenance table (A2), and the `.ll` text with the source path
normalised. Store location differs by cwd (`Cas.create ~project_root:(Sys.getcwd ())`) and is
not compared. **Prove it red first** (add a lambda to a stdlib module in one run). Non-determinism
is itself a bug and masks others; B1 needs this green.

**A6.** Per-pass counts in `--timings` output (functions, allocs, `EIncRC`/`EDecRC`, reuse
tokens, join points) so a fix that adds 400 incrcs elsewhere is a number in the log, not a perf
regression weeks later; pin a handful in the snapshot corpus. An **idempotence test**: run `Opt`
and `Perceus` twice over the snapshot corpus and assert the second run is a no-op, since
non-idempotent passes are a classic source of order-dependent bugs. Both ~½ session.

---

# Part B — Incremental compilation

## 10. B0 — Measure before building

`--timings` exists (`stamp` in `bin/main.ml` and the finer `mono`/`fusion`/`defun`/`perceus`/
`drop`/`escape`/`opt` stamps in `contract_pipeline.ml:88–249`); A6 adds counts to the same lines.

- `scripts/compile-time-bench.sh [--opt N] [--corpus small|bench|topology|all]`, under a private
  `HOME`; corpus: a `test/snapshots/src/` pick, `bench/tree_transform.march`,
  `examples/topology_app`; scenarios, 3× median: cold; warm no change; comment-only edit; leaf
  body edit; signature edit with many callers; record field added to a common type.
- Three reported buckets: **front end** (`parse`…`typecheck`), **whole-program TIR**
  (`lower`…`opt`), **back end** (`llvm-emit` + `clang`).
- Results committed once as `specs/plans/incremental-codegen-cas-baseline.md`; a "compile time"
  row in `specs/benchmarks.md`.

**Gate.** If for the edit scenarios at `--opt 2` the back end is under half of wall time,
re-order: B6 before B3b–B5. B1, B2, B3a and all of Part A proceed either way.

## 11. B1 — Deterministic symbols (every counter that reaches a name)

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
| `$t<n>`, `_i<n>` | lowering/inliner temps | locals only; alpha-normalised by `Serialize`; not symbols |

Why the hash can't absorb this: a cached `.o` binds to callees **by symbol**; a renumbered helper
is an undefined symbol (loud) or the wrong function (silent).

**Design: host-scoped ordinals, minted at lowering, recorded in the provenance table (A2).**
- `Lower_expr` names a lambda `<host>$lam<i>` (`i` = index in a deterministic traversal of the
  host's body; nested → `<host>$lam<i>$lam<j>`) and records `host` in provenance.
- `Defun` keeps the **lambda's own name** as the apply prefix (`<lam>$apply$0`, `$Clo_<lam>$0`);
  `lam_uid` degenerates and is removed. The prefix must stay the lambda's self-binding name:
  `Tir_names.apply_fn_base` (`tir_names.ml:151–170`) feeds `llvm_emit_call.ml:830–833`'s
  self-tail-call recognition (a measured 20k-depth stack overflow otherwise).
- `Fusion`: name from the fused callees plus call-site ordinal in the host. `Hof_spec`: from `g`
  plus the specialised argument's symbol. `Mono`: `$V_` suffix from canonical position in the
  specialisation's type-argument list. Each records a `derived` entry.
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
- Also fix `specs/todos/2026-10-01-cold-stdlib-cache-changes-specializations.md` (cold vs warm
  `stdlib_tcenv_cli_*.bin` emits different TIR); its repro and byte-identical `--emit-llvm`
  acceptance are reused here.

**Acceptance.** A5 green with a recorded red run; `ir-oracle` shows only renames; snapshots
regenerated (renames only); the P2 repro gives identical manifests; `forge deploy hot` lists zero
spurious functions between cold and warm builds.

**Effort.** ~1 week.

## 12. B2 — A per-function object key that doesn't cascade

`hash_module` folds each callee's **full** Merkle hash into its caller's: right for the
whole-binary key, wrong for objects (a leaf edit misses everything up to `main`; the HCR code
already works around this at `bin/main.ml` ~3320).

**A function's `.o` depends on:**
1. its post-opt TIR body with real symbols (TIR-level inlining is already in it);
2. each callee's symbol and **ABI**: `Serialize.write_fn_sig` (`serialize.ml:371–375`) is
   name + param types + return type only, but call sites also read `native_vec_params`
   (from the callee's **body**, `native_vec_param_idxs`, and **off for mutual-TCO members**,
   `llvm_toplevel.ml:1183–1189`). Define
   `abi_hash fd = BLAKE3(sig_hash ++ native_vec_param_idxs fd ++ in_mutual_tco_group fd)`;
3. the transitive type-layout closure (`type_closure_hashes`);
4. program-wide emitter inputs — `globals_digest` below;
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
`collision_set` — which changes constructor tags — `poly_ctors`, `type_params`, `field_map`,
`ctor_info`, descriptors); `tm_externs`, `tm_tests`, `tm_exports`, `tm_io_fns`, `tm_name`; the
**order of `tm_fns` names** (`unqualified_fns` first-wins at `llvm_toplevel.ml:1136–1160`,
`main` last-wins at `1377–1385` — A5 shows whether this order is stable; if not, sort at
registration); `build_cas_key`'s flag list verbatim plus **`MARCH_NO_INLINE_RC`** (gates
`maybe_inline_rc`, `bin/main.ml:1054–1059`; not in `codegen_cas_tags` today, §15.4);
`Llvm_toplevel.pin_main`; `Llvm_builtins.called_syms`.

Per-unit dedup tables (`emitted_eq_fns`, `emitted_dispatch_fns`, `emitted_wraps`,
`unknown_decls`, `str_ctr`, `ctor_desc_ids`, `rec_shape_globals`, `call_tag_globals`) are
per-unit after the split and not in the digest. Constructor descriptors are declaration-ordered
and already per-unit (`llvm_ctor_desc.ml:80–96`, runtime interns by content).

**A1 runs before hashing.** `unit_keys` refuses (hard error under `--incremental`) if the
verifier reports anything on the post-opt TIR: a key over ill-formed TIR is a key over a bug.

**Tests** (`test/test_cas.ml`): leaf body edit → only leaf's `fn_key`; leaf param-type edit →
leaf + direct callers; native-vec eligibility change → `abi_hash` + callers; record layout edit →
transitive users only; `fast_math` → every `unit_key`; mutual-recursion group edits move together.

**Effort.** ~3–4 days.

## 13. B3 — Split LLVM emission into units

### B3a — refactor, `--codegen-units=1` byte-identical (no dependency on B1)
`Llvm_emit.emit_module` → `Llvm_toplevel.emit_module ~emit_expr` (`llvm_toplevel.ml:976`) builds
one ctx (`buf`, `preamble`, `extra_fns`), runs a pre-pass (`top_fns`, `top_fn_*`,
`native_vec_params`, `unqualified_fns`, mutual-TCO groups via `Llvm_tco.find_mutual_tco_groups`,
`llvm_tco.ml:409`), emits every function, finalises program-wide pieces. Split into:

```
Llvm_toplevel.emit_shared : prepass -> tir_module -> string
Llvm_toplevel.emit_unit   : prepass -> unit_id -> fn_def list -> string
```
- **Pre-pass** runs once over the whole module (no emission): the tables above plus
  `collision_set`, the atom-literal scan, the `called_syms` union, provenance lookups.
- **Shared unit**: type/struct declarations, record-shape globals, the atom show-table
  (external linkage — see below), HCR epoch + dispatch publish, cap declarations and markers,
  `@.rpc_impl_*` (indexed by `tm_fns` position, `llvm_toplevel.ml:1355–1373`), `@.hr_hash*`,
  module init, `main`, the `.march_build` manifest (A2), and under `MARCH_RC_TRACE` the site
  table (A3).
- **Per-unit ctx**: fresh `buf`, `preamble`, `extra_fns`, counters, dedup tables, own ctor
  descriptor; `declare`s for every external reference generated from the pre-pass.
- **Guard**: `scripts/ir-oracle.sh` zero-diff at `N=1` (prove red first); full suite; A6 counts
  unchanged.

### B3b — `N>1` (depends on B1 for host recovery, A2 for module partition)
What must stay together or be made link-safe (verified):
- **SCCs and mutual-TCO groups** are atomic; group membership comes from the shared pre-pass.
- **On-demand helpers with external linkage** — duplicate-symbol link errors otherwise:
  `$clo_wrap` trampolines (`llvm_calls.ml:465–483`, `emitted_wraps`), structural equality
  `__eq$…` (`llvm_eq.ml:126, 186, 345, 546`), interface dispatch `__march_ifdispatch$…`
  (`llvm_dispatch.ml:60`). Under `N>1` every helper in `extra_fns` is **`linkonce_odr`**;
  under `N=1` unchanged.
- **`internal` helpers** (`Llvm_rc_inline` twins, `@.str*`/`@.strcell*`): duplicated per unit.
- **Aliases** `__migrate_<Actor>`/`__migrate_msg_<Actor>` (`llvm_toplevel.ml:1222–1280`) in the
  aliasee's unit.
- **Atom show-table**: `atom_names` fills during emission (`llvm_emit.ml:371`,
  `llvm_case.ml:945`) and `@march_atom_to_string`/`@march_atom_name_or_null` are **`internal`**
  (`llvm_toplevel.ml:573, 596`); split naively, `show(:x)` silently renders `:<atom>` across
  units. The shared unit scans all `fn_def`s for atom literals and defines the table externally;
  units `declare` it. The `buffer_contains … "define internal ptr @march_atom_to_string"` check
  (`:541`) goes.
- **Partition**: by **source module** of the base function from the provenance table (mono
  specialisations with their generic's module; `$lam`/apply/fused helpers with their host); a
  module over ~400 fns splits into `BLAKE3(base_name) mod k` buckets; unit ids are stable strings.
- **`.ll` publication**: `write_ll_tmp`/`publish_ll` run on **every** compile (`bin/main.ml:3221–3238`)
  and ~20 `test/dune` rules grep `native/*.ll`. Under `N>1`, `<basename>.ll` is the concatenation
  (shared first, then units in id order) and `<basename>.<unit>.ll` are published alongside.
- **Guard**: per-unit `llvm-as` over the `test/native` corpus (there is no general IR-validity
  gate today; `test/dune:5023` has one local `check_ir`); link every `bench/*.march` and
  `test/native` fixture at `N=8` (the duplicate/undefined-symbol catcher); program output `N=1`
  vs `N=8` at `--opt 0`; full suite.

**Effort.** B3a 1–2 weeks (`llvm_toplevel.ml` is 1 809 lines; the boundary cuts the finaliser);
B3b ~1 week.

## 14. B4 — Object store, parallel compile, link

- **Store**: `<project>/.march/cas/objects-v1/<aa>/<rest>.o` + `.meta` (unit id, member
  symbols, provenance summary, cflags), write-through to `~/.march/cas/objects-v1/`; temp +
  `Unix.rename` as `Cas.copy_file_exec` already does (`cas.ml:283–297`). Key = B2 `unit_key` with
  the toolchain facet as `Runtime_archive.ensure` folds it.
- **Flow**: `unit_keys` → lookup per unit → emit + `clang -c` the misses in parallel
  (`Unix.create_process`, `-j ncpu`, `MARCH_JOBS`) → link runtime objects, shared, units,
  user FFI, `ffi_link` (order as today; `-Wl,--gc-sections` + `-ffunction-sections` apply to
  unit cflags) → store under both whole-binary keys as today.
- **Eligibility**: `Runtime_archive`'s predicate and `--incremental`/`MARCH_INCREMENTAL=1`;
  `MARCH_NO_RUNTIME_CACHE=1` also disables the object store. `MARCH_ECHO_CC` prints per-unit
  commands. `MARCH_DEBUG_UNITS=1` prints id, key, hit/miss, members.
- **Verify mode** `MARCH_INCREMENTAL_VERIFY=1`: on every hit, recompile and byte-compare the
  `.o` (clang is deterministic for identical input; keep `-grecord-command-line` off), **and**
  run A1 on the TIR the key was computed from. One CI job runs the native `test/dune` rules this
  way. The `.march_build` manifest (A2) lets a failing binary be checked against the entries it
  was linked from.
- **Edit-sequence differential test** (`test/test_incremental.ml`, Slow): ~50 generated programs
  plus `bench/`; seeded random sequences of 10 edits (rename a local, change a literal, add/remove
  a lambda, change a param type and fix callers, add a record field, add/remove a function, add
  an atom literal in one module and `show` it in another); after each edit compare incremental vs
  clean monolithic output and exit code. On failure, A4's reducer minimises the program and
  bisects the pass, and A3's trace dumps live objects if the divergence is a leak delta.
- **Forge**: `forge build` passes `--incremental` (it picks `--opt 0/2`,
  `forge/lib/cmd_build.ml:144`); `forge watch` is the first consumer; `forge clean --cas`
  (`cmd_clean.ml:16–21`) already removes the store; add `forge clean --objects` and
  `forge cache gc [--max-size 2G]` (LRU by atime, both stores; `march cache gc` for non-forge
  users), with a default bound applied after a build.

**Acceptance.** Leaf-edit scenario at `--opt 0` ≥ 3× faster than B0 baseline; comment-edit
scenario unchanged (post-TIR hit); verify-mode job green; differential test green.

**Effort.** ~1 week.

## 15. B5 — Optimised builds and default-on; B6; B7 quick wins

**B5.** Units as ThinLTO bitcode (`-flto=thin -c`), link with `-flto=thin
-Wl,--thinlto-cache-dir=<store>/thinlto` (lld; `-Wl,-cache_path_lto,<dir>` on ld64; the `zig cc`
driver bundles lld). Detect at link time; fall back to plain objects at `--opt 0/1` and monolithic
at `--opt 2/3`. **Gate**: `bench/tree_transform`, `bench/list_ops`, `bench/binary_trees`,
`bench/fib` compiled at `--opt 2`, 5× median, monolithic vs incremental+ThinLTO; no regression
over 3%, or `--opt 2/3` stays monolithic. Then `--incremental` default on for eligible native
builds, `--no-incremental` to opt out, `--codegen-units=1` kept for bisecting.

**B6 — front end (separate plan).** After B5 a warm edit still pays the front-end and
whole-program TIR buckets. Its design is §8b: the `Memo` primitive with recorded dependencies,
then `parse_desugar` → `typecheck_module` (per module, keyed on source + import **interface**
hashes, generalising the existing `check_module_with_env_full` / `typecheck_cache.ml` path) →
`lower_module` as query nodes, with mono-through-opt staying one whole-program node. Only if B0
shows that node dominating: a per-specialisation mono cache keyed on (generic `impl_hash`, type
args). A stale typecheck result is a soundness hole, so it gets its own plan and oracle
(`types-oracle.sh`, plus `Memo`'s strict mode).

**B7 — independent quick wins**, each its own todo → progress entry:
1. Replay stored diagnostics on a cache hit; removes the `contains_substring cache_input
   "no_alloc"` bailout (`bin/main.ml` ~2037) and the `--refine-report` class (`ci.yml` ~412/496).
2. Key the source-level cache on the resolver's actual load set, not every `.march` in the
   directory.
3. Write-through to the global store; fix `Runtime_archive`'s stale comment about
   `store_artifact` (`runtime_archive.ml:52–55`).
4. Add `MARCH_NO_INLINE_RC` to `codegen_cas_tags` — a live whole-binary-cache bug today.

---

## 16. Correctness strategy, risks, open questions

| Guard | Lands in | Catches |
|---|---|---|
| TIR verifier on every pass in tests | A1 | inter-pass invariant violations at the violating pass |
| Determinism oracle (two HOMEs, cold/warm, two cwds, provenance diff) | A5 | unstable symbols/hashes; passes that forget provenance |
| Idempotence test for `Opt`/`Perceus` | A6 | order-dependent passes |
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
| Duplicate-symbol link errors from on-demand helpers | high without `linkonce_odr` | §13 rule + `N=8` link guard |
| Verifier false positives block `--incremental` | medium early | verifier ships in tests first (A1), so its false positives are fixed before B2 depends on it |
| Provenance table drifts from TIR (a pass renames without recording) | medium | A5 diffs the table; B3b partition fails loudly on a missing host |
| `-O2` perf loss | medium | ThinLTO; 3% gate; else dev-builds only |
| `tm_fns` order unstable | low | sort at registration; A5 detects |
| B0 shows the front end dominates | possible | gate reorders B3b–B5; Part A and B1–B3a still pay off |

**Open questions.**
1. Concrete structural-naming schemes for `Fusion`/`Hof_spec`/`Mono` helpers and a collision
   argument for each (two fusions of the same callees in one host → ordinal; two `hspec`s of `g`
   on the same argument symbol → should be one function; dedupe).
2. Is `tm_fns` order already deterministic given deterministic input? A5 answers.
3. ThinLTO availability on every CI image and macOS developer setup.
4. `.ll` publication under `N>1`: concatenate (assumed) or update the ~20 `test/dune` rules.
5. A1's ownership check: can it reuse `Perceus_liveness` directly, or does checking need its own
   dataflow to avoid sharing the bug it is checking for? Lean to independent.
6. A2 `DILocation` granularity: function-level first; is per-instruction worth the span plumbing
   through mono/defun/fusion, or does `--explain-fn` cover the need?

## 17. Review record

### First draft (CAS-only), reviewed 2026-10-04 against the source
Four blockers, eleven should-fixes; all folded in.
- **Blockers:** the draft stabilised one counter (`lam_uid`) when six generators reach symbols
  (now §11's table); its naming scheme would have broken self-tail-call recognition
  (`apply_fn_base` must keep the lambda's self-binding name); three helper families have
  external linkage (`$clo_wrap`, `__eq$`, `__march_ifdispatch$`) and would have produced
  duplicate-symbol link errors (`linkonce_odr` rule); the atom show-table is `internal` and would
  have silently degraded across units (shared, external definition).
- **Should-fixes:** `globals_digest` missed `type_defs`, `collision_set`, `unqualified_fns`
  order, `tm_externs`/`tm_tests`/`tm_exports`/`tm_io_fns`, `pin_main`, `called_syms`,
  `MARCH_NO_INLINE_RC` (the last also a standalone cache bug, B7.4); `ctor_desc_ids` is
  declaration-ordered and already per-unit (draft's shared-unit treatment removed);
  `sig_hash` is narrower than assumed (→ `abi_hash`); `Cas.store_artifact` already does
  temp+rename (draft's "make atomic" item replaced by fixing the stale comment); B0 now uses the
  finer `Contract_pipeline` stamps; `.ll` publication happens on every compile and tests grep it;
  REPL counter persistence is in `lib/jit/repl_jit.ml`; forge integration is more than a
  pass-through; Windows out of scope; B3a doesn't depend on B1.
- **Confirmed:** `hash_module` on post-opt TIR; default linkage for user fns; `lam_uid` a
  cross-call global; `apply_fn_base` splits first / `drop.ml` last; `Runtime_archive`'s
  predicate and concurrency; `Llvm_rc_inline` twins `internal alwaysinline`; runtime atom namer
  accepts multiple registrations.

### Second draft (Part A added), 2026-10-04
Added after a survey of existing instrumentation (`--dump-phases`, `MARCH_DUMP_TXT`,
`MARCH_REPR_AUDIT`, `MARCH_ALIAS_AUDIT`, `MARCH_SANITIZE`, alloc counters, differential oracle,
snapshots, three oracles, parser fuzz, stdlib PBT) and of bug classes in `specs/progress/`. Facts
checked for Part A: TIR `fn_def` carries **no span** and the LLVM emitters emit **no**
`DILocation` (hence the side-table design, precedent `js_emit.ml`'s `fn_lines`); no TIR
well-formedness checker exists; `test_oracle.ml` has no reducer; pass switches that exist are
`MARCH_NO_{HOF_SPEC,INLINE_RC,TRMC,UNBOX,RUNTIME_CACHE}`. Part A has **not** yet had an
independent review; the same treatment as the first draft is owed before A1's ownership check
is relied on by B2.

### Third draft (queryability), 2026-10-04
Added A7 and §8b after checking: a front-end query facade already exists (`lsp/lib/query.ml`,
`query_cli.ml`, nine query kinds, JSON; `lsp/test/test_query_cli.ml`); `Typecheck` is 9 346
lines with module-level mutable state (`deferred_pending`, `wildcard_sink`,
`last_with_env_final`, `Typecheck_env.ctor_index_cache`); `lower_state.ml` holds ~20 module-level
tables; `Typecheck_reorder` already computes per-declaration and per-module dependency order;
`check_module_with_env_full` and `lsp/lib/typecheck_cache.ml` already implement a two-level
memoised typecheck keyed on `Cas.compiler_identity`. Verdict recorded in §8b: coarse query
layer yes, fine-grained query architecture no.

### Still unverified
Everything about *time* (no build was possible in the authoring environment; B0 exists for
this); ThinLTO on CI images; `tm_fns` order stability; whether A1's ownership check can be made
independent of `Perceus_liveness` cheaply.
