# Reflection phase 2: lemmas — implementation plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** add `@[lemma]` functions to March. A lemma is checked as a theorem, its proved post becomes a fact after each call, and every lemma is erased before anything runs.

**Architecture:**
- A lemma is a `DFn` carrying the `"lemma"` attribute. The generic `fn_attr` rule already parses it, so the parser and tree-sitter grammar don't change.
- The refinement checker validates rules L1-L5. It checks the lemma's `{Unit | P}` post as a closed goal at each tail of the body, under the walk's own facts: match arms, earlier lemma calls, and asserts that were proved.
- A lemma is admitted once its post is proved. Recursive lemmas are admitted through the existing `ih_spans` gate.
- At a statement-position call, the post is pushed into the block's `path` only when the lemma is admitted and every precondition at that span is `Proved`.
- A new front-end pass, `Lemma_erase` (in `lib/desugar`), runs after typechecking on every path that runs code. It replaces resolved lemma calls with `()`, blanks every lemma body, and drops each lemma declaration that is no longer referenced.

**Tech stack:** OCaml 5.5.1, dune, z3 (CI runs 4.8.12), alcotest.

**Spec:** `specs/2026-10-29-refinement-reflection-design.md`:
- §4 (lemmas) is the behaviour;
- §9.1's rows marked (2) are the soundness tests;
- §10 "Phase 2: lemmas" gives the scope, RED table, oracle gate and definition of done.

The user's decisions D3, D4 and D5 govern; see the memory note `project_reflection_decisions.md`.

## Global constraints

- `test_refinecheck.exe` stays green at every commit. Use `scripts/run-tests.sh refinecheck`, with z3 on PATH and a private `HOME`.
- Every new rule lands with a fixture that goes RED without it. Record the perturbation in the progress note.
- Assert ledger triples (proved, violated, skipped) or diagnostic slugs, never exit codes.
- Build with `dune build --root .` and explicit targets. Never use a targetless build, and never `eval $(opam env)`.
- New diagnostic codes go in `lib/errors/code.ml`, both as a `let` and in `all`. Doc-lint Check G forbids literal slugs anywhere else. Each code gets a hand-written page at `specs/lang/errors/<slug>.md`. Then run `scripts/seed-error-corpus.sh`, then `UPDATE_ERRORS=1 ./_build/default/test/run_errors.exe -e`.
- The new codes are `invalid_lemma`, `lemma_unproved`, `lemma_unproved_call` and `lemma_argument_impure`.
- `lemma_unproved` and `lemma_unproved_call` are warnings. Each becomes an error under `cap verified`.
- Stage 1's VC text stays byte-identical for every program without a lemma (F9).
- The oracle gate has two parts:
  - `scripts/oracle-base.sh refine` must be monotone (no proved→skipped/violated lines);
  - `scripts/oracle-base.sh ir` must be IDENTICAL.
  - CI runs neither, so run both locally and paste the results into the progress note.
- Commits stage explicit paths and carry no attribution lines.
- Docs:
  - edit `specs/lang/refinement-types.md`, then run `scripts/gen-lang-docs.py`;
  - add a CHANGELOG `[Unreleased]` bullet;
  - add `specs/progress/2026-11-XX-reflection-phase2-lemmas.md`.

## Rulings made while planning (deviations from the spec's letter)

1. **Erasure lives in `lib/desugar/lemma_erase.ml`, but is called after typechecking, not from `desugar_module`.**
   - The spec says to put it "beside the other AST rewrites". Every existing rewrite runs inside `desugar_module`, which is *before* typechecking, and the checker needs the un-erased AST.
   - So the pass is a separate entry, `Lemma_erase.erase_module : Ast.decl list -> Ast.decl list`, and each driver calls it.
   - Paths that never typecheck call it right after desugaring: `march dap`, the browser REPL `js/march_browser.ml`, and doctest expressions.
   - Cost if wrong: one driver forgets the call. Test `sound_erase_paths` covers every driver by name.
