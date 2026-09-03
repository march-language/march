# Refinement Precision: `let` Equalities and Nested-Pattern Facts Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Derive two facts the checker never derives today: the value of a `let` with a literal or arithmetic right-hand side, and the constructor of a nested pattern binder that a previous arm's refutable sub-pattern excludes.

**Architecture:** Both facts are pushed as ordinary PATH facts, which is a deliberate simplification of the design (recorded there). A `let n = rhs` with a reflectable `rhs` pushes `(n == rhs, positive)` onto `path`; the path translator already reflects arithmetic over variables, `path_shadow` already retires it when `n` or a mentioned name rebinds, and it flows through `push_user` so `Undecided.diagnose` sees it. A later arm `C(..., t, ...)` following an unguarded arm `C(..., D, ...)` with nullary `D` at the same index pushes `(is_D(t), negated)`, which `path_resolve_tester` already bridges to `len` for lists. No new `call_ctx` field, no selector aliasing.

**Tech Stack:** OCaml 5.3.0, dune, Z3 via `March_refine.Solver`, Alcotest.

## Global Constraints

- Opam switch `march`; NEVER `eval $(opam env ...)`. Nested worktree: EVERY dune command needs `--root .`.
- No false positives. A new path fact must be true at every program point where it is live; the shadow rule is what makes it live only there.
- Every obligation that moves must move to `proved` or `violated`. A skip changing bucket is a bug.
- Assert on message TEXT where a message is involved; assert on the ledger for verdicts.
- Test discipline: ONE process, foreground, `rm -rf .march/cas/vc` first, `pgrep` clean. z3 installed; `[OK]` not `[SKIP]`.
- Never `git stash`; never `git add -A`; stage by name; no attribution trailers.
- Corpus payoff is small (one site for the arm fact). Do not oversell it in the CHANGELOG.

---

### Task 1: `let` equalities as path facts

