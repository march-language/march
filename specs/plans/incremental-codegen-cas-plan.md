# Incremental Compilation via the CAS — Plan

**Date:** 2026-10-04
**Status:** Proposed (not yet measured; see Phase 0). Reviewed once against the source; see §16.

---

## 1. Problem

The CAS speeds up a compile only when nothing changed. Three caches exist today:

| Layer | Where | Key | A hit skips |
|---|---|---|---|
| Source-level | `bin/main.ml` (~2029–2090, `source_cas_state`) | MD5 of entry file + stdlib hash + every `.march` under the entry's directory and each `MARCH_LIB_PATH` dir | everything (copies the binary, `exit 0`) |
| Post-TIR | `bin/main.ml` (~3310–3395) | concatenation of every SCC's Merkle `impl_hash` from `Pipeline.hash_module`, through `build_cas_key` | `llvm-emit` + clang only |
| Runtime objects | `lib/cas/runtime_archive.ml` | runtime `*.{c,h}` digest + compiler identity + `cc --version` + exact cflags | recompiling the ~20-file C runtime |

Any real edit (one character in one function body) misses both whole-program keys and pays the
full pipeline: parse → desugar → resolve → stdlib-load → typecheck → lower → mono/fusion/defun/
Perceus/drop/escape/opt → LLVM emission of the **whole** program → one clang invocation over one
`.ll`. "Whole program" includes every monomorphised stdlib specialisation; the `--compile-so`
manifest for `examples/topology_app` lists ~13 000 functions.

`Pipeline.compile_scc` (`lib/cas/pipeline.ml`) is a tested per-SCC cache that nothing in the
driver calls. Its doc comment names the blocker: codegen emits one LLVM module and links one
binary, so there is no per-SCC artifact to store or serve. This plan does **not** revive
`compile_scc`: its key is the transitive Merkle hash, which §6 explains is the wrong key for
object files.

### Terms used below

- **Symbol**: the LLVM function name a TIR `fn_def` is emitted under (`fn_name` after mono/defun).
- **`impl_hash`**: `Hash.hash_fn_def`'s hash of signature + body, alpha-normalised locals
  (`Serialize`), callees referenced **by name**.
- **Merkle `impl_hash`**: `Pipeline.hash_module`'s fold of a definition's `impl_hash` with its
  callees' Merkle hashes and its transitive type-layout closure. Keys the post-TIR cache.
  Computed on `pipe.Contract_pipeline.final`, i.e. **post-optimisation** TIR
  (`bin/main.ml:3313`, after `Opt.run` / `Native_map_inline` / `Hof_spec` in
  `contract_pipeline.ml:222–246`).
- **Unit**: a set of `fn_def`s emitted into one `.ll` / compiled to one `.o` (Phase 3).

## 2. Goal and non-goals

**Goal.** After editing one function, the native `--compile` path re-emits and re-compiles
approximately the unit containing that function, then links. A cached object is never used when a
clean build would have produced different machine code for it.

**Non-goals for this plan.**
- WASM, JS, cross-compiled (`--target`) and `--compile-so` / `--hot-reload` builds keep today's
  monolithic path, for the same reasons `Runtime_archive`'s eligibility check excludes them
  (`bin/main.ml` ~4039–4046): per-invocation `-D`s and sysroots change how objects compile.
  Consequently the `.hcr_manifest` / `.schemas.json` sidecars (`cas.ml` ~325) are out of scope.
- Windows. Nothing in `bin/` or `lib/cas/` supports it today; this plan doesn't add it.
- Incremental *type checking* of user modules. Phase 6 sketches it; it needs its own plan.
- The REPL/JIT fragment emitters (`Llvm_repl`). They already emit per-fragment modules and are
  not on the `--compile` path, though Phase 1's naming change touches them (§5.2).

## 3. Phase overview

| Phase | Deliverable | Depends on | Can ship alone? |
|---|---|---|---|
| 0 | `scripts/compile-time-bench.sh` + measured baseline | — | yes |
| 1 | Deterministic symbols and hashes; determinism oracle in CI | — | yes (fixes an open P2 todo and spurious HCR diffs) |
| 2 | `Pipeline.unit_keys`: non-cascading per-function object keys | 1 | yes (library + tests only) |
| 3a | `Llvm_emit` refactored into shared + per-unit emission, `--codegen-units=1` byte-identical | — | yes (default `=1`) |
| 3b | `--codegen-units=N>1` working (linkage, partition) | 1, 3a | yes (opt-in flag) |
| 4 | Object store, parallel clang, link; `--incremental` opt-in | 2, 3b | yes (opt-in) |
| 5 | ThinLTO for `--opt 2/3`; incremental becomes default | 4 | gated on benchmarks |
| 6 | Front-end incrementality (separate plan) | 0 numbers | — |
| 7 | Independent quick wins | — | each alone |

Phases 0, 1, 3a and 7 can all start immediately and in parallel. 3a is the longest pole and
doesn't depend on Phase 1; only 3b does. Phases 1–2 run **regardless** of the Phase 0 gate,
because Phase 1 is also the fix for the open HCR P2 todo.

---

## 4. Phase 0 — Measure before building

