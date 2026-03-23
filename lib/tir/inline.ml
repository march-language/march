(** Function inlining pass.
    Inlines pure, small, non-recursive functions at call sites.
    Alpha-renames inlined bodies to avoid variable capture.
    One level of inlining per iteration; chains handled by the fixed-point loop. *)

let inline_size_threshold = 15

(** Count TIR nodes (approximate size). *)
let rec node_count : Tir.expr -> int = function
  | Tir.EAtom _ | Tir.ETuple _ | Tir.ERecord _ | Tir.EField _
  | Tir.EUpdate _ | Tir.EAlloc _ | Tir.EStackAlloc _
  | Tir.EIncRC _ | Tir.EDecRC _ | Tir.EFree _ | Tir.EReuse _
  | Tir.EAtomicIncRC _ | Tir.EAtomicDecRC _ -> 1
  | Tir.EApp (_, args)     -> 1 + List.length args
  | Tir.ECallPtr (_, args) -> 1 + List.length args
  | Tir.ELet (_, rhs, body) -> 1 + node_count rhs + node_count body
  | Tir.ELetRec (fns, body) ->
    1 + List.fold_left (fun a fd -> a + node_count fd.Tir.fn_body) 0 fns
    + node_count body
  | Tir.ECase (_, branches, default) ->
    1 + List.fold_left (fun a b -> a + node_count b.Tir.br_body) 0 branches
    + Option.fold ~none:0 ~some:node_count default
  | Tir.ESeq (e1, e2) -> 1 + node_count e1 + node_count e2

(** Check if a function calls itself (recursion detection). *)
let rec calls_self name : Tir.expr -> bool = function
  | Tir.EApp (f, _) when f.Tir.v_name = name -> true
  | Tir.ELet (_, rhs, body) -> calls_self name rhs || calls_self name body
  | Tir.ELetRec (fns, body) ->
    List.exists (fun fd -> calls_self name fd.Tir.fn_body) fns
    || calls_self name body
  | Tir.ECase (_, branches, default) ->
    List.exists (fun b -> calls_self name b.Tir.br_body) branches
    || Option.fold ~none:false ~some:(calls_self name) default
  | Tir.ESeq (e1, e2) -> calls_self name e1 || calls_self name e2
  | _ -> false

(** Alpha-rename: give each parameter and let-bound variable a fresh name. *)
let gensym =
  let ctr = ref 0 in
  fun prefix -> incr ctr; Printf.sprintf "%s_i%d" prefix !ctr

let alpha_rename (params : Tir.var list) (body : Tir.expr)
    : (Tir.var list * Tir.expr) =
  let tbl : (string, string) Hashtbl.t = Hashtbl.create 8 in
  let new_params = List.map (fun v ->
    let fresh = gensym v.Tir.v_name in
    Hashtbl.replace tbl v.Tir.v_name fresh;
    { v with Tir.v_name = fresh }
  ) params in
  let subst_var v =
    match Hashtbl.find_opt tbl v.Tir.v_name with
    | Some n -> { v with Tir.v_name = n }
    | None   -> v
  in
  let subst_atom = function
    | Tir.AVar v -> Tir.AVar (subst_var v)
    | a          -> a
  in
  let rec subst_expr = function
    | Tir.EAtom a            -> Tir.EAtom (subst_atom a)
    | Tir.EApp (f, args)     -> Tir.EApp (subst_var f, List.map subst_atom args)
    | Tir.ECallPtr (f, args) -> Tir.ECallPtr (subst_atom f, List.map subst_atom args)
    | Tir.ELet (v, rhs, body) ->
      let rhs' = subst_expr rhs in          (* process rhs with OLD tbl *)
      let fresh = gensym v.Tir.v_name in
      Hashtbl.replace tbl v.Tir.v_name fresh;
      let v' = { v with Tir.v_name = fresh } in
      Tir.ELet (v', rhs', subst_expr body)
    | Tir.ELetRec (fns, b) ->
      (* Freshen all locally-bound function names first *)
      let fns_renamed = List.map (fun fd ->
        let fresh = gensym fd.Tir.fn_name in
        Hashtbl.replace tbl fd.Tir.fn_name fresh;
        { fd with Tir.fn_name = fresh }
      ) fns in
      (* Then process each body with the updated tbl *)
      Tir.ELetRec (List.map (fun fd ->
        { fd with Tir.fn_body = subst_expr fd.Tir.fn_body }) fns_renamed,
        subst_expr b)
    | Tir.ECase (a, branches, default) ->
      Tir.ECase (subst_atom a,
        List.map (fun b ->
          let bound = List.map (fun v ->
            let fresh = gensym v.Tir.v_name in
            Hashtbl.replace tbl v.Tir.v_name fresh;
            { v with Tir.v_name = fresh }
          ) b.Tir.br_vars in
          { b with Tir.br_vars = bound; Tir.br_body = subst_expr b.Tir.br_body })
          branches,
        Option.map subst_expr default)
    | Tir.ETuple atoms       -> Tir.ETuple (List.map subst_atom atoms)
    | Tir.ERecord fields     ->
      Tir.ERecord (List.map (fun (k, a) -> (k, subst_atom a)) fields)
    | Tir.EField (a, f)      -> Tir.EField (subst_atom a, f)
    | Tir.EUpdate (a, fs)    ->
      Tir.EUpdate (subst_atom a, List.map (fun (k, v) -> (k, subst_atom v)) fs)
    | Tir.EAlloc (ty, args)  -> Tir.EAlloc (ty, List.map subst_atom args)
    | Tir.EStackAlloc (ty, args) -> Tir.EStackAlloc (ty, List.map subst_atom args)
    | Tir.EFree a            -> Tir.EFree (subst_atom a)
    | Tir.EIncRC a           -> Tir.EIncRC (subst_atom a)
    | Tir.EDecRC a           -> Tir.EDecRC (subst_atom a)
    | Tir.EAtomicIncRC a     -> Tir.EAtomicIncRC (subst_atom a)
    | Tir.EAtomicDecRC a     -> Tir.EAtomicDecRC (subst_atom a)
    | Tir.EReuse (a, ty, args) ->
      Tir.EReuse (subst_atom a, ty, List.map subst_atom args)
    | Tir.ESeq (e1, e2)      -> Tir.ESeq (subst_expr e1, subst_expr e2)
  in
  (new_params, subst_expr body)

