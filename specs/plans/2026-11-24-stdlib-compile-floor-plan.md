# Stdlib compile floor: implementation plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Cut ~0.6 s of stdlib work from every compile: a single-walk lemma erasure (Part 1), then a reachability prune before mono with a tripwire for missed edges (Part 2).

**Architecture:** Part 1 replaces a per-lemma whole-program walk in `Lemma_erase.drop_unreferenced` with one walk that builds a name set. Part 2 adds `lib/tir/dce_pre_mono.ml`, which runs in `Contract_pipeline.run` just before `Mono.monomorphize`. Its edges are `Dce.free_vars` plus `Mono.implicit_callees`, and mono refuses (internal error) any lookup of a name the prune removed.

**Tech Stack:** OCaml 5.5.1, dune, alcotest. Build and test only with `--root .` from the worktree, or with `scripts/run-tests.sh`.

**Spec:** `specs/2026-11-24-stdlib-compile-floor-design.md`

## Global Constraints

- Part 1 and Part 2 are separate PRs, each branched from `origin/main`. Part 2 doesn't depend on Part 1's code.
- Part 1 must not change any diagnostic or any emitted IR: `scripts/types-oracle.sh` and `scripts/ir-oracle.sh` show zero diff against the merge base (`scripts/oracle-base.sh ir types`).
- Part 2 is gated exactly like the early DCE (`opt && hot_reload = None && not is_js`), behind `Pass_switch` name `dce-pre-mono`.
- Part 2 accepts function reorders and `$nafuse_lam<N>` renumbering. Every program must be identical after canonicalisation (sort functions by name; mask `$nafuse_lam<N>` and SSA numbers), and no unqualified-name fallback may change target.
- The tripwire is always on, not gated on `--verify-tir`.
- Each PR moves its own `specs/todos/` entry (create one if none exists) to `specs/progress/` and adds a `CHANGELOG.md` `### Changed` bullet under `[Unreleased]`, in the same commit as the fix.
- No `Co-Authored-By` lines. Stage files by name, never `git add -A`.

## Review Focus

1. A tuple, record or ADT compared with `<`, `<=`, `>` or `>=` whose only route to `__ord_*` is mono's rewrite must still compare correctly (issue #1172 is the silent failure). Task 5 pins it in a compiled run.
2. `show`/`to_string`/`println` of a user type whose `Show` impl is reached only through interface dispatch must still print through that impl. Task 5 pins it.
3. A lemma mentioned only from a nested `mod`, an impl method or an actor handler must survive erasure. Task 1 pins all three.
4. A program with no `main` (a library, a test module) must still keep its tests and exports. Task 5 pins it: a `--test` compile of a module with only `test` blocks.
5. A function with the same name declared twice before mono (`tir_verify.ml:34–35`) must keep the callees of both bodies. Task 4 pins it in `test_dce_pre_mono`.

---

## Part 1 — lemma erasure (PR 1)

### Task 1: single-walk `drop_unreferenced`

**Files:**
- Modify: `lib/desugar/lemma_erase.ml` (`mentions`, `drop_unreferenced`, around lines 238–312)
- Modify: `bin/main.ml:832–836` (`lemma_reserved`: build the `reserved_by` table once, not per call)
- Test: `test/test_refine_lemma.ml` (new list `drop_unreferenced_cases`), registered in the `reflect-lemma` group at `test/test_refinecheck.ml:30999`
- Create: `specs/progress/2026-11-24-lemma-erase-single-walk.md`
- Modify: `CHANGELOG.md`, and `specs/2026-11-24-stdlib-compile-floor-design.md` (status line: Part 1 landed)

**Interfaces:**
- Produces: `Lemma_erase.mentioned_names : decl list -> SS.t`. It returns the last segment of every `EVar` reached by the traversal `mentions` uses today. `drop_unreferenced whole decls` keeps its signature.