Nothing in this plan has been timed yet; the ordering below rests on reading the code.
`--timings` already exists: `stamp` calls in `bin/main.ml` (`parse`, `desugar`,
`resolve-imports`, `stdlib-load`, `typecheck`, `lower`, `llvm-emit`, `clang`) **and** the finer
ones inside `Contract_pipeline.run` (`mono`, `fusion`, `defun`, `perceus`, `drop`, `escape`,
`opt`; `contract_pipeline.ml:88–249`). The work is a harness, not instrumentation.

### Deliverables
- `scripts/compile-time-bench.sh [--opt N] [--corpus small|bench|topology|all]`:
  - runs under a **private `HOME`** (same rule as the oracles: `~/.cache/march` carries
    worktree-specific spans), so cold/warm is under the script's control;
  - corpus: one tiny program (`test/snapshots/src/` pick), `bench/tree_transform.march`,
    `examples/topology_app` (via `MARCH_LIB_PATH`);
  - scenarios per program, each run 3× taking the median:
    1. cold (empty `HOME`, empty `.march/cas`);
    2. warm, no change (expects a source-level hit);
    3. warm, comment-only edit (expects a post-TIR hit: same TIR, different source digest);
    4. warm, leaf function body edit;
    5. warm, signature edit on a function with many callers;
    6. warm, record field added to a widely used type.
  - prints a table: scenario × stage, in seconds, grouped into three buckets: **front end**
    (`parse`…`typecheck`), **whole-program TIR** (`lower`…`opt`), **back end**
    (`llvm-emit` + `clang`). Phase 6 attacks the first two buckets differently, so they are
    reported separately.
- `specs/benchmarks.md` gains a "compile time" row pointing at the script.
- Results committed once as `specs/plans/incremental-codegen-cas-baseline.md` (a dated
  snapshot, not a hand-maintained running count).

### Gate
If, for scenarios 4–6 at `--opt 2`, the **back end** bucket is less than half of wall time,
re-order: do Phase 6 before Phases 3b–5. Phases 1, 2 and 3a proceed either way.

### Effort
~1 day.

---

## 5. Phase 1 — Make symbols and hashes deterministic

A finer-grained cache is only as sound as its keys. Two known sources of drift exist, and the
second is wider than one counter.

### 5.1 Cold vs. warm stdlib cache changes specialisations
`specs/todos/2026-10-01-cold-stdlib-cache-changes-specializations.md`: the same source compiled
with a cold then a warm `~/.cache/march` emits different TIR (one more unspecialised function and
one more `$lam` on the cold path). The todo already localises it to the `stdlib_tcenv_cli_*.bin`
round-trip and gives a repro; its acceptance text (byte-identical `--emit-llvm` cold vs. warm) is
the Phase 1 acceptance for this item. Reuse it rather than restating.

### 5.2 Counter-derived symbols — every counter that reaches a name
The driver's own HCR hashing comment (`bin/main.ml:947–951`) lists the problem: symbols like
`$lam39788$apply$4781` carry **two** global counters, and `$jp17442`, `$t12`, `_i<n>`, `'_<n>`
appear inside bodies. Every generator whose output can reach a symbol or a `TCon` name must become
structural. Inventory (verified):

| Name shape | Generator | Counter | Scope |
|---|---|---|---|
| `$lam<n>` | `Lower_expr` (`lower_expr.ml:900`, `fresh_name "lam"`) | `Lower_state._lower_counter` (`lower_state.ml:37–41`), reset once per `lower_module` | the lambda's own `fn_name`; prefix of the apply fn |
| `<lam>$apply$<n>`, `$Clo_<lam>$<n>` | `Defun` via `Tir_names.apply_fn_name`/`clo_struct_name` (`defun.ml:518–519, 585, 590`) | `Defun.lambda_counter` (`defun.ml:418–419`), never reset across calls | symbol + TCon |
| `$jp<n>` | `Join_points` (`join_points.ml:140`) | module-level, never reset | local labels today; check it never reaches a symbol |
| `$fused_<p>_<n>` | `Fusion` (`fusion.ml:35–38`, `gensym_ctr`) | module-level, never reset | symbol |
| `<g>$hspec$<n>` | `Hof_spec` (`hof_spec.ml:184`) | per-run `st.counter` | symbol |
| `$V__<n>` | `Mono.mangle_ty` (`mono.ml:167, 1129`, e.g. `Map.key_hash$V__4370`) | typecheck fresh-var ids | symbol |
| `$t<n>`, `_i<n>` | lower / inliner temps | lowering counter | locals only; `Serialize` alpha-normalises these, so hash-stable; not symbols |

`Trmc` (`trmc.ml:391–395`) already resets its counter per module; that is still order-dependent,
so the fix everywhere is **structural naming**, not resetting.

Why this can't be fixed inside the hash alone: `Serialize` could normalise the numbers away so
hashes stay stable, but a cached `.o` **binds to callees by symbol**. If an object compiled when a
helper was `$lam39788$apply$4781` is reused in a build where it is `$lam39790$apply$4782`, the
link fails with an undefined symbol (loud) or, where another function took the old name, binds to
the **wrong function** (silent). The symbol itself must be stable.

**Design: host-scoped ordinals, minted at lowering.**
- `Lower_expr` names a lambda `<host>$lam<i>` where `host` is the enclosing top-level
  `fn_name` and `i` is the lambda's index in a deterministic traversal of `host`'s body. Nested
  lambdas: `<host>$lam<i>$lam<j>`. The name is now unique by construction.
