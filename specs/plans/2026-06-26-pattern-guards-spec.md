# Pattern Guards (`when` in `match`) — Refinement Integration Spec

**Date:** 2026-06-26
**Status:** Ready to implement
**Scope:** `lib/refinecheck/division_safety.ml`, `lib/refinecheck/return_infer.ml`, `test/test_compiler.ml`, `test/test_refinecheck.ml`

---

## 1. What this enables

A `when` guard on a match arm establishes a fact that is provably true inside that arm's body.
Today the refinement passes don't use those facts. After this change:

```march
-- cap no_panic: guard proves b ≠ 0, so the division is safe
fn safe_div(a : Int, b : Int) : Int do
  match b do
    b when b != 0 -> a / b   -- today: division-safety error; after: clean
    _ -> 0
  end
end

-- return-refinement inference: guard proves return > 0
fn positive_half(x : Int) : Int do
  match x do
    x when x > 0 -> x        -- today: r > 0 not inferred; after: inferred
    _ -> 1
  end
end
```

---

## 2. Current state (what's already there)

### refine_check.ml — already correct, untested

`tails` (line 1076) and `visit` (line 1397) already prepend `(guard, false)` to the path
context when descending into a match arm body. `check_fn_post` and `visit_fn` do the same for
`fc_guard`. The SMT translation in `check_call` and `check_post` already processes the path
context into solver assumptions (lines 1007–1014 and 1293–1297).

**Gap:** zero tests exercise this code path. It may work already; it may have subtle bugs.
The first task is to write tests that confirm or surface failures.

### division_safety.ml — no path context at all

`iter_div_sites` has the signature `(A.span → A.expr → unit) → A.expr → unit`. The callback
receives the division site but nothing about where it is in the body. Match arm guards are
structurally walked over (line 139: `Option.iter go arm.A.branch_guard`) but do not
accumulate facts for the divisor check.

### return_infer.ml — let-bindings only, no guards

`body_context` returns `(extra_decls, extra_assumptions, last_expr)` by scanning the flat
block prefix for `ELet`. It does not track match arm guards or `if` conditions that contain
the return expression.

---

## 3. Implementation plan

### Task A — Confirm refine_check.ml guard support works

Write 4 tests in `test/test_refinecheck.ml` (new group `"guard-path-sensitivity"`):

```
A1. match-arm when guard discharges a postcondition
    fn abs(n : Int) : {v : Int | v >= 0} do
      match n do
        n when n >= 0 -> n
        n -> -n
      end
    end
    Expected: clean (no VC failure)

A2. match-arm when guard discharges a call-site VC
    fn req_pos(x : {v : Int | v > 0}) : Int do x end
    fn caller(n : Int) : Int do
      match n do
        n when n > 0 -> req_pos(n)
        _ -> 0
      end
    end
    Expected: clean

A3. match-arm without guard still errors when needed
    fn caller2(n : Int) : Int do
      match n do
        n -> req_pos(n)   -- no guard; n might be <= 0
      end
    end
    Expected: call-site VC error on req_pos(n)

A4. fn-clause guard (fc_guard) discharges postcondition
    fn clamp(n : Int) : {v : Int | v >= 0} do
    clamp(n) when n >= 0 = n
    clamp(_) = 0
    end
    Expected: clean
```

If any test fails, fix `refine_check.ml` before proceeding to Task B.

---

### Task B — Thread path context through division_safety.ml

**B1. Change `iter_div_sites` signature to carry path context.**

```ocaml
(* old *)
let rec iter_div_sites (f : A.span -> A.expr -> unit) (e : A.expr) : unit =

(* new *)
let rec iter_div_sites
    (f : A.span -> A.expr -> (A.expr * bool) list -> unit)
    (path : (A.expr * bool) list)
    (e : A.expr) : unit =
```

Update the recursive call binding:
```ocaml
let go e = iter_div_sites f path e
```

**B2. Add guard accumulation in the match and if arms.**

