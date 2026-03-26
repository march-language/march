(** March coverage tracking module.

    Records which expressions, branches, and function calls are executed
    during a test run.  All recording is gated behind [coverage_enabled]
    so there is zero overhead when coverage is off. *)

open March_ast.Ast

(* ------------------------------------------------------------------ *)
(* Global state                                                        *)
(* ------------------------------------------------------------------ *)

(** Master switch — set to [true] before running tests. *)
let coverage_enabled : bool ref = ref false

(** expr_hits: keyed by "file:line:col" *)
let expr_hits   : (string, int) Hashtbl.t = Hashtbl.create 512

(** branch_hits: keyed by "file:line:col:T|F" (if/else) or
    "file:line:col:armN" (match arm N). *)
let branch_hits : (string, int) Hashtbl.t = Hashtbl.create 128

(** fn_hits: keyed by function name string. *)
let fn_hits     : (string, int) Hashtbl.t = Hashtbl.create 64

let span_key (sp : span) =
  Printf.sprintf "%s:%d:%d" sp.file sp.start_line sp.start_col

let incr_hit tbl key =
  Hashtbl.replace tbl key (1 + (try Hashtbl.find tbl key with Not_found -> 0))

(* ------------------------------------------------------------------ *)
(* Recording functions — all gated by [!coverage_enabled]             *)
(* ------------------------------------------------------------------ *)

let record_expr (sp : span) =
  if !coverage_enabled then
    incr_hit expr_hits (span_key sp)

let record_branch (sp : span) (taken : bool) =
  if !coverage_enabled then
    incr_hit branch_hits
      (Printf.sprintf "%s:%s" (span_key sp) (if taken then "T" else "F"))

let record_arm (sp : span) (arm_idx : int) =
  if !coverage_enabled then
    incr_hit branch_hits
      (Printf.sprintf "%s:arm%d" (span_key sp) arm_idx)

let record_fn_call (name : string) =
  if !coverage_enabled then
    incr_hit fn_hits name

(** Clear all hit counters.  Call between test files when running
    per-file coverage. *)
let reset () =
  Hashtbl.clear expr_hits;
  Hashtbl.clear branch_hits;
  Hashtbl.clear fn_hits

(* ------------------------------------------------------------------ *)
(* AST walker — computes the denominator for coverage percentages     *)
(* ------------------------------------------------------------------ *)

(** Reproduce [span_of_expr] locally so [coverage] does not depend on
    [march_eval] (which would create a circular dependency). *)
let span_of_expr (e : expr) : span =
  match e with
  | ELit (_, sp) | EApp (_, _, sp) | ECon (_, _, sp)
  | ELam (_, _, sp) | EBlock (_, sp) | ELet (_, sp)
  | EMatch (_, _, sp) | ETuple (_, sp) | ERecord (_, sp)
  | ERecordUpdate (_, _, sp) | EField (_, _, sp)
  | EIf (_, _, _, sp) | ECond (_, sp) | EPipe (_, _, sp) | EAnnot (_, _, sp)
  | EHole (_, sp) | EAtom (_, _, sp) | ESend (_, _, sp)
  | ESpawn (_, sp) | EDbg (_, sp) | ELetFn (_, _, _, _, sp) -> sp
  | EAssert (_, sp) -> sp
  | EVar n -> n.span
  | EResultRef _ -> dummy_span

let is_real_span (sp : span) =
  sp.file <> "" && sp.file <> "<none>" && sp.file <> "<unknown>"

(** Walk an expression tree counting nodes whose span matches [file].
    When [file] is [""], all nodes are counted. *)
