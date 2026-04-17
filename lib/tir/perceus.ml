(** Perceus RC Analysis — Pass 4.

    Inserts reference-counting operations (EIncRC / EDecRC) into the TIR,
    exploiting static last-use information to elide as many RC ops as
    possible.  Linear and affine values get EFree instead of RC.
    Adjacent Inc/Dec cancel pairs are removed, and FBIP reuse is detected.

    Atomic RC (EAtomicIncRC / EAtomicDecRC) is emitted for values that are
    passed as message arguments to [send()].  These values may cross actor
    thread boundaries and require C11-atomic RC to avoid data races.
    All other values use fast non-atomic RC (march_incrc_local / march_decrc_local).

    Borrow Inference integration (Pass 4.0, via Borrow.infer_module):
    Before inserting RC ops, the pass analyses every function to determine
    which parameters are "borrowed" — only read (via pattern match / field
    access), never stored, returned, or passed to an owning position.
    For borrowed parameters:
    - In the callee: no EDecRC is emitted (the parameter is added to the
      [borrowed] live-at-exit set, suppressing last-use ownership transfer).
    - At call sites: no EIncRC is emitted for arguments at borrowed positions
      that are still live after the call.
    - At call sites where the borrowed arg IS the caller's last use (ownership
      would normally transfer): the caller instead emits EDecRC after the call,
      since the callee will not decrement the value. *)

module StringSet = Set.Make (String)
module StringMap = Map.Make (String)

(* ── Fresh variable counter for RC restructuring ─────────────────────────── *)

let _rc_fresh_ctr = ref 0

let fresh_rc_var (ty : Tir.ty) : Tir.var =
  incr _rc_fresh_ctr;
  { Tir.v_name = Printf.sprintf "$rc_%d" !_rc_fresh_ctr;
    v_ty = ty; v_lin = Tir.Unr }

(* ── Borrow map — module-level state ─────────────────────────────────────── *)

