# Predicate names: resolve and print them right — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** One PR that closes four refinement todos about how a name inside a predicate is printed, resolved and warned about.

**Architecture:** All four live in the predicate front end of `lib/refinecheck/`: the printer `Refine_scope.pred_str`, the declaration-site warning walk `Refine_check.warn_predicate_decls` → `warn_predicate_ty` → `warn_predicate_expr`, and the encoder's same-short-name type table in `Refine_encode`. Task 3 threads the enclosing module's function names into the warning walk; Task 4 reuses that list. Each task is test-first and lands as its own commit on one branch.

**Tech Stack:** OCaml 5.5.1 (dune, alcotest), z3, the March compiler's `--check --refine-report-sites=all` output.

**Spec:** the four todos, which this plan argues from:
- `specs/todos/2026-11-04-refine-pred-str-drops-parens.md` (#18)
- `specs/todos/2026-10-31-reflection-encoder-gaps.md`, bullet "Predicate display-name resolution in the propagation pre-pass" (#20)
- `specs/todos/2026-10-29-predicate-vocabulary-shadows-user-functions.md` (#2; reflection design `specs/2026-10-29-refinement-reflection-design.md` fact F21, §0.12 row r3)
- `specs/todos/2026-11-03-reflect-type-name-clash-with-stdlib.md` (#8)

## Findings that shaped the plan (2026-11-06 probes)

- **#20 is already closed.** Commit 71f112f4a ("resolve every reflected call by site", review C-1/C-2) replaced name-based predicate resolution with per-span resolution (`Refine_term.pred_expr` → `g.pred_sites` → `Refine_reflect.install` → `Reflect_state.call_sym`; every reader calls `Reflect_state.resolve_site span`). The bullet was copied into the todo afterwards. Probing the pre-pass (`Refine_post.gate_unverified_posts_ih`) with a bare `dbl` inside `mod Inner` and an outer decoy `dbl` resolves to `Inner.dbl`. What is left: a regression test, deleting the bullet, and one false warning the probe found (a qualified `Inner.dbl(n)` that resolved and proved still gets `refinement_unchecked`, because `warn_predicate_expr` takes its dotted-name branch before the `resolve_site` check, `refine_check.ml` ~6613 vs ~6642).
- **#8's cause.** `size` is reported reflected, but `Refine_reflect.install`'s `poly_sort` (~2263) asks `adt_of_short_type_name "Tree"` (`refine_encode.ml` ~2271), which returns `ambiguous_adt_sentinel` because `short_name_conflated "Tree"` is true (`adt_decl_paths["M_Tree"]` holds the user's and `OrderedMap`'s). `Decline` is swallowed, `RS.register` never runs, the predicate site gets no `call_sym`, and it is filed `unreflectable-predicate`.
- **#8's sound fix is arity, not module path.** The typechecker conflates same-short-name types only at the SAME arity: a user `type Tree` (arity 0) against `OrderedMap`'s `Tree(k, v)` is a type error (`expected Tree but got Tree(Int, Int)`), while a user `type Tree(a, b)` accepts an `OrderedMap` value (`size(m.tree)` typechecks). "The current module's declaration wins" would give that value the user's sort and could prove a false fact, so same-arity names must stay a skip until the typechecker todo `2026-10-13-same-short-name-nested-types-unify` lands.
- **#8 side bug.** `conflated_param_type` (`refine_check.ml` ~4975) finds the function by bare name with a `find_map` over all decls and hits a stdlib `fn size` first, so the "Rename your type" message never shows for a user `size`.
- **#2 must not fire in the stdlib.** `stdlib/map.march` declares `fn keys` and writes `keys(_) == empty` meaning the built-in; `stdlib/list.march` declares `fn member` and writes `member(prev, elts(_))` meaning the set operator.
- **#18 is more than display.** `pred_str` output is parsed back into candidates (`Infer_vocab.candidate_of_text`) and written by `--refine-infer-apply` (`Infer_slot.respell`, ~153). Today `_ == (a + b) * 2` prints `_ == a + b * 2` and `_ == (keys(m) == empty)` prints `_ == keys(m) == empty`, which does not parse.

## Global Constraints

- Build and test from the worktree with `--root .`; never `eval $(opam env)`; never run a dune build while `scripts/run-tests.sh` runs.
- Stage files by name; never `git add -A`; never stash; no `Co-Authored-By` lines.
- In the same PR as the code: `git mv`/delete the closed todos into `specs/progress/`, one `specs/progress/2026-11-06-predicate-names.md`, a `CHANGELOG.md` bullet under `## [Unreleased]`.
- Language reference edits go in `specs/lang/`, then `scripts/gen-lang-docs.py`; commit both.
- A new diagnostic code needs `lib/errors/code.ml` (constant and both lists), a `specs/lang/errors/<code>.md` page, `scripts/seed-error-corpus.sh`, then `UPDATE_ERRORS=1 ./_build/default/test/run_errors.exe -e` and a review of `git diff test/errors/`.
- Soundness rule: a change may turn a skip into a proof only where the logic can tell the values apart; anything ambiguous stays a skip, never a proof.
- Oracles run under a private HOME: `scripts/oracle-base.sh refine types`.

## Review Focus

1. A predicate with grouping (`(_ == a || _ == b)`, `(a + b) * 2`, `(keys(m) == empty)`) must re-parse to the same tree wherever `pred_str` text is read back or written (inference candidates, `--refine-infer-apply`). Pinned in Task 1 (round-trip test through `Infer_vocab.candidate_of_text`).
2. Stdlib modules that deliberately use a built-in name they also declare (`Map.keys`, `List.member`) must get no new warning, including under `--check --stdlib-source`. Pinned in Task 3.
3. A value of a stdlib type that reaches a user type of the same short name and the same arity (`OrderedMap.Tree` into a user `Tree(a, b)`) must never be proved. Pinned in Task 4 (`leak3`).
4. A user type named like a typechecker built-in of the same arity (`type DownReason`, `type Option(a)`) stays a skip. Pinned in Task 4.
5. The shadow warning follows lexical scope: a `fn len` in an enclosing module warns, one in a sibling module does not. Pinned in Task 3.

---

### Task 0: Branch and test module

**Files:**
- Create: `test/test_refine_pred_names.ml` (empty `let suite = []` to start)
- Modify: `test/dune` (add `test_refine_pred_names` to the `modules` list of the `test_refinecheck` executable, line ~1401)
- Modify: `test/test_refinecheck.ml` (register `("pred-names", Test_refine_pred_names.suite)` beside `"reflect-unfold"`, ~line 29465)

**Interfaces:**
- Produces: `Test_refine_pred_names.suite : unit Alcotest.test_case list`. Tests use `Test_refine_unfold.run`, `expect`, `not_proved`, `has_code`, `count_code`, `gated` (open or alias `module U = Test_refine_unfold`).

- [ ] **Step 1:** `git switch -c claude/predicate-names origin/main` (already done if this file is on that branch).
- [ ] **Step 2:** Create the module and register it; `dune build --root . test/test_refinecheck.exe bin/main.exe`. Expected: builds; `./_build/default/test/test_refinecheck.exe list | grep -c pred-names` prints 0.
- [ ] **Step 3:** Commit `test: add the pred-names suite`.

---

### Task 1: `pred_str` keeps the parentheses a reparse needs (#18)

**Files:**
- Modify: `lib/refinecheck/refine_scope.ml` (`pred_str`, ~line 1)
- Test: `test/test_refine_pred_names.ml`

**Interfaces:**
- Consumes: nothing from other tasks.
- Produces: `Refine_scope.pred_str : A.expr -> string` (same signature) whose output re-parses to the input tree.

- [ ] **Step 1: Write the failing tests.** A helper `pred_of (src : string) : March_ast.Ast.expr` parses `mod P do fn f(a : Int, b : Int, c : Int, low : Int, high : Int, m : Map(Int, Int)) : {Int | <src>} do 0 end end` with `March_parser.Parse.module_` and returns the `TyRefine` predicate of the return type (a `{Bool | …}` return for the Boolean rows). Tests:

```ocaml
test "pred_str prints the parentheses a reparse needs" (fun () ->
  List.iter (fun (src, want) -> Alcotest.(check string) src want (RS.pred_str (pred_of src)))
    [ ("_ <= a && _ <= b && (_ == a || _ == b)", "_ <= a && _ <= b && (_ == a || _ == b)");
      ("high < low || (_ >= low && _ <= high)", "high < low || _ >= low && _ <= high");
      ("_ == (a + b) * 2", "_ == (a + b) * 2");
      ("_ == a - (b - c)", "_ == a - (b - c)");
      ("_ == a - b - c", "_ == a - b - c");
      ("_ == a * (b / c)", "_ == a * (b / c)");
      ("!(_ > 0 && _ < 9)", "!(_ > 0 && _ < 9)");
      ("_ == -(a + b)", "_ == -(a + b)") ]);
test "a Boolean equality of a comparison keeps its parentheses (Map.is_empty)" (fun () ->
  Alcotest.(check string) "is_empty" "_ == (keys(m) == empty)" (RS.pred_str (pred_of_bool "_ == (keys(m) == empty)")));
test "every printed predicate re-parses to the same text" (fun () ->
  (* print(parse(print(parse s))) = print(parse s), over the rows above and
     `(_ || a) && b`, `_ == (a == b)`, `a - b + c`, `a - (b + c)` *) ...);
test "an inference candidate read back from the text keeps its grouping" (fun () ->
  match IV.candidate_of_text (RS.pred_str (pred_of "_ == (a + b) * 2")) with
  | Some c -> Alcotest.(check string) "round trip" "_ == (a + b) * 2" c.PI.c_text
  | None -> Alcotest.fail "not a candidate");
gated "min_int's report row prints its disjunction in parentheses" (fun () ->
  (* march --check --stdlib-source --refine-report-sites=all stdlib/math.march, from the repo root *)
  ... check the min_int postcondition row contains "_ <= a && _ <= b && (_ == a || _ == b)");
```

`pred_of_bool` is `pred_of` with a `Bool` base. If `candidate_of_text` is not exported, expose it in `infer_vocab.mli` (or use the exported caller of it; do not copy its body into the test).

- [ ] **Step 2:** `dune build --root . test/test_refinecheck.exe bin/main.exe && MARCH_BIN=$PWD/_build/default/bin/main.exe ./_build/default/test/test_refinecheck.exe test pred-names`. Expected: FAIL; the first rows print `… && _ == a || _ == b`, `_ == a + b * 2`, `_ == a - b - c` for `a - (b - c)`.
- [ ] **Step 3: Implement minimal parentheses in `pred_str`.** Precedence follows `lib/parser/parser.mly` (`expr_or` … `expr_unary`): `||` 1, `&&` 2, comparisons (`== != < <= > >=`) 3 and non-associative, `+ - +. -. ++` 4, `* / % *. /.` 5, all left-associative; unary `!`/`-` and application bind tightest. A binary child is parenthesised when its level is lower than the parent's, or equal to it as the RIGHT operand, or when parent and child are both comparisons. The `!` and `-` arms parenthesise any binary operand (extend the existing `!` arm's operator list with the float operators). Every other arm is unchanged; `ERefineMsg` stays transparent.
- [ ] **Step 4:** Rerun Step 2's command. Expected: PASS.
- [ ] **Step 5: Re-pin what printed the old text.**
  - `UPDATE_ERRORS=1 ./_build/default/test/run_errors.exe -e`; `git diff test/errors/` may only add parentheses.
  - `UPDATE_SNAPSHOTS=1 ./_build/default/test/test_refinecheck.exe test audit-baseline`; same rule for `git diff test/refine_audit/`.
  - `scripts/run-tests.sh -q refinecheck test_refinecheck`; a failing assertion that pinned the paren-less text is updated to the parenthesised one. Any other failure is a bug in Step 3.
- [ ] **Step 6: Oracle.** `scripts/oracle-base.sh refine`. Expected: CHANGED only on lines that differ by inserted parentheses. Check it mechanically: in the manifests the oracle prints, `diff <(tr -d '()' < base) <(tr -d '()' < new)` is empty.
- [ ] **Step 7:** Commit `refine: pred_str keeps the parentheses a reparse needs`.

---

### Task 2: Pin #20 as closed; no false warning on a resolved qualified call

**Files:**
- Modify: `lib/refinecheck/refine_check.ml` (`warn_predicate_expr`, the dotted-name branch ~6613 and the `resolve_site` arm ~6642)
- Modify: `specs/todos/2026-10-31-reflection-encoder-gaps.md` (delete the "Predicate display-name resolution" bullet)
- Create: `specs/todos/2026-11-06-predicate-call-not-unfolded-from-body.md`
- Test: `test/test_refine_pred_names.ml`

**Interfaces:**
- Consumes: nothing.
- Produces: nothing new.

- [ ] **Step 1: Write the tests.**
  - `"a bare predicate call resolves in its own module, also in the postcondition pre-pass"` (regression for #20). Program: `mod G` with `needs IO.Console`, an outer decoy `fn dbl(x : Int) : Int do x + 1 end`, `mod Inner` with `fn dbl(x : Int) : Int do x + x end` and `fn twice(c : Cap(IO.Console), n : Int) : {Int | _ == dbl(n)} do println("hi")` / `dbl(n) end`, then `fn need6(x : {Int | _ == 6})`, `fn need4(x : {Int | _ == 4})`, `fn a(c) … need6(Inner.twice(c, 3))`, `fn b(c) … need4(Inner.twice(c, 3))`. Assert: `twice`'s postcondition `proved`; `need6` `proved` with `uses: Inner.dbl`; `need4` `violated`.
  - `"a qualified predicate call that resolved gets no unchecked warning"`. The same `Inner` without the decoy, the postcondition written `{Int | _ == Inner.dbl(n)}`, one caller `need6(Inner.twice(c, 3))`. Assert `need6` proved and `count_code out "refinement_unchecked" = 0`.
  - Control: `"a qualified predicate call that does not resolve still warns"`: `{Int | _ == Nowhere.dbl(n)}` keeps a `refinement_unchecked` warning.
- [ ] **Step 2:** Run the suite. Expected: the first test PASSES (it pins the closed gap: that is its job), the second FAILS with one `refinement_unchecked`, the control PASSES.
- [ ] **Step 3: Implement.** In `warn_predicate_expr`'s generic `EApp (EVar f, …)` arm, return before the dotted-name branch when `!Reflect_state.active && Reflect_state.resolve_site span <> None`; the existing later `resolve_site` arm then becomes dead for that case; leave it, it still covers bare names that reach it.
- [ ] **Step 4:** Run the suite. Expected: PASS.
- [ ] **Step 5: Specs.** Delete the bullet, and add to the file's parenthesised closed-items paragraph at the top: "predicate display-name resolution was closed by 71f112f4a (resolution by call site) and is pinned by the `pred-names` suite." File the new todo `2026-11-06-predicate-call-not-unfolded-from-body.md` (`[P3]`): `fn twice(n : Int) : {Int | _ == dbl(n)} do n + n end` is `skip unreflectable-predicate` even at top level, while the body `dbl(n)` proves; stage 2 does not unfold a predicate-side call the body does not mention. Include the program.
- [ ] **Step 6:** Commit `refine: no unchecked warning on a resolved qualified predicate call; pin #20 closed`.

---

### Task 3: Warn when a predicate's built-in name shadows the user's function (#2)

**Files:**
- Modify: `lib/errors/code.ml` (new `predicate_vocabulary_shadowed`, added to the all-codes list and the refinement category list next to `predicate_eq_structural`)
- Modify: `lib/refinecheck/refine_check.ml` (`warn_predicate_decls` ~7041, `warn_predicate_ty` ~6691, `warn_predicate_expr` ~6578)
- Create: `specs/lang/errors/predicate_vocabulary_shadowed.md` (its first ```march block is `test/refine/reflect/r3_shadow.march`'s program)
- Modify: `specs/lang/refinement-types.md` (the Measures / vocabulary paragraph: one sentence on the warning)
- Generated: `docs/errors/predicate_vocabulary_shadowed.md`, `docs/refinement-types.md` (`scripts/gen-lang-docs.py`), `test/errors/predicate_vocabulary_shadowed_1.*` (`scripts/seed-error-corpus.sh`, `UPDATE_ERRORS=1`)
- Test: `test/test_refine_pred_names.ml`

**Interfaces:**
- Consumes: nothing.
- Produces: an in-scope function list threaded through the walk, used again by Task 4:
  - `type scope_fn = { sf_name : string; sf_qualified : string; sf_span : A.span }` in `refine_check.ml`
  - `warn_predicate_decls : Err.ctx -> strict:bool -> ?in_scope:scope_fn list -> A.decl list -> unit` — `in_scope` is the functions declared directly in each enclosing module, innermost first; recursing into `DMod (name, …)` prepends that module's own top-level `DFn`s (qualified with the module path)
  - `warn_predicate_ty ?abstract_refs ?(in_scope = []) …` and `warn_predicate_expr ?abstract_refs ?(in_scope = []) …` pass it down unchanged

- [ ] **Step 1: Write the failing tests.**
  - `"r3: a user len shadowed by the predicate's built-in len is warned"`: the `r3_shadow.march` program. Assert `count_code out "predicate_vocabulary_shadowed" = 1`; the warning is at line 5 (the predicate) and its text contains ``means the built-in length measure`` and ``Shadow.len`` and `(line 3)`; `need` at line 9 is still `proved` (the verdict does not change; F21 is pinned, not altered).
  - `"a len declared in an enclosing module warns inside a nested one"`: `fn len` in the outer module, the predicate in `mod Inner`. Expect 1.
  - `"a len in a sibling module does not warn"`: `fn len` in `mod Other`, the predicate in `mod Inner`. Expect 0.
  - `"an elts, keys or is_<Ctor> function warns too"`: three small programs (`fn elts(xs : List(Int)) : Int`, `fn keys(m : Map(Int, Int)) : Int`, `type T = A | B` with `fn is_A(t : T) : Bool` and a predicate `is_A(_)`). Expect 1 each.
  - `"a set operator the user also declares does not warn when well-formed"`: `fn member(x : Int, xs : List(Int)) : Bool` and a predicate `member(1, elts(_))`. Expect 0 (well-formed set use is the set operator; a malformed one already warns `refinement_unchecked`).
  - `"the stdlib's deliberate uses get no warning"`: run `--check --stdlib-source` on `stdlib/map.march`, `stdlib/list.march` and `stdlib/set.march` from the repo root. Expect 0 each.
- [ ] **Step 2:** Run the suite. Expected: the four positive tests FAIL with count 0; the negative ones PASS.
- [ ] **Step 3: Implement.**
  - Thread `in_scope` as in the Interfaces block.
  - In `warn_predicate_expr`, before the existing generic arm: for `A.EApp (A.EVar { txt = f; _ }, args, span)` with `f = "len" || f = "elts" || f = "keys" || Refine_encode.ctor_of_tester f <> None`, find the first `sf` in `in_scope` with `sf.sf_name = f` whose `sf.sf_span.file` is user code: `not (Typecheck_builtins.file_under_stdlib_root file) && not (List.mem file !Typecheck_builtins.stdlib_source_files)`. If found, `Err.warning ~code:Err.Code.predicate_vocabulary_shadowed errctx ~span` with exactly:
    "In a refinement predicate `%s` means the built-in %s, not your function `%s` (line %d): a predicate cannot call a function whose name is predicate vocabulary. Rename your function to use it in a predicate."
    where the second `%s` is `"length measure"` for `len`, `"set of elements"` for `elts`, `"set of keys"` for `keys`, and `"constructor test"` for a tester. Then continue into `args` as the other arms do (no `List.iter go args` duplication: fall through to the existing arm's recursion).
  - Do not touch `Refine_audit`: this warning is not an unchecked predicate (the predicate is checked, with the built-in meaning), so the audit's categories do not change.
- [ ] **Step 4:** Run the suite. Expected: PASS.
- [ ] **Step 5: Docs and corpus.** Write `specs/lang/errors/predicate_vocabulary_shadowed.md` in the shape of `specs/lang/errors/predicate_eq_structural.md` (what it means, the program, the fix: rename). One sentence in `specs/lang/refinement-types.md` where the vocabulary is listed. Run `scripts/gen-lang-docs.py`, `scripts/seed-error-corpus.sh`, `UPDATE_ERRORS=1 ./_build/default/test/run_errors.exe -e`; `git diff test/errors/` adds only `predicate_vocabulary_shadowed_1.*`. `./_build/default/test/run_errors.exe -e` passes (it lints messages for compiler-internal names).
- [ ] **Step 6:** Commit `refine: warn when predicate vocabulary shadows the user's function`.

---

### Task 4: A user type sharing a stdlib type's short name, at another arity, is usable (#8)

**Files:**
- Modify: `lib/refinecheck/refine_encode.ml` (`short_name_conflated` ~1782, `conflated_declarants`, `adt_canonical` ~1810, `adt_sort_name` ~1833, `finalize_adt_canonical`, `finalize_ctor_names` ~2014, `adt_of_short_type_name` ~2265, `adt_of_type_name`, `adt_of_tc_ty` ~2230)
- Modify: `lib/refinecheck/refine_reflect.ml` (`poly_sort` ~1645 and its callers at ~2263, ~2355)
- Modify: `lib/refinecheck/refine_scope.ml` (`refined_param_ty` callers of `adt_sort_name` ~894, ~917, ~1146)
- Modify: `lib/refinecheck/refine_check.ml` (`conflated_param_type` ~4975, its caller in `warn_predicate_expr`)
- Test: `test/test_refine_pred_names.ml`

**Interfaces:**
- Consumes: Task 3's `in_scope : scope_fn list` in `warn_predicate_expr`.
- Produces:
  - `Refine_encode.short_name_conflated : ?arity:int -> string -> bool`. With `~arity:n` only declarants of arity `n` count (each entry's arity from the recorded datatype; a typechecker built-in counts at its `Typecheck_builtins.builtin_types` arity; a built-in name with no recorded arity counts at every arity). Without `?arity`, today's answer.
  - `Refine_encode.adt_sort_name : ?arity:int -> string -> string` and `adt_of_type_name : ?arity:int -> string -> …` (same results as today without `?arity`); `adt_canonical` keyed by `(bare, arity)`.
  - Every caller that has the type's arguments in hand passes `~arity:(List.length args)`.
  - `conflated_param_type : ?in_scope:scope_fn list -> string -> (string * string list) option`, searching `in_scope` first, then user-file declarations, then any.

- [ ] **Step 1: Write the failing tests** (each program inline in the test file):
  - `"a user Tree beside OrderedMap's Tree(k, v) is usable in a predicate"`: `mod TreeUser` with `type Tree = Leaf | Node(Tree, Int, Tree)`, `fn size(t : Tree) : Int` (structural recursion), `fn need_one(t : {Tree | size(_) == 1})`, `main` calls `need_one(Node(Leaf, 5, Leaf))`. Expect `need_one` at line 10 `proved` with `uses: size`.
  - The same with constructors `Lf`/`Nd` (no constructor shares a name with OrderedMap's): `proved`.
  - `"…and a wrong size is a violation"`: `need_one(Node(Node(Leaf, 1, Leaf), 5, Leaf))` → `violated`.
  - `"a user type Array (arity 0) beside the built-in Array(a)"` and `"a user type Option (arity 0)"`: `proved`.
  - Soundness controls, each `not_proved`:
    - `leak3`: `type Tree(a, b) = Leaf | Node(Tree(a, b), a, Tree(a, b))`, `fn size(t : Tree(a, b))`, `need_one(t : {Tree(Int, Int) | size(_) == 1})`, `main` passes `m.tree` of `OrderedMap.put(OrderedMap.new(fn (a, b) -> a - b), 1, 2)`.
    - `drleak`: `type DownReason = Lf | Nd(DownReason, Int, DownReason)`, `need_one(Normal)`.
    - `optleak`: `type Option(a) = Nope | Yep(a)`, `fn cnt(t : Option(Int))`, `need_one(List.head_opt([1])) + need_one(Yep(3))` (both rows).
  - Still type errors (exit 1, no change): a user arity-0 `Tree` given an `OrderedMap` tree; `Tree` with the wrong number of type arguments.
  - `"the rename message names the user's own function"`: `leak3` again; the warning text contains "has the same name as a type declared in" (today: "is not a measure", because a stdlib `fn size` is found first).
- [ ] **Step 2:** Run the suite. Expected: the five `proved`/`violated` tests FAIL (`skip:unreflectable-predicate`); the controls PASS; the rename-message test FAILS.
- [ ] **Step 3: Implement** per the Interfaces block. `finalize_ctor_names` marks a key ambiguous only when another declarant has the same short name AND the same arity. `adt_of_short_type_name ?arity` returns the sentinel only for a same-arity conflict and otherwise the declarant of that arity. `ctor_decls`/`unique_ctor` are unchanged: an untyped constructor site that two datatypes declare still declines, so the two never share constructors in the logic.
- [ ] **Step 4:** Run the suite. Expected: PASS.
- [ ] **Step 5: Wider checks.** `scripts/run-tests.sh refinecheck test_refinecheck`; `scripts/oracle-base.sh refine types`. Expected: types IDENTICAL; refine CHANGED only by Task 1's parentheses plus rows that move skip → proved/violated in fixtures with a same-name, different-arity user type. List every such row in the progress note; none may move to `proved` for a same-arity name.
- [ ] **Step 6:** Commit `refine: tell same-named types apart by arity`.

---

### Task 5: Specs, changelog, full verification, PR

**Files:**
- Move: `specs/todos/2026-11-04-refine-pred-str-drops-parens.md`, `specs/todos/2026-10-29-predicate-vocabulary-shadows-user-functions.md`, `specs/todos/2026-11-03-reflect-type-name-clash-with-stdlib.md` → `git rm` (content summarised in the progress note)
- Create: `specs/progress/2026-11-06-predicate-names.md` (what changed per task, the probes' findings above, the verification table)
- Modify: `specs/todos/2026-11-04-stdlib-lemma-sweep-s2-s3.md` (S3's qualified `List.is_empty` was blocked on the type-name todo: say only same-arity clashes remain)
- Modify: `specs/todos/2026-10-13-same-short-name-nested-types-unify.md` (one line: the checker now separates different arities; same arity waits on this todo)
- Modify: `CHANGELOG.md` (`### Fixed`: report predicates keep their parentheses; a user type named like a stdlib type of another arity works in predicates; no false "not checked" warning on a qualified call that is checked. `### Added`: the `predicate_vocabulary_shadowed` warning)

- [ ] **Step 1:** Write the specs and changelog.
- [ ] **Step 2:** `scripts/affected.sh --run --full > /tmp/... 2>&1` (nothing else building meanwhile). Expected: "affected: all selected steps passed".
- [ ] **Step 3:** CI's conformance ceiling: `./_build/default/bin/main.exe --check --stdlib-source --refine-report stdlib/list.march` from the repo root under a private HOME; the `user + stdlib` skipped count must not exceed `baseline=` in `.github/workflows/ci.yml` (it can only drop).
- [ ] **Step 4:** `scripts/check-docs.sh` passes (doc-lint, generated `docs/` chapters fresh).
- [ ] **Step 5:** Commit `docs: predicate names — progress note, changelog, todos`; push over HTTPS (`git push https://github.com/march-language/march.git claude/predicate-names`); open the PR with the verification table.
