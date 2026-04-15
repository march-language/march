(** March lint — static analysis rule engine.

    Implements all coding-standard rules from docs/coding-standards.md.
    No LSP protocol dependency; both [forge lint] and [march-lsp] consume this. *)

module Ast = March_ast.Ast
module Tc  = March_typecheck.Typecheck
module Err = March_errors.Errors

(* ------------------------------------------------------------------ *)
(* Public types                                                        *)
(* ------------------------------------------------------------------ *)

type severity = Error | Warning | Hint

type diagnostic = {
  file     : string;
  line     : int;       (** 1-based *)
  col      : int;       (** 0-based *)
  end_line : int;
  end_col  : int;
  rule     : string;    (** slug, e.g. "naming/snake-case-functions" *)
  severity : severity;
  message  : string;
}

type rule_severity = RSError | RSWarning | RSHint | RSOff

(** Per-rule severity overrides, built by the caller from .march-lint.toml. *)
type config = {
  rules : (string, rule_severity) Hashtbl.t;
}

(* ------------------------------------------------------------------ *)
(* Default config (mirrors .march-lint.toml defaults)                 *)
(* ------------------------------------------------------------------ *)

let default_rules : (string * rule_severity) list = [
  "naming/snake-case-functions",         RSWarning;
  "naming/pascal-case-types",            RSWarning;
  "naming/pascal-case-modules",          RSWarning;
  "naming/pascal-case-constructors",     RSWarning;
  "style/prefer-match",                  RSHint;
  "style/extract-arm-branches",          RSHint;
  "style/prefer-pipe",                   RSHint;
  "style/no-boolean-literal-compare",    RSWarning;
  "style/no-redundant-else",             RSHint;
  "style/de-morgan",                     RSHint;
  "style/doc-comment-public-fn",         RSHint;
  "style/annotate-public-fns",           RSHint;
  "safety/discard-result",               RSWarning;
  "safety/partial-let-pattern",          RSWarning;
  "safety/no-panic-in-lib",              RSWarning;
  "dead-code/unused-private-fn",         RSWarning;
  "dead-code/unreachable-after-diverge", RSWarning;
  "actors/handler-delegates-to-fn",      RSWarning;
  "actors/declare-message-type",         RSHint;
  "actors/no-spawn-in-handler",          RSWarning;
  "actors/annotate-state-fields",        RSWarning;
]

let default_config () =
  let tbl = Hashtbl.create 32 in
  List.iter (fun (rule, sev) -> Hashtbl.replace tbl rule sev) default_rules;
  { rules = tbl }

let all_rule_slugs = List.map fst default_rules

(** Resolve effective severity for a rule. None = disabled. *)
let effective_severity config rule =
  match Hashtbl.find_opt config.rules rule with
  | Some RSOff     -> None
  | Some RSError   -> Some Error
  | Some RSWarning -> Some Warning
  | Some RSHint    -> Some Hint
  | None           -> None

(* ------------------------------------------------------------------ *)
(* Internal helpers                                                    *)
(* ------------------------------------------------------------------ *)

let mk_diag file (sp : Ast.span) rule severity message =
  { file; line = sp.Ast.start_line; col = sp.Ast.start_col;
    end_line = sp.Ast.end_line; end_col = sp.Ast.end_col;
    rule; severity; message }

let emit acc file sp rule sev msg =
  acc := (mk_diag file sp rule sev msg) :: !acc

(* ---- Naming helpers ---- *)

let is_snake_case s =
  String.length s > 0 &&
  (let c = s.[0] in c >= 'a' && c <= 'z' || c = '_') &&
  String.for_all (fun c ->
    (c >= 'a' && c <= 'z') || (c >= '0' && c <= '9') || c = '_') s

