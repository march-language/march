(** Function inlining pass.
    Inlines pure, small, non-recursive functions at call sites.
    Alpha-renames inlined bodies to avoid variable capture.
    One level of inlining per iteration; chains handled by the fixed-point loop. *)

(** Maximum TIR node count for a function to be considered for inlining.
    Set higher than the original 15 to capture typical HTTP middleware helpers
    (header accessors, conn builders) that are otherwise too large to inline.
    Single-expression functions (node_count = 1) are always eligible regardless
    of this threshold — they are handled by the size check implicitly. *)
let inline_size_threshold = 50

module SSet = Set.Make (String)

(** Hot Code Reload boundary config, set by [Opt.run] for the duration of a
    run. When [Some], reloadable (boundary) functions are excluded from the
    inline-candidate set so a boundary→boundary call survives to codegen as a
    real call site that can route through the versioned dispatch table.
    [None] (the default) keeps the inliner fully aggressive. *)
let boundary_config : Hot_reload.config option ref = ref None

let is_reloadable_name name =
  match !boundary_config with
  | Some config ->
      Hot_reload.is_reloadable config (Hot_reload.module_of_name name)
  | None -> false

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

(** Collect direct calls to functions in the current candidate pool. *)
let direct_candidate_calls candidates expr =
  let rec collect acc = function
    | Tir.EApp (fn, _) when Hashtbl.mem candidates fn.Tir.v_name ->
      SSet.add fn.Tir.v_name acc
    | Tir.ELet (_, rhs, body) ->
      collect (collect acc rhs) body
    | Tir.ELetRec (fns, body) ->
      let acc =
        List.fold_left
          (fun calls fn -> collect calls fn.Tir.fn_body)
          acc fns
      in
      collect acc body
    | Tir.ECase (_, branches, default) ->
      let acc =
        List.fold_left
          (fun calls branch -> collect calls branch.Tir.br_body)
          acc branches
      in
      Option.fold ~none:acc ~some:(collect acc) default
    | Tir.ESeq (e1, e2) ->
      collect (collect acc e1) e2
    | _ -> acc
  in
  collect SSet.empty expr

(** Return candidates that participate in recursive call-graph SCCs. *)
let recursive_candidate_names (candidates : (string, Tir.fn_def) Hashtbl.t)
    : SSet.t =
  let successors : (string, SSet.t) Hashtbl.t = Hashtbl.create 16 in
  Hashtbl.iter (fun name fn ->
    Hashtbl.add successors name (direct_candidate_calls candidates fn.Tir.fn_body)
  ) candidates;
  let indices : (string, int) Hashtbl.t = Hashtbl.create 16 in
  let lowlinks : (string, int) Hashtbl.t = Hashtbl.create 16 in
  let index = ref 0 in
  let stack = ref [] in
  let on_stack = ref SSet.empty in
  let recursive = ref SSet.empty in
  let rec strongconnect name =
    Hashtbl.add indices name !index;
    Hashtbl.add lowlinks name !index;
    incr index;
    stack := name :: !stack;
    on_stack := SSet.add name !on_stack;
    SSet.iter (fun successor ->
      if not (Hashtbl.mem indices successor) then begin
        strongconnect successor;
        let lowlink = min (Hashtbl.find lowlinks name)
            (Hashtbl.find lowlinks successor) in
        Hashtbl.replace lowlinks name lowlink
      end else if SSet.mem successor !on_stack then begin
        let lowlink = min (Hashtbl.find lowlinks name)
            (Hashtbl.find indices successor) in
        Hashtbl.replace lowlinks name lowlink
      end
    ) (Hashtbl.find successors name);
    if Hashtbl.find lowlinks name = Hashtbl.find indices name then begin
      let rec pop_component component =
        match !stack with
        | member :: rest ->
          stack := rest;
          on_stack := SSet.remove member !on_stack;
          let component = SSet.add member component in
          if String.equal member name then component
          else pop_component component
        | [] -> assert false
      in
      let component = pop_component SSet.empty in
      if SSet.cardinal component > 1
         || SSet.mem name (Hashtbl.find successors name) then
        recursive := SSet.union !recursive component
    end
  in
  Hashtbl.iter (fun name _ ->
    if not (Hashtbl.mem indices name) then strongconnect name
  ) successors;
  !recursive

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
let subst_args ?(fn_name="?") params args body =
  if List.length params <> List.length args then
    failwith (Printf.sprintf
      "inline: arity mismatch in '%s': %d params vs %d args"
      fn_name (List.length params) (List.length args));
  List.fold_right2 (fun param arg acc ->
    Tir.ELet (param, Tir.EAtom arg, acc)
  ) params args body

let expand_call (fd : Tir.fn_def) args =
  if List.length fd.Tir.fn_params <> List.length args then None
  else
    let (new_params, new_body) =
      alpha_rename fd.Tir.fn_params fd.Tir.fn_body
    in
    if List.length new_params <> List.length args then
      failwith (Printf.sprintf
        "inline: alpha_rename changed arity for '%s': %d params -> %d new_params vs %d args"
        fd.Tir.fn_name (List.length fd.Tir.fn_params)
        (List.length new_params) (List.length args));
    Some (subst_args ~fn_name:fd.Tir.fn_name new_params args new_body)

let inline_expr ~changed (fn_env : (string, Tir.fn_def) Hashtbl.t)
    : Tir.expr -> Tir.expr =
  let rec go = function
    | Tir.EApp (f, args) ->
      (match Hashtbl.find_opt fn_env f.Tir.v_name with
       | Some fd ->
         (match expand_call fd args with
          | Some inlined ->
            changed := true;
            inlined
          | None -> Tir.EApp (f, args))
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
    (* Hot Code Reload: a reloadable (boundary) function must never be inlined,
       or its call sites would be fixed into callers and could not be swapped. *)
    let is_reloadable = is_reloadable_name fd.Tir.fn_name in
    if is_pure && is_small && not is_reloadable then
      Hashtbl.add fn_env fd.Tir.fn_name fd
  ) m.Tir.tm_fns;
  let recursive = recursive_candidate_names fn_env in
  SSet.iter (Hashtbl.remove fn_env) recursive;
  { m with Tir.tm_fns = List.map (fun fd ->
      { fd with Tir.fn_body = inline_expr ~changed fn_env fd.Tir.fn_body }
    ) m.Tir.tm_fns }
