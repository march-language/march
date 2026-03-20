(** Dead code elimination pass.
    - Removes pure unused let bindings (converts impure ones to ESeq)
    - Removes top-level functions not reachable from main (seeds all fns if no main)
    Precondition: must run after Defun. ECallPtr post-Defun dispatches through
    apply-functions that are themselves reachable via EApp; running before Defun
    could eliminate lambda-lifted functions that ECallPtr would have reached. *)

module StringSet = Set.Make (String)

(** Collect all variable names free in an expression. *)
let rec free_vars : Tir.expr -> StringSet.t = function
  | Tir.EAtom (Tir.AVar v)     -> StringSet.singleton v.Tir.v_name
  | Tir.EAtom (Tir.ADefRef _) -> StringSet.empty  (* global ref — not a local binding *)
  | Tir.EAtom (Tir.ALit _)    -> StringSet.empty
  | Tir.EApp (f, args)      ->
    List.fold_left (fun s a -> StringSet.union s (free_atom a))
      (StringSet.singleton f.Tir.v_name) args
  | Tir.ECallPtr (f, args)  ->
    List.fold_left (fun s a -> StringSet.union s (free_atom a))
      (free_atom f) args
  | Tir.ELet (v, rhs, body) ->
    StringSet.union (free_vars rhs) (StringSet.remove v.Tir.v_name (free_vars body))
  | Tir.ELetRec (fns, body) ->
    let names = StringSet.of_list (List.map (fun fd -> fd.Tir.fn_name) fns) in
    let fn_free = List.fold_left (fun s fd ->
        StringSet.union s (StringSet.diff (free_vars fd.Tir.fn_body) names)
      ) StringSet.empty fns in
    StringSet.union fn_free (StringSet.diff (free_vars body) names)
  | Tir.ECase (a, branches, default) ->
    let bf = List.fold_left (fun s b ->
        let bound = StringSet.of_list (List.map (fun v -> v.Tir.v_name) b.Tir.br_vars) in
        StringSet.union s (StringSet.diff (free_vars b.Tir.br_body) bound)
      ) (free_atom a) branches in
    Option.fold ~none:bf ~some:(fun d -> StringSet.union bf (free_vars d)) default
  | Tir.ETuple atoms | Tir.EAlloc (_, atoms) | Tir.EStackAlloc (_, atoms) ->
    List.fold_left (fun s a -> StringSet.union s (free_atom a)) StringSet.empty atoms
  | Tir.ERecord fields ->
    List.fold_left (fun s (_, a) -> StringSet.union s (free_atom a)) StringSet.empty fields
  | Tir.EField (a, _)        -> free_atom a
  | Tir.EUpdate (a, fields)  ->
    List.fold_left (fun s (_, v) -> StringSet.union s (free_atom v)) (free_atom a) fields
  | Tir.EFree a | Tir.EIncRC a | Tir.EDecRC a -> free_atom a
  | Tir.EReuse (a, _, args)  ->
    List.fold_left (fun s v -> StringSet.union s (free_atom v)) (free_atom a) args
  | Tir.ESeq (e1, e2)        -> StringSet.union (free_vars e1) (free_vars e2)

and free_atom : Tir.atom -> StringSet.t = function
  | Tir.AVar v    -> StringSet.singleton v.Tir.v_name
  | Tir.ADefRef _ -> StringSet.empty  (* global ref — not a local binding *)
  | Tir.ALit _    -> StringSet.empty

(** Collect all function names called from an expression.
    ECallPtr (indirect closure dispatch) is not tracked — post-Defun its targets
    are apply-functions already reachable via EApp from the closure constructor. *)