**Files:**
- Modify: `lib/refinecheck/refine_check.ml:232-236` (the block fold's `path'` arm)
- Modify: `lib/refinecheck/refine_scope.ml` (a shape predicate beside `launder`)
- Test: `test/test_refinecheck.ml`, a new group `let-equality`

**Interfaces:**
- Produces: `Refine_scope.let_equality_rhs : A.expr -> bool`, true for the shapes admitted (integer literal; `+`, `-` over admitted shapes and bare variables; `*` with one integer-literal operand). No `if`, no calls, no floats.

- [ ] **Step 1: Write the failing tests**

```ocaml
let let_equality_suite =
  [ (* The literal case: identical verdict to passing the literal directly. *)
    gated "a let-bound literal into a refined parameter is a definite violation"
      (fun () ->
        Alcotest.(check bool) "violated" true
          (has_refine_error_d
             {|mod LE1 do
  fn pos(n : {Int | _ > 0}) : Int do n end
  fn go(xs : List(Int)) : Int do
    let n = 0
    pos(n)
  end
end|}));

    (* Arithmetic over a guarded variable proves. *)
    gated "a let-bound arithmetic expression carries the guard on its operands"
      (fun () ->
        let proved, skipped =
          ledger_counts
            {|mod LE2 do
  fn pos(n : {Int | _ > 0}) : Int do n end
  fn go(k : Int) : Int do
    if k >= 0 do
      let n = k + 1
      pos(n)
    else 0 end
  end
end|}
        in
        Alcotest.(check (pair int int)) "proved" (1, 0) (proved, skipped));

    (* Rebinding an operand retires the equality: the obligation must NOT be
       proved from a stale `n == k + 1`.  Silence-shaped, so it needs the
       positive case above as its control. *)
    gated "rebinding a mentioned name retires the let equality"
      (fun () ->
        let proved, _ =
          ledger_counts
            {|mod LE3 do
  fn pos(n : {Int | _ > 0}) : Int do n end
  fn dec(k : Int) : Int do k - 10 end
  fn go(k : Int) : Int do
    if k >= 0 do
      let n = k + 1
      let k = dec(k)
      pos(n)
    else 0 end
  end
end|}
        in
        Alcotest.(check int) "not proved from a stale equality" 0 proved) ]
```

Register the group next to the others at the bottom of the file.

- [ ] **Step 2: Run to verify LE1 and LE2 fail**

```bash
rm -rf .march/cas/vc
dune build --root . test/test_refinecheck.exe && ./_build/default/test/test_refinecheck.exe test let-equality
```

Expected: LE1 fails (today it is an undecided hint, not an error), LE2 fails (`(0, 1)`), LE3 passes already (it is the guard).

- [ ] **Step 3: Admit the shapes**

In `refine_scope.ml` beside `launder`:

```ocaml
(* Right-hand sides a `let` may turn into the path fact `n == rhs`: pure,
   deterministic, and inside the linear fragment the path translator already
   reflects.  Calls are excluded (a refined return is handled by
   [scope_add_binding]; an unrefined one carries no fact); `if` is excluded
   (its encoding is a separate decision); floats are excluded (symbolic float
   arithmetic does not reflect). *)
let rec let_equality_rhs (e : A.expr) : bool =
  match e with
  | A.ELit (A.LitInt _, _) -> true
  | A.EVar _ -> true
  | A.EApp (A.EVar { A.txt = ("+" | "-"); _ }, [ a; b ], _) ->
    let_equality_rhs a && let_equality_rhs b
  | A.EApp (A.EVar { A.txt = "*"; _ }, [ a; b ], _) ->
    (match a, b with
     | A.ELit (A.LitInt _, _), _ -> let_equality_rhs b
     | _, A.ELit (A.LitInt _, _) -> let_equality_rhs a
     | _ -> false)
  | _ -> false
```

Confirm the AST spelling of the operators and of `LitInt` against `lib/ast/ast.ml` and against how `smt_of` in `refine_scope.ml:131-147` matches `+`/`-`/`*`; use exactly those constructors. A bare `A.EVar` right-hand side is admitted so `let m = n` carries `m == n`.

- [ ] **Step 4: Push the fact**

In `refine_check.ml`'s block fold, the `path'` arm currently only shadows:

```ocaml
           let path' =
             match e with
             | A.ELet (b, _) ->
               let names = pat_binders b.A.bind_pat in
               let path = path_shadow path names in
               (match b.A.bind_pat, b.A.bind_expr with
                | A.PatVar n, rhs when let_equality_rhs rhs ->
                  let sp = n.A.span in
                  let eq =
                    A.EApp
                      ( A.EVar { A.txt = "=="; A.span = sp }
                      , [ A.EVar { A.txt = n.A.txt; A.span = sp }; rhs ]
                      , sp )
                  in
                  (eq, false) :: path
                | _ -> path)
             | _ -> path_shadow path ... (* keep the existing non-let arms exactly *)
           in
```

Keep the existing shadowing for every other binding construct untouched. Confirm `==` is the comparison spelling `smt_of` maps to `Smt.Eq` (grep `"=="` in `refine_scope.ml`), and that path facts are translated with a `resolve_var` that maps a bare name to `Const name` (`path_resolve_var`, `refine_call.ml` ~1947-1954), so `k + 1` reflects with `k` resolvable. The fact is pushed positive (`false` = not negated).

**Correction (plan-2 whole-plan review).** The push above is unsound as
written for a SELF-REFERENTIAL right-hand side: `let k = k - 100` pushes
`k == k - 100` with both `k`s resolving to one SMT constant, which is
unsatisfiable and proves every downstream obligation; `let k = k * 2` forces
`k = 0` and rejects a correct program. The shipped push is guarded with
`not (expr_mentions names rhs)`, with fixtures for both shapes. The bare
`A.EVar` right-hand side is also DROPPED from `let_equality_rhs`: an alias of
an ADT-typed name reflects at the scalar sort while its tester facts are at
the datatype sort, and the sort-conflict gate then drops the whole VC,
including unrelated obligations; the alias carried no exclusion fact anyway.

- [ ] **Step 5: Run, mutation, commit**

All three `[OK]`. Mutation: change the push to `path` (drop the fact); LE1 and LE2 redden; LE3 stays green. Restore.

```bash
git add lib/refinecheck/refine_scope.ml lib/refinecheck/refine_check.ml test/test_refinecheck.ml
git commit -m "refine: carry a let's literal or arithmetic value as a path equality"
```

---

### Task 2: Nested-pattern exclusion over the binder

**Files:**
- Modify: `lib/refinecheck/refine_check.ml:427-444` (the arm-exclusion fold) and `refine_scope.ml:615-626` (`arm_excludes_tag`)
- Test: `test/test_refinecheck.ml`, a new group `arm-exclusion-nested`

**Interfaces:**
- Produces: `Refine_scope.arm_excludes_nested : A.branch -> (string * int * string) option` returning `(ctor, index, sub_ctor)` when the branch is unguarded, its head is `ctor`, every sub-pattern is irrefutable except exactly one at `index` which is a nullary `PatCon sub_ctor`.

- [ ] **Step 1: Write the failing tests**

```ocaml
let arm_exclusion_nested_suite =
  [ (* The flagship: List.last's own shape.  Arm 2 excludes a Nil tail, so in
       arm 3 the binder `t` is a Cons and `len(t) > 0`. *)
    gated "a refutable sibling sub-pattern gives the later binder its tag"
      (fun () ->
        let proved, skipped =
          ledger_counts
            {|mod AE1 do
  fn last(xs : {List(Int) | len(_) > 0}) : Int do
    match xs do
    Nil          -> panic("empty")
    Cons(x, Nil) -> x
    Cons(_, t)   -> last(t)
    end
  end
end|}
        in
        Alcotest.(check (pair int int)) "recursive call proved" (1, 0) (proved, skipped));

    (* A GUARDED sibling licenses nothing: it can fail with the tag matching. *)
    gated "a guarded sibling arm yields no exclusion" (fun () ->
        let proved, _ =
          ledger_counts
            {|mod AE2 do
  fn last(xs : {List(Int) | len(_) > 0}) : Int do
    match xs do
    Nil                        -> panic("empty")
    Cons(x, Nil) when x > 0    -> x
    Cons(_, t)                 -> last(t)
    end
  end
end|}
        in
        Alcotest.(check int) "not proved" 0 proved);

    (* Two levels of nesting are out of scope and must stay silent. *)
    gated "a two-level sub-pattern yields no exclusion" (fun () ->
        let proved, _ =
          ledger_counts
            {|mod AE3 do
  fn f(xs : {List(Int) | len(_) > 0}) : Int do
    match xs do
    Nil                  -> panic("empty")
    Cons(x, Cons(y, Nil)) -> x + y
    Cons(_, t)           -> f(t)
    end
  end
end|}
        in
        Alcotest.(check int) "not proved" 0 proved) ]
```

Check the guard syntax (`when`) against `specs/lang/surface-syntax.md` before relying on AE2.

**Correction (Task 2 review).** As written above, AE2 and AE3 assert only
`proved = 0`. That is an inert guard for AE3: removing the nullary
requirement makes the mutant push `not is_Cons(t)`, which becomes
`len(t) = 0`, false, and the compiler reports a spurious VIOLATED, which a
`proved`-only assertion discards. The shipped tests assert the whole ledger,
`(proved, skipped) = (0, 1)` and `violated = 0`, and AE3 was mutation-tested
against exactly that mutant. A silence guard for a feature that can produce a
false positive must assert every verdict that a false positive can take.

- [ ] **Step 2: Run to verify AE1 fails**

Expected: AE1 `(0, 1)` against `(1, 0)`; AE2 and AE3 pass already (silence guards).

- [ ] **Step 3: The nested-exclusion predicate**

`refine_scope.ml`, beside `arm_excludes_tag`:

```ocaml
(* [Some (ctor, i, d)] when reaching a LATER arm with head [ctor] implies
   that its binder at field [i] is not [d]: the earlier arm is unguarded, has
   head [ctor], and is irrefutable everywhere except a nullary constructor
   [d] at exactly one position.  One level only, nullary only: that is the
   `Cons(x, Nil)` shape, and it is the only shape whose negation is a single
   tester over a single binder. *)
let arm_excludes_nested (br : A.branch) : (string * int * string) option =
  match br.A.branch_pat, br.A.branch_guard with
  | A.PatCon (ctor, subs), None ->
    let refutable =
      List.mapi (fun i p -> (i, p)) subs
      |> List.filter (fun (_, p) -> not (irrefutable_pat p))
    in
    (match refutable with
     | [ (i, A.PatCon (d, [])) ] -> Some (ctor.A.txt, i, d.A.txt)
     | _ -> None)
  | _ -> None
```

- [ ] **Step 4: Push the fact over the binder**

In the arm-exclusion fold at `refine_check.ml:427-444`, after the existing per-`prev` match, add a second derivation for the CURRENT arm's binders. The current arm's pattern is in scope as the branch being visited (`br.A.branch_pat`); when it is `A.PatCon (cur, cur_subs)`:

```ocaml
                (match arm_excludes_nested prev, br.A.branch_pat with
                 | Some (ctor, i, d), A.PatCon (cur, cur_subs)
                   when cur.A.txt = ctor && sort_of_ctor d <> None ->
                   (match List.nth_opt cur_subs i with
                    | Some (A.PatVar t) ->
                      let sp = t.A.span in
                      let tester =
                        A.EApp
                          ( A.EVar { A.txt = "is_" ^ d; A.span = sp }
                          , [ A.EVar { A.txt = t.A.txt; A.span = sp } ]
                          , sp )
                      in
                      (tester, true) :: p
                    | _ -> p)
                 | _ -> p)
```

`(tester, true)` is the NEGATED polarity, matching how the existing exclusion pushes `not is_ctor(s)`. This must be pushed AFTER the arm's binders have been shadowed (the existing order at `:311-329`), since `t` is new in this arm. Confirm `path_resolve_tester` receives a bare `A.EVar t` here, which is the case it already handles for `List`.

- [ ] **Step 5: Run, mutation, real file, commit**

All three `[OK]`. Mutation: make `arm_excludes_nested` return `None` and AE1 reddens. Then build `bin/main.exe`, clear both caches, `--check --refine-report stdlib/list.march`: the `user code` line's skipped count drops by one and `proved` rises by one; the line-128 hint is gone. Paste both.

```bash
git add lib/refinecheck/refine_scope.ml lib/refinecheck/refine_check.ml test/test_refinecheck.ml
git commit -m "refine: a refutable sibling sub-pattern gives a later arm's binder its tag"
```

---

### Task 3: Measure, oracle, record

**Files:**
- Modify: `CHANGELOG.md` (`### Changed`), `specs/2026-09-02-refinement-precision-lets-and-arms-design.md` (status)
- Move: `specs/todos/2026-09-02-refinement-precision-lets-and-arms.md` to `specs/progress/`

- [ ] **Step 1: Corpus sweep, before and after**

Baseline compiler from the merge-base with `origin/main` in a scratchpad worktree, private `HOME`, caches cleared once per sweep, section-aware aggregation (the `user code` and `user + stdlib` blocks share a line format; sum them separately). Table per bucket. Every moved obligation must be `proved` or `violated`; list each with file:line.

- [ ] **Step 2: Oracle with RED proof, full suite, CI checks**

As in the previous plan: RED-proof first, classify every moved line as "newly proved", "newly violated", or unexplained. `scripts/run-tests.sh` full; `@types-check --force` and `@grammar-check --force` with non-zero logs; `check-docs.sh`. Cold `--check` on a trivial file against the baseline compiler.

- [ ] **Step 3: Record**

CHANGELOG `### Changed`, two bullets, plain: a `let` with a literal or arithmetic right-hand side now carries its value into refinement checking; a binder in a constructor pattern now inherits the constructor a previous arm's sub-pattern excluded. State the one corpus site. Move the todo to `specs/progress/` with the tables, the oracle classification, and the two deviations from the design (path facts instead of a channel; binder-level exclusion instead of selector aliasing). Set the design status to landed.

```bash
git add CHANGELOG.md specs/progress/2026-09-02-refinement-precision-lets-and-arms.md specs/2026-09-02-refinement-precision-lets-and-arms-design.md
git commit -m "docs: record let equalities and nested-pattern exclusions"
```
