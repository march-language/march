# Incremental Compilation via the CAS — Plan

**Date:** 2026-10-04
**Status:** Proposed

---

## Problem

The CAS speeds up a compile only when nothing changed. Today there are three caches:

| Layer | Where | Key | Hit skips |
|---|---|---|---|
| Source-level | `bin/main.ml` (~2029–2090) | digest of entry + stdlib hash + every `.march` in source dir and `MARCH_LIB_PATH` | everything |
| Post-TIR | `bin/main.ml` (~3310–3395) | concatenation of every SCC's Merkle `impl_hash` | `llvm-emit` + clang only |
| Runtime objects | `lib/cas/runtime_archive.ml` | runtime sources + compiler + cc version + cflags | recompiling the C runtime |

Any real edit (one character in one function body) misses both whole-program keys and pays the full
pipeline: front end, lowering, mono/defun/Perceus/opt, LLVM emission of the *whole* program (including
every monomorphised stdlib specialisation; a `--compile-so` manifest for `examples/topology_app` lists
~13 000 functions), and one clang `-O2` invocation over that single `.ll`.

`Pipeline.compile_scc` (`lib/cas/pipeline.ml`) is a tested per-SCC cache that nothing calls. Its doc
comment names the blocker: codegen emits one LLVM module and links one binary, so there is no per-SCC
artifact to store.

## Goal

An edit to a function recompiles roughly that function's codegen unit, plus a link. Cached objects
must never produce a binary that differs in behaviour from a clean build.

## Non-goals (for this plan)

- WASM, JS, cross-compiled targets, `--compile-so` hot-reload patches: they keep today's monolithic
  path until the native path is proven.
- Incremental type checking for user modules (sketched in Phase 6, but needs its own plan).

---

## Phase 0 — Measure before building

No timings have been collected for this plan yet; everything above is from reading the code. Before
committing to Phases 2–5, confirm where the time goes.

- Add `scripts/compile-time-bench.sh`: runs `march --compile --timings` under a private `HOME` over
  a small fixed corpus: one tiny program, one `bench/*.march`, `examples/topology_app`.
- For each program, measure four scenarios: cold cache; warm with no change; warm after a comment-only
  edit; warm after a leaf function body edit; warm after a signature edit. Do this at `--opt 0` and
  `--opt 2`.
- Record the per-stage breakdown from the existing `stamp` points (`parse`, `desugar`,
  `resolve-imports`, `stdlib-load`, `typecheck`, `lower`, `llvm-emit`, `clang`).

**Gate:** if `llvm-emit` + `clang` aren't the majority of a warm leaf-edit compile, re-order the
plan to do Phase 6 (front end) first.

## Phase 1 — Make the keys deterministic

Finer-grained keys are useless, and dangerous, if the same source can produce different TIR or symbol
names. Two known sources of drift:

1. **Cold vs warm stdlib cache changes specialisations.**
   `specs/todos/2026-10-01-cold-stdlib-cache-changes-specializations.md`: a fresh `~/.cache/march`
   and a warm one emit different TIR for the same source. Fix it as that todo describes.

2. **Counter-numbered generated symbols.** Defunctionalised apply functions are named
   `"%s$apply$%d" fn_name lam_uid` (`lib/tir/tir_names.ml`), and `lam_uid` is a global counter, so an
   unrelated edit renumbers every later one. `serialize.ml` already normalises local variable names,
   but it hashes free references (callees) **by name**, so renumbering shifts hashes.

   Normalising this away *only in the hash* is not enough. A cached `.o` binds to its callees by
   **symbol name**, so a reused object whose callee was renamed fails to link or, worse, binds to
   the wrong function. The fix is a stable name: derive the suffix from the enclosing definition
   (e.g. the parent function's name plus the lambda's ordinal within that parent), not from a
   global counter. Audit mono's `$V_<n>` mangling (`lib/tir/mono.ml`, `mangle_ty`) and any other
   `fresh`/counter name that can reach a top-level symbol.

