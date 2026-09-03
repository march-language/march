# `unreflectable-predicate` Attribution Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Stop blaming the predicate for a subject that failed to reflect: reflect arithmetic actuals, file a failed scalar subject as `unreflectable-subject` naming the actual, and name the failing sub-expression when a predicate genuinely does not reflect.

**Architecture:** Three independent parts. (1) `reflect_scalar` gains an operator arm ahead of the named-call dispatch so `n - 1` reflects through the same scope as `n`. (2) `check_call` files `Unreflectable_subject` for a scalar actual whose reflection failed, before ever reflecting the predicate; the reason gains a string payload rendered in `reason_detail`. (3) A new `smt_of_r` returns the innermost failing sub-expression; `smt_of` becomes a wrapper so 18 call sites are untouched, and only the two goal sites switch.

**Tech Stack:** OCaml 5.3.0, dune, Z3 via `March_refine.Solver`, Alcotest.

## Global Constraints

- Opam switch `march`; NEVER `eval $(opam env ...)`. Nested worktree: `--root .` on every dune command.
- Slugs are frozen: `unreflectable-predicate` and `unreflectable-subject` keep their spellings. Payloads ride in `reason_detail` only (the Task 1 rule of the 2026-09-01 project). `--refine-report` groups by `reason_name`, so a payload must not split buckets.
- A payload reaching user text is source syntax via `pred_str`, never an SMT spelling.
- Assert on message TEXT for every new detail string.
- Reasons whose detail names a specific expression report PER SITE (the Task 3 rule); add them to the diagnosed set in `refine_call.ml`'s hint branch, with every constructor named and no wildcard.
- `reason_name` and `reason_detail` in `obligation.ml` are the only exhaustive matches on `reason`; adding payloads changes those two and nothing else should need a wildcard.
- The reference docs' reasons table (`specs/lang/refinement-types.md` and `docs/refinement-types.md`, both) shows `reason_detail` text; update both when the text changes, plain style, no em dashes.
- Test discipline as in the sibling plans. Never `git stash`; stage by name; no attribution trailers.

---

### Task 1: Reflect arithmetic actuals

**Files:**
- Modify: `lib/refinecheck/refine_resolve.ml:515-536` (`reflect_scalar`, before the named-call arm)
- Test: `test/test_refinecheck.ml`, new group `arith-actual`

**Interfaces:**
- Produces: `reflect_scalar` returns `Some` for `EApp (EVar ("+"|"-"), [a; b])` and for `*` with one integer-literal operand, when both operands reflect at the same sort.

- [ ] **Step 1: Write the failing tests**

```ocaml
let arith_actual_suite =
  [ gated "an arithmetic actual carries its operand's guard" (fun () ->
        let proved, skipped =
          ledger_counts
            {|mod AA1 do
  fn pos(n : {Int | _ > 0}) : Int do n end
  fn go(i : Int) : Int do
    if i >= 0 do pos(i + 1) else 0 end
  end
end|}
        in
        Alcotest.(check (pair int int)) "proved" (1, 0) (proved, skipped));

    (* The operand reflects but the guard is insufficient: this must be a
       DIAGNOSED skip about `i`, never unreflectable-predicate. *)
    gated "an insufficiently guarded arithmetic actual is diagnosed, not unreflectable"
      (fun () ->
        let rs =
          skip_reasons
            {|mod AA2 do
  fn pos(n : {Int | _ > 0}) : Int do n end
  fn go(i : Int) : Int do
    if i >= 0 do pos(i - 1) else 0 end
  end
end|}
        in
        Alcotest.(check bool) "not unreflectable-predicate" false
          (List.mem "unreflectable-predicate" rs);
        Alcotest.(check bool) "one skip, diagnosed" true
          (List.length rs = 1
           && (List.mem "unconstrained-subject" rs || List.mem "solver-undecided" rs))) ]
```

- [ ] **Step 2: Run to verify both fail**

Expected: AA1 `(0, 1)`; AA2 reports `["unreflectable-predicate"]`.

- [ ] **Step 3: The operator arm**