```ocaml
(* was: *)
| A.EMatch (scrut, arms, _) ->
  go scrut;
  List.iter
    (fun (arm : A.branch) ->
      Option.iter go arm.A.branch_guard;
      go arm.A.branch_body)
    arms

(* becomes: *)
| A.EMatch (scrut, arms, _) ->
  go scrut;
  List.iter
    (fun (arm : A.branch) ->
      Option.iter go arm.A.branch_guard;
      let arm_path = match arm.A.branch_guard with
        | Some g -> (g, false) :: path
        | None   -> path
      in
      iter_div_sites f arm_path arm.A.branch_body)
    arms

(* similarly for EIf: *)
| A.EIf (cond, t, e, _) ->
  go cond;
  iter_div_sites f ((cond, false) :: path) t;
  iter_div_sites f ((cond, true)  :: path) e

(* ECond: *)
| A.ECond (arms, _) ->
  List.iter (fun (c, b) ->
    go c;
    iter_div_sites f ((c, false) :: path) b) arms
```

**B3. Thread path into `check_var_divisor`.**

Change the call site in `check_clause`:
```ocaml
(* was: *)
| A.EVar { A.txt = var_name; _ } ->
  check_var_divisor ~root errctx span var_name params let_values

(* becomes: *)
| A.EVar { A.txt = var_name; _ } ->
  check_var_divisor ~root errctx span var_name params let_values path
```

And the callback passed to `iter_div_sites`:
```ocaml
iter_div_sites
  (fun span divisor path ->
    match divisor with
    ...
    | A.EVar { A.txt = var_name; _ } ->
      check_var_divisor ~root errctx span var_name params let_values path
    ...)
  []   (* initial empty path *)
  clause.A.fc_body
```

**B4. Add path-context assumptions in `check_var_divisor`.**

The `None` branch (variable not in refined params, not in let_values) currently always errors.
Add a path-context check before emitting the conservative error:

```ocaml
| None ->
  (match List.assoc_opt var_name let_values with
   | ...existing let_values logic...
   | None ->
     (* NEW: try path context before emitting the conservative error *)
     if path_proves_nonzero var_name path then ()
     else
       Err.error errctx ~span
         (Printf.sprintf "division by `%s` ..." ...))
```

where `path_proves_nonzero` is:

```ocaml
(* Returns true if any condition in [path] syntactically implies [var] ≠ 0.
   Uses the existing syntactic_nonzero check — no Z3 needed for simple guards. *)
let path_proves_nonzero (var : string) (path : (A.expr * bool) list) : bool =
  List.exists
    (fun (cond, negated) ->
      if negated then false
      else
        match cond with
        | A.EApp (A.EVar { A.txt = op; _ }, [ a; b ], _) ->
          let is_var = function A.EVar { A.txt = x; _ } -> x = var | _ -> false in
          let int_of = function A.ELit (A.LitInt n, _) -> Some n | _ -> None in
          (match op with
           | "!=" -> (is_var a && int_of b = Some 0) || (is_var b && int_of a = Some 0)
           | ">"  -> is_var a && Option.fold ~none:false ~some:(fun n -> n >= 0) (int_of b)
           | ">=" -> is_var a && Option.fold ~none:false ~some:(fun n -> n >= 1) (int_of b)
           | "<"  -> is_var b && Option.fold ~none:false ~some:(fun n -> n <= 0) (int_of a)
           | "<=" -> is_var b && Option.fold ~none:false ~some:(fun n -> n <= -1) (int_of a)
           | _ -> false)
        | _ -> false)
    path
```

This is syntactic (no Z3). For the common guard patterns (`b != 0`, `b > 0`, `b >= 1`) it
discharges immediately. For a complex guard the check returns false and the conservative error
fires as before — sound.

**Also handle the refined-param branch:** when the variable IS a refined param but its
refinement alone is insufficient, path conditions can add extra assumptions. Add path
conditions to the VC's assumption list:

