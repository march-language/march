(** Escape Analysis — Pass 5.

    Stack-promotes heap allocations whose lifetimes are provably bounded
    to the current function's stack frame.  An EAlloc that does not escape
    is replaced with EStackAlloc, and dead RC ops on stack-allocated
    variables are removed. *)

module StringSet = Set.Make (String)

(* ── Helpers ──────────────────────────────────────────────────────────────── *)

let vars_of_atom : Tir.atom -> StringSet.t = function
  | Tir.AVar v -> StringSet.singleton v.Tir.v_name
  | Tir.ALit _ -> StringSet.empty

let vars_of_atoms (atoms : Tir.atom list) : StringSet.t =
  List.fold_left (fun s a -> StringSet.union s (vars_of_atom a))
    StringSet.empty atoms

(** Collect all variable names that appear in any atom position of [e].
    Used to conservatively mark captures in ELetRec inner functions. *)
let rec all_atom_vars (e : Tir.expr) : StringSet.t =
  match e with
  | Tir.EAtom a -> vars_of_atom a
  | Tir.EApp (f, args) ->
    StringSet.add f.Tir.v_name (vars_of_atoms args)
  | Tir.ECallPtr (a, args) ->
    StringSet.union (vars_of_atom a) (vars_of_atoms args)
  | Tir.ELet (_, e1, e2) ->
    StringSet.union (all_atom_vars e1) (all_atom_vars e2)
  | Tir.ELetRec (fns, body) ->
    List.fold_left (fun acc fn ->
      StringSet.union acc (all_atom_vars fn.Tir.fn_body)
    ) (all_atom_vars body) fns
  | Tir.ECase (a, branches, default) ->
    let from_a = vars_of_atom a in
    let from_branches =
      List.fold_left (fun acc br ->
        StringSet.union acc (all_atom_vars br.Tir.br_body)
      ) StringSet.empty branches
    in
    let from_default = match default with
      | Some d -> all_atom_vars d
      | None -> StringSet.empty
    in
    StringSet.union from_a (StringSet.union from_branches from_default)
  | Tir.ESeq (e1, e2) ->
    StringSet.union (all_atom_vars e1) (all_atom_vars e2)
  | Tir.ETuple atoms | Tir.EAlloc (_, atoms) | Tir.EStackAlloc (_, atoms) ->
    vars_of_atoms atoms
  | Tir.ERecord fields ->
    vars_of_atoms (List.map snd fields)
  | Tir.EField (a, _) -> vars_of_atom a
  | Tir.EUpdate (a, fields) ->
    StringSet.union (vars_of_atom a) (vars_of_atoms (List.map snd fields))
  | Tir.EFree a | Tir.EIncRC a | Tir.EDecRC a -> vars_of_atom a
  | Tir.EReuse (a, _, args) ->
    StringSet.union (vars_of_atom a) (vars_of_atoms args)

(* ── Phase 1: Collect EAlloc candidates ──────────────────────────────────── *)

(** Walk [e] and collect names of variables bound directly to EAlloc.
    Does not descend into ELetRec inner function bodies (separate scopes). *)
let rec collect_alloc_candidates (e : Tir.expr) : StringSet.t =
  match e with
  | Tir.ELet (v, Tir.EAlloc _, body) ->
    StringSet.add v.Tir.v_name (collect_alloc_candidates body)
  | Tir.ELet (_, e1, e2) ->
    StringSet.union (collect_alloc_candidates e1) (collect_alloc_candidates e2)
  | Tir.ELetRec (_, body) ->
    (* Inner fn bodies are separate scopes; only collect from the outer body *)
    collect_alloc_candidates body
  | Tir.ECase (_, branches, default) ->
    let from_branches =
      List.fold_left (fun acc br ->
        StringSet.union acc (collect_alloc_candidates br.Tir.br_body)
      ) StringSet.empty branches
    in
    let from_default = match default with
      | Some d -> collect_alloc_candidates d
      | None -> StringSet.empty
    in
    StringSet.union from_branches from_default
  | Tir.ESeq (e1, e2) ->
    StringSet.union (collect_alloc_candidates e1) (collect_alloc_candidates e2)
  | _ -> StringSet.empty

(* ── Phase 2: Escape check ────────────────────────────────────────────────── *)

(** Returns the subset of [candidates] that appear in escaping atom positions
    within [e]. *)
