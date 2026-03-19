(** Perceus RC Analysis — Pass 4.

    Inserts reference-counting operations (EIncRC / EDecRC) into the TIR,
    exploiting static last-use information to elide as many RC ops as
    possible.  Linear and affine values get EFree instead of RC.
    Adjacent Inc/Dec cancel pairs are removed, and FBIP reuse is detected. *)

module StringSet = Set.Make (String)

(* ── Helpers ─────────────────────────────────────────────────────────────── *)

(** Returns true if this type needs reference counting (heap-allocated). *)
let needs_rc : Tir.ty -> bool = function
  | Tir.TCon _ | Tir.TString | Tir.TPtr _ -> true
  | Tir.TInt | Tir.TFloat | Tir.TBool | Tir.TUnit
  | Tir.TTuple _ | Tir.TRecord _ | Tir.TFn _ | Tir.TVar _ -> false

(** Returns the set of variable names referenced by an atom. *)
let vars_of_atom : Tir.atom -> StringSet.t = function
  | Tir.AVar v -> StringSet.singleton v.Tir.v_name
  | Tir.ALit _ -> StringSet.empty

(** Union of all variable sets from a list of atoms. *)
let vars_of_atoms (atoms : Tir.atom list) : StringSet.t =
  List.fold_left (fun s a -> StringSet.union s (vars_of_atom a))
    StringSet.empty atoms

(** Shape compatibility for FBIP reuse. *)
let shape_matches (t1 : Tir.ty) (t2 : Tir.ty) : bool =
  match t1, t2 with
  | Tir.TCon (n1, ts1), Tir.TCon (n2, ts2) ->
    String.equal n1 n2 && List.length ts1 = List.length ts2
  | _ -> false

(* ── Phase 1: Backwards Liveness Analysis ────────────────────────────────── *)

type live_set = StringSet.t

(** Compute the set of variables live *before* [e], given those live *after*. *)
let rec live_before (e : Tir.expr) (live_after : live_set) : live_set =
  match e with
  | Tir.EAtom (Tir.AVar v) ->
    StringSet.add v.Tir.v_name live_after
  | Tir.EAtom (Tir.ALit _) ->
    live_after
  | Tir.EApp (f, args) ->
    live_after
    |> StringSet.add f.Tir.v_name
    |> StringSet.union (vars_of_atoms args)
  | Tir.ECallPtr (a, args) ->
    live_after
    |> StringSet.union (vars_of_atom a)
    |> StringSet.union (vars_of_atoms args)
  | Tir.ELet (v, e1, e2) ->
    let l2 = live_before e2 live_after in
    let l1_after = StringSet.remove v.Tir.v_name l2 in
    live_before e1 l1_after
  | Tir.ELetRec (fns, body) ->
    let lb = live_before body live_after in
    let fn_names =
      List.fold_left (fun s fn -> StringSet.add fn.Tir.fn_name s)
        StringSet.empty fns
    in
    (* Remove the recursive names, then add free vars from each fn body *)
    let base = StringSet.diff lb fn_names in
    List.fold_left (fun acc fn ->
      let params =
        List.fold_left (fun s p -> StringSet.add p.Tir.v_name s)
          StringSet.empty fn.Tir.fn_params
      in
      let body_live = live_before fn.Tir.fn_body StringSet.empty in
      StringSet.union acc (StringSet.diff body_live params)
    ) base fns
  | Tir.ECase (a, branches, default) ->
    let arm_lives = List.map (fun br ->
      let bound =
        List.fold_left (fun s v -> StringSet.add v.Tir.v_name s)
          StringSet.empty br.Tir.br_vars
      in
      live_before br.Tir.br_body (StringSet.diff live_after bound)
    ) branches in
    let default_lives = match default with
      | Some d -> [live_before d live_after]
      | None -> []
    in
    let all_lives = arm_lives @ default_lives in
    let union = List.fold_left StringSet.union StringSet.empty all_lives in
    StringSet.union (vars_of_atom a) union
  | Tir.ESeq (e1, e2) ->
    let l2 = live_before e2 live_after in
    live_before e1 l2
  | Tir.ETuple atoms ->
    StringSet.union live_after (vars_of_atoms atoms)
  | Tir.ERecord fields ->
    let atoms = List.map snd fields in
    StringSet.union live_after (vars_of_atoms atoms)
  | Tir.EField (a, _) ->
    StringSet.union live_after (vars_of_atom a)
  | Tir.EUpdate (a, fields) ->
    let atoms = List.map snd fields in
    live_after
    |> StringSet.union (vars_of_atom a)
    |> StringSet.union (vars_of_atoms atoms)
  | Tir.EAlloc (_, atoms) | Tir.EStackAlloc (_, atoms) ->
    StringSet.union live_after (vars_of_atoms atoms)
  | Tir.EFree a ->
    StringSet.union live_after (vars_of_atom a)
  | Tir.EIncRC a ->
    StringSet.union live_after (vars_of_atom a)
  | Tir.EDecRC a ->
    StringSet.union live_after (vars_of_atom a)
  | Tir.EReuse (a, _, atoms) ->
    live_after
    |> StringSet.union (vars_of_atom a)
    |> StringSet.union (vars_of_atoms atoms)