(** The current module's borrow map, set at the start of [perceus] and cleared
    on exit.  Using a ref (rather than threading it through every helper) keeps
    the helpers' signatures unchanged and avoids pervasive API churn. *)
let _borrow_map : Borrow.borrow_map ref = ref Borrow.empty

(** Name of the function currently being processed by [insert_rc].
    Used in the EApp case to detect self-recursive calls, so that
    ESeq(EApp(self,...), EDecRC(arg)) is left intact for TCO to handle
    (the EDecRC becomes dead code after the back-edge is emitted). *)
let _current_fn_name : string ref = ref ""

(** Closure free-variable names for the function currently being processed.
    Variables in this set are bound by [let fv = $clo.$fvN] in apply functions.
    They are OWNED by the closure, not by the apply function body.
    The closure's RC keeps them alive for the duration of every call, so:
    - They must NOT be decreffed at last use (suppresses post_dec_vars).
    - They must NOT be increffed when passed as arguments (suppresses find_inc_vars).
    - A dead binding of such a variable must NOT emit EDecRC / EFree.
    Removing these RC ops also eliminates the data race between the non-atomic
    [march_decrc_local] in the generated apply function and the atomic
    [march_incrc] in the C HTTP runtime's per-request incref loop. *)
let _closure_fvs : StringSet.t ref = ref StringSet.empty

(** Collect the names of variables loaded directly from the closure parameter
    [$clo] via EField.  Only apply functions have [$clo] as first param. *)
let collect_closure_fvs (fn : Tir.fn_def) : StringSet.t =
  match fn.Tir.fn_params with
  | p :: _ when String.equal p.Tir.v_name "$clo" ->
    let clo_name = p.Tir.v_name in
    let rec scan e acc =
      match e with
      | Tir.ELet (v, Tir.EField (Tir.AVar src, _), rest)
        when String.equal src.Tir.v_name clo_name ->
        scan rest (StringSet.add v.Tir.v_name acc)
      | Tir.ELet (_, e1, e2) ->
        scan e2 (scan e1 acc)
      | Tir.ELetRec (fns, body) ->
        let from_fns = List.fold_left (fun a fd -> scan fd.Tir.fn_body a) acc fns in
        scan body from_fns
      | Tir.ESeq (e1, e2) ->
        scan e2 (scan e1 acc)
      | Tir.ECase (_, branches, default) ->
        let from_branches =
          List.fold_left (fun a br -> scan br.Tir.br_body a) acc branches
        in
        (match default with Some d -> scan d from_branches | None -> from_branches)
      | _ -> acc
    in
    scan fn.Tir.fn_body StringSet.empty
  | _ -> StringSet.empty

(* ── Actor-send analysis ─────────────────────────────────────────────────── *)

(** Variables that appear as message arguments to [send()] in the current
    function.  Set by [insert_rc] before processing each function body.
    Values in this set use atomic RC operations. *)
let _actor_sent : StringSet.t ref = ref StringSet.empty

(** Collect the set of variable names passed as messages to [send()].
    [send(actor, msg)] — msg is the 2nd argument. *)
let rec collect_actor_sent_vars (e : Tir.expr) : StringSet.t =
  match e with
  | Tir.EApp (f, [_; Tir.AVar msg])
    when String.equal f.Tir.v_name "send" ->
    StringSet.singleton msg.Tir.v_name
  | Tir.EApp _ -> StringSet.empty
  | Tir.EAtom _ | Tir.ECallPtr _ -> StringSet.empty
  | Tir.ELet (_, e1, e2) ->
    StringSet.union (collect_actor_sent_vars e1) (collect_actor_sent_vars e2)
  | Tir.ELetRec (fns, body) ->
    List.fold_left (fun acc fn ->
      StringSet.union acc (collect_actor_sent_vars fn.Tir.fn_body)
    ) (collect_actor_sent_vars body) fns
  | Tir.ECase (_, branches, default) ->
    let from_branches = List.fold_left (fun acc br ->
      StringSet.union acc (collect_actor_sent_vars br.Tir.br_body)
    ) StringSet.empty branches in
    let from_default = match default with
      | Some d -> collect_actor_sent_vars d
      | None -> StringSet.empty
    in
    StringSet.union from_branches from_default
  | Tir.ESeq (e1, e2) ->
    StringSet.union (collect_actor_sent_vars e1) (collect_actor_sent_vars e2)
  | _ -> StringSet.empty

(** Choose the appropriate IncRC variant for [v].
    Actor-sent vars use atomic; all others use local (non-atomic). *)
let incrc_for (v : Tir.var) (a : Tir.atom) : Tir.expr =
  if StringSet.mem v.Tir.v_name !_actor_sent
  then Tir.EAtomicIncRC a
  else Tir.EIncRC a

(** Choose the appropriate DecRC variant for [v]. *)
let decrc_for (v : Tir.var) (a : Tir.atom) : Tir.expr =
  if StringSet.mem v.Tir.v_name !_actor_sent
  then Tir.EAtomicDecRC a
  else Tir.EDecRC a

(* ── Helpers ─────────────────────────────────────────────────────────────── *)

(** Returns true if this type needs reference counting (heap-allocated). *)
let needs_rc : Tir.ty -> bool = function
  | Tir.TCon ("Atom", []) -> false  (* atoms are i64 scalars, not heap-allocated *)
  | Tir.TCon _ | Tir.TString | Tir.TPtr _ -> true
  | Tir.TVar "_" -> true  (* lower.ml placeholder for ECase br_vars / closure params:
                              conservatively treat as heap-carrying.  The LLVM emit
                              guards all RC calls with [if ty = "ptr" then …], so
                              emitting EIncRC/EDecRC for a scalar TVar "_" is safe —
                              the guard prevents the actual C call from firing. *)
  | Tir.TVar _ -> false  (* unresolved user type-var after mono: skip RC *)
  | Tir.TInt | Tir.TFloat | Tir.TBool | Tir.TUnit
  | Tir.TTuple _ | Tir.TRecord _ | Tir.TFn _ -> false

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
  | Tir.EAtom (Tir.ADefRef _) ->
    live_after  (* global ref — no local liveness *)
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

(* ── Phase 2: RC Insertion ────────────────────────────────────────────────── *)

(** Wrap [inner] with IncRC (atomic if actor-sent) for each variable in [incs]. *)
let wrap_incrcs (incs : Tir.var list) (inner : Tir.expr) : Tir.expr =
  List.fold_right (fun v acc ->
    Tir.ESeq (incrc_for v (Tir.AVar v), acc)
  ) incs inner

(** Determine which AVar atoms in a list need EIncRC because they are
    Unr, needs_rc, and still live after this use.
    Closure FVs are handled via the [borrowed] set in [insert_rc]: they are
    added to [borrowed] so they are always considered live, which causes this
    function to emit an EIncRC before any consuming (last-use) call.  That
    keeps the closure's reference alive regardless of how many times the apply
    function is invoked (i.e., when the closure's own RC > 1). *)
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
      (Tir.ESeq (incrc_for v (Tir.AVar v), e), lb)
    else
      (e, lb)

  | Tir.EAtom (Tir.ADefRef _) ->
    (e, live_after)  (* global ref — no RC, no liveness change *)

  | Tir.EAtom (Tir.ALit _) ->
    (e, live_after)

  | Tir.EApp (f, args) ->
    (* Borrow-aware Inc insertion for direct (known) calls.
       For each argument at position [i]:
         - Standard (owned) parameter: insert EIncRC if Unr+needs_rc+live_after.
         - Borrowed parameter (per _borrow_map):
             • Arg still live after call → skip EIncRC (callee will not Dec).
             • Arg NOT live after call  → no EIncRC (same as before), but emit
               EDecRC *after* the call because the callee will not Dec it. *)
    let indexed_args = List.mapi (fun i a -> (i, a)) args in
    (* 1. Args that go to owned parameters — standard Inc logic. *)
    let non_borrowed_args =
      List.filter_map (fun (i, a) ->
        if Borrow.is_borrowed !_borrow_map f.Tir.v_name i then None
        else Some a
      ) indexed_args
    in
    let inc_vars = find_inc_vars ((Tir.AVar f) :: non_borrowed_args) live_after in
    (* 2. Borrowed args whose last use is this call: caller is responsible for Dec.
          Closure FVs are exempt: the closure owns them and keeps them alive.
          Dedup by v_name: when the same variable is passed at multiple
          borrowed positions (e.g. [f(x, x)] both borrowed, [x] dead after),
          the caller still owns exactly one reference and must emit exactly
          one DecRC.  Without dedup we would underflow the RC. *)
    let post_dec_vars =
      let seen = ref StringSet.empty in
      List.filter_map (fun (i, a) ->
        match a with
        | Tir.AVar v
          when v.Tir.v_lin = Tir.Unr
               && needs_rc v.Tir.v_ty
               && not (StringSet.mem v.Tir.v_name live_after)
               && Borrow.is_borrowed !_borrow_map f.Tir.v_name i
               && not (StringSet.mem v.Tir.v_name !_closure_fvs)
               && not (StringSet.mem v.Tir.v_name !seen) ->
          seen := StringSet.add v.Tir.v_name !seen;
          Some v
        | _ -> None
      ) indexed_args
    in
    let e' = wrap_incrcs inc_vars e in
    (* Wrap with post-call Decs.
       When there are post-call decrefs and the call has a non-unit return
       type, ESeq would discard the call result (ESeq returns its LAST
       expression's value).  Instead, bind the result to a fresh temp, run
       the decrefs, then return the temp.
       For unit-returning calls ESeq is fine — the result is not used.
       EXCEPTION: self-recursive tail calls keep the old ESeq form.
       has_self_tail_call in llvm_emit.ml explicitly handles
       ESeq(EApp(self,...), EDecRC(arg)) — after TCO emits the back-edge,
       the EDecRC is dead code and everything is correct.  Wrapping with
       ELet would hide the self-call from has_self_tail_call and kill TCO. *)
    let is_self_call = String.equal f.Tir.v_name !_current_fn_name in
    let e'' =
      match post_dec_vars with
      | [] -> e'
      | _ when is_self_call ->
        (* Self-tail-call: keep ESeq so TCO detection finds the call *)
        List.fold_left (fun acc v ->
          Tir.ESeq (acc, decrc_for v (Tir.AVar v))
        ) e' post_dec_vars
      | _ ->
        let call_ret_ty = match f.Tir.v_ty with
          | Tir.TFn (_, r) -> r
          | _ -> Tir.TVar "_"
        in
        (match call_ret_ty with
         | Tir.TUnit ->
           (* Unit return: plain ESeq is fine *)
           List.fold_left (fun acc v ->
             Tir.ESeq (acc, decrc_for v (Tir.AVar v))
           ) e' post_dec_vars
         | _ ->
           (* Non-unit return: bind result, run decrefs, return result.
              Build ESeq(EDecRC(v1), ESeq(EDecRC(v2), ..., EAtom($rc)))
              so that ESeq returns the last expression ($rc), not the
              last DecRC.  Use fold_right so decrefs wrap the atom. *)
           let tmp = fresh_rc_var call_ret_ty in
           let decrcs =
             List.fold_right (fun v acc ->
               Tir.ESeq (decrc_for v (Tir.AVar v), acc)
             ) post_dec_vars (Tir.EAtom (Tir.AVar tmp))
           in
           Tir.ELet (tmp, e', decrcs))
    in
    let lb =
      live_after
      |> StringSet.add f.Tir.v_name
      |> StringSet.union (vars_of_atoms args)
    in
    (e'', lb)

  | Tir.ECallPtr (a, args) ->
    (* Conservative borrow treatment (audit P5): we have no borrow map for
       the indirect callee, so every arg is treated as owning.  For args
       still live after the call, [find_inc_vars] inserts an EIncRC so the
       callee's consumed reference is balanced against the caller's retained
       one.  For dead-after args, no IncRC is emitted — the caller's
       reference transfers to the callee, which is expected to decrement it
       (the closure-apply ABI used for ECallPtr always consumes args).
       The perf cost is extra Inc/Dec pairs around higher-order calls whose
       underlying apply function actually borrows.  A full fix would require
       attaching per-call-site borrow modes to closures at EAlloc time and
       plumbing them through the call dispatch — a sizeable architectural
       change deferred beyond this audit pass. *)
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
      if not (StringSet.mem v.Tir.v_name live_into_e2)
         && not (StringSet.mem v.Tir.v_name !_closure_fvs) then
        (* Dead binding — insert cleanup at start of e2.
           Use atomic DecRC for actor-sent values (may be concurrently accessed).
           Closure FVs are exempt: the closure holds the reference; the apply
           function must not decrement values it does not own. *)
        if v.Tir.v_lin = Tir.Unr && needs_rc v.Tir.v_ty then
          Tir.ESeq (decrc_for v (Tir.AVar v), e2')
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
    (* Fix value-discarding ESeq patterns in the processed RHS.
       Borrow inference may produce ESeq(call, DecRC(arg)) at tail positions
       of the RHS expression (including inside nested ELet chains).  ESeq
       returns the LAST expr's value, so the call result is discarded.
       We restructure by introducing a fresh let binding to capture the value:
         ESeq(value, cleanup)  →  ELet($rc_N, value, ESeq(cleanup, $rc_N))
       This preserves the value while still running the cleanup.
       The restructuring follows ELet chains to find tail ESeqs. *)
    let rec fix_tail_value (expr : Tir.expr) : Tir.expr =
      match expr with
      | Tir.ESeq (value_expr, ((Tir.EDecRC _ | Tir.EAtomicDecRC _
                                | Tir.EFree _) as cleanup)) ->
        let fixed = fix_tail_value value_expr in
        let tmp = fresh_rc_var v.Tir.v_ty in
        Tir.ELet (tmp, fixed, Tir.ESeq (cleanup, Tir.EAtom (Tir.AVar tmp)))
      | Tir.ELet (iv, ie1, ibody) ->
        Tir.ELet (iv, ie1, fix_tail_value ibody)
      | _ -> expr
    in
    let e1_fixed = fix_tail_value e1' in
    (Tir.ELet (v, e1_fixed, e2''), live_before_e1)

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
                     && not (StringSet.mem v.Tir.v_name live_after)
                     && not (name_free_in v.Tir.v_name body) ->
        (* Use the concrete ctor type so shape_matches works in FBIP.
           Do not dec_rc if the branch body still uses the scrutinee (e.g.,
           when the scrutinee is passed through as an argument after inspection
           of one of its fields via a nested match).
           IMPORTANT: qualify the ctor_tag with the scrutinee's type name so it
           matches the key format used by EAlloc (see lower.ml ECon case:
           ctor_key = type_name ^ "." ^ tag).  Without this, shape_matches
           compares e.g. "Leaf" vs "Tree.Leaf" and always returns false,
           preventing FBIP from ever firing.
           When the scrutinee's type is unknown (TVar — typical for closure-
           internal helpers whose params are erased to TVar "_"), we cannot
           form a qualified tag.  Falling back to the bare ctor_tag would let
           shape_matches false-positive against any same-name ctor of a
           different type and silently write wrong-layout fields into the
           reused cell.  Instead, leave the var's type untouched: shape_matches
           is total on its arguments and will simply return false, suppressing
           FBIP for this scrutinee — the safe choice. *)
        let ctor_v = match v.Tir.v_ty with
          | Tir.TCon (type_name, _) ->
            let qualified_tag = type_name ^ "." ^ ctor_tag in
            { v with Tir.v_ty = Tir.TCon (qualified_tag, []) }
          | _ -> v
        in
        Tir.ESeq (decrc_for v (Tir.AVar ctor_v), body)
      | _ -> body
    in
    let branches' = List.map (fun br ->
      let bound =
        List.fold_left (fun s v -> StringSet.add v.Tir.v_name s)
          StringSet.empty br.Tir.br_vars
      in
      let la = StringSet.diff live_after bound in
      (* When the scrutinee is borrowed (not freed in this branch), its branch
         variables are borrowed references extracted from it.  They must not be
         freed at their last use; re-add them to live_after so post_dec_var
         does not fire for them after borrowed calls inside the branch body.
         The scrutinee is borrowed in two cases:
         1. It lives in live_after (used after the entire case).
         2. It appears free in this branch's body (used in a different sub-path
            within the branch, e.g. the else side of an if inside the branch).
         Case 2 was previously unhandled, causing br_vars to be passed to owning
         positions without IncRC — the root cause of the sort_by RC underflow. *)
      let scrutinee_borrowed = match a with
        | Tir.AVar v ->
          StringSet.mem v.Tir.v_name live_after
          || (needs_rc v.Tir.v_ty
              && name_free_in v.Tir.v_name br.Tir.br_body)
        | _ -> false
      in
      let la = if scrutinee_borrowed then
        List.fold_left (fun s bv -> StringSet.add bv.Tir.v_name s)
          la br.Tir.br_vars
      else la
      in
      let (body', _) = insert_rc_expr br.Tir.br_body la in
      { br with Tir.br_body = add_scrutinee_free_for br.Tir.br_tag body' }
    ) branches in
    let default' = Option.map (fun d ->
      let (d_rc, _) = insert_rc_expr d live_after in
      (* Default branch: no constructor tag known, use original type.
         Only free the scrutinee if the branch body does NOT use it directly —
         if the body uses it, ownership transfers into the body. *)
      (match a with
       | Tir.AVar v when needs_rc v.Tir.v_ty
                      && not (StringSet.mem v.Tir.v_name live_after)
                      && not (name_free_in v.Tir.v_name d) ->
         Tir.ESeq (decrc_for v (Tir.AVar v), d_rc)
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

  | Tir.EIncRC a | Tir.EAtomicIncRC a ->
    let lb = StringSet.union live_after (vars_of_atom a) in
    (e, lb)

  | Tir.EDecRC a | Tir.EAtomicDecRC a ->
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

(** Insert RC ops into a function definition.
    [borrowed] names are treated as still-live at the function's exit,
    preventing Perceus from treating their last use as an ownership transfer.
    Used for REPL globals that persist across compilation units.
    Pre-computes the actor-sent variable set so that values sent across actor
    thread boundaries use atomic RC operations. *)
(** Rename ELet/ECase-bound variables whose names collide with [borrowed]
    parameters.  When [let s = f(s, …)] appears in a function whose parameter
    [s] is borrowed, Perceus's backward liveness analysis removes "s" from
    live_after when computing the live set for the RHS.  This causes
    post_dec_var to fire for the borrowed parameter — a spurious dec_rc.
    By renaming only the offending bindings, we break the aliasing without
    disturbing unrelated variable names (which preserves test expectations). *)
let rename_borrowed_shadows (borrowed : StringSet.t) (body : Tir.expr) : Tir.expr =
  if StringSet.is_empty borrowed then body
  else
  let ctr = ref 0 in
  let fresh n = incr ctr; Printf.sprintf "%s_b%d" n !ctr in
  (* subst: maps old_name → new_name only for bindings we have renamed *)
  let atom subst a = match a with
    | Tir.AVar v -> (match StringMap.find_opt v.Tir.v_name subst with
        | Some n -> Tir.AVar { v with Tir.v_name = n }
        | None -> a)
    | _ -> a
  in
  let var subst v = match StringMap.find_opt v.Tir.v_name subst with
    | Some n -> { v with Tir.v_name = n }
    | None -> v
  in
  let bind subst v =
    (* Rename if this binding's name is a borrowed param OR is currently
       being substituted (to prevent chained aliasing). *)
    if StringSet.mem v.Tir.v_name borrowed || StringMap.mem v.Tir.v_name subst then
      let n = fresh v.Tir.v_name in
      ({ v with Tir.v_name = n }, StringMap.add v.Tir.v_name n subst)
    else
      (* Clear any outer substitution for this name: a fresh binding shadows it *)
      (v, StringMap.remove v.Tir.v_name subst)
  in
  let rec go subst e =
    match e with
    | Tir.EAtom a -> Tir.EAtom (atom subst a)
    | Tir.EApp (f, args) -> Tir.EApp (var subst f, List.map (atom subst) args)
    | Tir.ECallPtr (fn_a, args) ->
      Tir.ECallPtr (atom subst fn_a, List.map (atom subst) args)
    | Tir.ELet (v, rhs, bdy) ->
      let rhs' = go subst rhs in   (* rhs sees old subst — references the param, not the binding *)
      let (v', subst') = bind subst v in
      Tir.ELet (v', rhs', go subst' bdy)
    | Tir.ELetRec (fns, bdy) ->
      (* Freshen any fn names that collide with borrowed params *)
      let (fns1, subst1) = List.fold_left (fun (fs, s) fd ->
        let tmp = { Tir.v_name = fd.Tir.fn_name; v_ty = Tir.TUnit; v_lin = Tir.Unr } in
        let (tmp', s') = bind s tmp in
        ({ fd with Tir.fn_name = tmp'.Tir.v_name } :: fs, s')
      ) ([], subst) fns in
      let fns2 = List.rev_map (fun fd ->
        { fd with Tir.fn_body = go subst1 fd.Tir.fn_body }) fns1 in
      Tir.ELetRec (fns2, go subst1 bdy)
    | Tir.ECase (a, branches, default) ->
      let a' = atom subst a in
      let branches' = List.map (fun br ->
        let (br_vars', subst') = List.fold_left (fun (vs, s) bv ->
          let (bv', s') = bind s bv in (vs @ [bv'], s')
        ) ([], subst) br.Tir.br_vars in
        { br with Tir.br_vars = br_vars'; Tir.br_body = go subst' br.Tir.br_body }
      ) branches in
      let default' = Option.map (go subst) default in
      Tir.ECase (a', branches', default')
    | Tir.ESeq (e1, e2) -> Tir.ESeq (go subst e1, go subst e2)
    | Tir.ETuple atoms -> Tir.ETuple (List.map (atom subst) atoms)
    | Tir.ERecord fields ->
      Tir.ERecord (List.map (fun (k, a) -> (k, atom subst a)) fields)
    | Tir.EField (a, f) -> Tir.EField (atom subst a, f)
    | Tir.EUpdate (a, fs) ->
      Tir.EUpdate (atom subst a, List.map (fun (k, v) -> (k, atom subst v)) fs)
    | Tir.EAlloc (ty, args) -> Tir.EAlloc (ty, List.map (atom subst) args)
    | Tir.EStackAlloc (ty, args) -> Tir.EStackAlloc (ty, List.map (atom subst) args)
    | Tir.EFree a -> Tir.EFree (atom subst a)
    | Tir.EIncRC a -> Tir.EIncRC (atom subst a)
    | Tir.EDecRC a -> Tir.EDecRC (atom subst a)
    | Tir.EAtomicIncRC a -> Tir.EAtomicIncRC (atom subst a)
    | Tir.EAtomicDecRC a -> Tir.EAtomicDecRC (atom subst a)
    | Tir.EReuse (a, ty, args) ->
      Tir.EReuse (atom subst a, ty, List.map (atom subst) args)
  in
  go StringMap.empty body

let insert_rc ?(borrowed = StringSet.empty) (fn : Tir.fn_def) : Tir.fn_def =
  (* Rename ELet/ECase-bound variables that shadow borrowed parameters before
     RC insertion.  See [rename_borrowed_shadows] for the full rationale. *)
  let body_renamed = rename_borrowed_shadows borrowed fn.Tir.fn_body in
  let fn' = { fn with Tir.fn_body = body_renamed } in
  _actor_sent    := collect_actor_sent_vars fn'.Tir.fn_body;
  _current_fn_name := fn'.Tir.fn_name;
  let closure_fvs = collect_closure_fvs fn' in
  _closure_fvs   := closure_fvs;
  (* Closure FVs are owned by the closure struct, not by the apply function.
     The apply function merely borrows them for the duration of one call.
     Adding them to the borrowed set makes Perceus treat them as always-live:
     find_inc_vars then inserts EIncRC before any consuming (last-use) call,
     so the closure's reference to each FV survives even when the closure
     itself has RC > 1 and the apply function is invoked multiple times.
     Without this, a single-use FV (e.g. the inner Generator in Gen.map) is
     silently transferred to the callee on the first call, freed when the
     callee's pattern-match decrements its RC to 0, and becomes a dangling
     pointer on the second call → SIGSEGV. *)
  let borrowed' = StringSet.union borrowed closure_fvs in
  let (body', _) = insert_rc_expr fn'.Tir.fn_body borrowed' in
  _actor_sent    := StringSet.empty;
  _current_fn_name := "";
  _closure_fvs   := StringSet.empty;
  { fn' with Tir.fn_body = body' }

(* ── Phase 3: RC Elision (cancel pairs) ──────────────────────────────────── *)

(** Remove adjacent EIncRC/EDecRC cancel pairs.

    Also elide pairs that span an ELet binding whose RHS does not reference
    the cancelled variable (audit L5).  Perceus's [fix_tail_value]
    restructuring frequently wraps tail-position cleanup in an ELet, which
    otherwise prevents the simple adjacent-cancel detection from firing
    even though the Inc/Dec are semantically a no-op pair.

    Atomicity strictness (audit P4): a cancel pair is only elided when BOTH
    halves have the same atomicity.  Mixed (atomic↔non-atomic) pairs are
    left in place.  Rationale: [incrc_for] and [decrc_for] pick atomicity
    from [_actor_sent] per function, so same-variable ops should always
    match in correct code.  If a future pass ever produces a mismatch
    (e.g. inliner copying code across actor-send boundaries), eliding would
    silently drop the atomic op and introduce a data race.  Being strict
    lets that class of bug surface via still-present RC operations rather
    than turning into a memory-ordering heisenbug.  The dedicated test
    [tir/perceus/p4_mixed_atomicity_preserved] pins the invariant. *)
let rec elide_expr (e : Tir.expr) : Tir.expr =
  let inc_dec_match v1 v2 = String.equal v1.Tir.v_name v2.Tir.v_name in
  match e with
  (* Cancel pair, matching atomicity *)
  | Tir.ESeq (Tir.EIncRC (Tir.AVar v1),
              Tir.ESeq (Tir.EDecRC (Tir.AVar v2), rest))
    when inc_dec_match v1 v2 -> elide_expr rest
  | Tir.ESeq (Tir.EAtomicIncRC (Tir.AVar v1),
              Tir.ESeq (Tir.EAtomicDecRC (Tir.AVar v2), rest))
    when inc_dec_match v1 v2 -> elide_expr rest
  | Tir.ESeq (Tir.EDecRC (Tir.AVar v1),
              Tir.ESeq (Tir.EIncRC (Tir.AVar v2), rest))
    when inc_dec_match v1 v2 -> elide_expr rest
  | Tir.ESeq (Tir.EAtomicDecRC (Tir.AVar v1),
              Tir.ESeq (Tir.EAtomicIncRC (Tir.AVar v2), rest))
    when inc_dec_match v1 v2 -> elide_expr rest
  (* L5: cancel pair that spans an ELet whose RHS does not reference the
     RC'd variable.  Same atomicity-strictness rule as above. *)
  | Tir.ESeq (Tir.EIncRC (Tir.AVar v1),
              Tir.ELet (x, rhs,
                Tir.ESeq (Tir.EDecRC (Tir.AVar v2), rest)))
    when inc_dec_match v1 v2 && not (name_free_in v1.Tir.v_name rhs) ->
    elide_expr (Tir.ELet (x, rhs, rest))
  | Tir.ESeq (Tir.EAtomicIncRC (Tir.AVar v1),
              Tir.ELet (x, rhs,
                Tir.ESeq (Tir.EAtomicDecRC (Tir.AVar v2), rest)))
    when inc_dec_match v1 v2 && not (name_free_in v1.Tir.v_name rhs) ->
    elide_expr (Tir.ELet (x, rhs, rest))
  | Tir.ESeq (Tir.EDecRC (Tir.AVar v1),
              Tir.ELet (x, rhs,
                Tir.ESeq (Tir.EIncRC (Tir.AVar v2), rest)))
    when inc_dec_match v1 v2 && not (name_free_in v1.Tir.v_name rhs) ->
    elide_expr (Tir.ELet (x, rhs, rest))
  | Tir.ESeq (Tir.EAtomicDecRC (Tir.AVar v1),
              Tir.ELet (x, rhs,
                Tir.ESeq (Tir.EAtomicIncRC (Tir.AVar v2), rest)))
    when inc_dec_match v1 v2 && not (name_free_in v1.Tir.v_name rhs) ->
    elide_expr (Tir.ELet (x, rhs, rest))
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
  | Tir.EAtomicIncRC _ | Tir.EAtomicDecRC _ | Tir.EReuse _ ->
    e

(** Elide cancel pairs in a function definition. *)
let elide_cancel_pairs (fn : Tir.fn_def) : Tir.fn_def =
  { fn with Tir.fn_body = elide_expr fn.Tir.fn_body }

(* ── Phase 4: FBIP Reuse Detection ──────────────────────────────────────── *)

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
  | Tir.EAtomicIncRC _ | Tir.EAtomicDecRC _ | Tir.EReuse _ ->
    e

(** Apply FBIP reuse to a function definition. *)
let insert_fbip (fn : Tir.fn_def) : Tir.fn_def =
  { fn with Tir.fn_body = fbip_expr fn.Tir.fn_body }

(* ── Phase 0.5: whole-scrutinee-escape rewrite ───────────────────────────────
   Problem: when a pattern-match arm returns the scrutinee verbatim in one
   path while consuming its fields in sibling paths, e.g.

     match ls do
       Nil -> Nil
       Cons(l, rest) ->
         if String.is_empty(trim(l)) do drop_blank(rest)
         else ls
         end
     end

   Perceus sees the scrutinee `ls` as free in the Cons arm body (used in the
   `else ls` branch) and therefore SKIPS emitting `dec_rc ls` at the arm
   start.  But on the `drop_blank(rest)` sub-path, `rest` and `l` are still
   treated as independent owning vars — including a post-call `dec_rc l`
   after the `trim(l)` borrow — yet no ownership was ever transferred from
   the scrutinee to them.  The `dec_rc l` then underflows the string's RC
   and corrupts the heap (see commit 6065f30 for the fields-escape sibling
   issue).

   Fix: BEFORE Perceus, rewrite every tail-position occurrence of the
   scrutinee inside a matched arm into a reconstruction of the matched
   constructor.  E.g. `Cons(l, rest) -> ... ls` becomes
   `Cons(l, rest) -> ... Cons(l, rest)`.  After rewriting:
   - The arm body no longer mentions the scrutinee → the existing
     `add_scrutinee_free_for` emits the usual `dec_rc ls` at arm start.
   - `llvm_emit`'s `strip_scrut_decrc` converts that into the
     `march_decrc_freed` + conditional field-IncRC pattern, which correctly
     transfers ownership of the extracted fields into the arm.
   - The trailing EAlloc re-packs those owned fields into a fresh cell,
     which FBIP can collapse to an EReuse of the scrutinee's storage.

   Only SYNTACTIC tail positions are rewritten: an EAtom(AVar scrut) that
   is the arm's result, or the result of a tail sub-expression (ECase arm,
   ELet body, ESeq tail, ELetRec body).  Non-tail occurrences (scrut used
   inside a call argument that is not itself a tail call) stay untouched;
   if those patterns turn out to matter in practice they can be handled
   separately. *)

(** Scan the straight-line ELet prefix of [e] for the user-level rebinds
    of each [br_var] (e.g. `let l = $f1` after pattern decomposition).  If
    a rebind is found its typed var replaces the anonymous br_var; this
    lets the reconstructed EAlloc store atoms that already carry their
    concrete types, so downstream Perceus/FBIP RC analysis sees the right
    shape.  Falls back to the raw br_var when no rebind is present. *)
let scrut_escape_field_atoms (br_vars : Tir.var list) (body : Tir.expr)
    : Tir.atom list =
  let rec gather acc e =
    match e with
    | Tir.ELet (v, Tir.EAtom (Tir.AVar src), rest) ->
      gather ((src.Tir.v_name, v) :: acc) rest
    | Tir.ELet (_, _, rest) -> gather acc rest
    | _ -> List.rev acc
  in
  let rebinds = gather [] body in
  List.map (fun bv ->
    match List.assoc_opt bv.Tir.v_name rebinds with
    | Some v -> Tir.AVar v
    | None -> Tir.AVar bv
  ) br_vars

(** Replace every tail-position occurrence of [EAtom (AVar scrut_name)] in
    [e] with an EAlloc reconstructing the matched constructor.  Stops
    recursing through binders that shadow [scrut_name]. *)
let rec rewrite_scrut_tail (scrut_name : string) (alloc_ty : Tir.ty)
    (field_atoms : Tir.atom list) (e : Tir.expr) : Tir.expr =
  match e with
  | Tir.EAtom (Tir.AVar v) when String.equal v.Tir.v_name scrut_name ->
    Tir.EAlloc (alloc_ty, field_atoms)
  | Tir.ELet (v, e1, e2) ->
    if String.equal v.Tir.v_name scrut_name then e
    else Tir.ELet (v, e1, rewrite_scrut_tail scrut_name alloc_ty field_atoms e2)
  | Tir.ELetRec (fns, body) ->
    let shadows =
      List.exists (fun fn -> String.equal fn.Tir.fn_name scrut_name) fns
    in
    if shadows then e
    else Tir.ELetRec (fns, rewrite_scrut_tail scrut_name alloc_ty field_atoms body)
  | Tir.ESeq (e1, e2) ->
    Tir.ESeq (e1, rewrite_scrut_tail scrut_name alloc_ty field_atoms e2)
  | Tir.ECase (a, branches, default) ->
    let branches' = List.map (fun br ->
      let shadows =
        List.exists (fun bv -> String.equal bv.Tir.v_name scrut_name) br.Tir.br_vars
      in
      if shadows then br
      else { br with Tir.br_body =
        rewrite_scrut_tail scrut_name alloc_ty field_atoms br.Tir.br_body }
    ) branches in
    let default' =
      Option.map (rewrite_scrut_tail scrut_name alloc_ty field_atoms) default
    in
    Tir.ECase (a, branches', default')
  | _ -> e

(** Walk the function body, applying the scrut-escape rewrite inside every
    ECase arm whose scrutinee is a heap-valued AVar and whose branch binds
    at least one field. *)
let rec preprocess_scrut_escape (e : Tir.expr) : Tir.expr =
  match e with
  | Tir.ECase (a, branches, default) ->
    let branches' = List.map (fun br ->
      let body' = preprocess_scrut_escape br.Tir.br_body in
      let body'' =
        match a with
        | Tir.AVar sv
          when needs_rc sv.Tir.v_ty
               && br.Tir.br_vars <> []
               && not (List.exists
                         (fun bv -> String.equal bv.Tir.v_name sv.Tir.v_name)
                         br.Tir.br_vars)
               && name_free_in sv.Tir.v_name body' ->
          let qualified_tag = match sv.Tir.v_ty with
            | Tir.TCon (type_name, _) -> type_name ^ "." ^ br.Tir.br_tag
            | _ -> br.Tir.br_tag
          in
          let alloc_ty = Tir.TCon (qualified_tag, []) in
          let field_atoms = scrut_escape_field_atoms br.Tir.br_vars body' in
          rewrite_scrut_tail sv.Tir.v_name alloc_ty field_atoms body'
        | _ -> body'
      in
      { br with Tir.br_body = body'' }
    ) branches in
    let default' = Option.map preprocess_scrut_escape default in
    Tir.ECase (a, branches', default')
  | Tir.ELet (v, e1, e2) ->
    Tir.ELet (v, preprocess_scrut_escape e1, preprocess_scrut_escape e2)
  | Tir.ELetRec (fns, body) ->
    let fns' = List.map (fun fn ->
      { fn with Tir.fn_body = preprocess_scrut_escape fn.Tir.fn_body }
    ) fns in
    Tir.ELetRec (fns', preprocess_scrut_escape body)
  | Tir.ESeq (e1, e2) ->
    Tir.ESeq (preprocess_scrut_escape e1, preprocess_scrut_escape e2)
  | _ -> e

let preprocess_fn (fn : Tir.fn_def) : Tir.fn_def =
  { fn with Tir.fn_body = preprocess_scrut_escape fn.Tir.fn_body }

(* ── Debug stats ──────────────────────────────────────────────────────────── *)

let _perceus_debug : bool Lazy.t =
  lazy (Sys.getenv_opt "MARCH_DEBUG_PERCEUS" <> None)

type rc_counts = {
  inc_rc      : int;
  dec_rc      : int;
  atomic_inc  : int;
  atomic_dec  : int;
  free        : int;
  reuse       : int;
}

let zero_counts = { inc_rc = 0; dec_rc = 0; atomic_inc = 0; atomic_dec = 0; free = 0; reuse = 0 }

let add_counts a b = {
  inc_rc     = a.inc_rc     + b.inc_rc;
  dec_rc     = a.dec_rc     + b.dec_rc;
  atomic_inc = a.atomic_inc + b.atomic_inc;
  atomic_dec = a.atomic_dec + b.atomic_dec;
  free       = a.free       + b.free;
  reuse      = a.reuse      + b.reuse;
}

let rec count_rc_ops_expr (e : Tir.expr) : rc_counts =
  let recurse_fn fn = count_rc_ops_expr fn.Tir.fn_body in
  match e with
  | Tir.EIncRC _                                -> { zero_counts with inc_rc = 1 }
  | Tir.EDecRC _                                -> { zero_counts with dec_rc = 1 }
  | Tir.EAtomicIncRC _                          -> { zero_counts with atomic_inc = 1 }
  | Tir.EAtomicDecRC _                          -> { zero_counts with atomic_dec = 1 }
  | Tir.EFree _                                 -> { zero_counts with free = 1 }
  | Tir.EReuse _                                -> { zero_counts with reuse = 1 }
  | Tir.ELet (_, e1, e2)                        -> add_counts (count_rc_ops_expr e1) (count_rc_ops_expr e2)
  | Tir.ELetRec (fns, body)                     ->
    List.fold_left (fun acc fn -> add_counts acc (recurse_fn fn))
      (count_rc_ops_expr body) fns
  | Tir.ESeq (e1, e2)                           -> add_counts (count_rc_ops_expr e1) (count_rc_ops_expr e2)
  | Tir.ECase (_, branches, default)            ->
    let from_branches = List.fold_left (fun acc br ->
      add_counts acc (count_rc_ops_expr br.Tir.br_body)) zero_counts branches in
    let from_default = Option.fold ~none:zero_counts ~some:count_rc_ops_expr default in
    add_counts from_branches from_default
  | _ -> zero_counts

let count_rc_ops_module (fns : Tir.fn_def list) : rc_counts =
  List.fold_left (fun acc fn ->
    add_counts acc (count_rc_ops_expr fn.Tir.fn_body)) zero_counts fns

let print_perceus_stats ~(label : string) ~(before : rc_counts) ~(after : rc_counts) () =
  let cancelled_inc = before.inc_rc     - after.inc_rc in
  let cancelled_dec = before.dec_rc     - after.dec_rc in
  let cancelled_a_inc = before.atomic_inc - after.atomic_inc in
  let cancelled_a_dec = before.atomic_dec - after.atomic_dec in
  Printf.eprintf "[perceus] %s\n" label;
  Printf.eprintf "  inserted:  inc=%d dec=%d atomic_inc=%d atomic_dec=%d free=%d reuse=%d\n"
    before.inc_rc before.dec_rc before.atomic_inc before.atomic_dec before.free before.reuse;
  Printf.eprintf "  after elision+fbip: inc=%d dec=%d atomic_inc=%d atomic_dec=%d free=%d reuse=%d\n"
    after.inc_rc after.dec_rc after.atomic_inc after.atomic_dec after.free after.reuse;
  Printf.eprintf "  cancelled: inc=%d dec=%d atomic_inc=%d atomic_dec=%d\n"
    cancelled_inc cancelled_dec cancelled_a_inc cancelled_a_dec;
  Printf.eprintf "%!"

(* ── Entry point ──────────────────────────────────────────────────────────── *)

(** Run all four Perceus phases over every function in the module.
    [repl_vars] is a list of bare variable names that correspond to REPL
    globals bridged into the current compilation unit.  They are injected
    into the borrowed set of the [main] function so Perceus never treats
    their last use as an ownership transfer, preventing RC underflow when
    the same global is passed to multiple successive REPL lines.

    Borrow inference (Phase 0) runs first: it analyses the whole module to
    determine which function parameters are borrowed, then passes that
    information into the RC insertion phase so that:
    - Callee: borrowed params are added to the live-at-exit set, suppressing
      EDecRC / scrutinee-free on those params.
    - Caller: EIncRC is skipped for args at borrowed positions that are still
      live after the call; a post-call EDecRC is emitted instead when the arg
      is the caller's last use. *)
let perceus ?(repl_vars : string list = []) (m : Tir.tir_module) : Tir.tir_module =
  (* Reset the fresh-name counter per module so that compiling the same module
     twice produces identical IR.  A monotonic counter that survives across
     modules makes IR diffs unstable and causes spurious churn in test
     baselines. *)
  _rc_fresh_ctr := 0;
  (* Phase 0: borrow inference *)
  let borrow_map = Borrow.infer_module m in
  _borrow_map := borrow_map;
  let repl_set =
    List.fold_left (fun s n -> StringSet.add n s) StringSet.empty repl_vars
  in
  let fns_after_insert =
    m.Tir.tm_fns
    |> List.map preprocess_fn
    |> List.map (fun fn ->
         let base =
           if fn.Tir.fn_name = "main" then repl_set else StringSet.empty
         in
         let borrowed =
           List.fold_left (fun s (i, p) ->
             if Borrow.is_borrowed borrow_map fn.Tir.fn_name i
             then StringSet.add p.Tir.v_name s
             else s
           ) base (List.mapi (fun i p -> (i, p)) fn.Tir.fn_params)
         in
         insert_rc ~borrowed fn)
  in
  let fns' =
    fns_after_insert
    |> List.map elide_cancel_pairs
    |> List.map insert_fbip
  in
  if Lazy.force _perceus_debug then begin
    let before = count_rc_ops_module fns_after_insert in
    let after  = count_rc_ops_module fns' in
    print_perceus_stats ~label:m.Tir.tm_name ~before ~after ()
  end;
  _borrow_map := Borrow.empty;
  { m with Tir.tm_fns = fns' }