In `reflect_scalar`, immediately BEFORE the `| A.EApp (A.EVar { A.txt = fname; _ }, cargs, _) ->` arm:

```ocaml
  (* An infix operator is spelled as an application of its name.  Dispatching
     it as a named call sends it to [plain], whose variable resolver is
     hard-coded to None, so `n - 1` never reflected and the PREDICATE was
     blamed.  Reflect the operands through this same function so a guard on
     `n` reaches `n - 1`. *)
  | A.EApp (A.EVar { A.txt = ("+" | "-" as op); _ }, [ a; b ], _) ->
    (match reflect_scalar ~sort ~sc ~postcond ?foreign_field a,
           reflect_scalar ~sort ~sc ~postcond ?foreign_field b with
     | Some (ta, da, aa), Some (tb, db, ab) ->
       let t = if op = "+" then Smt.Add (ta, tb) else Smt.Sub (ta, tb) in
       Some (t, da @ db, aa @ ab)
     | _ -> plain actual)
  | A.EApp (A.EVar { A.txt = "*"; _ }, [ a; b ], _) ->
    (match a, b with
     | A.ELit (A.LitInt k, _), e | e, A.ELit (A.LitInt k, _) ->
       (match reflect_scalar ~sort ~sc ~postcond ?foreign_field e with
        | Some (te, de, ae) -> Some (Smt.MulLit (k, te), de, ae)
        | None -> plain actual)
     | _ -> plain actual)
```

Read `reflect_scalar`'s actual signature (its `let rec` header and how `sc`, `postcond`, `foreign_field`, `sort` are threaded) and match it exactly; the labelled names above are from the exploration and may differ. Confirm operators are `EApp (EVar "+", ...)` in the AST. Deduplicate declarations if `da @ db` can repeat a symbol (check how the existing arms merge `extra`).

- [ ] **Step 4: Run, mutation, commit**

Both `[OK]`. Mutation: delete the two new arms; both redden. Restore.

```bash
git add lib/refinecheck/refine_resolve.ml test/test_refinecheck.ml
git commit -m "refine: reflect arithmetic actuals through the subject's own scope"
```

---

### Task 2: File a failed scalar subject as `unreflectable-subject`