let rec walk_expr ~file acc_e acc_b (e : expr) : unit =
  let sp = span_of_expr e in
  let in_file = (file = "" || sp.file = file) && is_real_span sp in
  if in_file then begin
    incr acc_e;
    match e with
    | EIf _ -> acc_b := !acc_b + 2
    | EMatch (_, branches, _) -> acc_b := !acc_b + List.length branches
    | _ -> ()
  end;
  (* Always recurse into children regardless of current node's file. *)
  match e with
  | EIf (cond, then_, else_, _) ->
    walk_expr ~file acc_e acc_b cond;
    walk_expr ~file acc_e acc_b then_;
    walk_expr ~file acc_e acc_b else_
  | ECond (arms, _) ->
    acc_b := !acc_b + List.length arms;
    List.iter (fun (ce, be) ->
      walk_expr ~file acc_e acc_b ce;
      walk_expr ~file acc_e acc_b be
    ) arms
  | EMatch (scrut, branches, _) ->
    walk_expr ~file acc_e acc_b scrut;
    List.iter (fun br ->
      walk_expr ~file acc_e acc_b br.branch_body;
      Option.iter (walk_expr ~file acc_e acc_b) br.branch_guard
    ) branches
  | EApp (f, args, _) ->
    walk_expr ~file acc_e acc_b f;
    List.iter (walk_expr ~file acc_e acc_b) args
  | ELam (_, body, _) ->
    walk_expr ~file acc_e acc_b body
  | EBlock (es, _) ->
    List.iter (walk_expr ~file acc_e acc_b) es
  | ELet (b, _) ->
    walk_expr ~file acc_e acc_b b.bind_expr
  | ELetFn (_, _, _, body, _) ->
    walk_expr ~file acc_e acc_b body
  | ETuple (es, _) ->
    List.iter (walk_expr ~file acc_e acc_b) es
  | ERecord (fields, _) ->
    List.iter (fun (_, ex) -> walk_expr ~file acc_e acc_b ex) fields
  | ERecordUpdate (base, updates, _) ->
    walk_expr ~file acc_e acc_b base;
    List.iter (fun (_, ex) -> walk_expr ~file acc_e acc_b ex) updates
  | EField (ex, _, _) | EAnnot (ex, _, _) ->
    walk_expr ~file acc_e acc_b ex
  | EDbg (Some ex, _) ->
    walk_expr ~file acc_e acc_b ex
  | ECon (_, args, _) ->
    List.iter (walk_expr ~file acc_e acc_b) args
  | EPipe (a, b, _) ->
    walk_expr ~file acc_e acc_b a;
    walk_expr ~file acc_e acc_b b
  | ESend (c, m, _) ->
    walk_expr ~file acc_e acc_b c;
    walk_expr ~file acc_e acc_b m
  | ESpawn (ex, _) ->
    walk_expr ~file acc_e acc_b ex
  | EAssert (ex, _) ->
    walk_expr ~file acc_e acc_b ex
  | EAtom (_, args, _) ->
    List.iter (walk_expr ~file acc_e acc_b) args
  | ELit _ | EVar _ | EHole _ | EDbg (None, _) | EResultRef _ -> ()

let walk_fn_clauses ~file acc_e acc_b (fn : fn_def) =
  List.iter (fun clause ->
    walk_expr ~file acc_e acc_b clause.fc_body;
    Option.iter (walk_expr ~file acc_e acc_b) clause.fc_guard
  ) fn.fn_clauses

let rec walk_decl ~file acc_e acc_b (d : decl) : unit =
  match d with
  | DFn (fn, _) ->
    walk_fn_clauses ~file acc_e acc_b fn
  | DLet (_, b, _) ->
    walk_expr ~file acc_e acc_b b.bind_expr
  | DMod (_, _, decls, _) ->
    List.iter (walk_decl ~file acc_e acc_b) decls
  | DTest (td, _) ->
    walk_expr ~file acc_e acc_b td.test_body
  | DSetup (body, _) | DSetupAll (body, _) ->
    walk_expr ~file acc_e acc_b body
  | DImpl (impl, _) ->
    List.iter (fun (_, fn) ->
      walk_fn_clauses ~file acc_e acc_b fn
    ) impl.impl_methods
  | DDescribe (_, decls, _) ->
    List.iter (walk_decl ~file acc_e acc_b) decls
  | DType _ | DActor _ | DInterface _ | DExtern _ | DNeeds _
  | DProtocol _ | DSig _ | DUse _ | DAlias _ | DApp _ | DDeriving _ -> ()

(** Count the total expressions and branches in [m], restricted to
    [file] when it is non-empty. *)
let count_totals ~file (m : module_) : int * int =
  let acc_e = ref 0 in
  let acc_b = ref 0 in
  List.iter (walk_decl ~file acc_e acc_b) m.mod_decls;
  (!acc_e, !acc_b)

(* ------------------------------------------------------------------ *)
(* Reporting                                                          *)
(* ------------------------------------------------------------------ *)

let pct n d =
  if d = 0 then 100.0
  else float_of_int n *. 100.0 /. float_of_int d

(** Count unique hit sites in [tbl] whose key starts with [file].
    When [file] is [""], all keys are counted. *)
let count_unique_hits (tbl : (string, int) Hashtbl.t) ~file =
  Hashtbl.fold (fun key _n acc ->
    let file_part = match String.index_opt key ':' with
      | None   -> key
      | Some i -> String.sub key 0 i
    in
    if file = "" || file_part = file then acc + 1 else acc
  ) tbl 0

(** Print a human-readable coverage summary table. *)
let report_summary ?(target_file="") (m : module_) () =
  let (total_exprs, total_branches) = count_totals ~file:target_file m in
  let hit_exprs    = count_unique_hits expr_hits   ~file:target_file in
  let hit_branches = count_unique_hits branch_hits ~file:target_file in
  Printf.printf "\n=== Coverage Summary";
  (if target_file <> "" then
    Printf.printf " [%s]" (Filename.basename target_file));
  Printf.printf " ===\n";
  Printf.printf "  Expressions: %4d / %4d  (%5.1f%%)\n"
    hit_exprs total_exprs (pct hit_exprs total_exprs);
  Printf.printf "  Branches:    %4d / %4d  (%5.1f%%)\n"
    hit_branches total_branches (pct hit_branches total_branches);
  let hit_fns = Hashtbl.length fn_hits in
  if hit_fns > 0 then
    Printf.printf "  Functions called: %d unique\n" hit_fns;
  Printf.printf "========================\n%!"

(** Print a machine-readable JSON coverage report to stdout. *)
let report_json () =
  let buf = Buffer.create 512 in
  let emit_table label tbl =
    Buffer.add_string buf (Printf.sprintf "  %S: {" label);
    let first = ref true in
    Hashtbl.iter (fun key count ->
      if not !first then Buffer.add_char buf ',';
      first := false;
      Buffer.add_string buf (Printf.sprintf "\n    %S: %d" key count)
    ) tbl;
    Buffer.add_string buf "\n  }"
  in
  Buffer.add_string buf "{\n";
  emit_table "expr_hits"   expr_hits;
  Buffer.add_string buf ",\n";
  emit_table "branch_hits" branch_hits;
  Buffer.add_string buf ",\n";
  emit_table "fn_hits"     fn_hits;
  Buffer.add_string buf "\n}\n";
  print_string (Buffer.contents buf)