- [ ] **Step 1: Write the failing tests.** Add them to a new non-gated list in `test/test_refine_lemma.ml` (no z3 needed). Each one parses and desugars a source string with `Test_helpers.parse_and_desugar`, runs `Test_helpers.erase_lemmas`, and asserts which `@[lemma]` `DFn`s remain, by name:
  - `lemma_used_from_nested_mod_kept`: lemma `l1` is called only inside `mod Inner do … end`. Assert `l1` is still declared.
  - `lemma_used_from_impl_method_kept`: lemma `l2` is called only inside an `impl Show for T` method. Assert kept.
  - `lemma_used_from_actor_handler_kept`: lemma `l3` is called only in an actor `on` handler. Assert kept.
  - `lemma_unmentioned_dropped`: lemma `l4` is never called. Assert dropped.
  - `mentioned_names_matches_mentions`: over that combined program, for every name `n` in `mentioned_names decls`, assert `mentions n decls = true`; for each of the four lemma names, assert `SS.mem n (mentioned_names decls) = mentions n decls`.
- [ ] **Step 2: Run them.** `dune build --root . test/test_refinecheck.exe && MARCH_TEST_GROUP=reflect-lemma ./_build/default/test/test_refinecheck.exe -e`. Expected: the four behaviour cases PASS (they pin today's behaviour), and `mentioned_names_matches_mentions` FAILS to compile (`mentioned_names` undefined).
- [ ] **Step 3: Implement.** Add `mentioned_names`, reusing `mentions`' `children` and declaration cases. Keep `mentions` as a thin wrapper (`SS.mem n (mentioned_names decls)`) so the two can't diverge. `drop_unreferenced` computes `mentioned_names whole` once, then filters with `SS.mem`. In `bin/main.ml`, bind `let lemma_reserved = March_desugar.Lemma_erase.reserved_by (…)` as a value, not a function of `n`.
- [ ] **Step 4: Run them.** The same command; expected all PASS. Then `scripts/run-tests.sh` (full), and `scripts/run-tests.sh refinecheck`; expected green apart from the failures already listed in `project_preexisting_suite_failures`.
- [ ] **Step 5: Oracles.** `scripts/oracle-base.sh ir types`. Expected: zero changed programs and zero changed diagnostics.
- [ ] **Step 6: Timing.** Warm hello world (`needs IO.Console`), private `HOME`, a unique `pfn probe_<n>()` per run, `--compile --opt 2 --timings`. Run 5 alternating runs of the merge-base build and this build, and record the medians of the `typecheck → lower` gap. Expected about −0.35 s. Put the numbers in the progress entry.
- [ ] **Step 7: Commit** (lemma_erase.ml, main.ml, the two test files, the progress entry, CHANGELOG, the design doc, this plan), push, and open PR 1.

---

## Part 2 — prune before mono (PR 2)

### Task 2: audit for implicit callees

**Files:**
- Modify: `specs/2026-11-24-stdlib-compile-floor-design.md` (new section "Implicit-callee audit")

**Interfaces:**
- Produces: the list `implicit_callees` must cover (Task 3 reads it).

- [ ] **Step 1:** For `lib/tir/mono.ml`, `lib/tir/fusion.ml` (including `run_nativearr`) and `lib/tir/defun.ml`, list every place that introduces a call (`EApp`), or looks up a `fn_table`/`tm_fns` entry, by a name that isn't a free variable of the body being rewritten. For each: file:line, the name or naming rule, and whether it's (a) an interface impl reachable through `find_iface_impls`, (b) a fixed helper name like `__ord_lt`, or (c) a function the pass creates itself (no edge needed).
- [ ] **Step 2:** Write the table into the design doc. Any (b) outside mono gets a note for Task 3 (add it to `implicit_callees`) or Task 4 (add a tripwire at that site).
- [ ] **Step 3: Commit** the doc change.

### Task 3: `Mono.implicit_callees`, with no behaviour change

**Files:**
- Modify: `lib/tir/mono.ml` (the ord rewrite at ~895–913, iface resolution at ~762 and ~945) and `lib/tir/mono.mli` (export both new functions; Task 4 adds `?pruned` there too)
- Test: `test/test_codegen.ml` (or the mono unit-test file the suite already uses for mono; put it next to existing `Mono.` tests)

**Interfaces:**
- Produces:
  - `Mono.ord_helper_of_op : string -> string option`: `"<"` → `"__ord_lt"`, `"<="` → `"__ord_le"`, `">"` → `"__ord_gt"`, `">="` → `"__ord_ge"`, anything else → `None`.
  - `Mono.implicit_callees : iface_methods:(string, (string * string) list) Hashtbl.t -> string -> string list`: `ord_helper_of_op n` (as a list) followed by every impl symbol of `Tir_names.find_iface_impls iface_methods n` (the default, aliasing lookup), plus any (b) entries from Task 2.

- [ ] **Step 1: Write the failing tests.**
  - `implicit_callees_ord`: `implicit_callees ~iface_methods:(empty) "<" = ["__ord_lt"]`, and likewise for the other three operators.
  - `implicit_callees_iface`: a table mapping `"show"` to `[("Int","Show$Int.show"); ("Foo","Show$Foo.show")]`. Expect `implicit_callees ~iface_methods:tbl "show"` to equal both symbols, and `"to_string"` to give the same (the alias).
  - `implicit_callees_plain`: `implicit_callees ~iface_methods:tbl "List.map" = []`.
- [ ] **Step 2:** Run them. Expected: they fail to compile.
- [ ] **Step 3: Implement.** The ord rewrite calls `ord_helper_of_op` instead of its inline match on the operator name. The routing condition on the argument type stays where it is.
- [ ] **Step 4:** Run the tests: PASS. `scripts/oracle-base.sh ir`: zero diff (this task changes no behaviour).
- [ ] **Step 5: Commit.**

### Task 4: the pre-mono prune and the mono tripwire

**Files:**
- Create: `lib/tir/dce_pre_mono.ml` (and `.mli`)
- Modify: `lib/tir/mono.ml` (`monomorphize` gains `?pruned`; all 7 `fn_table` lookups at ~568, 659, 818, 907, 915, 1170 go through one helper; the `not (Hashtbl.mem fn_table …)` locality test at ~835 is **not** a resolution lookup and stays as it is)
- Modify: `lib/tir/pass_switch.ml` (`known` gains `("dce-pre-mono", "prune functions unreachable from the roots before Mono")`)
- Test: `test/test_dce_pre_mono.ml`, registered in `test/run_compiler.ml` and `test/dune`

**Interfaces:**
- Consumes: `Mono.implicit_callees` (Task 3), `Dce.free_vars`, `Dce.root_names`, `Dce.remote_ref_targets`, `Alloc_contract.has_noalloc_policy`.
- Produces:
  - `Dce_pre_mono.prune : ?iface_methods:(string, (string * string) list) Hashtbl.t -> extra_roots:string list -> fail_open:bool -> Tir.tir_module -> Tir.tir_module * (string, unit) Hashtbl.t`. It returns the pruned module (survivors in their original order) and the set of removed names.
  - `Mono.monomorphize : ?iface_methods:… -> ?pruned:(string, unit) Hashtbl.t -> Tir.tir_module -> Tir.tir_module`. A resolution lookup of a name in `pruned` raises `Failure "internal error: Mono resolved <callee> (from <caller>), which the pre-mono prune removed; rerun with --disable-pass dce-pre-mono and report it"`.

- [ ] **Step 1: Write the failing tests** in `test/test_dce_pre_mono.ml`, building TIR with `Test_helpers.lower_module_typed`:
  - `prune_keeps_main_closure`: a `main` calling `f`, where `f` calls `g`, plus an unused `h`. Assert survivors ⊇ {main, f, g}, `h` removed.
  - `prune_follows_iface_impls`: `main` calls `show(x)` on a user type with `impl Show`. Assert the impl symbol survives.
  - `prune_follows_ord_helpers`: `main` compares two tuples with `<`. Assert `__ord_lt` survives.
  - `prune_duplicate_names_union`: two `fn_def`s named `dup` (construct the module by hand) whose bodies call `a` and `b` respectively, with `main` calling `dup`. Assert both `a` and `b` survive.
  - `prune_no_main_keeps_tests`: a module with only `test` blocks. `lower_module_typed` has no test-mode option, so lower it with `March_tir.Lower.lower_module ~type_map ~test_mode:true`, following `lower_module_typed`'s body. Assert every `tm_tests` function survives.
  - `tripwire_fires`: call `Mono.monomorphize ~pruned` where the set contains `"__ord_lt"`, on a program comparing tuples with `<`. Assert it raises `Failure` mentioning `__ord_lt`.
- [ ] **Step 2:** Run them (`scripts/run-tests.sh compiler`). Expected: they fail to compile.
- [ ] **Step 3: Implement `Dce_pre_mono.prune`.** Do a BFS. Roots are `Dce.root_names ~fail_open`, `extra_roots`, `Dce.remote_ref_targets`, functions with a no-alloc policy, and names ending in `__rpc_stub`. For a reached name, take the union over every `fn_def` with that name of `free_vars body ∩ names` and `implicit_callees`.
- [ ] **Step 4: Implement the mono helper and `?pruned`.**
- [ ] **Step 5: Wire it into `Contract_pipeline.run`,** after the wasm-island export block and before `Mono.monomorphize`, under the early DCE's gate plus `Pass_switch.on "dce-pre-mono"`. Pass the removed set to mono. Stamp `dce-pre-mono` under `--timings`.
- [ ] **Step 6:** Run the tests: PASS. Then run `scripts/run-tests.sh` (full) and `scripts/run-tests.sh test_jit lsp`.
- [ ] **Step 7: Prove it red.** Temporarily make `implicit_callees` return `[]` for ord operators. A compiled program comparing tuples with `<` must now fail with the tripwire's message, not print a wrong answer. Do the same for the iface rule with a `show` program. Record both in the progress entry, then revert the perturbation.
- [ ] **Step 8: Commit.**

### Task 5: end-to-end correctness, oracles, timing

**Files:**
- Create: `test/native/pre_mono_prune_ord_show.march` (plus its expected output, wired the way neighbouring `test/native` fixtures are, including the refine-audit baseline step from `feedback_new_native_fixture_needs_refine_audit_baseline`)
- Create: `scripts/ir-canon-diff.sh` (canonicalising comparison for this PR, reusable)
- Create: `specs/progress/2026-11-24-pre-mono-dce.md`; modify `CHANGELOG.md`, the design doc's status line, and `specs/todos/2026-11-19-ocap-authority-mono-compile-cost.md` (note that the prune removes Authority before mono, and check whether that closes it)

- [ ] **Step 1: Native fixture.** It compares tuples, records and an ADT with each ordering operator, prints a user type through its `Show` impl, and uses `to_string`. The expected output is the interpreter's. Run it compiled and interpreted, and confirm both match.
- [ ] **Step 2: Canonicalising diff.** `scripts/ir-canon-diff.sh <base-dir> <new-dir>` takes two `ir-oracle` output trees. For each `.ll`, it sorts the `define` blocks by symbol, masks `$nafuse_lam<N>` and `%<N>` SSA names, and diffs. It exits non-zero listing any program that differs after that. Prove it red by feeding it one hand-edited `.ll`.
- [ ] **Step 3:** Run `scripts/oracle-base.sh ir`, then `scripts/ir-canon-diff.sh` over the base and branch trees. Expected: zero programs differ after canonicalisation. Then run `scripts/determinism-oracle.sh --corpus all`: DETERMINISTIC.
- [ ] **Step 4: Snapshots.** Run `UPDATE_SNAPSHOTS=1 ./_build/default/test/run_snapshots.exe -e` only if `run_snapshots` fails, and confirm `git diff test/snapshots/` is reorder/renumber only. Say so in the PR body.
- [ ] **Step 5: Timing.** Measure hello world and `bench/tree_transform` as in Task 1 Step 6, at the `cas-hash` stamp, alternating the merge-base build and this build, 5 runs each. Expected about −0.3 s. Also run `scripts/compile-time-bench.sh --opt 2 --corpus small`. Record the numbers in the progress entry.
- [ ] **Step 6: Commit,** push, and open PR 2.
