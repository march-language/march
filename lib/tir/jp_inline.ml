(** Inline single-use join points back into their creator
    (specs/todos/2026-10-01-join-point-self-tail-call-not-looped.md).

    The match compiler hoists a shared arm or a non-atomic fallback into a join
    point ([Lower_match.hoist_fallback_jp]): a local lambda, which Defun turns
    into a closure allocation plus a lifted [$jp…$apply$N] function, and which
    [Known_call] turns into a direct call:

    {v
    fn ordered(xs) =
      case xs of
        Cons(a0, t0) ->
          let c = alloc $Clo_$jp7($jp7$apply$9, a0, t0) in
          case t0 of Nil() -> true
                     _     -> $jp7$apply$9(c)
    fn $jp7$apply$9($clo) =
      let a0 = $clo.$fv1 in let t0 = $clo.$fv2 in
      ... ordered(Cons(b, rest))          (* tail call *)
    v}

    A self tail call written inside the hoisted arm is then a call from the join
    point to its creator: [ordered] -> [$jp$apply] -> [ordered]. That is not a
    self call, so [Llvm_tco] does not turn it into a loop, and it is not a
    mutual-TCO group either (the join point returns the erased ['_], so the
    group's return types differ). The function recurses once per element:
    [test/native/array_sort_by.march]'s [ordered_and_stable] overflowed its
    1 MiB green-thread stack at about 8,000 elements.

    When a join point's closure is allocated once and called once, in the same
    function, and its apply function is referenced nowhere else, the join point
    exists only because the match compiler shared code that ended up with one
    use. This pass puts its body back at the call site: each [$clo.$fvK] load
    becomes the captured atom, the remaining parameters are bound to the call's
    arguments, the allocation is dropped, and the call to the creator becomes a
    plain self tail call that [Llvm_tco] loops.

    Runs after [Known_call] (which makes the call direct) and before Perceus, so
    there are no RC operations to move: Perceus computes ownership for the
    inlined code as for any other. The lifted function is left in place;
    reachability-based DCE drops it once nothing references it. *)

module SSet = Set.Make (String)

let is_jp_apply (name : string) : bool =
  String.length name > 3 && String.sub name 0 3 = "$jp" && Tir_names.is_apply_fn name

(** Every top-level-name reference in [e]: call targets and atom variables. *)
let rec count_refs (tbl : (string, int) Hashtbl.t) (e : Tir.expr) : unit =
  let bump n = Hashtbl.replace tbl n (1 + Option.value ~default:0 (Hashtbl.find_opt tbl n)) in
  let atom = function Tir.AVar v -> bump v.Tir.v_name | _ -> () in
  let atoms = List.iter atom in
  match e with
  | Tir.EAtom a -> atom a
  | Tir.EApp (f, args) -> bump f.Tir.v_name; atoms args
  | Tir.ECallPtr (f, args) -> atom f; atoms args
  | Tir.ELet (_, e1, e2) | Tir.ESeq (e1, e2) -> count_refs tbl e1; count_refs tbl e2
  | Tir.ELetRec (fns, body) ->
    List.iter (fun (fd : Tir.fn_def) -> count_refs tbl fd.Tir.fn_body) fns; count_refs tbl body
  | Tir.ECase (a, brs, def) ->
    atom a;
    List.iter (fun (b : Tir.branch) -> count_refs tbl b.Tir.br_body) brs;
    Option.iter (count_refs tbl) def
  | Tir.ETuple xs -> atoms xs
  | Tir.ERecord fs -> List.iter (fun (_, a) -> atom a) fs
  | Tir.EField (a, _) -> atom a
  | Tir.EUpdate (a, fs) -> atom a; List.iter (fun (_, a) -> atom a) fs
  | Tir.EAlloc (_, xs) | Tir.EStackAlloc (_, xs) -> atoms xs
  | Tir.EAllocHole (tok, _, xs, _) -> Option.iter atom tok; atoms xs
  | Tir.ESetField (o, _, v) -> atom o; atom v
  | Tir.EFree a | Tir.EIncRC a | Tir.EAtomicIncRC a | Tir.EDecRC a | Tir.EAtomicDecRC a -> atom a
  | Tir.EReuse (a, _, xs) -> atom a; atoms xs

let uses (name : string) (e : Tir.expr) : int =
  let t = Hashtbl.create 8 in
  count_refs t e;
  Option.value ~default:0 (Hashtbl.find_opt t name)

(** Names bound anywhere in [e]. *)
let rec binders (e : Tir.expr) (acc : SSet.t) : SSet.t =
  match e with
  | Tir.ELet (v, e1, e2) -> binders e2 (binders e1 (SSet.add v.Tir.v_name acc))
  | Tir.ESeq (e1, e2) -> binders e2 (binders e1 acc)
  | Tir.ELetRec (fns, body) ->
    let acc = List.fold_left (fun acc (fd : Tir.fn_def) ->
        let acc = SSet.add fd.Tir.fn_name acc in
        let acc = List.fold_left (fun a (p : Tir.var) -> SSet.add p.Tir.v_name a) acc fd.Tir.fn_params in
        binders fd.Tir.fn_body acc) acc fns in
    binders body acc
  | Tir.ECase (_, brs, def) ->
    let acc = List.fold_left (fun acc (b : Tir.branch) ->
        let acc = List.fold_left (fun a (v : Tir.var) -> SSet.add v.Tir.v_name a) acc b.Tir.br_vars in
        binders b.Tir.br_body acc) acc brs in
    (match def with Some d -> binders d acc | None -> acc)
  | _ -> acc

(** Replace [$clo.$fvK] loads with the K-th captured atom. [None] if the body
    uses [$clo] any other way (a recursive lambda's self-binding, say). *)
let substitute_captures (clo : string) (caps : Tir.atom list) (body : Tir.expr) : Tir.expr option =
  let fields = List.mapi (fun i a -> (Tir_names.fv_field (i + 1), a)) caps in
  let ok = ref true in
  let rec go e =
    match e with
    | Tir.EField (Tir.AVar v, f) when v.Tir.v_name = clo ->
      (match List.assoc_opt f fields with
       | Some a -> Tir.EAtom a
       | None -> ok := false; e)
    | Tir.ELet (v, e1, e2) -> Tir.ELet (v, go e1, go e2)
    | Tir.ESeq (e1, e2) -> Tir.ESeq (go e1, go e2)
    | Tir.ELetRec (fns, b) ->
      Tir.ELetRec (List.map (fun (fd : Tir.fn_def) -> { fd with Tir.fn_body = go fd.Tir.fn_body }) fns, go b)
    | Tir.ECase (a, brs, def) ->
      Tir.ECase (a, List.map (fun (b : Tir.branch) -> { b with Tir.br_body = go b.Tir.br_body }) brs,
                 Option.map go def)
    | other -> other
  in
  let body' = go body in
  if !ok && uses clo body' = 0 then Some body' else None

(** Replace the one [EApp(apply, AVar c :: args)] in [e] with [inlined args]. *)
let rec replace_call (apply : string) (c : string) (inline : Tir.atom list -> Tir.expr)
    (e : Tir.expr) : Tir.expr =
  let go = replace_call apply c inline in
  match e with
  | Tir.EApp (f, Tir.AVar v :: args) when f.Tir.v_name = apply && v.Tir.v_name = c -> inline args
  | Tir.ELet (v, e1, e2) -> Tir.ELet (v, go e1, go e2)
  | Tir.ESeq (e1, e2) -> Tir.ESeq (go e1, go e2)
  | Tir.ELetRec (fns, b) ->
    Tir.ELetRec (List.map (fun (fd : Tir.fn_def) -> { fd with Tir.fn_body = go fd.Tir.fn_body }) fns, go b)
  | Tir.ECase (a, brs, def) ->
    Tir.ECase (a, List.map (fun (b : Tir.branch) -> { b with Tir.br_body = go b.Tir.br_body }) brs,
               Option.map go def)
  | other -> other

(** The single direct call [EApp(apply, AVar c :: _)] exists in [e]. *)
let rec has_call (apply : string) (c : string) (e : Tir.expr) : bool =
  match e with
  | Tir.EApp (f, Tir.AVar v :: _) when f.Tir.v_name = apply && v.Tir.v_name = c -> true
  | Tir.ELet (_, e1, e2) | Tir.ESeq (e1, e2) -> has_call apply c e1 || has_call apply c e2
  | Tir.ELetRec (fns, b) ->
    List.exists (fun (fd : Tir.fn_def) -> has_call apply c fd.Tir.fn_body) fns || has_call apply c b
  | Tir.ECase (_, brs, def) ->
    List.exists (fun (b : Tir.branch) -> has_call apply c b.Tir.br_body) brs
    || (match def with Some d -> has_call apply c d | None -> false)
  | _ -> false

(** Drop [let c = alloc $Clo_$jp…(…) in body] when [c] is unused in [body].
    The match compiler mints a join-point closure for every fallback it might
    need, including ones a branch never calls; such a dead allocation still
    CAPTURES the closures it would have called, which makes a live join point
    look used twice. An allocation has no effect, and before Perceus there is no
    ownership to account for, so dropping the dead one is exact. Bottom-up, so a
    chain of dead closures capturing each other goes in one pass. *)
let rec drop_dead_jp_allocs (e : Tir.expr) : Tir.expr =
  let go = drop_dead_jp_allocs in
  match e with
  | Tir.ELet (c, (Tir.EAlloc (Tir.TCon (_, _), Tir.AVar apply_v :: _) as alloc), body)
    when is_jp_apply apply_v.Tir.v_name ->
    let body = go body in
    if uses c.Tir.v_name body = 0 then body else Tir.ELet (c, alloc, body)
  | Tir.ELet (v, e1, e2) -> Tir.ELet (v, go e1, go e2)
  | Tir.ESeq (e1, e2) -> Tir.ESeq (go e1, go e2)
  | Tir.ELetRec (fs, b) ->
    Tir.ELetRec (List.map (fun (fd : Tir.fn_def) -> { fd with Tir.fn_body = go fd.Tir.fn_body }) fs, go b)
  | Tir.ECase (a, brs, def) ->
    Tir.ECase (a, List.map (fun (b : Tir.branch) -> { b with Tir.br_body = go b.Tir.br_body }) brs,
               Option.map go def)
  | other -> other

let run (m : Tir.tir_module) : Tir.tir_module =
  let m = { m with Tir.tm_fns = List.map (fun (fd : Tir.fn_def) ->
      { fd with Tir.fn_body = drop_dead_jp_allocs fd.Tir.fn_body }) m.Tir.tm_fns } in
  let fns = Hashtbl.create 256 in
  List.iter (fun (fd : Tir.fn_def) -> Hashtbl.replace fns fd.Tir.fn_name fd) m.Tir.tm_fns;
  (* Module-wide reference counts: an inlinable join point's apply fn is named
     exactly twice -- the allocation that stores it and the one call. *)
  let refs = Hashtbl.create 1024 in
  List.iter (fun (fd : Tir.fn_def) -> count_refs refs fd.Tir.fn_body) m.Tir.tm_fns;
  let inlined = ref 0 in
  let rec rw (e : Tir.expr) : Tir.expr =
    match e with
    | Tir.ELet (c, (Tir.EAlloc (Tir.TCon (_, _), Tir.AVar apply_v :: caps) as alloc), body)
      when is_jp_apply apply_v.Tir.v_name
        && Hashtbl.find_opt refs apply_v.Tir.v_name = Some 2
        && Hashtbl.mem fns apply_v.Tir.v_name ->
      let body = rw body in
      let apply = apply_v.Tir.v_name in
      let jp = Hashtbl.find fns apply in
      let cap_names = List.filter_map (function Tir.AVar v -> Some v.Tir.v_name | _ -> None) caps in
      let rebinds = binders body SSet.empty in
      if uses c.Tir.v_name body <> 1 || not (has_call apply c.Tir.v_name body)
         || List.exists (fun n -> SSet.mem n rebinds) cap_names
      then Tir.ELet (c, alloc, body)
      else begin
        match jp.Tir.fn_params with
        | clo :: params ->
          (match substitute_captures clo.Tir.v_name caps jp.Tir.fn_body with
           | None -> Tir.ELet (c, alloc, body)
           | Some jp_body ->
             (* Hygiene: freshen every binder of the copied body. *)
             let (params', jp_body') = Inline.alpha_rename params jp_body in
             let inline args =
               if List.length args <> List.length params' then
                 failwith ("jp_inline: arity mismatch inlining " ^ apply);
               (* The copied body may itself hold an inlinable join point. *)
               rw (Inline.subst_args ~fn_name:apply params' args jp_body')
             in
             incr inlined;
             replace_call apply c.Tir.v_name inline body)
        | [] -> Tir.ELet (c, alloc, body)
      end
    | Tir.ELet (v, e1, e2) -> Tir.ELet (v, rw e1, rw e2)
    | Tir.ESeq (e1, e2) -> Tir.ESeq (rw e1, rw e2)
    | Tir.ELetRec (fs, b) ->
      Tir.ELetRec (List.map (fun (fd : Tir.fn_def) -> { fd with Tir.fn_body = rw fd.Tir.fn_body }) fs, rw b)
    | Tir.ECase (a, brs, def) ->
      Tir.ECase (a, List.map (fun (b : Tir.branch) -> { b with Tir.br_body = rw b.Tir.br_body }) brs,
                 Option.map rw def)
    | other -> other
  in
  let fns' = List.map (fun (fd : Tir.fn_def) ->
      if is_jp_apply fd.Tir.fn_name then fd   (* the join points themselves: left for DCE *)
      else { fd with Tir.fn_body = rw fd.Tir.fn_body }) m.Tir.tm_fns in
  if !inlined = 0 then m else { m with Tir.tm_fns = fns' }
  (* [m] already has the dead join-point allocations dropped. *)