2. **Erasure resolves names itself, conservatively, and blanks lemma bodies as a backstop.**
   - `march_desugar` can't depend on `march_refinecheck`'s resolvers.
   - The pass erases a call `EApp (EVar n, args)` only when both hold:
     - `n` resolves to a lemma by the module path, `alias` and `use` rules of `Refine_resolve.resolve_call_gen`, mirrored in a small resolver;
     - no local or parameter shadows `n`.
   - It replaces every lemma body with `()`. It drops a lemma `DFn` only when no reference to it is left.
   - A missed call therefore runs an empty body, which has no effect and is never a dangling name. A call that could be resolved wrongly is left alone, never erased.
   - `sound_erase_ir` still requires byte-identical IR on every phase-2 fixture, so a miss on any fixture is RED.
   - Cost if wrong: in a corner the resolver can't decide, a leftover call to `()`. That is only a performance cost.
3. **Lemma posts are checked by the walk (`visit`), not by `check_post`'s tail engine.**
   - `tails_bound` folds in only `let`, so it never sees asserts or statement-position calls.
   - A lemma tail `()` instead files a `Postcondition` obligation on `P[params]` under the walk's `path`/`sc` at that point. The obligation goes through `Reflect_stage.two_stage`, so stage 2 gets unfoldings.
   - The lemma is admitted when every tail obligation is `Proved`.
   - Cost if wrong: two engines for posts. Ordinary `{Unit | P}` functions keep today's behaviour, as §4.3 requires.
4. **A lemma fact enters only through a statement-position call or `let _ = l(..)`.**
   - A lemma call in any other position is accepted, but contributes no fact.
   - Cost if wrong: a proof written in another shape skips instead of proving. Never unsound.
5. **The `stdlib_lemma_manifest` row belongs to phase 3.** The RED table itself marks it "(phase 3)".
6. **Hover for lemma calls.** LSP hover has no refinement content today. Phase 2 adds one hover line for a call to a lemma: `lemma <name>: <P>`, plus `admitted` or `not proved`. The `uses:` note in hover is deferred to a todo, because hover has no per-site verdict channel yet.

## Review focus

The five inputs most likely to bite, with the task that pins each one:

1. A lemma that is recursive but uncertified, or that reaches its own post through `panic` or `assert false`, must never prove (Tasks 1 and 3).
2. A lemma fact must not leak out of an `if` or `match` branch, and must not be assumed when a precondition is unproved (Task 4).
3. A program with a lemma must run exactly like the same program with its lemmas removed, on every backend and with z3 absent (Task 6).
4. A lemma or assert in ordinary (non-lemma) code must keep today's behaviour exactly (Tasks 3 and 4: `assert_runtime`, `two_stage_identical`).
5. Two modules that both define a lemma named `l`: erasure must remove only the lemma, never a non-lemma `l` in another module, and the checker must resolve the call the same way (Tasks 4 and 6: `lemma_shadow`).

---

### Task 1: `@[lemma]` and the L-rules (`invalid_lemma`)

**Files:**
- Modify:
  - `lib/errors/code.ml` (adds `invalid_lemma`, `lemma_unproved`, `lemma_unproved_call`, `lemma_argument_impure`);
  - `lib/refinecheck/refine_check.ml` (`known_fn_attributes` at :7819, plus a new `check_lemmas` called from `check_module` next to the `reflect_conflict` block at about :8818);
  - `lib/refinecheck/refine_reflect.ml` (exposes a rule-filtered blocker query).
- Create:
  - `specs/lang/errors/invalid_lemma.md`;
  - test group `reflect-lemma` in `test/test_refine_lemma.ml`, registered in `test/test_refinecheck.ml`.

**Interfaces:**
- Produces:
  - `Refine_reflect.lemma_blockers : row list -> span -> (int * string) option`. It returns the first R3, R4, R5 or R7 event of a unit, ignoring R8 "returns Unit" and R4's `assert` event, and it treats a callee that is a lemma as reflected for R6.
  - `Refine_check.lemma_names : (string, A.fn_def) Hashtbl.t`, keyed by the resolved declaration name. Later tasks read it.

- [ ] **Step 1: write the failing tests.** Each is `check_src … |> expect_code "invalid_lemma"` with a rule substring:
  - `not_unit`: `@[lemma] fn l(x : Int) : Int do x end`, message contains `L1`.
  - `lemma_as_value`: `let f = cat_nil`, `L5`.
  - `l3_callee`: the body calls `noisy(0)` (`println`), `L3`.
  - `sound_lemma_panic`: `bogus` from §9.1, `L2`.
  - `sound_lemma_ih` part 1: `bad(n) : {Unit | false} = bad(n)`, `L4`.
  - `lemma_attr_conflict`: `@[lemma] @[opaque]` and `@[lemma] @[measure]`, `L5`.
  - Control `lemma_ok`: `cat_nil_left` from §4.6 has no `invalid_lemma` and no `unknown_attribute`.
