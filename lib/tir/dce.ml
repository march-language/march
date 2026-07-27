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
  | Tir.EFree a | Tir.EIncRC a | Tir.EDecRC a
  | Tir.EAtomicIncRC a | Tir.EAtomicDecRC a -> free_atom a
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
let root_names (m : Tir.tir_module) : string list =
  let roots = ref StringSet.empty in
  let add name = roots := StringSet.add name !roots in
  let is_main_name name =
    name = "main"
    || let suffix = ".main" in
       let name_len = String.length name
       and suffix_len = String.length suffix in
       name_len >= suffix_len
       && String.sub name (name_len - suffix_len) suffix_len = suffix
  in
  List.iter
    (fun (fn : Tir.fn_def) ->
      if is_main_name fn.Tir.fn_name then add fn.Tir.fn_name;
      if fn.Tir.fn_name = Tir_names.setup_fn_name
         || fn.Tir.fn_name = Tir_names.setup_all_fn_name
         || Tir_names.is_migrate_fn_name fn.Tir.fn_name
      then add fn.Tir.fn_name)
    m.Tir.tm_fns;
  List.iter add m.Tir.tm_exports;
  List.iter (fun (name, _) -> add name) m.Tir.tm_tests;
  if StringSet.is_empty !roots then
    List.iter (fun (fn : Tir.fn_def) -> add fn.Tir.fn_name) m.Tir.tm_fns;
  StringSet.elements !roots

let reachable_fns (m : Tir.tir_module) : StringSet.t =
  let fn_map : (string, Tir.fn_def) Hashtbl.t = Hashtbl.create 16 in
  List.iter (fun fd -> Hashtbl.add fn_map fd.Tir.fn_name fd) m.Tir.tm_fns;
  let fn_names = StringSet.of_list (List.map (fun fd -> fd.Tir.fn_name) m.Tir.tm_fns) in
  let visited = ref StringSet.empty in
  let queue = Queue.create () in
  List.iter (fun name -> Queue.push name queue) (root_names m);
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
        let body_refs = free_vars fd.Tir.fn_body in
        let refs = StringSet.inter body_refs fn_names in
        StringSet.iter (fun callee -> Queue.push callee queue) refs;
        (* Collision-dispatch sentinels ([Mono] → [Llvm_dispatch]) are not TIR
           functions, so the intersection above drops them — but the
           module-qualified impl symbols they route to at LLVM time ARE real
           fn_defs that would otherwise look unreachable (nothing in the TIR
           call graph names them). Follow the [Dispatch_registry] rows so those
           impl bodies survive to link. Empty for any non-colliding program. *)
        StringSet.iter (fun name ->
          if Dispatch_registry.is_sentinel name then
            match Dispatch_registry.lookup name with
            | Some rows -> List.iter (fun (_, sym) -> Queue.push sym queue) rows
            | None -> ())
          body_refs
    end
  done;
  !visited

let rec dce_expr ~impure_fns ~changed : Tir.expr -> Tir.expr = function
  | Tir.ELet (v, rhs, body) ->
    let rhs'  = dce_expr ~impure_fns ~changed rhs in
    let body' = dce_expr ~impure_fns ~changed body in
    let used  = StringSet.mem v.Tir.v_name (free_vars body') in
    if used then Tir.ELet (v, rhs', body')
    else if Purity.is_pure_ext impure_fns rhs' then begin
      changed := true; body'
    end else begin
      changed := true; Tir.ESeq (rhs', body')
    end
  | Tir.ECase (a, branches, default) ->
    Tir.ECase (a,
      List.map (fun b -> { b with Tir.br_body = dce_expr ~impure_fns ~changed b.Tir.br_body }) branches,
      Option.map (dce_expr ~impure_fns ~changed) default)
  | Tir.ELetRec (fns, body) ->
    Tir.ELetRec (List.map (fun fd -> { fd with Tir.fn_body = dce_expr ~impure_fns ~changed fd.Tir.fn_body }) fns,
                 dce_expr ~impure_fns ~changed body)
  | Tir.ESeq (e1, e2) -> Tir.ESeq (dce_expr ~impure_fns ~changed e1, dce_expr ~impure_fns ~changed e2)
  | other -> other

(** Remove top-level functions unreachable from the entry points (main /
    tm_exports / tm_tests / setup / migrate stubs).  This is a LINKABILITY
    requirement, not an optimization: the injected prelude/http stack references
    externs (e.g. [_http_fetch]) that are not always linked, so an unreachable
    function that mentions one produces "undefined symbols" at link time.  It
    must therefore run before LLVM emit EVEN when the optimizer is disabled
    (--no-opt).  Idempotent: filtering an already-pruned module is a no-op, so
    it is safe to call both here and (transitively via [run]) inside [Opt.run]. *)
let prune_unreachable (m : Tir.tir_module) : Tir.tir_module =
  let reachable = reachable_fns m in
  let fns = List.filter
      (fun fd -> StringSet.mem fd.Tir.fn_name reachable) m.Tir.tm_fns in
  { m with Tir.tm_fns = fns }

let run ~changed (m : Tir.tir_module) : Tir.tir_module =
  (* Step 1: remove dead let bindings within function bodies.
     Compute the transitive set of impure top-level functions first so we never
     drop a binding whose RHS calls (directly or indirectly) an impure builtin
     — e.g. [let _ = System.put_env(k, v)], which performs a [setenv]. *)
  let impure_fns = Purity.impure_fns_of_module m in
  let fns' = List.map (fun fd ->
    { fd with Tir.fn_body = dce_expr ~impure_fns ~changed fd.Tir.fn_body }
  ) m.Tir.tm_fns in
  (* Step 2: remove unreachable top-level functions *)
  let m1 = { m with Tir.tm_fns = fns' } in
  let m2 = prune_unreachable m1 in
  if List.compare_lengths m2.Tir.tm_fns m1.Tir.tm_fns < 0 then changed := true;
  m2
