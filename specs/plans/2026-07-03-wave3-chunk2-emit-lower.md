# Wave 3 Chunk 2: llvm_emit + lower Restructure, Assert Retirement

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Complete the deep-review §7 refactors: consolidate llvm_emit's tagging/builtin machinery then split the file (~7k lines → orchestrator + ~9 modules); thread an env through lower.ml then split it; retire Chunk 1's transitional fn_kind asserts (gated on FnFused coverage); convert the drift-class stragglers Chunk 1's final review found.

**Architecture:** Same discipline as Chunk 1 (specs/plans/2026-07-03-wave3-chunk1-refactors.md): behavior-preserving commits, helpers-before-splits, one commit per task. Two chunk-2-specific IR-identity hazards are addressed by explicit constraints: (H1) any helper replacing inline IR-emission sequences must reproduce each site's exact register-name prefixes (fresh-counter sequences must not drift); (H2) the generated builtin preamble must reproduce the current hand-written text byte-identically (declaration order and whitespace preserved by the table's ordering).

**Tech Stack:** OCaml 5.3 / dune; new files join `lib/tir` flat (chunk-1 precedent).

## Global Constraints — STANDARD GATES (referenced by every task as "the standard gates")

1. Six runners exit 0: `dune build --root . test/run_compiler.exe test/run_eval.exe test/run_codegen.exe test/run_stdlib.exe test/test_stdlib_march.exe test/run_snapshots.exe`, then each `HOME=$PWD/.w3home ./_build/default/test/<t>.exe -e` (mkdir -p .w3home once), judged by EXIT CODE.
2. ZERO TIR snapshot churn (no `.expected` diffs).
3. Baseline IR diff: build the task's base commit in a temp worktree (`git worktree add /tmp/w3c2-<task>-kapitsa <base>; dune build --root . bin/main.exe` there), `--emit-llvm` all four benchmarks with both compilers, byte-identical `.ll` required; remove the temp worktree after.
4. Four compiled benchmarks (`--compile --opt 2`): outputs per specs/benchmarks.md; timings ±10%.
5. Refactor discipline: bugs found while moving get FILED (specs/todos.md) not fixed; verbatim whole-function moves; never duplicate to dodge a dependency; no cycles (restructure the cut instead).
6. Process: foreground only; wedge rule (runner >4 min → kill, retry once isolated-HOME, else BLOCKED naming the wedge); no `git stash`; never pipe `march --compile` output; explicit staging; no Co-Authored-By; deciduous action node linked from goal 1619 before edits, outcome `--commit HEAD` after.
7. Worktree: ONLY /Users/80197052/code/march/.claude/worktrees/hopeful-kapitsa-9f49f3 (branch claude/hopeful-kapitsa-9f49f3, base bb6d1cfd == main == origin/main). Do not touch test/test_properties.ml or runtime/.
8. Known pre-existing failures (NOT yours): bench/heapsort.march RC underflow; examples/supervision_linear_drop.march race; mono "Monomorphization limit reached" (documented skip).
9. Stale-pointer rule: all line refs in this plan are locate-by-grep hints, not gospel.

---

### Task 1: FnFused coverage + drift-class stragglers

**Files:** Modify `lib/tir/tir_names.ml` (+ mono suffix-mangle helper), `lib/tir/mono.ml`, `lib/tir/known_call.ml`; Test `test/test_codegen.ml`.