- `Defun` keeps the **lambda's own name** as the apply prefix (`<lam>$apply$0`,
  `$Clo_<lam>$0`), so `lam_uid` degenerates to a constant and can be removed. Keeping the
  lambda's name as the prefix matters: `Tir_names.apply_fn_base` (`tir_names.ml:151–170`,
  splits at the FIRST `$apply$`) must keep returning the lambda's source-level self-binding
  name, because `llvm_emit_call.ml:830–833` compares it against the callee variable to keep a
  self-tail-call free of Float temp-box releases (a measured 20k-depth stack overflow otherwise).
  A scheme that put the *host* in the prefix would silently break that.
- `Fusion` names fused helpers after the two fused callees plus their call-site ordinal within
  the host; `Hof_spec` names specialisations after `g` plus the specialised argument's symbol;
  `Mono` derives `$V_` suffixes from the type structure (or canonical position in the
  specialisation's type-argument list), not from fresh-var ids.
- The REPL/JIT persists and restores `Defun.lambda_counter` in the `.names` file
  (`lib/jit/repl_jit.ml:1657–1767`, `lambda_counter=N` sentinel) and `test/test_snapshots.ml`
  resets it (`49–55, 187, 197`). With structural names a fragment needs only a per-fragment host
  name (`$repl<n>`) as the `<host>` prefix; remove the counter persistence together with the
  `Lower_state.reset_counter` interplay (`lower_state.ml:30–36`).

**Consumers to update** (grep for `$apply$`, `$Clo_`, `lam_uid`, `apply_fn_base`,
`$lam`): `drop.ml:709–722` (reconstructs `apply` name from `$Clo_` name: int after LAST `$` —
still valid with ordinal `0`), `borrow.ml:679, 1064`, `perceus.ml:702, 772`,
`perceus_core.ml:886`, `known_call.ml:41, 176`, `alloc_contract.ml:412, 461`,
`hof_spec.ml:287`, `llvm_emit_call.ml:194, 244, 364, 545, 830`, `llvm_toplevel.ml:200, 222`,
`native_map_inline.ml:108`, `llvm_emit_alloc.ml:46`, `js_emit.ml:6`, `llvm_emit.ml:2364–2374`
(comment saying the host is not recoverable from the name; after this change it is),
`test/test_codegen.ml:130–144, 5700–5785, 15066–15243`, `test/snapshots/`.

Also update `hr_slot_hashes`'s `counter_re` canonicaliser (`bin/main.ml:982`): with
structural names it becomes a no-op and can be retired, which is itself a check that nothing
counter-shaped is left.

### 5.3 Determinism oracle
New `scripts/determinism-oracle.sh` and a CI job:
- compile `test/snapshots/src/*.march`, `bench/*.march`, `examples/topology_app` twice with
  `--emit-llvm`, under **two different private `HOME`s**, cold then warm, from two different
  cwds;
- compare the set of `(symbol, impl_hash, sig_hash)` triples via a new `--dump-impl-hashes`
  driver flag (one line per fn), and compare the `.ll` text. Expected diffs: none in the IR
  except the embedded source path (normalise it). The CAS *store location* differs by cwd
  (`Cas.create ~project_root:(Sys.getcwd ())`); that's not an IR diff and isn't compared;
- **prove it red first**: reintroduce one global counter (or add a lambda to a stdlib module
  in one of the two runs) and check the diff is reported. Record that run in the PR
  description. CLAUDE.md's oracle rule exists because two of three existing oracles shipped
  broken.

### Acceptance
- The P2 todo's repro produces identical manifests (13376 = 13376) and identical `--emit-llvm`.
- Determinism oracle green on CI, with a recorded red run.
- `scripts/ir-oracle.sh check` against a pre-change baseline shows **only** symbol renames;
  any other diff is a bug.
- Full test suite; `run_snapshots` regenerated and diffed (renames only).
- `forge deploy hot` manifest diff on `examples/topology_app` between a cold and a warm build
  lists zero spurious functions.

### Effort
~1 week. Six generators, many consumers, plus the REPL persistence removal.

---

## 6. Phase 2 — A per-function object key that doesn't cascade

### Why `hash_module`'s key can't be reused
`hash_module` folds each callee's **full** Merkle hash into its caller's. That's exactly right
for the whole-binary key (any transitive change must miss) and must stay. For object files it
makes almost every edit a near-total miss: a leaf body change propagates up to `main`. The HCR
slot-identity code already hit this and uses the non-transitive `Hash.hash_fn_def` instead
(comment at `bin/main.ml` ~3320).

### What a function's machine code actually depends on
1. **Its own post-optimisation TIR body**, with real symbol names. `hash_module` runs on
   post-opt TIR, so anything the *TIR-level* optimiser inlined is already in this body.
   (LLVM-level cross-function inlining is separate; see Phase 5.)
2. For each **callee**, its symbol and its **ABI**, which is more than `sig_hash` covers.
   `Serialize.write_fn_sig` (`serialize.ml:371–375`) is name + param types + return type only.
   Call sites also consult `native_vec_params` (whether a param gets a native `<N x T>` TCO
   slot: derived from the callee's **body** by `native_vec_param_idxs`, and **disabled for
   mutual-TCO members**, `llvm_toplevel.ml:1183–1189`), `zero_arg_fns` (param count, covered),
   `is_apply_fn` (name-derived, covered), and `top_fn_param_tys` coercions (types, covered).
   Define
   `abi_hash fd = BLAKE3(sig_hash ++ native_vec_param_idxs fd ++ in_mutual_tco_group fd)`
   and key callers on `(symbol, abi_hash)`.
3. **Type layouts** it references, transitively: `type_closure_hashes` already computes this.
4. **Program-wide emitter inputs** — see `globals_digest` below.
5. **Toolchain**: `Cas.compiler_identity`, `Runtime_archive.cc_identity`, the exact cflags
   (same list `Runtime_archive` already keys on).

### Design
```
Pipeline.unit_keys :
  tir_module -> globals_digest:string -> partition:(fn_def -> unit_id)
  -> (unit_id * string (* unit key *) * fn_def list) list
```
- `fn_key fd = BLAKE3(impl_hash fd ++ sorted [callee symbol ++ callee abi_hash] ++
  sorted type-closure hashes)`.
- `unit_key = BLAKE3(sorted member fn_keys ++ globals_digest ++ "unit-format-v1")`.
  (No `Serialize` version bump is needed; the literal tag versions the key. Note
  `Serialize`'s "format version 2" exists only in its doc comment, not in the bytes.)
- **`globals_digest`**, computed once per build in the driver, **starts coarse**: every unit's
  key includes all of it, so a change to any program-wide input misses every unit. That is safe
  and still the main win, since function bodies change far more often than these. It is the
  BLAKE3 of:
  - every `emit_module` argument (`llvm_toplevel.ml:976–985`): `fast_math`, `pmap_threshold`,
    `target`, `hot_reload`, `impl_hashes`, `remote_impl_hashes`, `remote_sig_hashes`,
    `emit_main`, `cap_attrib`, `cap_decls`, `k_table`;
  - `Serialize.serialize_type_def` of **all** `tm_types`, in order (feeds `type_defs`,
    `collision_set` — which changes constructor **tags** for same-short-name types and so
    affects every match/alloc — `poly_ctors`, `type_params`, `field_map`, `ctor_info`, and the
    constructor descriptor, see below). Yes: adding any type misses every unit under the coarse
    digest. Accepted for v1;
  - `tm_externs` (→ `extern_map`, `blocking_externs`, `raises_externs`), `tm_tests`,
    `tm_exports`, `tm_io_fns`, `tm_name`;
  - the **order of `tm_fns` names**: `unqualified_fns` is first-registration-wins
    (`llvm_toplevel.ml:1136–1160`) and `main` is last-wins (`1377–1385`). This order dependence
    is itself a determinism hazard; Phase 1's oracle will show whether it is stable. If not,
    sort at registration;
  - `build_cas_key`'s flag list **verbatim** (opt level, `pmt`, `dbg`, `sanitize=`, `cpu:`,
    `capstrip`/`capsandbox`/`capstrict`, `spk:`, `pbase:`, `pexpand:`, …), plus
    **`MARCH_NO_INLINE_RC`**, which gates the post-emission `maybe_inline_rc` text rewrite
    (`bin/main.ml:1054–1059`, `llvm_rc_inline.ml:51–54`) and is **not** in `codegen_cas_tags`
    today — a latent whole-binary-cache bug; file a todo and fix it independently (§11.4);
  - module-level emitter state outside `ctx`: `Llvm_toplevel.pin_main` (already a CAS tag),
    `Llvm_builtins.called_syms` (program-wide union driving cap markers,
    `llvm_toplevel.ml:1695–1720`; lives in the shared unit, see §7).
- The per-unit dedup tables (`emitted_eq_fns`, `emitted_dispatch_fns`, `emitted_wraps`,
  `unknown_decls`, `str_ctr`, `ctor_desc_ids`, `rec_shape_globals`, `call_tag_globals`) are
  genuinely per-unit after the split and fall out of the unit's own bodies; they are not in the
  digest.
- **Constructor descriptors are already per-unit.** `Llvm_ctor_desc.assign_ids`
  (`llvm_ctor_desc.ml:80–96`) assigns ids over `ctx.type_defs` in *declaration* order, all at
  once, and emits a `private` descriptor string that the runtime interns by content
  (`march_ctor_table_ensure`). Each unit emitting its own descriptor is correct and already
  supported ("once per compilation unit", its doc comment). Its content depends on all
  `type_defs` + tags, which the coarse digest covers.

### Tests (`test/test_cas.ml`, extended)
- Edit a leaf's body → only the leaf's `fn_key` changes.
- Edit a leaf's param type → leaf's and each direct caller's `fn_key` change; callers-of-callers
  unchanged.
- Make a leaf eligible for a native vector TCO slot → its `abi_hash` and its callers' keys change.
- Edit a record layout → every transitive user changes; non-users unchanged.
- Change `fast_math` → every `unit_key` changes (coarse globals).
- Mutual-recursion group: editing one member changes the whole group's keys.

### Effort
~3–4 days.

---

## 7. Phase 3 — Split LLVM emission into units

### Current structure
`Llvm_emit.emit_module` → `Llvm_toplevel.emit_module ~emit_expr` (`llvm_toplevel.ml:976`)
builds one `Llvm_ctx.ctx` with one `buf`, one `preamble` and one `extra_fns`, runs a pre-pass
over all functions (fills `top_fns`, `top_fn_*`, `native_vec_params`, `unqualified_fns`,
mutual-TCO groups via `Llvm_tco.find_mutual_tco_groups ctx m.tm_fns`, `llvm_tco.ml:409`), emits
every function into `buf`, then finalises program-wide pieces and concatenates. User functions
are emitted with default (external) linkage (`hidden` only under `compile_so`,
`llvm_toplevel.ml:258–268`), so cross-unit calls need **no linkage change**.

### What must live together or be made link-safe (verified)
- **SCCs** and **mutual-TCO groups**: atomic; the group's tag slot and loop label are emitted
  together, and group membership is an ABI input (§6). The shared pre-pass computes the groups
  once and publishes membership to every unit; units never recompute them.
- **On-demand helpers with external linkage** — these would be *duplicate-symbol link errors*
  if two units both needed one:
  - `$clo_wrap` trampolines: `define ptr @%s(…) alwaysinline` (`llvm_calls.ml:465–483`),
    deduped per module via `emitted_wraps` into `extra_fns`;
  - structural equality `define i64 @__eq$…` (`llvm_eq.ml:126, 186, 345, 546`, `emitted_eq_fns`);
  - interface dispatch `define … @__march_ifdispatch$…` (`llvm_dispatch.ml:60`,
    `emitted_dispatch_fns`).
  Under `N>1` every helper in `extra_fns` is emitted **`linkonce_odr`** (identical bodies by
  construction, so the linker keeps one). Under `N=1` linkage stays as today for byte-identity.
- **`internal` helpers** (`Llvm_rc_inline`'s `define internal … alwaysinline` twins, string
  literal cells `@.str<n>`/`@.strcell<n>` which are `private`): duplicated per unit; fine.
- **Aliases** `__migrate_<Actor>` / `__migrate_msg_<Actor>` (`llvm_toplevel.ml:1222–1280`): an
  LLVM alias cannot target a declaration, so they are emitted in the aliasee's unit.
- **Atom show-table.** `atom_names` is filled during emission (`llvm_emit.ml:371`,
  `llvm_case.ml:945`) and `@march_atom_to_string` / `@march_atom_name_or_null` are emitted
  **`internal`** at finalisation (`llvm_toplevel.ml:573, 596`). Under units, `Show$Atom.show`
  would bind to its own unit's partial table and render `:<atom>` for any literal from another
  unit. The runtime namer list (`runtime/march_runtime.c` ~13426–13440) serves only the logger.
  Design: the **shared unit** scans all `fn_def`s for atom literals (TIR `LitAtom` + case tags)
  up front and defines `@march_atom_to_string` with **external** linkage; units `declare` it.
  The `buffer_contains ctx.extra_fns "define internal ptr @march_atom_to_string"` check
  (`llvm_toplevel.ml:541`) goes away with it.
- **`@.rpc_impl_<i>`** (indexed by position in `tm_fns`, `llvm_toplevel.ml:1355–1373`) and
  `@.hr_hash<slot>`: program-wide, shared unit.

### Design
Two emission entry points sharing `emit_expr`:
```
Llvm_toplevel.emit_shared : prepass -> tir_module -> string
Llvm_toplevel.emit_unit   : prepass -> unit_id -> fn_def list -> string
```
- **Pre-pass** (`top_fns`, `top_fn_ret_ty`, `top_fn_nparams`, `top_fn_param_tys`,
  `native_vec_params`, `zero_arg_fns`, `unqualified_fns`, `field_map`, `ctor_info`,
  `collision_set`, mutual-TCO groups, atom literal scan, `called_syms` union) runs **once**
  over the whole module and is shared read-only by every unit's ctx. No emission happens in it.
- **Shared unit**: type/struct declarations, record-shape globals, the atom show-table and its
  register/unregister, the HCR epoch cell + dispatch publish, cap declarations and markers
  (from the `called_syms` union), `@.rpc_impl_*`, module init, `main`.
- **Per-unit ctx**: fresh `buf`, `preamble`, `extra_fns`, `ctr`, `blk`, `str_ctr`, dedup
  tables, its own ctor descriptor. Every external symbol a unit references gets a `declare`
  generated from the pre-pass tables (callees, shared-unit globals, runtime functions).
- **`--codegen-units=N`** (default **1**): `N=1` emits a `.ll` byte-identical to today's. For
  `N>1`, partition:
  1. SCCs and mutual-TCO groups are atomic.
  2. By **source module** of the base function; mono specialisations `Foo.bar$Int$String` go
     with `Foo`; apply fns and `$lam` fns go with their host (recoverable from the name after
     Phase 1 — this is why 3b depends on Phase 1). Each stdlib module is its own unit, so a user
     edit never re-emits the stdlib.
  3. A module with more than ~400 functions is split into `BLAKE3(base_name) mod k` buckets,
     which are stable under unrelated edits by construction.
  4. Unit ids are strings (`"stdlib/list"`, `"user/Main#2"`), stable across builds.
- **`.ll` publication.** `write_ll_tmp`/`publish_ll` run on **every** compile, not only under
  `--emit-llvm` (`bin/main.ml:3221–3238`), and ~20 `test/dune` rules grep `native/*.ll`. Under
  `N>1`, `<basename>.ll` is the **concatenation** of the shared unit and all units in unit-id
  order (so existing greps keep working), and `<basename>.<unit>.ll` files are published
  alongside. Under `N=1` nothing changes.

### Regression guard
- **3a** (`N=1`): `scripts/ir-oracle.sh baseline` before, `check` after: **zero diffs**. Prove
  the oracle red first. Full suite.
- **3b** (`N=8`): full suite; a new per-unit `llvm-as` validity step over every unit `.ll` for
  the `test/native` corpus (today only one rule has a local `check_ir`, `test/dune:5023` — there
  is no general IR-validity gate, so this adds one); link every `bench/*.march` and every
  `test/native` fixture at `N=8` specifically to catch duplicate/undefined symbols from the
  helper families above; compare program output `N=1` vs `N=8` at `--opt 0`.

### Effort
3a ~1–2 weeks (`llvm_toplevel.ml` is 1 809 lines and the boundary cuts through its finaliser);
3b ~1 week.

---

## 8. Phase 4 — Object store, parallel compile, link

### Store
- `<project>/.march/cas/objects-v1/<aa>/<rest>.o` plus a `.meta` sidecar (unit id, member
  symbols, cflags) for `gc` and debugging. Also write-through to `~/.march/cas/objects-v1/`
  so worktrees share.
- Writes: temp file in the destination directory + `Unix.rename`, the pattern
  `Cas.copy_file_exec` already uses (`cas.ml:283–297`). (`Runtime_archive`'s comment claiming
  `store_artifact` "writes its pointer file directly" is stale; §11.3.)
- Key = Phase 2 `unit_key` with the toolchain facet folded in exactly as
  `Runtime_archive.ensure` does.

### Driver flow (native, eligible builds only)
```
tir ─► Pipeline.unit_keys ─► for each unit: lookup objects-v1/<key>.o
                                 hit  → reuse
                                 miss → emit_unit → clang -c   (parallel, -j ncpu)
     shared unit: emitted and cached under its own key like any unit
     link: cc <runtime .o from Runtime_archive> <shared.o> <unit .o …> <user FFI> <ffi_link> -o out
     store out under both whole-binary keys (source-level + post-TIR) as today
```
- Parallelism: `Unix.create_process` per miss, bounded by `-j` (default `ncpu`, `MARCH_JOBS`
  override). clang `-O2` on a 1/16th-size unit is where the cold-cache wall-clock win comes from.
- **Link order and dead-strip.** Unit objects go where the single `.ll` went: after runtime
  objects, before `ffi_link` (GNU ld resolves archives only against already-undefined symbols,
  the `--ffi-link` note at the link command). `-Wl,--gc-sections` + `-ffunction-sections`
  (`strip_flag`/`section_cflags`, `bin/main.ml` ~3871–3900) apply to unit cflags too, so
  capability-by-absence stripping still works per function.
- **Eligibility**: `Runtime_archive`'s predicate (Native, not `compile_so`, no evloop/signing
  defines, no `hot_reload_prefix`) **and** `--incremental` / `MARCH_INCREMENTAL=1`.
  `MARCH_NO_RUNTIME_CACHE=1` also disables the object store (one switch for A/B checks).
  Everything else: `N=1`, monolithic, unchanged.