(** Substitute parameters for call arguments, wrapped in ANF lets. *)
let subst_args params args body =
  if List.length params <> List.length args then
    failwith (Printf.sprintf
      "inline: arity mismatch: %d params vs %d args"
      (List.length params) (List.length args));
  List.fold_right2 (fun param arg acc ->
    Tir.ELet (param, Tir.EAtom arg, acc)
  ) params args body

let inline_expr ~changed (fn_env : (string, Tir.fn_def) Hashtbl.t)
    : Tir.expr -> Tir.expr =
  let rec go = function
    | Tir.EApp (f, args) ->
      (match Hashtbl.find_opt fn_env f.Tir.v_name with
       | Some fd ->
         let (new_params, new_body) = alpha_rename fd.Tir.fn_params fd.Tir.fn_body in
         let inlined = subst_args new_params args new_body in
         changed := true;
         inlined
       | None -> Tir.EApp (f, args))
    | Tir.ELet (v, rhs, body) -> Tir.ELet (v, go rhs, go body)
    | Tir.ELetRec (fns, body) ->
      Tir.ELetRec (List.map (fun fd ->
        { fd with Tir.fn_body = go fd.Tir.fn_body }) fns, go body)
    | Tir.ECase (a, branches, default) ->
      Tir.ECase (a,
        List.map (fun b -> { b with Tir.br_body = go b.Tir.br_body }) branches,
        Option.map go default)
    | Tir.ESeq (e1, e2) -> Tir.ESeq (go e1, go e2)
    | other -> other
  in
  go

let run ~changed (m : Tir.tir_module) : Tir.tir_module =
  let fn_env : (string, Tir.fn_def) Hashtbl.t = Hashtbl.create 16 in
  List.iter (fun fd ->
    let is_pure     = Purity.is_pure fd.Tir.fn_body in
    let is_small    = node_count fd.Tir.fn_body <= inline_size_threshold in
    let is_nonrec   = not (calls_self fd.Tir.fn_name fd.Tir.fn_body) in
    if is_pure && is_small && is_nonrec then
      Hashtbl.add fn_env fd.Tir.fn_name fd
  ) m.Tir.tm_fns;
  (* Conservative mutual-recursion filter:
     Remove any candidate that calls another candidate to prevent infinite
     fixed-point loops. Chains (f→g→h non-circular) still work correctly:
     only g/h are inlined in this pass; f gains their bodies and becomes
     eligible in subsequent fixed-point iterations. *)
  let candidate_names = Hashtbl.fold (fun k _ acc -> k :: acc) fn_env [] in
  List.iter (fun name ->
    match Hashtbl.find_opt fn_env name with
    | None -> ()  (* already removed *)
    | Some fd ->
      let calls_other =
        let rec check = function
          | Tir.EApp (f, _) -> List.mem f.Tir.v_name candidate_names && f.Tir.v_name <> name
          | Tir.ELet (_, rhs, body) -> check rhs || check body
          | Tir.ELetRec (fns, body) ->
            List.exists (fun nfd -> check nfd.Tir.fn_body) fns || check body
          | Tir.ECase (_, branches, default) ->
            List.exists (fun b -> check b.Tir.br_body) branches
            || Option.fold ~none:false ~some:check default
          | Tir.ESeq (e1, e2) -> check e1 || check e2
          | _ -> false
        in
        check fd.Tir.fn_body
      in
      if calls_other then Hashtbl.remove fn_env name
  ) candidate_names;
  { m with Tir.tm_fns = List.map (fun fd ->
      { fd with Tir.fn_body = inline_expr ~changed fn_env fd.Tir.fn_body }
    ) m.Tir.tm_fns }