- [ ] **Step 2: run them and see them fail.**
  - Command: `scripts/run-tests.sh refinecheck` (or the group filter `test_refinecheck.exe test reflect-lemma`).
  - Expected: FAIL. Today `@[lemma]` gives `unknown_attribute` and none of the codes exist.
- [ ] **Step 3: implement.**
  - Add the four codes.
  - Add `"lemma"` to `known_fn_attributes`.
  - Write `check_lemmas`:
    - L1: the declared return type is `{Unit | P}`, and `P` does not mention `_`.
    - L2: `lemma_blockers`.
    - L3: every call site of the unit resolves to a reflected unit, a lemma, a constructor or an R6 builtin.
    - L4: a recursive SCC must be certified `structural` or `metric`, read the same way as `ih_prepare`'s `certified` at :8392.
    - L5: no conflicting attribute, and no `S_value` site that names a lemma, anywhere in the module.
  - Each failure emits `invalid_lemma` with the rule number and the reason.
  - Write the error page, then seed and regenerate the corpus.
- [ ] **Step 4: run until green.**
  - Commands: `scripts/run-tests.sh refinecheck`, then `scripts/run-tests.sh errors`.
  - Expected: PASS, plus the new `invalid_lemma_1.expected`.
- [ ] **Step 5: commit.** `refine: @[lemma] and the L1-L5 rules (invalid_lemma)`.

### Task 2: closed `{Unit | P}` posts for non-recursive lemmas, and the static `assert`

