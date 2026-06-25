# Refinement Check — Record Type Spike — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Prove the EField + TDRecord approach works end-to-end: `{ v : State | v.count >= 0 }` as a return refinement discharges on `{ count = 1 }` and rejects `{ count = -1 }`. This is the load-bearing spike for Gap #1 of `specs/2026-06-25-refinement-verified-state-migration-design.md`.

**Scope:** Return-type refinements on record types (postconditions) only. Record-typed *parameter* refinements (preconditions on `old : State`) and `@invariant` wiring are Gap #1 proper, not this spike.

**Decisions made:**
- Risk 1 (field name→index mapping): **Option A** — new `ctor_field_names : (string, string list) Hashtbl.t` parallel to `ctor_field_sorts`, populated for every `TDRecord`
- Risk 2 (preamble scoping): **Option C** — new `type_preamble : string ref` built after `measure_preamble`, tracking which sorts are already declared there to avoid Z3 duplicate-sort errors

**All changes in one file:** `lib/refinecheck/refine_check.ml`

**No changes to:** `lib/refine/`, `lib/ast/`, `lib/typecheck/`, `lib/tir/`, `bin/main.ml`, `forge/`

---

## Verified codebase structures

All line numbers confirmed against the worktree (2026-06-25):

| Symbol | Location | Notes |
|--------|----------|-------|
| `ctor_field_sorts` | line 75 | ctor → `sort list` (positional); TDVariant only today |
| `adt_ctors` | line 76 | sort name → ctor list |
| `measure_preamble` | line 80 | global `string ref` for measure VC preambles |
| `register_adt_names` | lines 103–112 | handles `TDVariant` + `DMod` only |
| `register_field_sorts` | lines 115–127 | handles `TDVariant` + `DMod` only |
| `adt_closure` / `datatype_decls` | lines 199, 225 | existing preamble builders; reused as-is |
| `ctor_decl` | line 215 | accessor name convention: `<ctor>_<idx>` |
| `build_measure_preamble` | line 282 | ends at line 351 assigning `measure_preamble` |
| `register_builtin_adts` | line 357 | seeds List into `adt_ctors` / `ctor_field_sorts` |
| `smt_of` | lines 487–517 | 8 call sites; `~resolve_var` + `~resolve_measure`; no `EField` case |
| `is_int_base` | line 32 | gates `refined_int_ty` (553) and `return_refine` (840) |
| `return_refine` | lines 838–842 | extracts `(binder, pred)` from `fn_ret_ty` |
| `check_post` | lines 870–913 | `preamble:""` at lines 902/905 |
| `check_fn_post` | lines 915–926 | calls `return_refine` then `check_post` |
| `reflect_dt` | line 755 | handles `ECon`/`EVar`; no `ERecord` case |
| `check_module` reset block | lines 1106–1109 | `Hashtbl.reset` calls + `measure_preamble := ""` |
| `check_module` axioms block | lines 1110–1129 | `register_builtin_adts` + `build_measure_preamble` |

`EField` in the AST: `A.EField of expr * name * span` — the field name is the second component (`.A.txt`). `ERecord`: `A.ERecord of (name * expr) list * span`. Both confirmed in `lib/ast/ast.ml:61–64`.

`TDRecord` in the AST: `A.TDRecord of field list` where `field = { fld_name : name; fld_ty : ty; fld_lin : linearity }` (`ast.ml:249–252`).

---

## Task 1: New global data structures

**File:** `lib/refinecheck/refine_check.ml`

Add three globals alongside `measure_preamble` (after line 80):

```ocaml
(* ctor name -> field names in declaration order.  Only populated for TDRecord
   1-ctor datatypes; used to map EField/ERecord field names to selector indices. *)
let ctor_field_names : (string, string list) Hashtbl.t = Hashtbl.create 16

(* declare-datatypes preamble for all registered TDRecord types; included in
   every VC that refines over a record value.  Built after measure_preamble
   so sort deduplication (below) works. *)
let type_preamble : string ref = ref ""

(* ADT sort names already declared in measure_preamble; populated by
   build_measure_preamble so build_type_preamble can skip them and avoid
   duplicate sort declarations in the same VC (Z3 rejects those). *)
let measure_preamble_sorts : (string, unit) Hashtbl.t = Hashtbl.create 8
```