```ocaml
| Some (_, bdr, pred) ->
  if syntactic_nonzero bdr pred then ()
  else
    (match smt_of ~b:bdr ~var:var_name pred with
     | None -> ()
     | Some assumption ->
       (* NEW: collect path assumptions for var_name *)
       let path_assumes =
         List.filter_map (fun (cond, negated) ->
           match smt_of ~b:var_name ~var:var_name cond with
           | None -> None
           | Some t -> Some (if negated then Smt.Not t else t))
           path
       in
       let vc = Smt.{
         decls = [(var_name, Smt.SInt)];
         assumptions = assumption :: path_assumes;
         goal = Smt.Ne (Smt.Const var_name, Smt.IntLit 0) }
       in
       ...)
```

---

### Task C — Thread guard context through return_infer.ml

The issue: `infer_clause` calls `body_context` which only looks at the flat block prefix for
let-bindings. It misses guards on match arms that contain the return expression.

**C1. Add `guard_context` to collect guards reaching a return expression.**

Mirror what `tails` does in `refine_check.ml` but return guard assumptions:

```ocaml
(* Walk body, collecting (guard_terms, return_expr) pairs — one per return position.
   [path] is the accumulated guard context: (cond_expr, negated) list. *)
let rec return_positions
    (path : (A.expr * bool) list)
    (e : A.expr)
  : ((A.expr * bool) list * A.expr) list =
  match e with
  | A.EBlock (es, _) ->
    (match List.rev es with
     | [] -> []
     | last :: _ -> return_positions path last)
  | A.EIf (c, t, el, _) ->
    return_positions ((c, false) :: path) t @
    return_positions ((c, true)  :: path) el
  | A.ECond (arms, _) ->
    List.concat_map (fun (c, b) -> return_positions ((c, false) :: path) b) arms
  | A.EMatch (_, branches, _) ->
    List.concat_map
      (fun (br : A.branch) ->
        let p = match br.A.branch_guard with
          | Some g -> (g, false) :: path
          | None   -> path
        in
        return_positions p br.A.branch_body)
      branches
  | other -> [(path, other)]
```

**C2. Update `infer_clause` to use `return_positions` instead of `body_context`.**

```ocaml
let infer_clause ~root (clause : A.fn_clause) : string list =
  let params = clause_refined_params clause in
  if params = [] then []
  else
    let (base_decls, base_assume) = param_vc_base params in
    let clause_path =
      match clause.A.fc_guard with Some g -> [(g, false)] | None -> []
    in
    let ret_positions = return_positions clause_path clause.A.fc_body in
    (* A predicate is verified if it holds for ALL return positions.
       (If the function returns different things on different paths, we only
       report predicates that hold everywhere.) *)
    let candidate_results =
      List.map (fun (path, ret_expr) ->
        (* let-binding equalities from the block (existing body_context logic) *)
        let (let_decls, let_assume, _) = body_context ret_expr in
        (* guard assumptions from the path to this return *)
        let guard_assume =
          List.filter_map (fun (cond, negated) ->
            match smt_term cond with
            | None -> None
            | Some t -> Some (if negated then Smt.Not t else t))
            path
        in
        match smt_term ret_expr with
        | None -> []
        | Some ret_term ->
          let all_consts = Hashtbl.create 8 in
          collect_consts all_consts ret_term;
          List.iter (collect_consts all_consts) let_assume;
          List.iter (collect_consts all_consts) guard_assume;
          let declared = Hashtbl.create 8 in
          List.iter (fun (n, _) -> Hashtbl.replace declared n ())
            (base_decls @ let_decls);
          let extra_decls =
            Hashtbl.fold
              (fun v () acc ->
                if Hashtbl.mem declared v then acc else (v, Smt.SInt) :: acc)
              all_consts []
          in
          let decls =
            List.fold_left
              (fun acc d -> if List.mem d acc then acc else d :: acc)
              [] (base_decls @ let_decls @ extra_decls)
          in
          let assumptions = base_assume @ let_assume @ guard_assume in
          List.filter_map
            (fun (pred_str, candidate_fn) ->
              if probe ~root decls assumptions ret_term candidate_fn
              then Some pred_str
              else None)
            candidates)
        ret_positions
    in
    (* Intersect: only predicates that hold for every return position *)
    match candidate_results with
    | [] -> []
    | first :: rest ->
      List.fold_left
        (fun acc preds -> List.filter (fun p -> List.mem p preds) acc)
        first rest
```