**Files:**
- Modify: `lib/refinecheck/obligation.ml` (`Unreflectable_subject of string`, `reason_name`, `reason_detail`)
- Modify: `lib/refinecheck/refine_call.ml` (the `mode`/`Skip` computation and the `None` arm at ~`:1960-1980`; the hint branch's diagnosed set)
- Test: `test/test_refinecheck.ml`, `reason_suite`

**Interfaces:**
- Produces: `Obligation.Unreflectable_subject of string` (payload: the actual in source syntax). `reason_name` unchanged: `"unreflectable-subject"`.

- [ ] **Step 1: Write the failing test**

```ocaml
    (* The predicate `0 <= _ && _ < 4` is fully reflectable; `lane(1)` is a
       call with no refined return and cannot be.  Blame the subject, and
       name it. *)
    gated "an opaque call actual is filed as unreflectable-subject naming the call"
      (fun () ->
        let src =
          {|mod US1 do
  cap verified
  fn at(i : {Int | 0 <= _ && _ < 4}) : Int do i end
  fn lane(k : Int) : Int do k end
  fn go() : Int do at(lane(1)) end
end|}
        in
        Alcotest.(check (list string)) "slug" [ "unreflectable-subject" ] (skip_reasons src);
        let text = refine_error_text_d src in
        Alcotest.(check bool) "names the actual" true (contains text "`lane(1)`");
        Alcotest.(check bool) "does not blame the predicate" false
          (contains text "vocabulary the checker cannot translate"));
```

Check the spelling of `cap verified` and of `refine_error_text_d` against existing fixtures.

- [ ] **Step 2: Run to verify it fails**

Expected: slug is `["unreflectable-predicate"]`.

- [ ] **Step 3: Payload and filing**

`obligation.ml`: `| Unreflectable_subject of string` (comment: the actual, rendered by `pred_str`, following `Alias_withdrawn`'s payload discipline). `reason_name`: `| Unreflectable_subject _ -> "unreflectable-subject"`. `reason_detail`:

```ocaml
  | Unreflectable_subject actual ->
    Printf.sprintf
      "the argument `%s` could not be translated to SMT, so no goal was built" actual
```

Update the existing `Skip` filing site to pass `(pred_str self_actual)`.

In `check_call`, find where the self actual is reflected for `Other` mode (the `scalar_arg`/`absorb`/`mark_self` path; `self_symbol` is `None` after reflection exactly when the subject did not resolve). Before the predicate is reflected, add: if `mode` is `Other` and the subject's reflection returned `None`, `note (Obligation.Skipped (Obligation.Unreflectable_subject (pred_str self_actual)))` and stop. Do not reach the predicate.

Hint branch: add `Unreflectable_subject _` to the PER-SITE set (its detail names the actual). Keep `Unreflectable_predicate` throttled until Task 3 gives it a payload.

- [ ] **Step 4: Run the whole `reason-suite` and `obligation-reasons` groups**

The existing record-subject case (`RS1`, `serve(mk())`) must still report `unreflectable-subject`; its message now names `mk()`. Update its text assertion if it has one. Mutation: revert the early filing; US1 reddens.

- [ ] **Step 5: Commit**

```bash
git add lib/refinecheck/obligation.ml lib/refinecheck/refine_call.ml test/test_refinecheck.ml
git commit -m "refine: file a failed scalar subject as unreflectable-subject, naming the actual"
```

---

### Task 3: Name the failing sub-expression of a genuine predicate failure

**Files:**
- Modify: `lib/refinecheck/refine_scope.ml:71-148` (`smt_of` becomes a wrapper over new `smt_of_r`)
- Modify: `lib/refinecheck/obligation.ml` (`Unreflectable_predicate of string`)
- Modify: `lib/refinecheck/refine_call.ml` (~`:1964`) and `lib/refinecheck/refine_post.ml` (~`:406`): the two goal sites
- Test: `test/test_refinecheck.ml`, `reason_suite`

**Interfaces:**
- Produces: `Refine_scope.smt_of_r : ... -> (Smt.term, A.expr) result` with the same labelled resolvers as `smt_of`; `smt_of` = `Result.to_option (smt_of_r ...)`. `Obligation.Unreflectable_predicate of string` (the failing sub-expression via `pred_str`).

- [ ] **Step 1: Write the failing tests**

Four synthetic fixtures, since the corpus has no genuine case. Each asserts the slug AND that the message names the sub-expression:

```ocaml
    gated "a genuine unreflectable predicate names the failing sub-expression: opaque call"
      (fun () ->
        let src = {|mod UP1 do
  cap verified
  fn f(n : {Int | is_prime(_)}) : Int do n end
  fn go() : Int do f(7) end
end|} in
        Alcotest.(check (list string)) "slug" [ "unreflectable-predicate" ] (skip_reasons src);
        Alcotest.(check bool) "names is_prime(_)" true (contains (refine_error_text_d src) "`is_prime(_)`"));

    gated "... division" (fun () ->
        let src = {|mod UP2 do
  cap verified
  fn f(n : {Int | _ / 2 > 0}) : Int do n end
  fn go() : Int do f(7) end
end|} in
        Alcotest.(check bool) "names _ / 2" true (contains (refine_error_text_d src) "`_ / 2`"));

    gated "... symbolic float arithmetic" (fun () ->
        let src = {|mod UP3 do
  cap verified
  fn f(x : Float, y : {Float | _ *. x > 0.0}) : Float do y end
  fn go() : Float do f(1.0, 2.0) end
end|} in
        Alcotest.(check bool) "names _ *. x" true (contains (refine_error_text_d src) "`_ *. x`"));

    gated "... a string literal in a postcondition" (fun () ->
        let src = {|mod UP4 do
  cap verified
  fn f() : {String | _ == "a"} do "a" end
end|} in
        Alcotest.(check bool) "names the literal" true (contains (refine_error_text_d src) "\"a\""));
```

Confirm each fixture actually lands in `unreflectable-predicate` today (run `skip_reasons`) before relying on it; replace any that lands elsewhere with a shape from the enumeration in the design (`refine_scope.ml` `smt_of`'s `None` cases).

- [ ] **Step 2: Run to verify the text assertions fail**

Expected: slugs already right; every `contains` assertion fails (the message names nothing).

- [ ] **Step 3: `smt_of_r`**

Rename the existing `smt_of` body to `smt_of_r` returning `Ok term` where it returned `Some term`, and `Error e` at every `None`, where `e` is the innermost sub-expression that failed: at a leaf arm, the leaf itself; at a recursive arm, propagate the child's `Error` unchanged rather than wrapping. Then:

```ocaml
let smt_of ?resolve_var ?resolve_measure ?resolve_field ?resolve_measure_app
    ?resolve_tester ?resolve_str_lit e =
  Result.to_option
    (smt_of_r ?resolve_var ?resolve_measure ?resolve_field ?resolve_measure_app
       ?resolve_tester ?resolve_str_lit e)
```

Match the real optional-argument list exactly. The 18 existing callers compile unchanged.

- [ ] **Step 4: Payload and the two goal sites**

`obligation.ml`: `| Unreflectable_predicate of string`; `reason_name` unchanged slug; `reason_detail`:

```ocaml
  | Unreflectable_predicate sub ->
    Printf.sprintf "the predicate's `%s` has no SMT translation" sub
```

`refine_call.ml` goal site: call `smt_of_r`; on `Error e` note `Unreflectable_predicate (pred_str e)`. `refine_post.ml:406` likewise. The other `Unreflectable_predicate` sites (`refine_post.ml:360`, `:848`) have no sub-expression in hand; pass `pred_str` of the whole predicate there. Add `Unreflectable_predicate _` to the per-site diagnosed set.

- [ ] **Step 5: Run, mutation, commit**

All four `[OK]`; the existing `is_prime(_)` fixture (`~:4977`) still passes. Mutation: make `smt_of_r` return `Error e` for the WHOLE predicate at the top instead of propagating the leaf; UP2 and UP3 redden (their leaf is a proper sub-expression). Restore.

```bash
git add lib/refinecheck/refine_scope.ml lib/refinecheck/obligation.ml lib/refinecheck/refine_call.ml lib/refinecheck/refine_post.ml test/test_refinecheck.ml
git commit -m "refine: name the sub-expression a predicate failed to reflect"
```

---

### Task 4: Measure, docs, record

**Files:**
- Modify: `specs/lang/refinement-types.md` and `docs/refinement-types.md` (reasons table rows for the two reasons; the per-site rule now lists them)
- Modify: `CHANGELOG.md` (`### Changed`), design status
- Move: `specs/todos/2026-09-02-unreflectable-predicate-attribution.md` to `specs/progress/`

- [ ] **Step 1: Corpus sweep**

Baseline vs after, section-aware, private `HOME`. The claim: `unreflectable-predicate` 11 to 0 in the user-code slice, each of the 11 accounted for by file:line (7 become proved/violated/diagnosed via Task 1; 4 become `unreflectable-subject` via Task 2). Table per bucket.

- [ ] **Step 2: Oracle, suite, CI checks**

RED-proof first; classify every moved line as re-attribution of one of the 11, a new proof from Task 1, or a text change from Tasks 2 and 3. `scripts/run-tests.sh`; `@types-check --force` and `@grammar-check --force` with non-zero logs (the detail strings are pinned there; update a golden only when it pins the OLD text and say so); `check-docs.sh`. Cold `--check` timing against baseline.

- [ ] **Step 3: Docs, CHANGELOG, record**

Both reference docs: update the two table rows to the new detail wording with a generated example each; list both reasons among the per-site ones. Plain style, no em dashes; generate every quoted output from the compiler. CHANGELOG `### Changed`: one bullet. Move the todo to `specs/progress/` with the 11-site accounting and the oracle classification. Set the design status to landed.

```bash
git add specs/lang/refinement-types.md docs/refinement-types.md CHANGELOG.md specs/progress/2026-09-02-unreflectable-predicate-attribution.md specs/2026-09-02-unreflectable-predicate-attribution-design.md
git commit -m "docs: record the unreflectable-predicate re-attribution"
```