3. **Determinism oracle.** Add a test that compiles the snapshot corpus plus `examples/topology_app`
   twice: under different `HOME`s, cold then warm, from different cwds. It asserts identical
   per-function `(symbol, impl_hash)` sets. Prove it goes red on a deliberate perturbation (per
   CLAUDE.md's oracle rule) before trusting it.

**Exit:** the oracle is green in CI. This phase is valuable on its own: it also fixes the spurious
HCR manifest diffs that todo describes.

## Phase 2 — A codegen-unit key that doesn't cascade

`hash_module` folds each callee's **full** `impl_hash` into its caller's. That's correct for the
whole-binary key and must stay. For object files it's far too conservative: changing a leaf
function changes the key of every transitive caller up to `main`, so almost nothing would hit. HCR
already runs into this and works around it with a non-transitive hash (comment near `bin/main.ml:3320`).

New function `Pipeline.unit_keys : tir_module -> ...`. A function's object key covers exactly what
its compiled code depends on:

- its own serialized body, **with real symbol names** (Phase 1 makes them stable). Code the TIR
  optimiser inlined is already in this body, since hashing runs on post-opt TIR;
- for each callee: its symbol name and **signature hash** (calling convention / LLVM signature),
  not its body;
- the transitive type-layout closure it references (reuse `type_closure_hashes`);
- every **module-global emitter input** the function's codegen reads. This is the risky part, so
  audit `Llvm_ctx` and `Llvm_emit.emit_module`'s parameters: `fast_math`, `pmap_threshold`, target,
  `hot_reload` config, `impl_hashes`/`remote_*_hashes`, `cap_attrib`/`cap_decls`, `k_table`,
  constructor descriptor tables, `shape_meta`. Each one goes either into every unit's key
  (coarse, safe) or into the key of the functions that read it (precise, needs proof).

A unit's key = BLAKE3(sorted member keys ++ `build_cas_key` flags ++ unit-shape version tag).

**Exit:** unit tests in `test/test_cas.ml`. Editing a leaf's body changes only the leaf's key.
Editing its signature changes the leaf's and its direct callers' keys. Editing a record layout
changes every user of that record.

## Phase 3 — Split LLVM emission into units

Refactor `Llvm_emit.emit_module` / `Llvm_toplevel.emit_module` into:

- `emit_shared`: type declarations, constructor descriptor globals, the HCR dispatch table and epoch
  cell, atom name tables, module initialisation, `main`. Everything one-per-program.
- `emit_unit : fn_def list -> string`: a self-contained `.ll` with a fresh per-unit context
  (`str_ctr`, `ctr`, …), its own `internal` copies of helper functions (the `llvm_rc_inline`
  helpers, string literal cells), and `declare`s for every external callee and shared global.

Partitioning rules:

- An SCC and a mutual-TCO group (`mutual_tco_group`) are never split.
- Default unit = one source module (each stdlib module is its own unit; mono specialisations go
  with their generic's module). Split oversized modules into stable hash buckets of the base
  function name.
- Unit membership must not depend on unrelated code. That's the point of bucketing on names
  rather than on order.

User functions are already emitted with default (external) linkage (`define ptr @name`), so
cross-unit calls need no linkage changes. Only the `internal` helpers need duplicating.

**Regression guard:** a `--codegen-units=1` mode whose output is byte-identical to today's
`.ll`. Check with `scripts/ir-oracle.sh` (prove it red first). Then the multi-unit build must pass
the full test suite plus `test/run_snapshots.exe`.

## Phase 4 — Object cache, parallel compile, link

- Store: new CAS namespace `<root>/.march/cas/objects-v1/<key>.o`, with atomic temp-file + rename
  writes as in `runtime_archive.ml`. The key includes everything `Runtime_archive` already
  includes for objects: compiler identity, `cc --version`, exact cflags.
- Driver: emit units, look up each one, compile the misses **in parallel** (`-j` defaults to the
  core count; spawn clang processes), then link the runtime objects + unit objects + the shared
  object. Still store the final binary under the existing whole-binary keys, so the
  no-change path is unchanged.
- Flag: `--incremental` / `MARCH_INCREMENTAL=1`. Native target only, off for the excluded
  modes listed in the runtime cache's eligibility check (`bin/main.ml` ~4040). Start as opt-in at
  `--opt 0/1`.
- **Eviction:** an object store grows fast. Add `march cache gc --max-size N` (LRU by access time)
  and a default size bound.
- **Verify mode:** `MARCH_INCREMENTAL_VERIFY=1` recompiles every hit and byte-compares the `.o`
  (clang is deterministic for fixed inputs). Run it in CI over the test corpus.

## Phase 5 — Optimised builds without losing cross-unit inlining

Separate units cost LLVM's cross-unit inlining, which matters at `--opt 2/3`. Plan:

- Compile units to ThinLTO bitcode (`-flto=thin`) and link with `lld --thinlto-cache-dir=…`
  (`-Wl,-cache_path_lto,…` on macOS ld64). LLVM then caches the per-module backend work itself,
  and the CAS caches the per-unit front half.
- **Gate:** run `bench/` compiled (`--opt 2`) monolithic vs incremental+ThinLTO. No benchmark
  regresses by more than 3% (`bench/tree_transform`, `bench/list_ops`, `bench/binary_trees` at minimum,
  per `specs/benchmarks.md`). If it fails, `--opt 2/3` stays monolithic and incremental stays a
  dev-build feature.
- Once the gate passes, make `--incremental` the default for native builds.

## Phase 6 — Front-end incrementality (needs its own plan)

After Phases 3–5, a warm edit pays parse → typecheck → lower → opt for the whole program. The stdlib
already has AST and tcenv caches. Extend the idea to user modules: key each module on its source
plus the *interface* hashes of its imports, and skip re-checking modules whose dependencies'
interfaces didn't change. Mono and Perceus are whole-program, so the expected win is in the
typecheck/lower stages only. Write a separate plan once Phase 0 numbers show how much is left.

## Phase 7 — Independent quick wins (any time)

- **Replay diagnostics on a hit.** Store warnings alongside the artifact and print them again on a
  cache hit. This removes the `contains_substring cache_input "no_alloc"` bailout (`bin/main.ml` ~2037), and the same
  mechanism covers other warning-only output.
- **Key on the files actually loaded.** The source key hashes every `.march` file in the source
  directory and lib paths, imported or not. Key on the resolver's actual load set instead, while keeping the
  sibling-module fix described in the comment there.
- **Write through to the global store.** Artifacts are written only to the project store;
  `~/.march/cas` is only read as a fallback. Writing to both lets worktrees and repeated checkouts
  share hits.

---

## Correctness strategy

A stale object is a silent miscompile, so correctness gets more effort than speed:

1. Phase 1's determinism oracle (stable names and hashes).
2. Phase 3's `--codegen-units=1` byte-identity guard.
3. Phase 4's `MARCH_INCREMENTAL_VERIFY=1` mode in CI.
4. **Edit-sequence differential test:** take the differential oracle's generated programs, apply
   random edits (body, signature, record layout, add/remove function), and after each edit compare
   the incremental binary's output with a clean build's.

## Risks

| Risk | Mitigation |
|---|---|
| Missing a module-global emitter input in the unit key → stale object | Start coarse (all globals in every key), narrow only with tests; verify mode in CI |
| Generated names still unstable somewhere | Phase 1 oracle; link failures surface it loudly rather than silently |
| Perf loss from split units at `-O2` | Phase 5 ThinLTO gate; otherwise opt-in for dev builds only |
| Object store growth | `march cache gc` + default bound in Phase 4 |
| Emitter refactor regresses existing output | `--codegen-units=1` byte-identity + snapshots + full suite |

## Order and tracking

Phase 0 → 1 → 2 → 3 → 4 → 5. Phase 7 items are independent and can land at any time. Phase 6 waits on
Phase 0's numbers. File one `specs/todos/` entry per phase when its work starts, and move it to
`specs/progress/` in the PR that lands it.