let rec called_fns : Tir.expr -> StringSet.t = function
  | Tir.EApp (f, _)         -> StringSet.singleton f.Tir.v_name
  | Tir.ELet (_, rhs, body) -> StringSet.union (called_fns rhs) (called_fns body)
  | Tir.ELetRec (fns, body) ->
    List.fold_left (fun s fd -> StringSet.union s (called_fns fd.Tir.fn_body))
      (called_fns body) fns
  | Tir.ECase (_, branches, default) ->
    let bf = List.fold_left (fun s b -> StringSet.union s (called_fns b.Tir.br_body))
               StringSet.empty branches in
    Option.fold ~none:bf ~some:(fun d -> StringSet.union bf (called_fns d)) default
  | Tir.ESeq (e1, e2)       -> StringSet.union (called_fns e1) (called_fns e2)
  | _                        -> StringSet.empty

(** Transitive reachability from entry points.
    Uses [free_vars] (not [called_fns]) so that closure apply-function
    pointers stored in EAlloc args are also treated as references. *)
let reachable_fns (m : Tir.tir_module) : StringSet.t =
  let fn_map : (string, Tir.fn_def) Hashtbl.t = Hashtbl.create 16 in
  List.iter (fun fd -> Hashtbl.add fn_map fd.Tir.fn_name fd) m.Tir.tm_fns;
  let fn_names = StringSet.of_list (List.map (fun fd -> fd.Tir.fn_name) m.Tir.tm_fns) in
  let visited = ref StringSet.empty in
  let queue = Queue.create () in
  (* Seed with main; if no main, seed with all functions *)
  (match List.find_opt (fun fd -> fd.Tir.fn_name = "main") m.Tir.tm_fns with
   | Some main_fn -> Queue.push main_fn.Tir.fn_name queue
   | None -> List.iter (fun fd -> Queue.push fd.Tir.fn_name queue) m.Tir.tm_fns);
  while not (Queue.is_empty queue) do
    let name = Queue.pop queue in
    if not (StringSet.mem name !visited) then begin
      visited := StringSet.add name !visited;
      match Hashtbl.find_opt fn_map name with
      | None -> ()
      | Some fd ->
        (* Intersect all free variable names with known top-level function
           names — this covers both direct EApp calls and closure fn-ptr
           references stored in EAlloc args. *)
        let refs = StringSet.inter (free_vars fd.Tir.fn_body) fn_names in
        StringSet.iter (fun callee -> Queue.push callee queue) refs
    end
  done;
  !visited

let rec dce_expr ~changed : Tir.expr -> Tir.expr = function
  | Tir.ELet (v, rhs, body) ->
    let rhs'  = dce_expr ~changed rhs in
    let body' = dce_expr ~changed body in
    let used  = StringSet.mem v.Tir.v_name (free_vars body') in
    if used then Tir.ELet (v, rhs', body')
    else if Purity.is_pure rhs' then begin
      changed := true; body'
    end else begin
      changed := true; Tir.ESeq (rhs', body')
    end
  | Tir.ECase (a, branches, default) ->
    Tir.ECase (a,
      List.map (fun b -> { b with Tir.br_body = dce_expr ~changed b.Tir.br_body }) branches,
      Option.map (dce_expr ~changed) default)
  | Tir.ELetRec (fns, body) ->
    Tir.ELetRec (List.map (fun fd -> { fd with Tir.fn_body = dce_expr ~changed fd.Tir.fn_body }) fns,
                 dce_expr ~changed body)
  | Tir.ESeq (e1, e2) -> Tir.ESeq (dce_expr ~changed e1, dce_expr ~changed e2)
  | other -> other

let run ~changed (m : Tir.tir_module) : Tir.tir_module =
  (* Step 1: remove dead let bindings within function bodies *)
  let fns' = List.map (fun fd ->
    { fd with Tir.fn_body = dce_expr ~changed fd.Tir.fn_body }
  ) m.Tir.tm_fns in
  (* Step 2: remove unreachable top-level functions *)
  let m1 = { m with Tir.tm_fns = fns' } in
  let reachable = reachable_fns m1 in
  let fns'' = List.filter (fun fd ->
    if StringSet.mem fd.Tir.fn_name reachable then true
    else begin changed := true; false end
  ) m1.Tir.tm_fns in
  { m1 with Tir.tm_fns = fns'' }