- `MARCH_ECHO_CC` prints every per-unit `clang -c` command and the link command.
- `forge build` passes `--incremental` through (it already picks `--opt 0/2`,
  `forge/lib/cmd_build.ml:144`); `forge watch` is the first consumer. `forge clean --cas`
  (`cmd_clean.ml:16–21`) deletes `.march/cas` wholesale and so already covers `objects-v1/`;
  add `forge clean --objects` for just the object store.

### Operations
- `forge cache gc [--max-size 2G]` (and `march cache gc` for non-forge users): LRU by atime over
  `objects-v1/` in both stores. Default bound applied opportunistically after a build.
- `MARCH_INCREMENTAL_VERIFY=1`: on every hit, also recompile the unit and byte-compare the
  `.o`. clang output is deterministic for identical input and flags (check
  `-grecord-command-line` is off under `-g`). One CI job runs the native `test/dune` rules in
  this mode.
- `MARCH_DEBUG_UNITS=1` prints each unit's id, key, hit/miss and member count
  (`MARCH_DEBUG_CASFLAGS` style).

### Acceptance
- `compile-time-bench.sh` scenario 4 (leaf edit) at `--opt 0` ≥ 3× faster than the Phase 0
  baseline; scenario 3 (comment edit) unchanged (still a post-TIR hit).
