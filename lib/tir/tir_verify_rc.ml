(** TIR verifier, check 3: reference-count balance (observability plan A1,
    specs/plans/incremental-codegen-cas-plan.md §6 item 3).

    Run on the [tir-perceus] module only: that is where every RC operation is
    in its final Perceus form.  Drop rewrites releases into conditional deep
    drops, Escape deletes the releases of promoted cells, and Opt runs after
    both, so the invariant below does not hold verbatim at any later stage.

    {1 The model}

    Perceus is dup/drop: every owned reference is either consumed exactly
    once (passed to an owned parameter, stored into a constructor, returned)
    or released ([dec_rc] / [free] / a reuse token), and every extra use is
    preceded by a [inc_rc].  The checker counts, per heap {e object} (an alias
    class: [let go = inc_rc $clo; $clo] makes [go] and [$clo] one object), how
    many references this frame holds, along every path of the function:

    - consume / release need at least one held reference (else
      {b over-release}); a read needs the object to be live (else
      {b use-after-release});
    - [inc_rc] adds one; a call, allocation or constructor result is a fresh
      object holding one;
    - a projected field is a {e child} of its parent: held 0, live while the
      parent is (Perceus [inc_rc]s it before a consuming use);
    - a borrowed parameter ([Borrow.is_borrowed]) and a closure's captured
      variable are leased from the caller: held 0, live for the whole call;
    - at the end of every path nothing may still be held (else a {b leak}).

    Case arms take ownership of their binders exactly as codegen does
    ([Case_handoff]: the scrutinee's dec in the arm's leading run, or a reuse
    of its cell), or alias the scrutinee when its representation stores the
    payload in place ([Perceus_core.scrutinee_shares_payload_storage]).

    Where the model cannot decide (a linear or affine binding, a binder whose
    type disagrees with its value's, an untracked scrutinee) the object is
    marked {e opaque} and never reported: a false positive here would make
    the verifier unusable, a miss only makes it less useful.  A function
    containing a surviving [ELetRec] is skipped.

    Over-release and use-after-release are errors.  Leaks are reported only
    when asked ([~leaks:true], or [MARCH_VERIFY_TIR_LEAKS=1]): Perceus has
    documented "leak rather than risk a double free" fallbacks (aggregate
    drops it stands down from, variables moved on some path) that are
    deliberate, not bugs.  The model, its rules and the cases it was derived
    from are in specs/progress/2026-10-07-verify-rc-types-and-pass-bisect.md. *)

module IntMap = Map.Make (Int)
module StringMap = Map.Make (String)

type lease =
  | Own                 (** live iff held > 0 *)
  | Caller              (** borrowed for the whole call (param, capture, global) *)
  | Child of int        (** live iff held > 0 or the parent is live *)

type cls = {
  held     : int;
  lease    : lease;
  immortal : bool;
  opaque   : bool;
  label    : string;     (** the variable it was first bound to *)
  origin   : string;     (** how it came to be held, for the report *)
}

type st = {
  cls   : cls IntMap.t;
  names : int StringMap.t;
  path  : string list;   (** innermost first *)
}

type value =
  | VNone               (** a scalar, unit or nothing tracked *)
  | VImmortal           (** a literal or a global: never counted *)
  | VOpaque             (** tracked but undecidable *)
  | VFresh              (** a new object holding one reference *)
  | VCls of int         (** an existing object *)
  | VChild of int       (** a field of an existing object, held 0 *)
  | VCaller             (** a field of the closure environment, leased *)

let diverging = [ "panic"; "panic_"; "todo_"; "unreachable_" ]

(* TRMC's destination-passing helpers ([f$dps], and after Defun
   [go$dps$apply$N]) take the parent cell as their LAST argument and write
   through it ([dst.hole <- r]); it is never released there, so the slot is
   borrowed by protocol whatever the borrow map says of an apply fn's
   parameters (lib/tir/trmc.ml, Phase 3). *)
let is_dps name =
  let m = "$dps" in
  let n = String.length name and k = String.length m in
  let rec go i = i + k <= n && (String.sub name i k = m || go (i + 1)) in
  go 0