In the `check_module` reset block (lines 1106–1109), add resets for the new tables:

```ocaml
Hashtbl.reset ctor_field_names;
Hashtbl.reset measure_preamble_sorts;
type_preamble := "";
```

- [ ] Add `ctor_field_names`, `type_preamble`, `measure_preamble_sorts` after `measure_preamble` (line 80)
- [ ] Add three reset lines in `check_module` reset block (alongside existing resets at line 1106)
- [ ] Build: `dune build --root . 2>&1 | grep -iE "^Error" | head` — must be clean

---

## Task 2: Register TDRecord types in pass 1 and pass 2

**File:** `lib/refinecheck/refine_check.ml`

A record is a 1-constructor SMT datatype whose ctor name equals the type name. Both passes need a new `TDRecord` arm.

### `register_adt_names` (pass 1, around line 106)

After the `TDVariant` arm, add:

```ocaml
| A.DType (_, name, _, A.TDRecord _, _) ->
  (* A record type is a 1-ctor datatype; ctor name = type name. *)
  Hashtbl.replace adt_ctors (adt_sort_name name.A.txt) [ name.A.txt ]
```

### `register_field_sorts` (pass 2, around line 118)

After the `TDVariant` arm, add:

```ocaml
| A.DType (_, name, _, A.TDRecord fields, _) ->
  let ctor = name.A.txt in
  Hashtbl.replace ctor_field_sorts ctor
    (List.map (fun (f : A.field) -> smt_sort_of_field f.A.fld_ty) fields);
  Hashtbl.replace ctor_field_names ctor
    (List.map (fun (f : A.field) -> f.A.fld_name.A.txt) fields)
```

Field names are stored in **declaration order** (matching `ctor_field_sorts` positional order). `ctor_decl` generates `ctor_0`, `ctor_1`, … by position, so the two tables must agree on field ordering.

- [ ] Add `TDRecord` arm to `register_adt_names`
- [ ] Add `TDRecord` arm to `register_field_sorts` (both sorts and names)
- [ ] Smoke check: `type State = { count : Int }` in a test program → `adt_ctors["M_State"] = ["State"]`, `ctor_field_sorts["State"] = [SInt]`, `ctor_field_names["State"] = ["count"]` (verify by inspecting VC output in a test)

---

## Task 3: `type_preamble` and `record_vc_preamble`

**File:** `lib/refinecheck/refine_check.ml`

### Track covered sorts in `build_measure_preamble`

The last line of `build_measure_preamble`'s `else` branch (line 350) currently is:

```ocaml
let dts = datatype_decls (adt_closure (List.map (fun (_, adt, _) -> adt) axiomatized)) in
measure_preamble := "(declare-sort Elem 0)\n" ^ dts ^ "\n" ^ Buffer.contents buf
```

Replace with:

```ocaml
let covered = adt_closure (List.map (fun (_, adt, _) -> adt) axiomatized) in
let dts = datatype_decls covered in
measure_preamble := "(declare-sort Elem 0)\n" ^ dts ^ "\n" ^ Buffer.contents buf;
Hashtbl.reset measure_preamble_sorts;
List.iter (fun s -> Hashtbl.replace measure_preamble_sorts s ()) covered
```

### `build_type_preamble`

New function, placed after `build_measure_preamble`:

```ocaml
(* Build type_preamble from all registered TDRecord sorts, excluding any sorts
   already declared in measure_preamble (tracked in measure_preamble_sorts). *)
let build_type_preamble () : unit =
  (* Collect sort names that were registered as TDRecord (identified by having
     a single ctor with an entry in ctor_field_names). *)
  let record_sorts =
    Hashtbl.fold
      (fun sort _ctors acc ->
        match Hashtbl.find_opt adt_ctors sort with
        | Some [ ctor ] when Hashtbl.mem ctor_field_names ctor -> sort :: acc
        | _ -> acc)
      adt_ctors []
  in
  if record_sorts = [] then type_preamble := ""
  else begin
    let all_sorts = adt_closure record_sorts in
    let new_sorts =
      List.filter (fun s -> not (Hashtbl.mem measure_preamble_sorts s)) all_sorts
    in
    if new_sorts = [] then type_preamble := ""
    else type_preamble := "(declare-sort Elem 0)\n" ^ datatype_decls new_sorts
  end
```

### `record_vc_preamble`

Combines the two preambles; deduplication is already handled in `build_type_preamble`:

```ocaml
(* The preamble for a VC that refines over a record value.  Concatenates
   measure_preamble and type_preamble; sort deduplication is handled at build
   time so no sort is declared twice. *)
let record_vc_preamble () : string =
  match !measure_preamble, !type_preamble with
  | "", t -> t
  | m, "" -> m
  | m, t -> m ^ "\n" ^ t
```

### Wire into `check_module`

In the `if measure_axioms then begin ... end` block, add `build_type_preamble ()` immediately after `build_measure_preamble mfns`:

```ocaml
build_measure_preamble mfns;
build_type_preamble ();
```

- [ ] Modify `build_measure_preamble` to capture `covered` and populate `measure_preamble_sorts`
- [ ] Add `build_type_preamble` function
- [ ] Add `record_vc_preamble` helper
- [ ] Call `build_type_preamble ()` in `check_module` after `build_measure_preamble`
- [ ] Build clean

---

## Task 4: `EField` case in `smt_of`

**File:** `lib/refinecheck/refine_check.ml`

### Add `?resolve_field` optional parameter

Change the signature of `smt_of` (line 487):

```ocaml
let rec smt_of ~resolve_var ~resolve_measure ?(resolve_field = fun _ _ -> None) (e : A.expr)
    : Smt.term option =
  let r = smt_of ~resolve_var ~resolve_measure ~resolve_field in
  ...
```

### Add the `EField` case

Between the `EVar` case and the arithmetic cases (after line 499):

```ocaml
(* Field access on a bare variable: s.count → selector applied to s.
   Only EVar receivers are supported; complex receivers (function calls,
   nested access) conservatively return None — safe under definite-failure. *)
| A.EField (A.EVar { A.txt = x; _ }, { A.txt = fname; _ }, _) -> resolve_field x fname
```

All 8 existing call sites are unaffected: `?resolve_field` defaults to `fun _ _ -> None`, so they compile without change and all `EField` expressions in existing VCs conservatively return `None` as before.

- [ ] Add `?(resolve_field = fun _ _ -> None)` to `smt_of` signature
- [ ] Thread `~resolve_field` in the `r` self-recursive binding
- [ ] Add `EField(EVar x, fname)` case
- [ ] Build: confirm all 8 existing call sites compile without modification

---

## Task 5: Gate generalisation and `return_refine_ext`

**File:** `lib/refinecheck/refine_check.ml`

### `is_record_base`

New predicate for registered 1-ctor record TyCons:

```ocaml
let is_record_base (t : A.ty) : bool =
  match t with
  | A.TyCon ({ A.txt = name; _ }, []) ->
    (match Hashtbl.find_opt adt_ctors (adt_sort_name name) with
     | Some [ ctor ] -> Hashtbl.mem ctor_field_names ctor
     | _ -> false)
  | _ -> false
```

### `return_refine_ext`

A richer version of `return_refine` that also returns the record sort name when the base type is a registered record. Placed alongside `return_refine` (line 838):

```ocaml
(* Like return_refine but also returns the SMT sort name when the return base
   type is a registered TDRecord, so check_post can reflect ERecord literals
   and build the field resolver for EField predicates. *)
let return_refine_ext (fd : A.fn_def) : (string * A.expr * string option) option =
  match fd.A.fn_ret_ty with
  | Some (A.TyRefine (base, binder, pred)) when is_int_base base ->
    Some (binder_name binder, pred, None)
  | Some (A.TyRefine (A.TyCon ({ A.txt = name; _ }, []) as base, binder, pred))
    when is_record_base base ->
    Some (binder_name binder, pred, Some (adt_sort_name name))
  | _ -> None
```