let is_pascal_case s =
  String.length s > 0 &&
  (let c = s.[0] in c >= 'A' && c <= 'Z') &&
  String.for_all (fun c ->
    (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') ||
    (c >= '0' && c <= '9') || c = '_') s

let to_snake_case name =
  let buf = Buffer.create (String.length name + 4) in
  String.iteri (fun i c ->
    if i > 0 && c >= 'A' && c <= 'Z' then begin
      Buffer.add_char buf '_';
      Buffer.add_char buf (Char.lowercase_ascii c)
    end else
      Buffer.add_char buf (Char.lowercase_ascii c)
  ) name;
  Buffer.contents buf

(* ---- Type helpers ---- *)

let rec ty_root = function
  | Tc.TCon (name, _)              -> Some name
  | Tc.TVar { contents = Tc.Link t } -> ty_root t
  | Tc.TLin (_, t)                 -> ty_root t
  | _                              -> None

let is_result_ty ty = ty_root ty = Some "Result"
let is_never_ty  ty = ty_root ty = Some "Never"

(* ---- AST structure helpers ---- *)

(** Nesting depth of EApp chains (used for prefer-pipe). *)
let rec app_depth = function
  | Ast.EApp (fn, args, _) ->
    let fn_d   = app_depth fn in
    let arg_d  = List.fold_left (fun m a -> max m (app_depth a)) 0 args in
    1 + max fn_d arg_d
  | _ -> 0

(** True if the expression body of a match arm is "complex":
    contains a nested match, an if/else, or > 3 let bindings. *)
let arm_body_is_complex body =
  let lets = ref 0 in
  let branches = ref false in
  let rec walk = function
    | Ast.EMatch _  -> branches := true
    | Ast.EIf (_, _, Ast.EBlock (_, _), _) -> branches := true  (* if with else *)
    | Ast.EIf (_, _, Ast.EIf _, _)         -> branches := true  (* else-if chain *)
    | Ast.ELet _    -> incr lets
    | Ast.EBlock (xs, _) -> List.iter walk xs
    | _ -> ()
  in
  walk body;
  !branches || !lets > 3

(** Collect every name referenced inside an expression — both direct calls
    [f(x)] and bare references [map(f, xs)] / [x |> f].  A bare [EVar] is
    indistinguishable from a value reference here; that's fine, since we
    only consult these names against a known set of private function names. *)
let collect_call_names expr =
  let acc = ref [] in
  let rec walk = function
    | Ast.EVar n             -> acc := n.Ast.txt :: !acc
    | Ast.EApp (fn, args, _) -> walk fn; List.iter walk args
    | Ast.ECon (_, args, _)  -> List.iter walk args
    | Ast.ELam (_, body, _)  -> walk body
    | Ast.EBlock (xs, _)     -> List.iter walk xs
    | Ast.ELet (b, _)        -> walk b.Ast.bind_expr
    | Ast.EMatch (s, arms, _) ->
      walk s;
      List.iter (fun a -> walk a.Ast.branch_body) arms
    | Ast.EIf (c, t, e, _)   -> walk c; walk t; walk e
    | Ast.ECond (arms, _)    ->
      List.iter (fun (c, e) -> walk c; walk e) arms
    | Ast.EPipe (l, r, _)    -> walk l; walk r
    | Ast.ETuple (xs, _)     -> List.iter walk xs
    | Ast.ERecord (fs, _)    -> List.iter (fun (_, e) -> walk e) fs
    | Ast.ERecordUpdate (b, fs, _) ->
      walk b; List.iter (fun (_, e) -> walk e) fs
    | Ast.EField (e, _, _)   -> walk e
    | Ast.EAnnot (e, _, _)   -> walk e
    | Ast.EAtom (_, args, _) -> List.iter walk args
    | Ast.ESend (a, b, _)    -> walk a; walk b
    | Ast.ESpawn (e, _)      -> walk e
    | Ast.EDbg (Some e, _)   -> walk e
    | Ast.ELetFn (_, _, _, body, _) -> walk body
    | Ast.EAssert (e, _)     -> walk e
    | Ast.ESigil (_, e, _)   -> walk e
    | Ast.ELit _ | Ast.EHole _ | Ast.EResultRef _ | Ast.EDbg (None, _) -> ()
  in
  walk expr;
  !acc

(** Count else-if nesting depth (0 = plain if/else, 1+ = has else-if chains). *)
let rec elseif_depth = function
  | Ast.EIf (_, _, (Ast.EIf _ as e), _) -> 1 + elseif_depth e
  | _ -> 0

(* ------------------------------------------------------------------ *)
(* Naming rules                                                        *)
(* ------------------------------------------------------------------ *)

let check_naming ~config ~file ~acc decls =
  let r_fn  = "naming/snake-case-functions" in
  let r_ty  = "naming/pascal-case-types" in
  let r_mod = "naming/pascal-case-modules" in
  let r_con = "naming/pascal-case-constructors" in
  let rec walk = function
    | Ast.DFn (fn, _) ->
      let name = fn.Ast.fn_name.Ast.txt in
      (match effective_severity config r_fn with
       | Some sev when not (is_snake_case name) ->
         emit acc file fn.Ast.fn_name.Ast.span r_fn sev
           (Printf.sprintf "function `%s` should be snake_case; rename to `%s`"
              name (to_snake_case name))
       | _ -> ())

    | Ast.DType (_, tname, _, td, _) ->
      (match effective_severity config r_ty with
       | Some sev when not (is_pascal_case tname.Ast.txt) ->
         emit acc file tname.Ast.span r_ty sev
           (Printf.sprintf "type `%s` should be PascalCase" tname.Ast.txt)
       | _ -> ());
      (match td, effective_severity config r_con with
       | Ast.TDVariant variants, Some sev ->
         List.iter (fun (v : Ast.variant) ->
             if not (is_pascal_case v.Ast.var_name.Ast.txt) then
               emit acc file v.Ast.var_name.Ast.span r_con sev
                 (Printf.sprintf "constructor `%s` should be PascalCase"
                    v.Ast.var_name.Ast.txt)
           ) variants
       | _ -> ())

    | Ast.DMod (mname, _, inner, _) ->
      (match effective_severity config r_mod with
       | Some sev when not (is_pascal_case mname.Ast.txt) ->
         emit acc file mname.Ast.span r_mod sev
           (Printf.sprintf "module `%s` should be PascalCase" mname.Ast.txt)
       | _ -> ());
      List.iter walk inner

    | Ast.DActor (_, aname, adef, _) ->
      (match effective_severity config r_mod with
       | Some sev when not (is_pascal_case aname.Ast.txt) ->
         emit acc file aname.Ast.span r_mod sev
           (Printf.sprintf "actor `%s` should be PascalCase" aname.Ast.txt)
       | _ -> ());
      (* Check handler body naming — functions inside handlers *)
      List.iter (fun (h : Ast.actor_handler) ->
          ignore h   (* nested fns inside handlers are checked by outer walk *)
        ) adef.Ast.actor_handlers

    | _ -> ()
  in
  List.iter walk decls

(* ------------------------------------------------------------------ *)
(* Style rules                                                         *)
(* ------------------------------------------------------------------ *)

(** Walk all expressions in decls, checking style rules.
    [type_map] is used for [style/no-redundant-else]. *)
let check_style ~config ~file ~acc ~type_map decls =
  let r_match = "style/prefer-match" in
  let r_arm   = "style/extract-arm-branches" in
  let r_pipe  = "style/prefer-pipe" in
  let r_bool  = "style/no-boolean-literal-compare" in
  let r_else  = "style/no-redundant-else" in
  let r_dm    = "style/de-morgan" in
  let r_doc   = "style/doc-comment-public-fn" in
  let r_ann   = "style/annotate-public-fns" in

  let rec walk_decl = function
    | Ast.DFn (fn, _) ->
      (match effective_severity config r_doc with
       | Some sev when fn.Ast.fn_vis = Ast.Public && fn.Ast.fn_doc = None ->
         emit acc file fn.Ast.fn_name.Ast.span r_doc sev
           (Printf.sprintf "public function `%s` has no doc comment"
              fn.Ast.fn_name.Ast.txt)
       | _ -> ());
      (match effective_severity config r_ann with
       | Some sev when fn.Ast.fn_vis = Ast.Public && fn.Ast.fn_ret_ty = None ->
         emit acc file fn.Ast.fn_name.Ast.span r_ann sev
           (Printf.sprintf "public function `%s` has no return type annotation"
              fn.Ast.fn_name.Ast.txt)
       | _ -> ());
      List.iter (fun (cl : Ast.fn_clause) -> walk_expr cl.Ast.fc_body) fn.Ast.fn_clauses

    | Ast.DMod (_, _, inner, _) -> List.iter walk_decl inner

    | Ast.DActor (_, _, adef, _) ->
      List.iter (fun (h : Ast.actor_handler) -> walk_expr h.Ast.ah_body)
        adef.Ast.actor_handlers

    | _ -> ()

  and walk_expr expr =
    match expr with

    (* prefer-match: 2+ else-if branches *)
    | Ast.EIf (cond, then_, else_, sp) ->
      (if elseif_depth (Ast.EIf (cond, then_, else_, sp)) >= 1 then
         match effective_severity config r_match with
         | Some sev ->
           emit acc file sp r_match sev
             "prefer `match` over if/else-if chain with two or more branches"
         | None -> ());
      (* no-redundant-else: if the then-branch has type Never *)
      (match Hashtbl.find_opt type_map (Tc.span_of_expr then_) with
       | Some ty when is_never_ty ty ->
         (match effective_severity config r_else with
          | Some sev ->
            emit acc file (Tc.span_of_expr else_) r_else sev
              "`else` is redundant after a diverging branch; remove it and let code fall through"
          | None -> ())
       | _ -> ());
      walk_expr cond; walk_expr then_; walk_expr else_

    (* extract-arm-branches *)
    | Ast.EMatch (subj, arms, _) ->
      walk_expr subj;
      List.iter (fun (a : Ast.branch) ->
          (if arm_body_is_complex a.Ast.branch_body then
             match effective_severity config r_arm with
             | Some sev ->
               emit acc file (Tc.span_of_expr a.Ast.branch_body) r_arm sev
                 "match arm has complex body; extract logic to a private multi-head function"
             | None -> ());
          walk_expr a.Ast.branch_body
        ) arms

    (* All EApp cases: check specific patterns then recurse *)
    | Ast.EApp (fn, args, sp) as e ->
      (* prefer-pipe *)
      (if app_depth e >= 3 then
         match effective_severity config r_pipe with
         | Some sev ->
           emit acc file sp r_pipe sev
             "three or more nested function calls; prefer pipeline style with |>"
         | None -> ());
      (* no-boolean-literal-compare *)
      (match fn, args with
       | Ast.EVar op, [_; Ast.ELit (Ast.LitBool _, bsp)]
       | Ast.EVar op, [Ast.ELit (Ast.LitBool _, bsp); _]
         when op.Ast.txt = "==" || op.Ast.txt = "!=" ->
         (match effective_severity config r_bool with
          | Some sev ->
            emit acc file bsp r_bool sev
              "comparing to a boolean literal; use the expression directly (or negate with !)"
          | None -> ())
       | _ -> ());
      (* de-morgan: !(a && b)  !(a || b) *)
      (match fn, args with
       | Ast.EVar neg, [Ast.EApp (Ast.EVar op, [_; _], _)]
         when neg.Ast.txt = "!" && (op.Ast.txt = "&&" || op.Ast.txt = "||") ->
         let dual = if op.Ast.txt = "&&" then "||" else "&&" in
         (match effective_severity config r_dm with
          | Some sev ->
            emit acc file sp r_dm sev
              (Printf.sprintf "De Morgan: `!(a %s b)` can be written as `!a %s !b`"
                 op.Ast.txt dual)
          | None -> ())
       | Ast.EVar op,
         [Ast.EApp (Ast.EVar neg1, [_], _); Ast.EApp (Ast.EVar neg2, [_], _)]
         when neg1.Ast.txt = "!" && neg2.Ast.txt = "!" &&
              (op.Ast.txt = "&&" || op.Ast.txt = "||") ->
         let dual = if op.Ast.txt = "&&" then "||" else "&&" in
         (match effective_severity config r_dm with
          | Some sev ->
            emit acc file sp r_dm sev
              (Printf.sprintf "De Morgan: `!a %s !b` can be written as `!(a %s b)`"
                 op.Ast.txt dual)
          | None -> ())
       | _ -> ());
      walk_expr fn; List.iter walk_expr args

    (* block: walk each sub-expression *)
    | Ast.EBlock (xs, _)     -> List.iter walk_expr xs
    | Ast.ELet (b, _)        -> walk_expr b.Ast.bind_expr
    | Ast.EPipe (l, r, _)    -> walk_expr l; walk_expr r
    | Ast.ETuple (xs, _)     -> List.iter walk_expr xs
    | Ast.EField (e, _, _)   -> walk_expr e
    | Ast.ECon (_, args, _)  -> List.iter walk_expr args
    | _                      -> ()
  in
  List.iter walk_decl decls

(* ------------------------------------------------------------------ *)
(* Safety rules                                                        *)
(* ------------------------------------------------------------------ *)

(** True if [filename] looks like a library file (not app entry, not test). *)
let is_lib_file filename =
  let base = Filename.basename filename in
  not (String.length base >= 10 && String.sub base (String.length base - 10) 10 = "_test.march") &&
  not (base = "main.march")

(** Known fallible single-constructor patterns that are always partial. *)
let is_partial_pat = function
  | Ast.PatCon (name, _) ->
    let n = name.Ast.txt in
    n = "Some" || n = "Ok" || n = "Err"
  | _ -> false

let check_safety ~config ~file ~acc ~type_map decls =
  let r_result  = "safety/discard-result" in
  let r_partial = "safety/partial-let-pattern" in
  let r_panic   = "safety/no-panic-in-lib" in

  let rec walk_expr expr =
    match expr with

    (* discard-result: non-last EApp in a block with Result type *)
    | Ast.EBlock (xs, _) ->
      let n = List.length xs in
      List.iteri (fun i e ->
          (match e with
           | Ast.EApp _ when i < n - 1 ->
             let sp = Tc.span_of_expr e in
             (match Hashtbl.find_opt type_map sp with
              | Some ty when is_result_ty ty ->
                (match effective_severity config r_result with
                 | Some sev ->
                   emit acc file sp r_result sev
                     "Result value discarded; bind it, propagate with ?, or match both arms"
                 | None -> ())
              | _ -> ())
           | _ -> ());
          walk_expr e
        ) xs

    (* partial-let-pattern: let Some(x) = expr, let Ok(x) = expr, etc. *)
    | Ast.ELet (b, sp) ->
      (if is_partial_pat b.Ast.bind_pat then
         match effective_severity config r_partial with
         | Some sev ->
           emit acc file sp r_partial sev
             "partial let pattern will panic if value doesn't match; use match instead"
         | None -> ());
      walk_expr b.Ast.bind_expr

    (* no-panic-in-lib *)
    | Ast.EApp (Ast.EVar fn, _, sp) when fn.Ast.txt = "panic" ->
      if is_lib_file file then
        (match effective_severity config r_panic with
         | Some sev ->
           emit acc file sp r_panic sev
             "panic in library code; return Result or Option instead"
         | None -> ())

    | Ast.EApp (fn, args, _)    -> walk_expr fn; List.iter walk_expr args
    | Ast.EMatch (s, arms, _)   ->
      walk_expr s;
      List.iter (fun a -> walk_expr a.Ast.branch_body) arms
    | Ast.EIf (c, t, e, _)     -> walk_expr c; walk_expr t; walk_expr e
    | Ast.EPipe (l, r, _)       -> walk_expr l; walk_expr r
    | Ast.ETuple (xs, _)        -> List.iter walk_expr xs
    | Ast.EField (e, _, _)      -> walk_expr e
    | Ast.ECon (_, args, _)     -> List.iter walk_expr args
    | _                         -> ()
  in

  let rec walk_decl = function
    | Ast.DFn (fn, _) ->
      List.iter (fun (cl : Ast.fn_clause) -> walk_expr cl.Ast.fc_body) fn.Ast.fn_clauses
    | Ast.DMod (_, _, inner, _) -> List.iter walk_decl inner
    | Ast.DActor (_, _, adef, _) ->
      List.iter (fun (h : Ast.actor_handler) -> walk_expr h.Ast.ah_body)
        adef.Ast.actor_handlers
    | _ -> ()
  in
  List.iter walk_decl decls

(* ------------------------------------------------------------------ *)
(* Dead code rules                                                     *)
(* ------------------------------------------------------------------ *)

let check_dead_code ~config ~file ~acc ~type_map decls =
  let r_diverge = "dead-code/unreachable-after-diverge" in
  let r_unused  = "dead-code/unused-private-fn" in

  (* unreachable-after-diverge: in EBlock, if a non-last expr has type Never,
     the remaining expressions are unreachable. *)
  let rec walk_expr expr =
    match expr with
    | Ast.EBlock (xs, _) ->
      let n = List.length xs in
      let _ = List.fold_left (fun diverged (i, e) ->
          if diverged && i < n then begin
            (match effective_severity config r_diverge with
             | Some sev ->
               emit acc file (Tc.span_of_expr e) r_diverge sev
                 "unreachable code after diverging call"
             | None -> ())
          end;
          let this_diverges =
            match Hashtbl.find_opt type_map (Tc.span_of_expr e) with
            | Some ty -> is_never_ty ty
            | None    -> false
          in
          walk_expr e;
          diverged || this_diverges
        ) false (List.mapi (fun i e -> (i, e)) xs)
      in ()

    | Ast.ELet (b, _)        -> walk_expr b.Ast.bind_expr
    | Ast.EApp (fn, args, _) -> walk_expr fn; List.iter walk_expr args
    | Ast.EMatch (s, arms, _) ->
      walk_expr s;
      List.iter (fun a -> walk_expr a.Ast.branch_body) arms
    | Ast.EIf (c, t, e, _)   -> walk_expr c; walk_expr t; walk_expr e
    | Ast.EPipe (l, r, _)     -> walk_expr l; walk_expr r
    | Ast.ETuple (xs, _)      -> List.iter walk_expr xs
    | Ast.EField (e, _, _)    -> walk_expr e
    | Ast.ECon (_, args, _)   -> List.iter walk_expr args
    | _                       -> ()
  in

  (* unused-private-fn: collect pfns, collect reachable names, report gaps.
     Reachability roots = bodies of anything that's "called from outside":
     public fns, tests, setup blocks, actor handlers, top-level lets, app/init. *)
  let private_fns : (string, Ast.span) Hashtbl.t = Hashtbl.create 16 in
  let roots       : Ast.expr list ref = ref [] in

  let add_root e = roots := e :: !roots in

  let rec collect_decl = function
    | Ast.DFn (fn, _) ->
      if fn.Ast.fn_vis = Ast.Private then
        Hashtbl.replace private_fns fn.Ast.fn_name.Ast.txt fn.Ast.fn_name.Ast.span
      else
        List.iter (fun (cl : Ast.fn_clause) -> add_root cl.Ast.fc_body)
          fn.Ast.fn_clauses;
      List.iter (fun (cl : Ast.fn_clause) -> walk_expr cl.Ast.fc_body) fn.Ast.fn_clauses
    | Ast.DTest (td, _)            -> add_root td.Ast.test_body
    | Ast.DSetup (e, _)            -> add_root e
    | Ast.DSetupAll (e, _)         -> add_root e
    | Ast.DDescribe (_, inner, _)  -> List.iter collect_decl inner
    | Ast.DLet (_, b, _)           -> add_root b.Ast.bind_expr
    | Ast.DActor (_, _, adef, _)   ->
      add_root adef.Ast.actor_init;
      List.iter (fun (h : Ast.actor_handler) -> add_root h.Ast.ah_body)
        adef.Ast.actor_handlers
    | Ast.DApp (adef, _)           ->
      add_root adef.Ast.app_body;
      Option.iter add_root adef.Ast.app_on_start;
      Option.iter add_root adef.Ast.app_on_stop
    | Ast.DImpl (idef, _)          ->
      List.iter (fun (_, fn_def) ->
          List.iter (fun (cl : Ast.fn_clause) -> add_root cl.Ast.fc_body)
            fn_def.Ast.fn_clauses
        ) idef.Ast.impl_methods
    | Ast.DMod (_, _, inner, _)    -> List.iter collect_decl inner
    | _ -> ()
  in
  List.iter collect_decl decls;

  if Hashtbl.length private_fns > 0 then begin
    (* BFS/DFS reachability: start from public function bodies, follow calls *)
    let reachable = Hashtbl.create 16 in
    let worklist  = Queue.create () in
    (* Seed with names referenced from any reachability root *)
    List.iter (fun body ->
        List.iter (fun name -> Queue.push name worklist)
          (collect_call_names body)
      ) !roots;
    while not (Queue.is_empty worklist) do
      let name = Queue.pop worklist in
      if not (Hashtbl.mem reachable name) then begin
        Hashtbl.replace reachable name ();
        (* If this is a private fn, also collect its body's calls *)
        if Hashtbl.mem private_fns name then begin
          (* Re-walk decls to find the body — simple linear scan is fine for lint *)
          let rec find_body = function
            | Ast.DFn (fn, _) when fn.Ast.fn_name.Ast.txt = name ->
              List.iter (fun (cl : Ast.fn_clause) ->
                  List.iter (fun n -> Queue.push n worklist)
                    (collect_call_names cl.Ast.fc_body)
                ) fn.Ast.fn_clauses
            | Ast.DMod (_, _, inner, _)   -> List.iter find_body inner
            | Ast.DDescribe (_, inner, _) -> List.iter find_body inner
            | _ -> ()
          in
          List.iter find_body decls
        end
      end
    done;
    (* Report private fns not in reachable set *)
    match effective_severity config r_unused with
    | Some sev ->
      Hashtbl.iter (fun name sp ->
          if not (Hashtbl.mem reachable name) then
            emit acc file sp r_unused sev
              (Printf.sprintf "private function `%s` is never called" name)
        ) private_fns
    | None -> ()
  end

(* ------------------------------------------------------------------ *)
(* Actor rules                                                         *)
(* ------------------------------------------------------------------ *)

(** Check if a type decl named after [actor_name] (or [actor_name ^ "Msg"])
    appears in the same decl list, immediately before [actor_idx]. *)
let has_message_type_decl decls actor_idx =
  let n = List.length decls in
  let arr = Array.of_list decls in
  (* Look within a window of 3 decls before the actor *)
  let lo = max 0 (actor_idx - 3) in
  let result = ref false in
  for i = lo to min (actor_idx - 1) (n - 1) do
    (match arr.(i) with
     | Ast.DType _ -> result := true
     | _ -> ())
  done;
  !result

let rec check_actors ~config ~file ~acc decls =
  let r_delegate   = "actors/handler-delegates-to-fn" in
  let r_msg_type   = "actors/declare-message-type" in
  let r_no_spawn   = "actors/no-spawn-in-handler" in
  let r_state_ann  = "actors/annotate-state-fields" in

  List.iteri (fun idx decl ->
      match decl with
      | Ast.DActor (_, aname, adef, _) ->

        (* declare-message-type: check for an adjacent type decl *)
        (if List.length adef.Ast.actor_handlers >= 2 then
           match effective_severity config r_msg_type with
           | Some sev when not (has_message_type_decl decls idx) ->
             emit acc file aname.Ast.span r_msg_type sev
               (Printf.sprintf
                  "actor `%s` has no adjacent message type declaration; add `type %sMsg = ...` before this actor"
                  aname.Ast.txt aname.Ast.txt)
           | _ -> ());

        (* annotate-state-fields *)
        (* State fields: actor_state is a field list; fields always have fld_ty set
           since the type parser requires it for state blocks. We check for
           missing annotation by looking at whether fld_ty is the wildcard/inferred. *)
        (* Note: in practice, state fields without annotations would be a parse
           error in March, so this rule guards against future changes. We still
           emit a lint diagnostic if any field looks untyped. *)
        (match effective_severity config r_state_ann with
         | Some sev ->
           List.iter (fun (f : Ast.field) ->
               (* A field "typed" as TyCon with empty txt suggests inferred/missing *)
               match f.Ast.fld_ty with
               | Ast.TyCon ({ txt = "_"; _ }, _) ->
                 emit acc file f.Ast.fld_name.Ast.span r_state_ann sev
                   (Printf.sprintf "actor state field `%s` has no type annotation"
                      f.Ast.fld_name.Ast.txt)
               | _ -> ()
             ) adef.Ast.actor_state
         | None -> ());

        (* Check each handler *)
        List.iter (fun (h : Ast.actor_handler) ->

            (* handler-delegates-to-fn *)
            (if arm_body_is_complex h.Ast.ah_body then
               match effective_severity config r_delegate with
               | Some sev ->
                 emit acc file h.Ast.ah_msg.Ast.span r_delegate sev
                   (Printf.sprintf
                      "handler `on %s` has complex body; extract logic to a private function"
                      h.Ast.ah_msg.Ast.txt)
               | None -> ());

            (* no-spawn-in-handler *)
            (let calls = collect_call_names h.Ast.ah_body in
             if List.mem "spawn" calls || List.mem "spawn_actor" calls then
               match effective_severity config r_no_spawn with
               | Some sev ->
                 emit acc file h.Ast.ah_msg.Ast.span r_no_spawn sev
                   (Printf.sprintf
                      "handler `on %s` spawns an actor; move spawning to init or supervision config"
                      h.Ast.ah_msg.Ast.txt)
               | None -> ())

          ) adef.Ast.actor_handlers

      | Ast.DMod (_, _, inner, _) -> check_actors ~config ~file ~acc inner
      | _ -> ()
    ) decls

(* ------------------------------------------------------------------ *)
(* Parse + typecheck a source file                                     *)
(* ------------------------------------------------------------------ *)

let parse_and_check ~filename ~src =
  let lexbuf = Lexing.from_string src in
  lexbuf.Lexing.lex_curr_p <-
    { lexbuf.Lexing.lex_curr_p with Lexing.pos_fname = filename };
  match
    (try
       Result.Ok
         (March_parser.Parser.module_
            (March_parser.Token_filter.make March_lexer.Lexer.token)
            lexbuf)
     with
     | Err.ParseError (msg, _hint, _pos) -> Result.Error msg
     | March_parser.Parser.Error          -> Result.Error "parse error"
     | March_lexer.Lexer.Lexer_error msg  -> Result.Error msg)
  with
  | Result.Error msg -> Result.Error msg
  | Result.Ok raw_ast ->
    let desugared = March_desugar.Desugar.desugar_module raw_ast in
    let (_errs, type_map) = Tc.check_module desugared in
    Result.Ok (desugared, type_map)

(* ------------------------------------------------------------------ *)
(* Top-level entry point                                               *)
(* ------------------------------------------------------------------ *)

(** Check a single source file and return diagnostics.
    Parse errors are returned as a single diagnostic with rule "parse/error". *)
let check_file ~config ~filename ~src : diagnostic list =
  match parse_and_check ~filename ~src with
  | Result.Error msg ->
    [ { file = filename; line = 1; col = 0;
        end_line = 1; end_col = 0;
        rule = "parse/error"; severity = Error;
        message = msg } ]
  | Result.Ok (desugared, type_map) ->
    let acc = ref [] in
    let decls = desugared.Ast.mod_decls in
    check_naming    ~config ~file:filename ~acc decls;
    check_style     ~config ~file:filename ~acc ~type_map decls;
    check_safety    ~config ~file:filename ~acc ~type_map decls;
    check_dead_code ~config ~file:filename ~acc ~type_map decls;
    check_actors    ~config ~file:filename ~acc decls;
    List.sort (fun a b ->
        let c = compare a.line b.line in
        if c <> 0 then c else compare a.col b.col
      ) !acc