let rec contains_letrec (e : Tir.expr) =
  match e with
  | Tir.ELetRec _ -> true
  | Tir.ELet (_, a, b) | Tir.ESeq (a, b) -> contains_letrec a || contains_letrec b
  | Tir.ECase (_, brs, d) ->
    List.exists (fun (b : Tir.branch) -> contains_letrec b.Tir.br_body) brs
    || Option.fold ~none:false ~some:contains_letrec d
  | _ -> false

let rec mentions name (e : Tir.expr) =
  let atom = function Tir.AVar v -> v.Tir.v_name = name | _ -> false in
  let atoms = List.exists atom in
  match e with
  | Tir.EAtom a | Tir.EField (a, _) | Tir.EFree a | Tir.EIncRC a | Tir.EDecRC a
  | Tir.EAtomicIncRC a | Tir.EAtomicDecRC a -> atom a
  | Tir.EApp (_, xs) | Tir.ETuple xs | Tir.EAlloc (_, xs) | Tir.EStackAlloc (_, xs) -> atoms xs
  | Tir.ECallPtr (f, xs) -> atom f || atoms xs
  | Tir.ERecord fs -> atoms (List.map snd fs)
  | Tir.EUpdate (a, fs) -> atom a || atoms (List.map snd fs)
  | Tir.EReuse (a, _, xs) -> atom a || atoms xs
  | Tir.EAllocHole (t, _, xs, _) -> Option.fold ~none:false ~some:atom t || atoms xs
  | Tir.ESetField (o, _, v) -> atom o || atom v
  | Tir.ELet (_, a, b) | Tir.ESeq (a, b) -> mentions name a || mentions name b
  | Tir.ECase (s, brs, d) ->
    atom s || List.exists (fun (b : Tir.branch) -> mentions name b.Tir.br_body) brs
    || Option.fold ~none:false ~some:(mentions name) d
  | Tir.ELetRec (fns, b) ->
    List.exists (fun (f : Tir.fn_def) -> mentions name f.Tir.fn_body) fns || mentions name b