`refined_int_ty` (line 553, precondition gate) is **not changed** in this spike — record param refinements come in Gap #1 proper.

- [ ] Add `is_record_base` predicate
- [ ] Add `return_refine_ext` (returns `(binder, pred, sort_name option)`)
- [ ] Build clean

---

## Task 6: `ERecord` reflection and extended `check_post`

**File:** `lib/refinecheck/refine_check.ml`

This task is the core of the spike. Two helpers + one extended function.

### Helper: `make_field_resolver`

Builds a `resolve_field` closure for a known record binder. Given that `binder_name` maps to `binder_term` (a constructor-application SMT term), field access `binder_name.fname` becomes `App("<ctor>_<idx>", [binder_term])`:

```ocaml
let make_field_resolver (binder : string) (sort_name : string) (binder_term : Smt.term)
    : string -> string -> Smt.term option =
  fun varname fname ->
    if varname <> binder && varname <> "_" then None
    else
      match Hashtbl.find_opt adt_ctors sort_name with
      | Some [ ctor ] ->
        (match Hashtbl.find_opt ctor_field_names ctor with
         | None -> None
         | Some names ->
           let rec find_idx i = function
             | [] -> None
             | n :: _ when n = fname -> Some i
             | _ :: rest -> find_idx (i + 1) rest
           in
           (match find_idx 0 names with
            | None -> None
            | Some idx ->
              Some (Smt.App (Printf.sprintf "%s_%d" ctor idx, [ binder_term ]))))
      | _ -> None
```

### Helper: `reflect_record_literal`

Reflects `ERecord` field-value pairs as a constructor application. Field values are reflected by the caller-supplied `reflect_scalar` (which is `smt_of` with the current `resolve_var`/`resolve_measure`). Non-Int/Bool fields (nested records, lists) use `reflect_scalar` directly — if it returns `None`, the whole reflection returns `None` (conservative skip):

```ocaml
let reflect_record_literal (sort_name : string) (fields : (A.name * A.expr) list)
    (reflect_scalar : A.expr -> Smt.term option) : Smt.term option =
  match Hashtbl.find_opt adt_ctors sort_name with
  | Some [ ctor ] ->
    (match Hashtbl.find_opt ctor_field_names ctor with
     | None -> None
     | Some fname_list ->
       let field_map = List.map (fun (n, e) -> (n.A.txt, e)) fields in
       (* Reorder to match declaration order (ctor_field_sorts positional order). *)
       let in_order =
         List.filter_map (fun fname -> List.assoc_opt fname field_map) fname_list
       in
       if List.length in_order <> List.length fname_list then None
       else
         let reflected = List.map reflect_scalar in_order in
         if List.exists Option.is_none reflected then None
         else Some (Smt.App (ctor, List.filter_map Fun.id reflected)))
  | _ -> None
```

### Extended `check_post`

Add `?(record_sort : string option = None)` parameter. The record branch:
1. Uses `reflect_record_literal` for `ERecord` tail expressions
2. Builds a `make_field_resolver` closure once `tail_term` is known
3. Passes `~resolve_field` to the `smt_of` calls for path conditions and the return predicate
4. Uses `record_vc_preamble ()` instead of `""` for the VC preamble