- Verify-mode CI job green over the native test corpus.
- Edit-sequence differential test (§12) green.

### Effort
~1 week.

---

## 9. Phase 5 — Optimised builds and making it the default

Splitting into units removes LLVM's cross-unit inlining, which matters at `--opt 2/3`. The TIR
optimiser does the March-specific inlining, but LLVM still inlines small helpers across functions
in the monolithic module.

### Design
- Emit units as bitcode with `-flto=thin -c`, link with `-flto=thin
  -Wl,--thinlto-cache-dir=<store>/thinlto` (lld; `-Wl,-cache_path_lto,<dir>` on ld64). The CAS
  caches the per-unit front half; LLVM's ThinLTO cache keys the per-module backend on the import
  summary, so an unchanged unit whose imports didn't change is a backend hit too.
- Requires `lld` or Apple ld64 ≥ Xcode 10; the `zig cc` driver (`bin/main.ml` ~3912) bundles
  lld. Detect at link time; if unavailable, plain objects at `--opt 0/1` and monolithic at
  `--opt 2/3`, said once in `MARCH_DEBUG_UNITS` output.
- `Runtime_archive` objects stay native `.o`.

### Gate
Run the compiled benchmarks in `specs/benchmarks.md` (at least `bench/tree_transform`,
`bench/list_ops`, `bench/binary_trees`, `bench/fib`) monolithic vs. incremental+ThinLTO at
`--opt 2`, 5 runs each, median. **No benchmark regresses by more than 3%.** If the gate fails,
try import thresholds first; otherwise `--opt 2/3` stays monolithic and `--incremental` remains
a dev-build feature.