The intersection rule is important: if one arm returns `x` (where `x > 0` under its guard)
but another arm returns `1` unconditionally, `r > 0` should still be inferred (1 > 0 is
always true). The intersection handles this correctly because `probe` on `ret_term = 1` with
empty assumptions will verify `r > 0` trivially.

---

## 4. Tests

### test_refinecheck.ml additions (Task A)

New group `"guard-path-sensitivity"` with 4 tests as listed in Task A.

### test_compiler.ml additions (Tasks B, C)

New group `"divsafety_guards"` (5 tests):

```
B1. when_nonzero_guard_safe:
    cap no_panic; match b do b when b != 0 -> a / b | _ -> 0 end
    Expected: no error

B2. when_positive_guard_safe:
    cap no_panic; match b do b when b > 0 -> a / b | _ -> 0 end
    Expected: no error

B3. when_guard_other_var_still_errors:
    cap no_panic; match x do x when x != 0 -> a / b | _ -> 0 end
    -- guard is about x, not b; b still unproven
    Expected: division-safety error on a / b

B4. if_condition_safe:
    cap no_panic; if b != 0 do a / b else 0 end
    Expected: no error (EIf branch already handled, confirming)

B5. no_guard_unrefined_still_errors:
    cap no_panic; match b do b -> a / b end
    Expected: division-safety error
```

New group `"return_refine_guard"` in test_compiler.ml (3 tests, guarded on `z3_available()`):

```
C1. guard_infers_positive:
    fn f(x : Int) : Int do
      match x do x when x > 0 -> x | _ -> 1 end
    end
    Expected: has_pred results "f" "r > 0"

C2. guard_infers_nonneg:
    fn f(x : Int) : Int do
      match x do x when x >= 0 -> x | _ -> 0 end
    end
    Expected: has_pred results "f" "r >= 0"

C3. guard_only_refines_that_arm:
    fn f(x : Int) : Int do
      match x do x when x > 0 -> x | _ -> -1 end
    end
    -- one arm returns positive, other returns -1; no predicate holds for both
    Expected: verified_preds for "f" is []
```

---

## 5. Sizing

| Task | Scope | Effort |
|------|-------|--------|
| A — confirm/test refine_check.ml guards | 4 tests only; fix if broken | Small (½ session) |
| B — division_safety path context | ~60 lines change + 5 tests | Small (½ session) |
| C — return_infer guard threading | ~50 lines change + 3 tests | Small (½ session) |
| **Total** | | **~1 session** |

---

## 6. Explicitly out of scope

- **Pattern-variable bindings as assumptions.** `match n do 0 -> ... | k -> ... end` — in the
  `k` arm we know `n ≠ 0` and `n = k`. Threading pattern bindings as SMT equalities requires
  knowing the scrutinee's name, which `visit` discards. This is a separate, larger feature.
- **Negated guards for else-equivalent arms.** `match n do n when n > 0 -> ... | _ -> ... end`
  — the wildcard arm implicitly knows `n <= 0`. Supporting this requires accumulating the
  negations of all prior guards per arm. Deferred.
- **Higher-order / polymorphic guard contexts.** Passing a guard through a lambda or HOF call
  is not addressed here.
- **`division_safety.ml` Z3 path discharge.** Task B uses only syntactic non-zero checks for
  path conditions, matching the existing `syntactic_nonzero` approach. Wiring full Z3
  discharge over path conditions (for non-obvious guard forms) is a follow-up.

---

## 7. Decision record

**D1.** Path conditions for `division_safety.ml` use syntactic fast-path only (no Z3).
Rationale: the `cap no_panic` guarantee must hold even without Z3. Syntactic checks are
sound and cover the common patterns. Full Z3 path discharge is a follow-up.

**D2.** `return_infer.ml` intersects candidates across all return positions.
Rationale: a predicate that holds on only some paths is not a reliable return refinement.
The conservative intersection is sound; false negatives (missed predicates) are acceptable
since return_infer is informational only.

**D3.** Task A tests are written first. If they expose a bug in `refine_check.ml`'s existing
guard threading, fix it before proceeding. Tasks B and C are independent of each other.