- [ ] **Step 1 (FnFused consumer test — GATES Task 2):** fusion.ml tags its loop-fusion helper fns `FnFused` (Chunk 1 Task 3) with zero consumers/asserts. Add a codegen test that compiles a program known to trigger fusion (check bench/tree_transform.march's shapes or fusion.ml's own doc comments for the trigger pattern; `MARCH_DEBUG` or IR inspection to confirm fusion fired) and asserts — via a small test-only hook or by walking the TIR the way existing tests do (Test_helpers pipeline access) — that at least one `FnFused`-kind fn_def exists post-fusion AND its name matches whatever naming convention fusion uses (the flag-vs-reality cross-check the transitional asserts never covered). If fusion is genuinely unreachable from any test-corpus program, report that finding loudly — it gates Task 2's assert removal decision and is itself a todos entry.
- [ ] **Step 2:** `known_call.ml` (~:33): the 4-char `"$Clo"` prefix variant — convert to `Tir_names.is_clo_struct` ONLY if behaviorally safe: first verify no producer mints `"$Clo"` without the underscore (grep + Tir_names doc); the 4-char check also matches `"$Clo_"` names so switching to the 5-char predicate is behavior-narrowing in theory — prove no name shaped `"$Clo"`+non-underscore exists (producers all go through Tir_names now), then convert with a comment. If unprovable, leave + document + todos.
- [ ] **Step 3:** mono.ml (~:320): the specialization-suffix mangle (`name ^ "$" ^ mangled_ty`, W2's `Show$List.show$Int`) — add `Tir_names.specialize_mangle : string -> string -> string` (+ doc: relationship to `is_iface_mangled`, i.e. why `$`-after-last-dot does NOT trip the iface predicate — cite the W2 review analysis), convert mono's producer, fix the stale "that's Wave 3" comment.
- [ ] **Step 4:** Standard gates. **Commit** `refactor(tir): FnFused coverage test; convert known_call/mono name stragglers to Tir_names (W3C2.1)`.

### Task 2: Retire the transitional fn_kind asserts

**Files:** Modify `lib/tir/perceus.ml`, `lib/tir/llvm_emit.ml`. **PRE-CONDITION: Task 1's FnFused coverage landed (or its unreachability finding consciously accepted by the controller — do not self-approve).**

- [ ] **Step 1:** Remove exactly the inventory (grep to relocate): perceus.ml assert (~:514–526) + `env.fn_kinds` field + its `empty_env` init + table build (~:1548–1551) IF fn_kinds has no other reader post-assert (verify; if another reader exists, keep the field, remove only the assert); llvm_emit.ml assert (~:3579–3585) + `ctx.top_fn_kind` decl/init/population (~:38–48, :297, :6622–6627) same no-other-reader check; llvm_emit.ml self-check (~:5771–5779). The consumers keep their FLAG-based decisions (that was the point) — only the sniff-comparison scaffolding goes.
- [ ] **Step 2:** `lib/cas/serialize.ml`'s fn_kind exclusion warning is PERMANENT — verify untouched.
- [ ] **Step 3:** Standard gates. **Commit** `refactor(tir): retire transitional fn_kind asserts; flags are now the sole authority (W3C2.2)`.

### Task 3: `llvm_ctx.ml` + the audited tag/untag helpers

**Files:** Create `lib/tir/llvm_ctx.ml`; Modify `lib/tir/llvm_emit.ml`; Test unit tests in test/test_codegen.ml.

- [ ] **Step 1 (move):** ctx record + `make_ctx`, `fresh`/`fresh_block`/`emit`, `llvm_name`, type mapping (`llvm_ty`/`llvm_param_ty`), `coerce`, string-interning helpers, layout constants (tag/pad/fields offsets, alloc_size — cross-ref comment to `march_hdr` in runtime/march_runtime.h) — verbatim moves per chunk discipline. Anything with heavy back-references into emit arms stays put; map dependencies FIRST (chunk-1 Task-5 method) and justify the final cut.
- [ ] **Step 2 (consolidate — HAZARD H1):** two audited helpers, `emit_tag_scalar` / `emit_untag_scalar` (and a `restore_known_heap` if the inventory warrants), replacing the ~9 inline `(shl; or 1)` / conditional-`ashr` sequences (inventory hints: coerce internals, clo_wrap, EAlloc newtype ×2, EReuse ×2, trampoline, ECallPtr, case-guard — grep `shl i64` / `ashr` emitters). **Each helper takes the register-name prefix as a parameter** and each converted site passes its CURRENT prefix (`nt_sh`, `niche_sh`, …) so the emitted IR — register names included — is byte-identical. The helper doc states the conditional-untag law (ptr→i64 untags iff odd; never tag a pointer; known-heap restore is bare inttoptr) citing the erased-i64 convention.
- [ ] **Step 3:** Standard gates (the IR diff is the entire point here). **Commit** `refactor(llvm): llvm_ctx module + audited tag/untag helpers with per-site prefix preservation (W3C2.3)`.

### Task 4: `llvm_builtins.ml` — one declarative table (HAZARD H2)

**Files:** Create `lib/tir/llvm_builtins.ml`; Modify `lib/tir/llvm_emit.ml`; Test test/test_codegen.ml.

- [ ] **Step 1:** Inventory the four unsynchronized structures: `is_builtin_fn` (~230-name list), `builtin_ret_ty`, `mangle_extern`, and the hand-written preamble declare blob. Build ONE ordered table `{ march_name; c_name; ret_ty; declare_sig; … }` capturing ALL FOUR facts per builtin, **in the preamble's current declaration order**.
- [ ] **Step 2:** Reimplement the four consumers from the table. The preamble generator must reproduce the current text **byte-identically** (same order, same whitespace/newline layout — diff the generated preamble against the old literal as a unit test). `is_builtin_fn` becomes a hashtable built once from the table (the known O(n)-hot-path fix — allowed here because it's answer-identical; note the perf side-effect in the report).
- [ ] **Step 3:** Any builtin found in SOME structures but not all (the historical "missing builtin" drift class): preserve today's exact per-structure membership (the table gets optional fields / explicit absence markers), FILE the inconsistency in todos — do not repair it in this task.
- [ ] **Step 4:** Standard gates + the preamble byte-diff unit test. **Commit** `refactor(llvm): declarative builtin table generating all four consumer structures (W3C2.4)`.

### Task 5: Split llvm_emit — leaf emit modules

**Files:** Create `lib/tir/llvm_eq.ml` (mangle_ty_for_eq, ensure_adt_eq_fn family), `lib/tir/llvm_data.ml` (EAlloc/EStackAlloc/EReuse/ETuple/ERecord/EField/EUpdate arms' helper fns, ctor lookup, record shape metadata, the deduped emit_niche_payload), `lib/tir/llvm_case.ml` (emit_case + niche/newtype strategies); Modify llvm_emit.ml.

- [ ] Dependency-map first; verbatim moves; the `emit_expr` match arms themselves may need to stay in llvm_emit.ml with bodies delegated to module functions — prefer extracting whole helper functions over slicing match arms; justify the cut. Dedup the two identical `is_trivial_dec_chain_returning` copies into ONE (they carry a "must stay identical" comment — they are identical, so single-sourcing is a pure move; verify identity first). Standard gates. **Commit** `refactor(llvm): split eq/data/case emit modules out of llvm_emit (W3C2.5)`.

### Task 6: Split llvm_emit — calls + TCO

**Files:** Create `lib/tir/llvm_calls.ml` (EApp/ECallPtr helpers, wrappers incl. clo_wrap_define + fail_if_unresolved_iface_method, dispatch paths, the return-type-of-fn resolver honoring is_apply_fn), `lib/tir/llvm_tco.ml` (TCO predicates, Tarjan SCC, mutual-group analysis, emit_mutual_tco_group, the Perceus-wrapped interception arms' helpers); Modify llvm_emit.ml.

- [ ] Same discipline as Task 5. Extra care: the mutual-TCO arms (B7/B8 fixes) and the emitted_wraps dedup guard (B11) are recent, test-pinned behavior — their tests already exist; zero churn there is non-negotiable. Standard gates. **Commit** `refactor(llvm): split calls/TCO modules out of llvm_emit (W3C2.6)`.

### Task 7: Split llvm_emit — toplevel + REPL; orchestrator final form

**Files:** Create `lib/tir/llvm_toplevel.ml` (emit_fn, build_ctor_info, emit_module internals, entry/main/test emission, HCR setup), `lib/tir/llvm_repl.ml` (the five REPL/fragment emitters); Modify llvm_emit.ml → thin orchestrator + public API (external callers grep `Llvm_emit.` — bin/main.ml, lib/jit — must not change; re-export like perceus.ml did).

- [ ] Same discipline. Document at the top of llvm_emit.ml: the value-representation pointers (which module owns tagging law, layout constants, apply-fn ABI) — pointers to where things went, not new prose (Wave 4 owns the real doc). Standard gates. **Commit** `refactor(llvm): toplevel/REPL modules; llvm_emit becomes orchestrator (W3C2.7)`.

### Task 8: lower.ml env record (IN PLACE)

**Files:** Modify `lib/tir/lower.ml` only (+ single entry-point caller updates if the signature must carry the env — keep public API stable via the same wrapper trick as perceus).

- [ ] Chunk-1 Task-4's law verbatim: inventory the ~12 module-level refs/Hashtbls (`_type_map_ref`, `_iface_methods`, `_use_aliases`, `_lowered_modules`, `_current_module_fns`, `_default_dispatch`, `_fn_param_types`, fresh counter, + whatever grep finds — W1/W2 commits changed this file); saved-and-restored → env field; accumulators stay refs documented; restore-gaps → STOP converting that ref, preserve + file. KNOWN LANDMINES to handle as accumulators or explicitly scoped fields, not silently absorbed: the reset-at-entry set vs the NOT-reset trio (`_current_module_fns`, `_default_dispatch`, `_fn_param_types` — their staleness across `lower_module` calls is CURRENT BEHAVIOR the JIT may depend on; preserve exactly, document, file the reentrancy question in todos with a pointer to the analysis doc's lower.ml High finding); `reset_counter()` per-call semantics preserved. The six hand-rolled save/restore dances (analysis doc cites ~6 sites) map per the law.
- [ ] Standard gates + MARCH_DEBUG_PERCEUS-style spot check is N/A here — instead: lower-level TIR snapshots (the 14 post-lower snapshots) are the sharp gate. **Commit** `refactor(lower): thread explicit env; module-level mutable state contained and documented (W3C2.8)`.

### Task 9: lower.ml split

**Files:** Create `lower_types.ml` (BOTH ty converters moved VERBATIM — their arrow/Nat encoding disagreement is a FILED bug (analysis doc lower High #4), moving them side-by-side with a comment is the task; unifying them is NOT), `lower_match.ml` (compile_matrix + guards + join points + pat_tag_and_subs), `lower_decls.ml` (fn/type defs, aliases, extern lowering — dedup the two VERBATIM-identical DExtern blocks only if byte-identical, verify), `lower_actor.ml`, `lower_tests.ml`; Modify lower.ml → orchestrator.

- [ ] **The three module-decl walkers:** implement ONE parameterized walker ONLY IF each caller's current decl-kind coverage can be expressed as explicit parameters preserving TODAY'S divergence (lazy-stdlib path handling fewer kinds is CURRENT behavior — the gap is a filed bug, not yours to fix). If parameterization can't provably preserve each path, move the copies as-is and file. Standard gates. **Commit** `refactor(lower): split types/match/decls/actor/tests modules; lower becomes orchestrator (W3C2.9)`.

### Task 10: Bookkeeping

- [ ] Six runners final counts; `scripts/check-docs.sh` green (CLAUDE.md project-layout section lists lower.ml/llvm_emit.ml/perceus.ml paths — update the lib/tir lines for the new module map); compiler-rc guidance (~/.claude/commands/compiler-rc.md) already names perceus modules — extend for llvm_emit/lower if it references them; specs/progress.md chunk-2 entry + specs/todos.md: §7.2/§7.4 done, list all filings from Tasks 1–9, note Wave 4 (docs) is all that remains of the original plan. **Commit** `docs(specs): record Wave 3 chunk 2 (llvm_emit + lower restructure)`.