**Files:**
- Modify:
  - `lib/refinecheck/obligation.ml` (adds `Assertion` to `kind` at :206, plus its `by_kind_line` and the matches in `bin/main.ml` at :852 and :884);
  - `lib/refinecheck/refine_check.ml` (`visit`'s `EBlock` loop at :4914 and its `EAssert` arm at :5668; a lemma-tail obligation in `visit_fn`);
  - `lib/refinecheck/refine_scope.ml` (`return_refine_sorted` at :865 gains a Unit arm for lemmas only, so `sg.ret` is `Some`);
  - `lib/refinecheck/refine_post.ml` (`check_fn_post_verdict_core` at :2444 skips lemmas, so the tier-2 skip at :1627 is never recorded for them).
- Create: `specs/lang/errors/lemma_unproved.md`.

**Interfaces:**
- Consumes `lemma_names` from Task 1.
- Produces:
  - `Refine_check.lemma_admitted : string -> bool`;
  - `Obligation.Assertion`;
  - a walk flag `in_lemma : string option`. When it is set, an `assert` files an `Assertion` obligation and joins `path` only if `Proved`, and a tail `()` files the lemma's post.

- [ ] **Step 1: write the failing tests.**
  - `cat_nil_left`: proved, triple (1 proved post, 0, 0).
  - `assert_static`, the §10 row: an `Assertion` skip, and the post is unproved with `lemma_unproved`. The same verdict with the assert removed.
  - `sound_assert_false`: `assert false  ()` under `{Unit | false}`. Expect an `Assertion` skip or violation, and `lemma_unproved`. It must never prove.
  - `sound_domain`: `bad` gives `lemma_unproved`; `ok()` proves.
  - `known_overflow`: `{Unit | inc(n) > n}` proves. The test name and comment say it is a known gap, D8.
  - `assert_runtime`: the same `assert` in `main` keeps today's ledger, with no `Assertion` obligation, and the fact is assumed afterwards.
  - `unit_post_ordinary`: a non-lemma `fn f() : {Unit | false} do () end` keeps today's skip.
- [ ] **Step 2: run them and see them fail.** Expected: FAIL. `cat_nil_left` skips with `unreflectable-subject` today.
- [ ] **Step 3: implement as specified in the Interfaces block.** Under `cap verified`, `lemma_unproved` escalates to an error, following the pattern at refine_post.ml:597.
- [ ] **Step 4: run until green.**
  - Commands: `scripts/run-tests.sh refinecheck`, then `scripts/oracle-base.sh refine`.
  - Expected: green tests and a monotone oracle with no moves. No corpus program has a lemma.
- [ ] **Step 5: commit.**

### Task 3: lemma calls (facts, preconditions, scope, `lemma_unproved_call`)

**Files:**
- Modify:
  - `lib/refinecheck/refine_check.ml`: the `EBlock` loop at :4912/:5051. A statement-position or `let _ =` call to an admitted lemma pushes `instantiate_ret sg args` into `path'` and `sc'` when every `Precondition` obligation at its span is `Proved`. Read them the way rule (a) does at :8376.
  - `lib/refinecheck/refine_reflect.ml`: a lemma call is `()` in `tr_case`'s `EBlock` arm (:1159) and in `site_events`' `S_unit` arm (:430). This is phase 1's `lemma_in_body` row.
- Create: `specs/lang/errors/lemma_unproved_call.md`.

**Interfaces:**
- Consumes `lemma_admitted` and `lemma_names`.
- Produces `Refine_check.lemma_fact_at : A.span -> bool`, which says whether the call at a span contributed its fact. Task 5's hover reads it.

- [ ] **Step 1: write the failing tests.**
  - `len_cat`: the lemma proves, and the call proves. Without the lemma call it skips.
  - `pre_lemma`: with `k` unknown, expect `lemma_unproved_call`, and the following `need_nn(dbl(k))` skips. Under `if k >= 0` it proves.
  - `lemma_scope`: inside the branch, proved. After the `if`, skip.
  - `sound_eq_float`: both "must not prove" cases skip, and the control proves.
  - `lemma_in_body`: `safe_len` is reflected, and `need_eq(safe_len(Cons(1, Nil)), 1)` proves.
  - `lemma_shadow`: module `A` has lemma `l`, and module `B` has a non-lemma `l` returning `{Unit | false}` via `@[assume]`. A call `B.l(..)` gives no lemma fact, and `A.l` gives its fact.
  - `two_stage_identical`: compare the stage-1 VC dump for the a1-c4 fixtures before and after this change. Identical.
- [ ] **Step 2: run them and see them fail.** Expected: FAIL. No fact is added today.
- [ ] **Step 3: implement as specified in Files.**
- [ ] **Step 4: run until green.** Run `scripts/run-tests.sh refinecheck`. Expected: PASS.
- [ ] **Step 5: commit.**

### Task 4: recursive lemmas through `ih_spans`

**Files:**
- Modify:
  - `lib/refinecheck/refine_check.ml`: `ih_prepare` at :8303 takes the pending lemmas as demand. A lemma SCC is admitted atomically, in the IH rounds, when every member's tail obligations are proved with `ih_at` set at the eligible self-call spans.
  - `lib/refinecheck/refine_post.ml`: a `check_group` hook at :2738 for lemma members that runs the Task 2 walk instead of `check_post`.

**Interfaces:**
- Consumes `ih_spans`, `ih_at` and `call_post`, unchanged.

- [ ] **Step 1: write the failing tests.**
  - `cat_nil`, `cat_assoc`, `rev_cat` and `rev_rev` from §4.6: each proved.
  - `rev_rev_short`: `lemma_unproved`, with the post skipped as `reflect-fuel`.
  - `ih_pre_unproved`: `lemma_unproved`, because no IH is available at `n = 1`.
  - `sound_lemma_ih` part 2: `bad2` with exit `n == 0` gives `lemma_unproved`. Note that the spec says `invalid_lemma`, but its certificate is `metric`-unproved, so L4 rejects it: assert `invalid_lemma` if TERM leaves it uncertified, otherwise `lemma_unproved`. Record which one in the progress note. With exit `n <= 0`, it proves.
- [ ] **Step 2: run them and see them fail.** Expected: FAIL; the recursive call gives no fact.
- [ ] **Step 3: implement.**
- [ ] **Step 4: run until green.**
  - Commands: `scripts/run-tests.sh refinecheck`; `scripts/oracle-base.sh refine`.
  - Expected: PASS, and the oracle is monotone with no moves.
- [ ] **Step 5: commit.**

### Task 5: erasure on every path, and `lemma_argument_impure`

**Files:**
- Create: `lib/desugar/lemma_erase.ml` and its `.mli` (Ruling 2), and `specs/lang/errors/lemma_argument_impure.md`.
- Modify:
  - `bin/main.ml`: after `Refine.shutdown ()` at :3993, both `desugared` and `user_only_desugared`. Also `run_test_cmd` after :2660, before `run_tests` and `run_doctests`; the doctest `parse_expr` at :2728; and `dap` after :7100.
  - `lib/repl/repl.ml`: the REPL decl path, before `eval_decl` and `register_module_decl`.
  - `js/march_browser_compile.ml` at :107 and `js/march_browser.ml` at :543.
  - `lib/refinecheck/refine_check.ml`: `lemma_argument_impure` when a lemma call argument is not a reflectable term (a variable, a literal, a constructor, or a call to a reflected unit).

**Interfaces:**
- Produces:
  - `Lemma_erase.erase_module : Ast.decl list -> Ast.decl list`;
  - `Lemma_erase.erase_expr : lemmas:Lemma_erase.env -> Ast.expr -> Ast.expr` (for REPL and doctest expressions);
  - `Lemma_erase.env_of_decls`.
- The replacement `()` is `ETuple ([], call_span)`. Lowering reads the call's recorded Unit type, which is correct.

- [ ] **Step 1: write the failing tests.**
  - `erase_runtime` (test/run_codegen or test_jit): a program prints after lemma calls. Interpreted, compiled and `--jit` output all equal the lemma-free program's output.
  - `sound_erase_ir`: for every Task 1-4 fixture, `--emit-llvm` with lemmas and with them removed textually gives byte-identical `.ll`, and identical `--dump-impl-hashes`.
  - `sound_erase_paths`:
    - the lemma's symbol is absent from `--dump-tir`;
    - a lemma body containing `assert false` never aborts on any path, including `march test`, a doctest calling the lemma, and `PATH` without z3;
    - `scripts/browser-repl-smoke.js` gets a lemma case.
  - `erase_args`: `cat_nil(noisy_list())` gives `lemma_argument_impure`. So do `lemma(same(p, q))` over the printing `Eq` (§9.1 C4) and `lemma(guarded(...))`.
  - `lemma_shadow_erase`: in the two-module program from Task 3, `B.l` still runs.
- [ ] **Step 2: run them and see them fail.** Expected: FAIL. The lemma body runs and the IR differs.
- [ ] **Step 3: implement as specified in Files and Interfaces.**
- [ ] **Step 4: run until green.**
  - Commands: `scripts/run-tests.sh refinecheck codegen test_jit errors`; `scripts/determinism-oracle.sh --corpus small`; `scripts/oracle-base.sh ir`.
  - Expected: tests PASS, determinism holds, and the ir oracle is IDENTICAL.
- [ ] **Step 5: commit.**

### Task 6: LSP

**Files:**
- Modify:
  - `bin/main.ml`: `--reflect-deps` also prints `lemma-dep <name> <post-hash> <body-hash> <admitted>` for each lemma a file calls.
  - `lsp/lib/refine_diag.ml`: `lemma_key` at :133 parses those rows, and the key includes them.
  - `lsp/lib/server.ml`: `on_req_hover` at :585 adds the lemma line from Ruling 6.

- [ ] **Step 1: write the failing tests** in `lsp/test`.
  - `lsp_lemma_invalidate`: a dependency lemma that stops proving changes the caller's key, and the caller's fact is withdrawn.
  - `lsp_lemma_hover`: hovering a lemma call shows `lemma cat_nil: cat(xs, Nil) == xs (admitted)`.
- [ ] **Step 2: run them and see them fail.** Expected: FAIL.
- [ ] **Step 3: implement.**
- [ ] **Step 4: run until green.** Run `scripts/run-tests.sh lsp`. Expected: PASS.
- [ ] **Step 5: commit.**

### Task 7: docs, oracles and the whole-branch check

- [ ] Add a "Lemmas" section to `specs/lang/refinement-types.md`, with §4.6 as its example and D8 ("Int is mathematical") repeated. Then run `scripts/gen-lang-docs.py`.
- [ ] Add a CHANGELOG `Added` bullet. Write `specs/progress/2026-11-XX-reflection-phase2-lemmas.md`, with every perturbation, the oracle results and the rulings.
- [ ] File todos:
  - `uses:` in hover;
  - lemma facts from non-statement positions (Ruling 4);
  - the stdlib manifest (phase 3).
- [ ] Run the full suite with `scripts/run-tests.sh`. Run `scripts/oracle-base.sh refine ir`: refine must be monotone with no moves, and ir must be IDENTICAL.
- [ ] Get a fresh soundness review of the whole branch on the most capable model. The brief is §9.1's (2) rows plus Rulings 2-4. Each earlier phase needed rounds of these.