let rec escaping_vars (e : Tir.expr) (candidates : StringSet.t) : StringSet.t =
  let candidate_atom a =
    match a with
    | Tir.AVar v when StringSet.mem v.Tir.v_name candidates ->
      StringSet.singleton v.Tir.v_name
    | _ -> StringSet.empty
  in
  let candidate_atoms atoms =
    List.fold_left (fun acc a -> StringSet.union acc (candidate_atom a))
      StringSet.empty atoms
  in
  match e with
  (* Tail atom return — escapes *)
  | Tir.EAtom a -> candidate_atom a

  (* Passed as function call arguments — escapes *)
  | Tir.EApp (f, args) ->
    (* f is a var, not an atom; check if it's a candidate (used as closure) *)
    let fn_esc =
      if StringSet.mem f.Tir.v_name candidates
      then StringSet.singleton f.Tir.v_name
      else StringSet.empty
    in
    StringSet.union fn_esc (candidate_atoms args)

  | Tir.ECallPtr (a, args) ->
    (* a may be a closure — check both the fn ptr and all args *)
    StringSet.union (candidate_atom a) (candidate_atoms args)

  (* Stored into a heap allocation — escapes *)
  | Tir.EAlloc (_, args) -> candidate_atoms args

  (* Stored into stack alloc args (conservative; treat like EAlloc) *)
  | Tir.EStackAlloc (_, args) -> candidate_atoms args

  (* Stored via FBIP reuse: the reuse token (first atom) does NOT escape;
     the constructor args do *)
  | Tir.EReuse (_, _, args) -> candidate_atoms args

  (* Stored in a tuple — escapes *)
  | Tir.ETuple atoms -> candidate_atoms atoms

  (* Stored in a record — escapes *)
  | Tir.ERecord fields -> candidate_atoms (List.map snd fields)

  (* Stored in a functional update's new field values — escapes *)
  | Tir.EUpdate (_, fields) -> candidate_atoms (List.map snd fields)

  (* ELet: check RHS (which may itself be a tail atom, call, etc.) and body *)
  | Tir.ELet (_, e1, e2) ->
    StringSet.union (escaping_vars e1 candidates) (escaping_vars e2 candidates)

  (* ELetRec: conservatively mark all candidates mentioned in inner fn bodies
     as escaping (they are captured free variables) *)
  | Tir.ELetRec (fns, body) ->
    let from_fns =
      List.fold_left (fun acc fn ->
        let all_in_fn = all_atom_vars fn.Tir.fn_body in
        StringSet.union acc (StringSet.inter all_in_fn candidates)
      ) StringSet.empty fns
    in
    StringSet.union from_fns (escaping_vars body candidates)

  | Tir.ECase (_, branches, default) ->
    let from_branches =
      List.fold_left (fun acc br ->
        StringSet.union acc (escaping_vars br.Tir.br_body candidates)
      ) StringSet.empty branches
    in
    let from_default = match default with
      | Some d -> escaping_vars d candidates
      | None -> StringSet.empty
    in
    (* Note: the scrutinee atom is NOT an escaping position per spec *)
    StringSet.union from_branches from_default

  | Tir.ESeq (e1, e2) ->
    StringSet.union (escaping_vars e1 candidates) (escaping_vars e2 candidates)

  (* Non-escaping positions: ECase scrutinee (handled above), EField,
     EIncRC, EDecRC, EFree, EReuse first position *)
  | Tir.EField _ | Tir.EIncRC _ | Tir.EDecRC _ | Tir.EFree _ ->
    StringSet.empty

(** Returns the subset of [candidates] for which EIncRC appears anywhere in [e].
    Such variables have multiple live references — not safe to stack-promote. *)
let rec has_incrc_for (e : Tir.expr) (candidates : StringSet.t) : StringSet.t =
  match e with
  | Tir.EIncRC (Tir.AVar v) when StringSet.mem v.Tir.v_name candidates ->
    StringSet.singleton v.Tir.v_name
  | Tir.ELet (_, e1, e2) ->
    StringSet.union (has_incrc_for e1 candidates) (has_incrc_for e2 candidates)
  | Tir.ELetRec (fns, body) ->
    let from_fns =
      List.fold_left (fun acc fn ->
        StringSet.union acc (has_incrc_for fn.Tir.fn_body candidates)
      ) StringSet.empty fns
    in
    StringSet.union from_fns (has_incrc_for body candidates)
  | Tir.ECase (_, branches, default) ->
    let from_branches =
      List.fold_left (fun acc br ->
        StringSet.union acc (has_incrc_for br.Tir.br_body candidates)
      ) StringSet.empty branches
    in
    let from_default = match default with
      | Some d -> has_incrc_for d candidates
      | None -> StringSet.empty
    in
    StringSet.union from_branches from_default
  | Tir.ESeq (e1, e2) ->
    StringSet.union (has_incrc_for e1 candidates) (has_incrc_for e2 candidates)
  | _ -> StringSet.empty

(* ── Phase 3: Transform ───────────────────────────────────────────────────── *)

(** A unit no-op expression — used to replace dead RC ops. *)
let unit_expr : Tir.expr = Tir.ETuple []

(** Rewrite [e] applying stack-promotion for [promotable] variables. *)
let rec promote_expr (e : Tir.expr) (promotable : StringSet.t) : Tir.expr =
  match e with
  (* Rewrite A: promote EAlloc to EStackAlloc *)
  | Tir.ELet (v, Tir.EAlloc (ty, args), body)
    when StringSet.mem v.Tir.v_name promotable ->
    Tir.ELet (v, Tir.EStackAlloc (ty, args), promote_expr body promotable)

  (* Rewrite B: eliminate dead RC ops on stack variables in ESeq position *)
  | Tir.ESeq (Tir.EDecRC (Tir.AVar v), rest)
    when StringSet.mem v.Tir.v_name promotable ->
    promote_expr rest promotable
  | Tir.ESeq (Tir.EFree (Tir.AVar v), rest)
    when StringSet.mem v.Tir.v_name promotable ->
    promote_expr rest promotable

  (* Standalone EDecRC/EFree on promotable var — replace with unit no-op *)
  | Tir.EDecRC (Tir.AVar v) when StringSet.mem v.Tir.v_name promotable ->
    unit_expr
  | Tir.EFree (Tir.AVar v) when StringSet.mem v.Tir.v_name promotable ->
    unit_expr

  (* Recurse into compound expressions *)
  | Tir.ELet (v, e1, e2) ->
    Tir.ELet (v, promote_expr e1 promotable, promote_expr e2 promotable)
  | Tir.ELetRec (fns, body) ->
    (* Inner fn bodies are separate scopes; don't apply outer promotable set *)
    Tir.ELetRec (fns, promote_expr body promotable)
  | Tir.ECase (a, branches, default) ->
    let branches' = List.map (fun br ->
      { br with Tir.br_body = promote_expr br.Tir.br_body promotable }
    ) branches in
    let default' = Option.map (fun d -> promote_expr d promotable) default in
    Tir.ECase (a, branches', default')
  | Tir.ESeq (e1, e2) ->
    Tir.ESeq (promote_expr e1 promotable, promote_expr e2 promotable)

  (* Leaf forms — nothing to rewrite *)
  | Tir.EAtom _ | Tir.EApp _ | Tir.ECallPtr _
  | Tir.ETuple _ | Tir.ERecord _ | Tir.EField _ | Tir.EUpdate _
  | Tir.EAlloc _ | Tir.EStackAlloc _ | Tir.EFree _ | Tir.EIncRC _
  | Tir.EDecRC _ | Tir.EReuse _ ->
    e

(* ── Per-function entry ───────────────────────────────────────────────────── *)

let escape_fn (fn : Tir.fn_def) : Tir.fn_def =
  let body = fn.Tir.fn_body in
  (* Phase 1: collect EAlloc-bound variables *)
  let candidates = collect_alloc_candidates body in
  if StringSet.is_empty candidates then fn
  else begin
    (* Phase 2: compute promotable set *)
    let escaping = escaping_vars body candidates in
    let with_incrc = has_incrc_for body candidates in
    let non_promotable = StringSet.union escaping with_incrc in
    let promotable = StringSet.diff candidates non_promotable in
    if StringSet.is_empty promotable then fn
    else
      (* Phase 3: transform *)
      let body' = promote_expr body promotable in
      { fn with Tir.fn_body = body' }
  end

(* ── Module entry point ───────────────────────────────────────────────────── *)

let escape_analysis (m : Tir.tir_module) : Tir.tir_module =
  { m with Tir.tm_fns = List.map escape_fn m.Tir.tm_fns }