(** Check one function.  [report kind label path what]. *)
let check_fn ~(k_table : Kind.table) ~(borrow_map : Borrow.borrow_map)
    ~(penv : Perceus_core.env) ~(externs : (string, unit) Hashtbl.t)
    ~(leaks : bool) ~(report : string -> string -> string -> string -> unit)
    (fd : Tir.fn_def) =
  if contains_letrec fd.Tir.fn_body then () else begin
  let ctr = ref 0 in
  let tracked (v : Tir.var) = v.Tir.v_lin = Tir.Unr && Kind.needs_rc_of k_table v.Tir.v_ty in
  let path_str st = match st.path with [] -> "entry" | p -> String.concat " > " (List.rev p) in
  let find st id = IntMap.find id st.cls in
  let set st id c = { st with cls = IntMap.add id c st.cls } in
  let fresh st ?(held = 1) ?(lease = Own) ?(opaque = false) ?(immortal = false) ~label ~origin () =
    incr ctr;
    let id = !ctr in
    (set st id { held; lease; immortal; opaque; label; origin }, id) in
  let rec live st id =
    let c = find st id in
    c.immortal || c.opaque
    || (match c.lease with
        | Caller -> true
        | Own -> c.held > 0
        | Child p -> c.held > 0 || live st p) in
  let skip st id = let c = find st id in c.immortal || c.opaque in
  let silence st id = set st id { (find st id) with opaque = true } in
  let read st id where =
    if skip st id || live st id then st
    else begin
      let c = find st id in
      report "use-after-release" c.label (path_str st)
        (Printf.sprintf "read at %s after its last reference was released (%s)" where c.origin);
      silence st id
    end in
  let take kind st id where =
    if skip st id then st
    else
      let c = find st id in
      if c.held > 0 then set st id { c with held = c.held - 1 }
      else begin
        report "over-release" c.label (path_str st)
          (Printf.sprintf "%s at %s while this frame holds no reference to it (%s)" kind where c.origin);
        silence st id
      end in
  let consume = take "consumed" and release = take "released" in
  let inc st id where =
    let st = read st id where in
    if skip st id then st else let c = find st id in set st id { c with held = c.held + 1 } in
  let class_of st (a : Tir.atom) =
    match a with Tir.AVar v -> StringMap.find_opt v.Tir.v_name st.names | _ -> None in
  (* Perceus decides whether a USE is counted from the atom's own type, which
     can disagree with its binder's ([i : '_] bound, [i : Int] at the call):
     an untracked atom is no reference, and the object it names is no longer
     judged.  [use] is [class_of] for every counting site. *)
  let use st (a : Tir.atom) : st * int option =
    match a with
    | Tir.AVar v ->
      (match StringMap.find_opt v.Tir.v_name st.names with
       | Some id when not (tracked v) -> (silence st id, None)
       | r -> (st, r))
    | _ -> (st, None) in
  (* a value as an atom: a literal or global is immortal *)
  let atom_value st (a : Tir.atom) : value =
    match a with
    | Tir.ALit _ | Tir.ADefRef _ -> VImmortal
    | Tir.AVar v ->
      (match StringMap.find_opt v.Tir.v_name st.names with
       | Some id -> VCls id
       | None -> if tracked v then VImmortal else VNone) in
  let consume_atoms st where atoms =
    List.fold_left (fun st a -> match use st a with
        | st, Some id -> consume st id where | st, None -> st) st atoms in
  let bind st (v : Tir.var) (value : value) ~origin =
    let name = v.Tir.v_name in
    let unbound st = { st with names = StringMap.remove name st.names } in
    let to_new st ?held ?lease ?opaque ?immortal () =
      let st, id = fresh st ?held ?lease ?opaque ?immortal ~label:name ~origin () in
      { st with names = StringMap.add name id st.names } in
    if not (tracked v) then
      (* A tracked value bound to an untracked name ([let h : Int = $f3] with
         [$f3 : '_]): its type disagrees, so stop judging the object. *)
      match value with
      | VCls id -> unbound (silence st id)
      | _ -> if v.Tir.v_lin <> Tir.Unr then to_new st ~opaque:true () else unbound st
    else
      match value with
      | VCls id -> { st with names = StringMap.add name id st.names }
      | VFresh -> to_new st ()
      | VChild p -> to_new st ~held:0 ~lease:(Child p) ()
      | VCaller -> to_new st ~held:0 ~lease:Caller ()
      | VImmortal -> to_new st ~immortal:true ()
      | VOpaque | VNone -> to_new st ~opaque:true ()
  in
  let field_ty (a : Tir.atom) field : Tir.ty option =
    match a with
    | Tir.AVar v ->
      (match v.Tir.v_ty with
       | Tir.TRecord fs -> List.assoc_opt field fs
       | Tir.TCon (n, _) ->
         (match Kind.record_fields k_table n with
          | Some fs -> List.assoc_opt field fs
          | None -> Option.bind (Kind.record_fields_short k_table n) (List.assoc_opt field))
       | _ -> None)
    | _ -> None in
  (* An arm that takes over its scrutinee's fields makes a field projected
     BEFORE the case the same object as one of the arm's binders, which the
     model gives a new class; which binder is not decidable here, so the
     earlier projection is no longer judged. *)
  let orphan_children st parent =
    { st with cls = IntMap.map (fun (c : cls) ->
          match c.lease with Child p when p = parent -> { c with opaque = true } | _ -> c) st.cls } in
  let seq_of = Pp.string_of_expr in
  let short e = let s = seq_of e in if String.length s > 60 then String.sub s 0 57 ^ "..." else s in
  (* ── evaluation ── *)
  let rec eval ~tail st (e : Tir.expr) : (st * value) option =
    match e with
    | Tir.ELet (v, rhs, body) ->
      (match eval ~tail:false st rhs with
       | None -> None
       | Some (st', value) ->
         let st' = { st' with names = st.names; path = st.path } in
         let st' = bind st' v value ~origin:(Printf.sprintf "bound to `%s`" (short rhs)) in
         eval ~tail st' body)
    | Tir.ESeq (a, b) ->
      (match eval ~tail:false st a with
       | None -> None
       | Some (st', _) -> eval ~tail { st' with names = st.names } b)
    | Tir.ECase (scrut, brs, default) -> eval_case ~tail st scrut brs default
    | _ ->
      (match eval_simple st e with
       | None -> None
       | Some (st, value) -> if tail then (finish st value; None) else Some (st, value))
  and eval_simple st (e : Tir.expr) : (st * value) option =
    let where = short e in
    match e with
    | Tir.EAtom a -> Some (st, atom_value st a)
    | Tir.EApp (f, _) when List.mem f.Tir.v_name diverging -> None
    | Tir.EApp (f, args) ->
      let fname = f.Tir.v_name in
      let nargs = List.length args in
      let borrowed i =
        Borrow.is_borrowed borrow_map fname i || (is_dps fname && i = nargs - 1) in
      (* reads first, then consumes: a dual-position argument is still live
         when the call is entered *)
      let st = List.fold_left (fun st a -> match use st a with
          | st, Some id -> read st id where | st, None -> st) st args in
      let st = List.fold_left (fun st (i, a) -> match use st a with
          | st, Some id when not (borrowed i) -> consume st id where
          | st, _ -> st) st (List.mapi (fun i a -> (i, a)) args) in
      Some (st, VFresh)
    | Tir.ECallPtr (Tir.AVar fv, args) when Hashtbl.mem externs fv.Tir.v_name ->
      eval_simple st (Tir.EApp (fv, args))
    | Tir.ECallPtr (callee, args) ->
      let st = List.fold_left (fun st a -> match use st a with
          | st, Some id -> read st id where | st, None -> st) st (callee :: args) in
      let st = match use st callee with
        | st, Some id -> consume st id where
        | st, None -> st
      in
      let callee_is_dps =
        match callee with Tir.AVar v -> is_dps v.Tir.v_name | _ -> false
      in
      let nargs = List.length args in
      let st = List.fold_left (fun st (i, a) -> match use st a with
          | st, Some id when not (callee_is_dps && i = nargs - 1) ->
            consume st id where
          | st, _ -> st) st (List.mapi (fun i a -> (i, a)) args) in
      Some (st, VFresh)
    | Tir.EIncRC a | Tir.EAtomicIncRC a ->
      Some ((match use st a with st, Some id -> inc st id where | st, None -> st), VNone)
    | Tir.EDecRC a | Tir.EAtomicDecRC a | Tir.EFree a ->
      Some ((match use st a with st, Some id -> release st id where | st, None -> st), VNone)
    | Tir.ETuple xs | Tir.EAlloc (_, xs) | Tir.EStackAlloc (_, xs) ->
      Some (consume_atoms st where xs, VFresh)
    | Tir.ERecord fs -> Some (consume_atoms st where (List.map snd fs), VFresh)
    | Tir.EUpdate (base, fs) ->
      let st = match class_of st base with Some id -> read st id where | None -> st in
      Some (consume_atoms st where (List.map snd fs), VFresh)
    | Tir.EReuse (tok, _, xs) ->
      let st = match class_of st tok with Some id -> release st id where | None -> st in
      Some (consume_atoms st where xs, VFresh)
    | Tir.EAllocHole (tok, _, xs, _) ->
      let st = match Option.bind tok (class_of st) with
        | Some id -> release st id where | None -> st in
      Some (consume_atoms st where xs, VFresh)
    | Tir.ESetField (o, _, v) ->
      let st = match class_of st o with Some id -> read st id where | None -> st in
      (match class_of st v, class_of st o with
       | Some vid, oid ->
         let st = consume st vid where in
         (* stored into [o]: still readable while [o] is *)
         let c = find st vid in
         let st = match oid with
           | Some p when c.held = 0 -> set st vid { c with lease = Child p }
           | _ -> st in
         Some (st, VNone)
       | None, _ -> Some (st, VNone))
    | Tir.EField (a, field) ->
      (match a with
       | Tir.AVar src when Perceus_core.is_actor_move_source src -> Some (st, VFresh)
       | Tir.AVar src when src.Tir.v_name = Tir_names.clo_param_name -> Some (st, VCaller)
       | _ ->
         match class_of st a with
         | Some id ->
           let st = read st id where in
           if skip st id then Some (st, VOpaque)
           else
             (* The field's own type decides whether it is counted: an [Int]
                field read in tail position is no reference at all. *)
             (match field_ty a field with
              | Some t when Kind.needs_rc_of k_table t -> Some (st, VChild id)
              | Some _ -> Some (st, VNone)
              | None -> Some (st, VOpaque))
         | None -> Some (st, VOpaque))
    | Tir.ELet _ | Tir.ESeq _ | Tir.ECase _ | Tir.ELetRec _ -> assert false
  (* end of a path: hand the result to the caller, then nothing may be held *)
  and finish st value =
    let st = match value with
      | VCls id -> consume st id "the function's result"
      | VChild p ->
        let c = find st p in
        if not (c.immortal || c.opaque) then
          report "over-release" c.label (path_str st)
            "a field of it is returned without being dup'd (the caller would own a borrowed reference)";
        st
      | _ -> st in
    if leaks then
      IntMap.iter (fun _ c ->
          if c.held > 0 && not (c.immortal || c.opaque) then
            report "leak" c.label (path_str st)
              (Printf.sprintf "still holds %d reference(s) at the end of the path (%s)" c.held c.origin))
        st.cls
  and eval_case ~tail st scrut brs default : (st * value) option =
    let st = match class_of st scrut with Some id -> read st id "a case scrutinee" | None -> st in
    let scrut_name = match scrut with Tir.AVar v -> v.Tir.v_name | _ -> "" in
    let sc = class_of st scrut in
    let shares = match scrut with
      | Tir.AVar v -> Perceus_core.scrutinee_shares_payload_storage penv v.Tir.v_ty
      | _ -> false in
    let arm (b : Tir.branch) =
      let st = { st with path = Printf.sprintf "case %s: %s" scrut_name b.Tir.br_tag :: st.path } in
      let tracked_binders = List.filter tracked b.Tir.br_vars in
      let bind_all st mk =
        List.fold_left (fun st (v : Tir.var) ->
            if tracked v then mk st v
            else { st with names = StringMap.remove v.Tir.v_name st.names })
          st b.Tir.br_vars in
      let opaque_binders st = bind_all st (fun st v -> bind st v VOpaque ~origin:"a case binder") in
      let st, body =
        match sc with
        | None -> (opaque_binders st, b.Tir.br_body)
        | Some id when skip st id -> (opaque_binders st, b.Tir.br_body)
        | Some id when shares ->
          (match tracked_binders, b.Tir.br_vars with
           | [ v ], [ _ ] ->
             ({ st with names = StringMap.add v.Tir.v_name id st.names }, b.Tir.br_body)
           | [], [] -> (set st id { (find st id) with immortal = true }, b.Tir.br_body)
           | _ -> (opaque_binders st, b.Tir.br_body))
        | Some id ->
          (match Case_handoff.strip_scrut_decrc scrut_name b.Tir.br_body with
           | Some (_, rest) ->
             let st = orphan_children st id in
             let st = release st id "the arm's head (the arm takes the fields over)" in
             (bind_all st (fun st v -> bind st v VFresh ~origin:"a field the arm took over"), rest)
           | None when Case_handoff.body_reuses_scrut scrut_name b.Tir.br_body ->
             let st = orphan_children st id in
             (bind_all st (fun st v -> bind st v VFresh ~origin:"a field the arm took over"),
              b.Tir.br_body)
           | None ->
             (bind_all st (fun st v -> bind st v (VChild id) ~origin:"a field of the scrutinee"),
              b.Tir.br_body)) in
      eval ~tail st body in
    let def_arm d =
      eval ~tail { st with path = Printf.sprintf "case %s: _" scrut_name :: st.path } d in
    let results = List.map arm brs @ (match default with Some d -> [ def_arm d ] | None -> []) in
    if tail then None
    else begin
      let reaching = List.filter_map Fun.id results in
      match reaching with
      | [] -> None
      | _ ->
        let pre_max = IntMap.fold (fun id _ m -> max id m) st.cls 0 in
        let same_pre =
          match reaching with
          | (_, VCls id) :: rest when id <= pre_max ->
            if List.for_all (function (_, VCls j) -> j = id | _ -> false) rest then Some id else None
          | _ -> None in
        (* each arm hands one reference to the binding, unless all return the
           same pre-existing object *)
        let reaching =
          match same_pre with
          | Some _ -> reaching
          | None ->
            List.map (fun (st_a, v) ->
                match v with
                | VCls id -> (consume st_a id "the case's result", v)
                | VChild p ->
                  let c = find st_a p in
                  if not (c.immortal || c.opaque) then
                    report "over-release" c.label (path_str st_a)
                      "a field of it is the arm's result, not dup'd (the case binding would own a borrowed reference)";
                  (st_a, v)
                | _ -> (st_a, v)) reaching in
        (* arm-local objects must be settled by the join *)
        if leaks then
          List.iter (fun (st_a, _) ->
              IntMap.iter (fun id c ->
                  if id > pre_max && c.held > 0 && not (c.immortal || c.opaque) then
                    report "leak" c.label (path_str st_a)
                      (Printf.sprintf "still holds %d reference(s) where the case's arms join (%s)"
                         c.held c.origin))
                st_a.cls) reaching;
        (* pre-existing objects: every arm must leave them alike *)
        let merged = IntMap.mapi (fun id (c : cls) ->
            let cs = List.map (fun (st_a, _) -> find st_a id) reaching in
            let held = List.fold_left (fun m (c : cls) -> min m c.held) max_int cs in
            let opaque = List.exists (fun (c : cls) -> c.opaque) cs in
            if leaks && not opaque && not c.immortal then
              List.iter (fun (st_a, _) ->
                  let ca = find st_a id in
                  if ca.held > held then
                    report "leak" c.label (path_str st_a)
                      (Printf.sprintf "this arm holds %d more reference(s) than another arm where they join"
                         (ca.held - held)))
                reaching;
            { c with held; opaque; immortal = c.immortal && List.for_all (fun (c : cls) -> c.immortal) cs })
            st.cls in
        let st = { st with cls = merged } in
        let value = match same_pre with Some id -> VCls id | None -> VFresh in
        Some (st, value)
    end
  in
  (* ── entry ── *)
  let st0 = { cls = IntMap.empty; names = StringMap.empty; path = [] } in
  let st0 = List.fold_left (fun st (i, (p : Tir.var)) ->
      let name = p.Tir.v_name in
      let add st ?held ?lease ?opaque ?immortal origin =
        let st, id = fresh st ?held ?lease ?opaque ?immortal ~label:name ~origin () in
        { st with names = StringMap.add name id st.names } in
      let nparams = List.length fd.Tir.fn_params in
      if p.Tir.v_lin <> Tir.Unr then add st ~opaque:true "a linear parameter"
      else if not (tracked p) then st
      else if is_dps fd.Tir.fn_name && i = nparams - 1 then
        add st ~held:0 ~lease:Caller "a TRMC destination (written through, never released)"
      else if name = Tir_names.clo_param_name then
        (if mentions name fd.Tir.fn_body then add st "the closure environment"
         else add st ~immortal:true "an unused closure environment")
      else if Borrow.is_borrowed borrow_map fd.Tir.fn_name i then
        add st ~held:0 ~lease:Caller "a borrowed parameter"
      else add st "an owned parameter")
      st0 (List.mapi (fun i p -> (i, p)) fd.Tir.fn_params) in
  ignore (eval ~tail:true st0 fd.Tir.fn_body)
  end

let leaks_by_env : bool Lazy.t =
  lazy (match Sys.getenv_opt "MARCH_VERIFY_TIR_LEAKS" with
        | Some ("" | "0") | None -> false | Some _ -> true)

(** Findings for [m] at [stage] ([(fn_name, message)], as {!Tir_verify.check}). *)
let check ~(stage : string) ?(leaks = Lazy.force leaks_by_env)
    ~(k_table : Kind.table) ~(borrow_map : Borrow.borrow_map) (m : Tir.tir_module) :
    (string * string) list =
  let findings = ref [] and seen = Hashtbl.create 16 in
  let penv = { Perceus_core.empty_env with
               Perceus_core.k_table; borrow_map; type_defs = m.Tir.tm_types;
               collision_set = Kind.collision_set k_table } in
  let externs = Hashtbl.create 32 in
  List.iter (fun (ed : Tir.extern_decl) -> Hashtbl.replace externs ed.Tir.ed_march_name ())
    m.Tir.tm_externs;
  List.iter (fun (fd : Tir.fn_def) ->
      let report kind label path what =
        if not (Hashtbl.mem seen (fd.Tir.fn_name, label, kind)) then begin
          Hashtbl.replace seen (fd.Tir.fn_name, label, kind) ();
          findings := (fd.Tir.fn_name,
                       Printf.sprintf "[%s] rc-balance/%s: `%s` on path `%s`: %s"
                         stage kind label path what) :: !findings
        end in
      check_fn ~k_table ~borrow_map ~penv ~externs ~leaks ~report fd)
    m.Tir.tm_fns;
  List.rev !findings