Once the gate passes: `--incremental` default on for eligible native builds; `--no-incremental`
to opt out; `--codegen-units=1` still available for bisecting.

### Effort
~3–5 days plus benchmark time.

---

## 10. Phase 6 — Front-end incrementality (separate plan)

After Phases 3–5, a warm edit still pays the **front end** and **whole-program TIR** buckets.
Already cached: the stdlib AST (`stdlib_ast_*.bin`) and tcenv (`stdlib_tcenv_cli_*.bin`). Not
cached: user modules, and every whole-program TIR pass.

Sketch, to be planned once Phase 0 numbers show how much is left:
- per-user-module cache of (parsed + desugared AST, typecheck env delta), keyed on the module's
  source plus the **interface** hashes (exported signatures and type defs) of its imports;
- mono/defun are demand-driven from `main`; a per-specialisation cache keyed on
  (generic fn `impl_hash`, type args) could serve `fn_def`s without re-running mono;
- Perceus/borrow/fusion are per-SCC in principle; caching them is Phase 2's keys one stage
  earlier.

A stale typecheck result is a soundness hole, not just a miscompile, so it gets its own plan and
oracle (`types-oracle.sh` is the starting point).

---

## 11. Phase 7 — Independent quick wins

Each lands alone, any time, with its own `specs/todos/` → `specs/progress/` entry.

