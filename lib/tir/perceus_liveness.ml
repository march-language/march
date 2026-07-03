(** Perceus — Phase 1 liveness helpers (Wave 3 Task 5 file split).

    [live_before], [name_free_in], and [vars_of_atom]/[vars_of_atoms] are
    pure, [env]-free analyses over [Tir.expr] — they were already
    self-contained before the Wave 3 Task 4 env-threading (they take no
    [Perceus.env] parameter and never did).  Moved verbatim from
    [perceus.ml]; only the module qualification of cross-module references
    changed (none needed — this group has zero dependencies on the rest of
    Perceus).

    Consumers: [Perceus.insert_rc_expr] (core, via [vars_of_atom(s)] and
    [live_before]/[name_free_in]), [Perceus_elide.elide_expr] (via
    [name_free_in], the L5 cancel-pair-across-ELet case), and
    [Perceus_scrut.preprocess_scrut_escape] (via [name_free_in]). *)

module StringSet = Set.Make (String)

(** Returns the set of variable names referenced by an atom.

    [ADefRef] resolves to a code-segment address (the function's symbol)
    and so contributes no local-variable liveness AND needs no RC: function
    pointers are never heap-allocated and [march_incrc] / [march_decrc]
    would corrupt or crash if called on them.  This is consistent with the
    [Hashtbl.mem ctx.top_fns] guard in [llvm_emit.ml]'s RC-op cases, which
    also short-circuits RC ops on top-level function references. *)
let vars_of_atom : Tir.atom -> StringSet.t = function
  | Tir.AVar v    -> StringSet.singleton v.Tir.v_name
  | Tir.ADefRef _ -> StringSet.empty
  | Tir.ALit _    -> StringSet.empty

(** Union of all variable sets from a list of atoms. *)
let vars_of_atoms (atoms : Tir.atom list) : StringSet.t =
  List.fold_left (fun s a -> StringSet.union s (vars_of_atom a))
    StringSet.empty atoms

(* ── Phase 1: Backwards Liveness Analysis ────────────────────────────────── *)

type live_set = StringSet.t

(** Compute the set of variables live *before* [e], given those live *after*. *)
let rec live_before (e : Tir.expr) (live_after : live_set) : live_set =
  match e with
  | Tir.EAtom (Tir.AVar v) ->
    StringSet.add v.Tir.v_name live_after
  | Tir.EAtom (Tir.ADefRef _) ->
    live_after  (* global ref — no local liveness *)
  | Tir.EAtom (Tir.ALit _) ->
    live_after
  | Tir.EApp (_, args) ->
    (* After defun, the callee in EApp is always a top-level function symbol
       (a code-segment address), never a heap-allocated local variable.
       Only the call arguments contribute to local variable liveness.
       Including the callee name caused spurious liveness propagation for
       operators like &&, || whose llvm_name produces an invalid symbol. *)
    live_after
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
  | Tir.EIncRC a | Tir.EAtomicIncRC a ->
    StringSet.union live_after (vars_of_atom a)
  | Tir.EDecRC a | Tir.EAtomicDecRC a ->
    StringSet.union live_after (vars_of_atom a)
  | Tir.EReuse (a, _, atoms) ->
    live_after
    |> StringSet.union (vars_of_atom a)
    |> StringSet.union (vars_of_atoms atoms)

(* ── name_free_in (shared by Phase 2 and Phase 4) ─────────────────────────── *)

(** Returns true if [name] occurs free anywhere in [e]. *)
let rec name_free_in (name : string) (e : Tir.expr) : bool =
  let atom_uses a = match a with
    | Tir.AVar v    -> String.equal v.Tir.v_name name
    | Tir.ADefRef _ -> false  (* global ref, not a local name *)
    | Tir.ALit _    -> false
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
  | Tir.EFree a | Tir.EIncRC a | Tir.EDecRC a
  | Tir.EAtomicIncRC a | Tir.EAtomicDecRC a -> atom_uses a
  | Tir.EReuse (a, _, atoms)                 -> atom_uses a || atoms_use atoms