```ocaml
let check_post ~root errctx ~span ?(record_sort = None) (sc : scope) (binder : string)
    (ret_pred : A.expr) ((path, tail_e) : (A.expr * bool) list * A.expr) : unit =
  let base_decls, base_assume = scope_facts sc in
  let decls = ref base_decls and assume = ref base_assume in
  let var_const name = decls := (name, Smt.SInt) :: !decls; Some (Smt.Const name) in
  let resolve_measure m name =
    let c = Smt.Const (m ^ "$" ^ name) in
    decls := (m ^ "$" ^ name, Smt.SInt) :: !decls;
    if is_nonneg_measure m then assume := Smt.Ge (c, Smt.IntLit 0) :: !assume;
    Some c
  in
  let scalar e = smt_of ~resolve_var:var_const ~resolve_measure e in
  (* Reflect the return value: ERecord for known record sort, otherwise smt_of. *)
  let tail_term_opt =
    match record_sort with
    | Some sort_name ->
      (match tail_e with
       | A.ERecord (fields, _) -> reflect_record_literal sort_name fields scalar
       | _ -> scalar tail_e)
    | None -> scalar tail_e
  in
  match tail_term_opt with
  | None -> ()
  | Some tail_term ->
    let resolve_field = match record_sort with
      | Some sort_name -> make_field_resolver binder sort_name tail_term
      | None -> fun _ _ -> None
    in
    let resolve_var name =
      if name = binder || name = "_" then Some tail_term else var_const name
    in
    List.iter
      (fun (cond, negated) ->
        match smt_of ~resolve_var ~resolve_measure ~resolve_field cond with
        | Some t -> assume := (if negated then Smt.Not t else t) :: !assume
        | None -> ())
      path;
    (match smt_of ~resolve_var ~resolve_measure ~resolve_field ret_pred with
     | None -> ()
     | Some goal ->
       let decls =
         List.fold_left (fun acc d -> if List.mem d acc then acc else d :: acc) [] !decls
       in
       let vc = { Smt.decls; assumptions = !assume; goal } in
       let preamble = match record_sort with
         | Some _ -> record_vc_preamble ()
         | None -> ""
       in
       (match Refine.discharge ~root ~preamble vc with
        | Refine.Verified -> ()
        | first ->
          (match Refine.discharge ~root ~preamble { vc with Smt.goal = Smt.Not goal } with
           | Refine.Verified ->
             Err.error errctx ~span
               (Printf.sprintf
                  "refinement violation: return value cannot satisfy postcondition `%s`%s\n\
                   note: every return path of this function must satisfy `%s`"
                  (pred_str ret_pred) (format_cx (model_of first)) (pred_str ret_pred))
           | _ -> ())))
```

### Updated `check_fn_post`

Switch from `return_refine` to `return_refine_ext` and pass `~record_sort`:

```ocaml
let check_fn_post ~root errctx (fd : A.fn_def) : unit =
  match return_refine_ext fd with
  | None -> ()
  | Some (binder, ret_pred, record_sort) ->
    List.iter
      (fun (c : A.fn_clause) ->
        let sc = List.fold_left scope_add_fnparam [] c.A.fc_params in
        let base = match c.A.fc_guard with Some g -> [ (g, false) ] | None -> [] in
        List.iter
          (check_post ~root errctx ~span:c.A.fc_span ~record_sort sc binder ret_pred)
          (tails base c.A.fc_body))
      fd.A.fn_clauses
```

- [ ] Add `make_field_resolver` helper
- [ ] Add `reflect_record_literal` helper
- [ ] Replace `check_post` with the extended version (add `?record_sort` parameter)
- [ ] Replace `check_fn_post` to call `return_refine_ext` and thread `~record_sort`
- [ ] Build clean

---

## Task 7: Tests

**File:** `test/test_refinecheck.ml`

Add a `record_refinement` group alongside the existing groups. Use the same z3-gating pattern as other solver-dependent groups.

### SMT VC walkthrough (confirm the approach before writing tests)

For `fn ok_migrate() : { v : State | v.count >= 0 } do { count = 1 } end` with `type State = { count : Int }`:

- `return_refine_ext` → `(binder="v", pred=EApp(>=,[EField(EVar "v","count"),ELit 0]), record_sort=Some "M_State")`
- `tail_e = ERecord [("count", ELit(LitInt 1))]`
- `reflect_record_literal "M_State" [("count", ELit 1)] scalar` → `App("State", [IntLit 1])`  (`tail_term`)
- `make_field_resolver "v" "M_State" (App("State",[IntLit 1]))` → for `("v","count")`: index 0 → `App("State_0", [App("State",[IntLit 1])])`
- `smt_of ret_pred ~resolve_var:("v"→tail_term) ~resolve_field` → `Ge(App("State_0",[App("State",[IntLit 1])]), IntLit 0)`
- `record_vc_preamble()` includes `(declare-datatypes ((M_State 0)) (((State (State_0 Int)))))`
- Z3 knows `(State_0 (State x)) = x` → goal reduces to `(>= 1 0)` → `unsat` on negation → `Verified` ✓

For `{ count = -1 }`: goal reduces to `(>= -1 0)` → negation `(< -1 0)` is satisfiable with counterexample `count = -1` → `Refuted` → violation reported ✓

For `{ count = x }` (unknown Int): `App("State_0",[App("State",[Const "x"])])` reduces to `(>= x 0)`. Z3 cannot prove or disprove without assumptions → `Unverified` both ways → skip ✓

### Test cases

```ocaml
let record_refinement_tests root =
  let ok_src = {|
    mod M do
      type State = { count : Int }
      fn ok_migrate() : {v : State | v.count >= 0} do
        { count = 1 }
      end
    end
  |} in
  let bad_src = {|
    mod M do
      type State = { count : Int }
      fn bad_migrate() : {v : State | v.count >= 0} do
        { count = -1 }
      end
    end
  |} in
  let skip_src = {|
    mod M do
      type State = { count : Int }
      fn unknown_migrate(x : Int) : {v : State | v.count >= 0} do
        { count = x }
      end
    end
  |} in
  [
    Alcotest.test_case "record postcondition: literal satisfies" `Quick (fun () ->
      Alcotest.(check bool) "no error" false
        (has_refine_error ~root ok_src));
    Alcotest.test_case "record postcondition: literal violates" `Quick (fun () ->
      Alcotest.(check bool) "has error" true
        (has_refine_error ~root bad_src));
    Alcotest.test_case "record postcondition: unknown value skipped" `Quick (fun () ->
      Alcotest.(check bool) "no error" false
        (has_refine_error ~root skip_src));
  ]
```

Wire as a new `("record_refinement", record_refinement_tests root)` entry in the suite list, gated on `Solver.z3_available ()` like the existing solver-dependent groups.

- [ ] Add `record_refinement_tests` function using existing `has_refine_error` helper
- [ ] Add the group to `refinecheck_suites`, z3-gated
- [ ] Run: `dune build --root . test/test_refinecheck.exe && _build/default/test/test_refinecheck.exe 2>&1 | grep -E "record_refinement|FAIL|PASS"` — all three cases pass

---

## Task 8: Full regression

- [ ] `dune build --root .` — clean
- [ ] `scripts/run-tests.sh -q` — all quick suites green (exit 0)
- [ ] `_build/default/test/test_refinecheck.exe` — all existing groups pass; `record_refinement` group either passes (z3 present) or skips cleanly (z3 absent)

---

## Sizing summary

| Task | Estimated lines | Risk |
|------|----------------|------|
| T1: new globals + resets | ~15 | None |
| T2: TDRecord registration | ~12 | Low — mirrors TDVariant case |
| T3: type_preamble machinery | ~30 | Low — reuses adt_closure/datatype_decls |
| T4: EField in smt_of | ~10 | Low — optional arg, 0 call-site changes |
| T5: gate + return_refine_ext | ~20 | Low |
| T6: helpers + check_post | ~70 | Medium — most new logic here |
| T7: tests | ~40 | Low |
| **Total** | **~200** | |

---

## Exit criterion

The spike is done when:
1. `{ v : State | v.count >= 0 }` on a function returning `{ count = 1 }` → no error
2. `{ v : State | v.count >= 0 }` on a function returning `{ count = -1 }` → `"refinement violation"`
3. `{ v : State | v.count >= 0 }` on a function returning `{ count = x }` (unknown) → no error
4. All existing tests remain green
5. The approach is confirmed viable for Gap #1 (adding `@invariant`, record param refinements, `--check-migration` mode)