1. **Replay diagnostics on a cache hit.** Store the compile's stderr diagnostics next to the
   artifact (`<key>.diag`) and print them on a hit. This removes the
   `contains_substring cache_input "no_alloc"` bailout (`bin/main.ml` ~2037), which disables the
   early cache for any program that *mentions* `no_alloc`, and covers every other warning-only
   output the same way (`ci.yml` ~412/496 describe the `--refine-report` instance). Key
   semantics unchanged: a hit is still "same inputs, same verdict".
2. **Key on the files actually loaded.** The source-level key hashes every `.march` file under
   the entry's directory and each lib dir, imported or not. Key on the resolver's actual load
   set instead (the `resolve-imports` stage knows it), keeping the sibling-module safety the
   comment there describes. Cost today: editing an unrelated example in the same directory
   misses.
3. **Write-through to the global store** and fix the stale `Runtime_archive` comment about
   `store_artifact` (`runtime_archive.ml:52–55`; `copy_file_exec` has done temp+rename since).
4. **Add `MARCH_NO_INLINE_RC` to `codegen_cas_tags`.** Today a binary built with the inline-RC
   rewrite can satisfy a build with it disabled (and vice versa). Independent of this plan.

---

## 12. Correctness strategy

A stale object is a **silent miscompile**, so correctness gets more machinery than speed:

| Guard | Phase | What it catches |
|---|---|---|
| Determinism oracle (two HOMEs, cold/warm, two cwds) | 1 | unstable symbols/hashes |
| `ir-oracle` zero-diff at `--codegen-units=1` | 3a | emitter refactor changing output |
| Per-unit `llvm-as` + `N=8` link of bench + `test/native` | 3b | missing `declare`s, duplicate helper symbols, alias placement |
| `MARCH_INCREMENTAL_VERIFY=1` CI job | 4 | a key that under-approximates a dependency |
| Edit-sequence differential test | 4 | everything above, end to end |
| Benchmark gate ≤ 3% | 5 | perf regression from unit splitting |

**Edit-sequence differential test** (`test/test_incremental.ml`, Slow): ~50 programs from the
differential oracle's generator plus `bench/`; apply a seeded random sequence of 10 edits (rename a
local, change a literal, add/remove a lambda, change a param type and fix callers, add a record
field, add/remove a function, add an atom literal in one module and `show` it in another); after
each edit compare the incremental build's output and exit code against a clean monolithic build.

---

## 13. Risks

| Risk | Likelihood | Mitigation |
|---|---|---|
| A program-wide emitter input missing from `globals_digest` → stale object | medium | coarse digest first (§6 list is from a field-by-field audit of `Llvm_ctx.ctx` and `emit_module`); verify mode in CI; narrow only with a test per narrowing |
| A counter-derived name Phase 1 missed | medium | determinism oracle; retiring `counter_re` as a check; link failures are loud; the silent case needs the differential test |
| Phase 3a refactor changes codegen | high (large diff) | `N=1` byte-identity via `ir-oracle`; land behind default `N=1` |
| Duplicate-symbol link errors from on-demand helpers | high without the `linkonce_odr` rule | §7 rule + `N=8` link guard |
| `-O2` perf loss from splitting | medium | ThinLTO; hard 3% gate; else dev-builds-only |
| `tm_fns`-order dependence (`unqualified_fns`, `main`) proves unstable | low | sort at registration; oracle detects it |
| Object store growth | certain | `cache gc` + default bound |
| Phase 0 shows the front end dominates | possible | gate re-orders 3b–5; Phases 1–3a still pay off |

