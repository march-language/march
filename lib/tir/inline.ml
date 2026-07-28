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
module SMap = Map.Make (String)

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

let add_var_name names var = SSet.add var.Tir.v_name names

let add_atom_name names = function
  | Tir.AVar var -> add_var_name names var
  | Tir.ADefRef def -> SSet.add def.Tir.did_name names
  | Tir.ALit _ -> names

let add_atom_names names atoms =
  List.fold_left add_atom_name names atoms

let rec add_expr_names names = function
  | Tir.EAtom atom -> add_atom_name names atom
  | Tir.EApp (callee, args) ->
    add_atom_names (add_var_name names callee) args
  | Tir.ECallPtr (callee, args) ->
    add_atom_names (add_atom_name names callee) args
  | Tir.ELet (var, rhs, body) ->
    add_expr_names (add_expr_names (add_var_name names var) rhs) body
  | Tir.ELetRec (fns, body) ->
    let names =
      List.fold_left
        (fun names fn ->
          let names = SSet.add fn.Tir.fn_name names in
          List.fold_left add_var_name names fn.Tir.fn_params)
        names fns
    in
    List.fold_left
      (fun names fn -> add_expr_names names fn.Tir.fn_body)
      (add_expr_names names body) fns
  | Tir.ECase (atom, branches, default) ->
    let names = add_atom_name names atom in
    let names =
      List.fold_left
        (fun names branch ->
          let names =
            List.fold_left add_var_name names branch.Tir.br_vars
          in
          add_expr_names names branch.Tir.br_body)
        names branches
    in
    Option.fold ~none:names ~some:(add_expr_names names) default
  | Tir.ETuple atoms
  | Tir.EAlloc (_, atoms)
  | Tir.EStackAlloc (_, atoms) ->
    add_atom_names names atoms
  | Tir.ERecord fields ->
    List.fold_left
      (fun names (_, atom) -> add_atom_name names atom)
      names fields
  | Tir.EField (atom, _) ->
    add_atom_name names atom
  | Tir.EUpdate (atom, fields) ->
    List.fold_left
      (fun names (_, value) -> add_atom_name names value)
      (add_atom_name names atom) fields
  | Tir.EFree atom
  | Tir.EIncRC atom
  | Tir.EDecRC atom
  | Tir.EAtomicIncRC atom
  | Tir.EAtomicDecRC atom ->
    add_atom_name names atom
  | Tir.EReuse (reuse, _, args) ->
    add_atom_names (add_atom_name names reuse) args
  | Tir.ESeq (first, second) ->
    add_expr_names (add_expr_names names first) second

let alpha_rename (params : Tir.var list) (body : Tir.expr)
    : (Tir.var list * Tir.expr) =
  let used_names =
    ref
      (List.fold_left add_var_name
         (add_expr_names SSet.empty body) params)
  in
  let freshen_name env name =
    let rec choose () =
      let candidate = gensym name in
      if SSet.mem candidate !used_names then choose () else candidate
    in
    let fresh = choose () in
    used_names := SSet.add fresh !used_names;
    (fresh, SMap.add name fresh env)
  in
  let freshen_var env v =
    let fresh, env = freshen_name env v.Tir.v_name in
    ({ v with Tir.v_name = fresh }, env)
  in
  let freshen_vars env vars =
    let renamed, env =
      List.fold_left
        (fun (renamed, env) var ->
          let var, env = freshen_var env var in
          (var :: renamed, env))
        ([], env) vars
    in
    (List.rev renamed, env)
  in
  let subst_var env v =
    match SMap.find_opt v.Tir.v_name env with
    | Some n -> { v with Tir.v_name = n }
    | None   -> v
  in
  let subst_atom env = function
    | Tir.AVar v -> Tir.AVar (subst_var env v)
    | a          -> a
  in
  let rec subst_expr env = function
    | Tir.EAtom a            -> Tir.EAtom (subst_atom env a)
    | Tir.EApp (f, args)     ->
      Tir.EApp (subst_var env f, List.map (subst_atom env) args)
    | Tir.ECallPtr (f, args) ->
      Tir.ECallPtr (subst_atom env f, List.map (subst_atom env) args)
    | Tir.ELet (v, rhs, body) ->
      let rhs = subst_expr env rhs in
      let v, body_env = freshen_var env v in
      Tir.ELet (v, rhs, subst_expr body_env body)
    | Tir.ELetRec (fns, body) ->
      let fns, recursive_env =
        List.fold_left
          (fun (renamed, env) fn ->
            let fresh, env = freshen_name env fn.Tir.fn_name in
            ({ fn with Tir.fn_name = fresh } :: renamed, env))
          ([], env) fns
      in
      let fns = List.rev fns in
      let fns =
        List.map
          (fun fn ->
            let params, fn_env =
              freshen_vars recursive_env fn.Tir.fn_params
            in
            { fn with
              Tir.fn_params = params;
              fn_body = subst_expr fn_env fn.Tir.fn_body })
          fns
      in
      Tir.ELetRec (fns, subst_expr recursive_env body)
    | Tir.ECase (a, branches, default) ->
      let branches =
        List.map
          (fun branch ->
            let vars, branch_env = freshen_vars env branch.Tir.br_vars in
            { branch with
              Tir.br_vars = vars;
              Tir.br_body = subst_expr branch_env branch.Tir.br_body })
          branches
      in
      Tir.ECase
        (subst_atom env a, branches, Option.map (subst_expr env) default)
    | Tir.ETuple atoms       ->
      Tir.ETuple (List.map (subst_atom env) atoms)
    | Tir.ERecord fields     ->
      Tir.ERecord
        (List.map (fun (k, a) -> (k, subst_atom env a)) fields)
    | Tir.EField (a, f)      -> Tir.EField (subst_atom env a, f)
    | Tir.EUpdate (a, fs)    ->
      Tir.EUpdate
        (subst_atom env a,
         List.map (fun (k, v) -> (k, subst_atom env v)) fs)
    | Tir.EAlloc (ty, args)  ->
      Tir.EAlloc (ty, List.map (subst_atom env) args)
    | Tir.EStackAlloc (ty, args) ->
      Tir.EStackAlloc (ty, List.map (subst_atom env) args)
    | Tir.EFree a            -> Tir.EFree (subst_atom env a)
    | Tir.EIncRC a           -> Tir.EIncRC (subst_atom env a)
    | Tir.EDecRC a           -> Tir.EDecRC (subst_atom env a)
    | Tir.EAtomicIncRC a     -> Tir.EAtomicIncRC (subst_atom env a)
    | Tir.EAtomicDecRC a     -> Tir.EAtomicDecRC (subst_atom env a)
    | Tir.EReuse (a, ty, args) ->
      Tir.EReuse
        (subst_atom env a, ty, List.map (subst_atom env) args)
    | Tir.ESeq (e1, e2)      ->
      let e1 = subst_expr env e1 in
      let e2 = subst_expr env e2 in
      Tir.ESeq (e1, e2)
  in
  let params, env = freshen_vars SMap.empty params in
  (params, subst_expr env body)

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