(* ── Phase 2: RC Insertion ────────────────────────────────────────────────── *)

(** Wrap [inner] with EIncRC for each variable in [vars] that is Unr,
    needs_rc, and is still live after this point. *)
let wrap_incrcs (incs : Tir.var list) (inner : Tir.expr) : Tir.expr =
  List.fold_right (fun v acc ->
    Tir.ESeq (Tir.EIncRC (Tir.AVar v), acc)
  ) incs inner

(** Determine which AVar atoms in a list need EIncRC because they are
    Unr, needs_rc, and still live after this use. *)
let find_inc_vars (atoms : Tir.atom list) (live_after : live_set) : Tir.var list =
  List.filter_map (function
    | Tir.AVar v
      when v.Tir.v_lin = Tir.Unr
           && needs_rc v.Tir.v_ty
           && StringSet.mem v.Tir.v_name live_after ->
      Some v
    | _ -> None
  ) atoms

(** Insert RC operations into an expression.
    Returns [(expr', live_before)] where expr' has RC ops inserted and
    live_before is the set of variables live before this expression. *)
let rec insert_rc_expr (e : Tir.expr) (live_after : live_set)
    : Tir.expr * live_set =
  match e with
  | Tir.EAtom (Tir.AVar v) ->
    let lb = StringSet.add v.Tir.v_name live_after in
    if v.Tir.v_lin = Tir.Unr && needs_rc v.Tir.v_ty
       && StringSet.mem v.Tir.v_name live_after then
      (* Non-last use of Unr heap value: inc before use *)
      (Tir.ESeq (Tir.EIncRC (Tir.AVar v), e), lb)
    else
      (e, lb)

  | Tir.EAtom (Tir.ALit _) ->
    (e, live_after)

  | Tir.EApp (f, args) ->
    (* Collect vars that need incrc (Unr, needs_rc, still live after) *)
    let all_atoms = (Tir.AVar f) :: args in
    let inc_vars = find_inc_vars all_atoms live_after in
    let e' = wrap_incrcs inc_vars e in
    let lb =
      live_after
      |> StringSet.add f.Tir.v_name
      |> StringSet.union (vars_of_atoms args)
    in
    (e', lb)

  | Tir.ECallPtr (a, args) ->
    let all_atoms = a :: args in
    let inc_vars = find_inc_vars all_atoms live_after in
    let e' = wrap_incrcs inc_vars e in
    let lb =
      live_after
      |> StringSet.union (vars_of_atom a)
      |> StringSet.union (vars_of_atoms args)
    in
    (e', lb)

  | Tir.ELet (v, e1, e2) ->
    (* Process e2 first to discover what's live going into it *)
    let (e2', live_into_e2) = insert_rc_expr e2 live_after in
    (* Check if v is dead in e2 *)
    let e2'' =
      if not (StringSet.mem v.Tir.v_name live_into_e2) then
        (* Dead binding — insert cleanup at start of e2 *)
        if v.Tir.v_lin = Tir.Unr && needs_rc v.Tir.v_ty then
          Tir.ESeq (Tir.EDecRC (Tir.AVar v), e2')
        else if v.Tir.v_lin = Tir.Lin || v.Tir.v_lin = Tir.Aff then
          if needs_rc v.Tir.v_ty then
            Tir.ESeq (Tir.EFree (Tir.AVar v), e2')
          else
            e2'
        else
          e2'
      else
        e2'
    in
    let live_for_e1 = StringSet.remove v.Tir.v_name live_into_e2 in
    let (e1', live_before_e1) = insert_rc_expr e1 live_for_e1 in
    (Tir.ELet (v, e1', e2''), live_before_e1)

  | Tir.ELetRec (fns, body) ->
    let (body', live_body) = insert_rc_expr body live_after in
    let fns' = List.map (fun fn ->
      let (fb, _) = insert_rc_expr fn.Tir.fn_body StringSet.empty in
      { fn with Tir.fn_body = fb }
    ) fns in
    let fn_names =
      List.fold_left (fun s fn -> StringSet.add fn.Tir.fn_name s)
        StringSet.empty fns
    in
    let lb = StringSet.diff live_body fn_names in
    (Tir.ELetRec (fns', body'), lb)

  | Tir.ECase (a, branches, default) ->
    (* When the scrutinee is a heap value not live after the case, it is
       consumed by the match.  Free its header in every branch.  Branch-bound
       variables (br_vars) take over ownership of the children, so we only
       need to free the allocation header — EDecRC handles both the unique
       case (RC→0 → free) and the shared case (RC>1 → just decrement).
       We tag the DecRC var with the CONCRETE constructor type (br.br_tag)
       so that the FBIP pass can match it against same-constructor EAllocs. *)
    let add_scrutinee_free_for ctor_tag body =
      match a with
      | Tir.AVar v when needs_rc v.Tir.v_ty
                     && not (StringSet.mem v.Tir.v_name live_after) ->
        (* Use the concrete ctor type so shape_matches works in FBIP. *)
        let ctor_v = { v with Tir.v_ty = Tir.TCon (ctor_tag, []) } in
        Tir.ESeq (Tir.EDecRC (Tir.AVar ctor_v), body)
      | _ -> body
    in
    let branches' = List.map (fun br ->
      let bound =
        List.fold_left (fun s v -> StringSet.add v.Tir.v_name s)
          StringSet.empty br.Tir.br_vars
      in
      let la = StringSet.diff live_after bound in
      let (body', _) = insert_rc_expr br.Tir.br_body la in
      { br with Tir.br_body = add_scrutinee_free_for br.Tir.br_tag body' }
    ) branches in
    let default' = Option.map (fun d ->
      let (d_rc, _) = insert_rc_expr d live_after in
      (* Default branch: no constructor tag known, use original type *)
      (match a with
       | Tir.AVar v when needs_rc v.Tir.v_ty
                      && not (StringSet.mem v.Tir.v_name live_after) ->
         Tir.ESeq (Tir.EDecRC (Tir.AVar v), d_rc)
       | _ -> d_rc)
    ) default in
    (* Compute live_before from the original liveness *)
    let lb = live_before e live_after in
    (Tir.ECase (a, branches', default'), lb)

  | Tir.ESeq (e1, e2) ->
    let (e2', l2) = insert_rc_expr e2 live_after in
    let (e1', l1) = insert_rc_expr e1 l2 in
    (Tir.ESeq (e1', e2'), l1)

  | Tir.ETuple atoms ->
    let inc_vars = find_inc_vars atoms live_after in
    let e' = wrap_incrcs inc_vars e in
    let lb = StringSet.union live_after (vars_of_atoms atoms) in
    (e', lb)

  | Tir.ERecord fields ->
    let atoms = List.map snd fields in
    let inc_vars = find_inc_vars atoms live_after in
    let e' = wrap_incrcs inc_vars e in
    let lb = StringSet.union live_after (vars_of_atoms atoms) in
    (e', lb)

  | Tir.EField (a, f) ->
    let inc_vars = find_inc_vars [a] live_after in
    let e' = wrap_incrcs inc_vars (Tir.EField (a, f)) in
    let lb = StringSet.union live_after (vars_of_atom a) in
    (e', lb)

  | Tir.EUpdate (a, fields) ->
    let atoms = a :: List.map snd fields in
    let inc_vars = find_inc_vars atoms live_after in
    let e' = wrap_incrcs inc_vars e in
    let lb =
      live_after
      |> StringSet.union (vars_of_atom a)
      |> StringSet.union (vars_of_atoms (List.map snd fields))
    in
    (e', lb)

  | Tir.EAlloc (ty, atoms) ->
    let inc_vars = find_inc_vars atoms live_after in
    let e' = wrap_incrcs inc_vars (Tir.EAlloc (ty, atoms)) in
    let lb = StringSet.union live_after (vars_of_atoms atoms) in
    (e', lb)

  | Tir.EStackAlloc (ty, atoms) ->
    let inc_vars = find_inc_vars atoms live_after in
    let e' = wrap_incrcs inc_vars (Tir.EStackAlloc (ty, atoms)) in
    let lb = StringSet.union live_after (vars_of_atoms atoms) in
    (e', lb)

  | Tir.EFree a ->
    let lb = StringSet.union live_after (vars_of_atom a) in
    (e, lb)

  | Tir.EIncRC a ->
    let lb = StringSet.union live_after (vars_of_atom a) in
    (e, lb)

  | Tir.EDecRC a ->
    let lb = StringSet.union live_after (vars_of_atom a) in
    (e, lb)

  | Tir.EReuse (a, ty, atoms) ->
    let all_atoms = a :: atoms in
    let inc_vars = find_inc_vars all_atoms live_after in
    let e' = wrap_incrcs inc_vars (Tir.EReuse (a, ty, atoms)) in
    let lb =
      live_after
      |> StringSet.union (vars_of_atom a)
      |> StringSet.union (vars_of_atoms atoms)
    in
    (e', lb)

(** Insert RC ops into a function definition. *)
let insert_rc (fn : Tir.fn_def) : Tir.fn_def =
  let (body', _) = insert_rc_expr fn.Tir.fn_body StringSet.empty in
  { fn with Tir.fn_body = body' }

(* ── Phase 3: RC Elision (cancel pairs) ──────────────────────────────────── *)

(** Remove adjacent EIncRC/EDecRC cancel pairs. *)
let rec elide_expr (e : Tir.expr) : Tir.expr =
  match e with
  (* Cancel pair: ESeq(EIncRC v, ESeq(EDecRC v, rest)) -> rest *)
  | Tir.ESeq (Tir.EIncRC (Tir.AVar v1),
              Tir.ESeq (Tir.EDecRC (Tir.AVar v2), rest))
    when String.equal v1.Tir.v_name v2.Tir.v_name ->
    elide_expr rest
  (* Also check the reverse: ESeq(EDecRC v, ESeq(EIncRC v, rest)) -> rest *)
  | Tir.ESeq (Tir.EDecRC (Tir.AVar v1),
              Tir.ESeq (Tir.EIncRC (Tir.AVar v2), rest))
    when String.equal v1.Tir.v_name v2.Tir.v_name ->
    elide_expr rest
  (* Recurse into all sub-expressions *)
  | Tir.ESeq (e1, e2) ->
    Tir.ESeq (elide_expr e1, elide_expr e2)
  | Tir.ELet (v, e1, e2) ->
    Tir.ELet (v, elide_expr e1, elide_expr e2)
  | Tir.ELetRec (fns, body) ->
    let fns' = List.map (fun fn ->
      { fn with Tir.fn_body = elide_expr fn.Tir.fn_body }
    ) fns in
    Tir.ELetRec (fns', elide_expr body)
  | Tir.ECase (a, branches, default) ->
    let branches' = List.map (fun br ->
      { br with Tir.br_body = elide_expr br.Tir.br_body }
    ) branches in
    let default' = Option.map elide_expr default in
    Tir.ECase (a, branches', default')
  (* Leaf forms — no sub-expressions to recurse into *)
  | Tir.EAtom _ | Tir.EApp _ | Tir.ECallPtr _
  | Tir.ETuple _ | Tir.ERecord _ | Tir.EField _ | Tir.EUpdate _
  | Tir.EAlloc _ | Tir.EStackAlloc _ | Tir.EFree _ | Tir.EIncRC _ | Tir.EDecRC _
  | Tir.EReuse _ ->
    e

(** Elide cancel pairs in a function definition. *)
let elide_cancel_pairs (fn : Tir.fn_def) : Tir.fn_def =
  { fn with Tir.fn_body = elide_expr fn.Tir.fn_body }

(* ── Phase 4: FBIP Reuse Detection ──────────────────────────────────────── *)

(** Returns true if [name] occurs free anywhere in [e].  Used by FBIP to
    check that sinking a DecRC past an ELet is safe. *)
let rec name_free_in (name : string) (e : Tir.expr) : bool =
  let atom_uses a = match a with
    | Tir.AVar v -> String.equal v.Tir.v_name name
    | Tir.ALit _ -> false
  in
  let atoms_use = List.exists atom_uses in
  match e with
  | Tir.EAtom a                              -> atom_uses a
  | Tir.EApp (f, args)                       -> String.equal f.Tir.v_name name || atoms_use args
  | Tir.ECallPtr (a, args)                   -> atom_uses a || atoms_use args
  | Tir.ELet (v, e1, e2)                     ->
    name_free_in name e1
    || (not (String.equal v.Tir.v_name name) && name_free_in name e2)
  | Tir.ELetRec (fns, body)                  ->
    let bound = List.exists (fun fd -> String.equal fd.Tir.fn_name name) fns in
    (not bound && name_free_in name body)
    || List.exists (fun fd ->
         let param_bound = List.exists (fun p -> String.equal p.Tir.v_name name) fd.Tir.fn_params in
         not param_bound && name_free_in name fd.Tir.fn_body) fns
  | Tir.ECase (a, branches, default)         ->
    atom_uses a
    || List.exists (fun br ->
         let bv_bound = List.exists (fun v -> String.equal v.Tir.v_name name) br.Tir.br_vars in
         not bv_bound && name_free_in name br.Tir.br_body) branches
    || Option.fold ~none:false ~some:(name_free_in name) default
  | Tir.ESeq (e1, e2)                        -> name_free_in name e1 || name_free_in name e2
  | Tir.ETuple atoms | Tir.EAlloc (_, atoms)
  | Tir.EStackAlloc (_, atoms)               -> atoms_use atoms
  | Tir.ERecord fields                       -> List.exists (fun (_, a) -> atom_uses a) fields
  | Tir.EField (a, _)                        -> atom_uses a
  | Tir.EUpdate (a, fields)                  ->
    atom_uses a || List.exists (fun (_, a) -> atom_uses a) fields
  | Tir.EFree a | Tir.EIncRC a | Tir.EDecRC a -> atom_uses a
  | Tir.EReuse (a, _, atoms)                 -> atom_uses a || atoms_use atoms

(** Try to sink [EDecRC(dec_v)] into [body] through a chain of ELet
    bindings, stopping when we find an EAlloc of matching shape.  Safe
    only when [dec_v] does not appear in any RHS along the chain. *)
let rec try_fbip_sink (dec_v : Tir.var) (body : Tir.expr) : Tir.expr option =
  match body with
  (* EAlloc in tail position — reuse directly *)
  | Tir.EAlloc (ty, args)
    when shape_matches dec_v.Tir.v_ty ty ->
    Some (Tir.EReuse (Tir.AVar dec_v, ty, args))
  (* EAlloc bound to a result variable *)
  | Tir.ELet (result, Tir.EAlloc (ty, args), rest)
    when shape_matches dec_v.Tir.v_ty ty ->
    Some (Tir.ELet (result, Tir.EReuse (Tir.AVar dec_v, ty, args), rest))
  (* dec_v not used in rhs — safe to sink past this binding *)
  | Tir.ELet (v, rhs, inner)
    when not (name_free_in dec_v.Tir.v_name rhs) ->
    Option.map (fun inner' -> Tir.ELet (v, rhs, inner'))
               (try_fbip_sink dec_v inner)
  | _ -> None

(** Detect DecRC + Alloc of matching shape and replace with Reuse. *)
let rec fbip_expr (e : Tir.expr) : Tir.expr =
  match e with
  (* Pattern: let _ = decrc(v) in let result = alloc(ty, args) in rest
     where shape_matches(v.v_ty, ty)
     Replace the whole thing, dropping the dead let binding for the decrc. *)
  | Tir.ELet (_dead_v, Tir.EDecRC (Tir.AVar dec_v),
              Tir.ELet (result, Tir.EAlloc (ty, args), rest))
    when shape_matches dec_v.Tir.v_ty ty ->
    let rest' = fbip_expr rest in
    Tir.ELet (result, Tir.EReuse (Tir.AVar dec_v, ty, args), rest')
  (* ESeq(EDecRC v, body): try to sink the decrc to be adjacent to an
     EAlloc of matching shape anywhere down the let-chain. *)
  | Tir.ESeq (Tir.EDecRC (Tir.AVar dec_v), body) ->
    (match try_fbip_sink dec_v body with
     | Some body' -> fbip_expr body'
     | None       -> Tir.ESeq (Tir.EDecRC (Tir.AVar dec_v), fbip_expr body))
  (* Recurse into sub-expressions *)
  | Tir.ESeq (e1, e2) ->
    Tir.ESeq (fbip_expr e1, fbip_expr e2)
  | Tir.ELet (v, e1, e2) ->
    Tir.ELet (v, fbip_expr e1, fbip_expr e2)
  | Tir.ELetRec (fns, body) ->
    let fns' = List.map (fun fn ->
      { fn with Tir.fn_body = fbip_expr fn.Tir.fn_body }
    ) fns in
    Tir.ELetRec (fns', fbip_expr body)
  | Tir.ECase (a, branches, default) ->
    let branches' = List.map (fun br ->
      { br with Tir.br_body = fbip_expr br.Tir.br_body }
    ) branches in
    let default' = Option.map fbip_expr default in
    Tir.ECase (a, branches', default')
  | Tir.EAtom _ | Tir.EApp _ | Tir.ECallPtr _
  | Tir.ETuple _ | Tir.ERecord _ | Tir.EField _ | Tir.EUpdate _
  | Tir.EAlloc _ | Tir.EStackAlloc _ | Tir.EFree _ | Tir.EIncRC _ | Tir.EDecRC _
  | Tir.EReuse _ ->
    e

(** Apply FBIP reuse to a function definition. *)
let insert_fbip (fn : Tir.fn_def) : Tir.fn_def =
  { fn with Tir.fn_body = fbip_expr fn.Tir.fn_body }

(* ── Entry point ──────────────────────────────────────────────────────────── *)

(** Run all four Perceus phases over every function in the module. *)
let perceus (m : Tir.tir_module) : Tir.tir_module =
  let fns' =
    m.Tir.tm_fns
    |> List.map insert_rc
    |> List.map elide_cancel_pairs
    |> List.map insert_fbip
  in
  { m with Tir.tm_fns = fns' }