---

## 14. Open questions

1. Phase 1 naming for `Fusion`/`Hof_spec`/`Mono` helpers: the sketch in §5.2 needs a concrete
   scheme per generator and a check that none can collide (two fusions of the same callees in
   one host → ordinal disambiguates; two `hspec`s of `g` on the same argument symbol → should be
   the same function anyway, dedupe).
2. Does the `tm_fns`-order dependence in `unqualified_fns` / last-`main`-wins need fixing before
   Phase 2, or is `tm_fns` order already deterministic given deterministic input? Phase 1's
   oracle answers this.
3. Is ThinLTO available on every CI image and macOS developer setup? If not, Phase 5 needs a
   detection matrix.
4. Should `.ll` publication under `N>1` concatenate (keeps existing greps working) or publish
   only per-unit files and update the ~20 `test/dune` rules? Plan assumes concatenate.

(Closed by review: constructor descriptor ids are declaration-ordered and per-unit already, so
they need no shared-unit treatment.)

---

## 15. Order and tracking

Phase 0 ∥ 1 ∥ 3a ∥ 7 → 2 → 3b → 4 → 5. Phase 6 waits on Phase 0's numbers. File one
`specs/todos/` entry per phase when its work starts and `git mv` it to `specs/progress/` in the
PR that lands it. Add a `CHANGELOG.md` entry under `### Added` when `--incremental` becomes
user-visible (Phase 4) and under `### Changed` when it becomes the default (Phase 5).

---

## 16. Review

An independent read of the first draft against the source (2026-10-04) found four blockers,
eleven should-fixes and some nits. All are folded into the text above; this section records what
changed and what the review confirmed, so a later reader knows which claims were checked.

### Blockers found and fixed
1. **The first draft fixed only one of several counters.** It proposed stabilising
   `Defun.lambda_counter`, but the lambda's own name `$lam<n>` comes from
   `Lower_state._lower_counter`, and `Fusion`, `Hof_spec` and `Mono` have counters of their own
   that reach symbols. §5.2 now inventories every generator (table) and makes the fix structural
   at lowering (`<host>$lam<i>`), with the others following the same pattern.
2. **The proposed "per-parent" apply-fn prefix would have broken self-tail-call recognition.**
   `apply_fn_base` must keep returning the lambda's self-binding name for
   `llvm_emit_call.ml:830–833`. The scheme now keeps the lambda's name as the prefix and makes
   the lambda's *own* name structural instead.
3. **Three families of on-demand helpers have external linkage** (`$clo_wrap`, `__eq$…`,
   `__march_ifdispatch$…`); the draft said only `internal` helpers needed duplication, which
   would have produced duplicate-symbol link errors under `N>1`. §7 adds the `linkonce_odr`
   rule, the alias-placement rule, and an `N=8` link guard aimed at exactly this.
4. **The atom show-table is `internal`**, so the draft's "scan up front" was right but
   incomplete: the table must be defined once, externally, in the shared unit, or `show(:x)`
   silently degrades across units. §7 now says so and the differential test gets a cross-unit
   atom edit.

### Should-fixes applied
- `globals_digest` was missing most of what is actually program-wide (`type_defs`,
  `collision_set`, `unqualified_fns` order, `tm_externs`/`tm_tests`/`tm_exports`/`tm_io_fns`,
  `pin_main`, `called_syms`, `MARCH_NO_INLINE_RC`). §6 now lists them from a field-by-field
  audit, and the `MARCH_NO_INLINE_RC` gap became a standalone todo (§11.4).
- `ctor_desc_ids` is declaration-ordered and already per-unit, not encounter-ordered; the
  draft's "move descriptors to the shared unit" was unnecessary and is removed (open question
  closed).
- `sig_hash` is narrower than assumed (name + param types + return type), so the key gets an
  explicit `abi_hash` covering `native_vec_params` and mutual-TCO membership.
- `Cas.store_artifact` already does temp+rename (`copy_file_exec`); the draft's Phase 7.4
  "make it atomic" was wrong and is replaced by fixing the stale comment that misled it.
- Phase 0 now uses the existing finer `Contract_pipeline` stamps and reports three buckets.
- `.ll` publication happens on every compile and tests grep it; §7 defines what `N>1` publishes.
- REPL counter persistence is in `lib/jit/repl_jit.ml`, not `lib/repl/`; corrected.
- Forge integration is more than a pass-through (`forge clean --cas`, `forge watch` as first
  consumer); §8 covers it. Windows is explicitly out of scope.
- Phase 3a does not depend on Phase 1; the ordering now runs them in parallel, and Phases 1–2
  are unconditional on the Phase 0 gate.

### Confirmed correct
`hash_module` runs on post-opt TIR (`pipe.final`); user functions have default linkage;
`lam_uid` is a cross-call global counter; `apply_fn_base` splits at the first marker and `drop.ml`
at the last `$`; `Runtime_archive`'s eligibility predicate and concurrency pattern are as
described; `Llvm_rc_inline` twins are `internal alwaysinline`; the runtime atom namer accepts
multiple registrations.

### Still unverified
Everything about *time* (no build was possible in the reviewing environment; Phase 0 exists for
this), ThinLTO availability on the CI images (§14.3), and whether `tm_fns` order is already
deterministic (§14.2).
