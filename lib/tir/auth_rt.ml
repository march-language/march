(** Run-time frames for function `needs` clauses (ocap phase 4, Task 4;
    specs/plans/2026-11-15-ocap-p4-runtime-plan.md).

    The type checker already proves that every operation reached by direct
    calls under a fn [f] with `needs N` has a kind in [N].  At run time a
    frame is needed only where it cannot see:
    - the clause carries a scope (a computed target can fall outside it), or
    - [f] reaches an actor spawn: the actor's handlers are charged to the
      actor's module, not to [f], yet a worker spawned under [f] keeps [f]'s
      authority for life (the spawn copies the current authority);
    - [f] reaches a call of a function value: the checker proves only direct
      calls, and a function value runs under its caller's authority, so the
      call must happen under [f]'s frame (this also covers a spawn reached
      only through a function value, e.g. [List.each(xs, spawner)]).

    Such an [f] is rewritten to

    {v
      f(args)       = let l = f$auth_layer() in
                      let s = Authority.enter_fn(l) in
                      let r = f$auth(args) in
                      cap_restore(s); r
      f$auth(args)  = the original body, its own self calls (not those
                      in a lambda it makes) retargeted here
      f$auth_layer()= Authority.frame_layer("<name>", "<needs text>")
    v}

    [f$auth_layer] runs once per program: the LLVM emitter turns every call
    of it into [march_cap_layer_once] on a per-site cell (the layer is parsed
    on first entry, made immortal and shared by every later entry and
    thread), and the JS emitter memoises it; the inliners leave it alone so
    that call reaches codegen.  [Authority.enter_fn] pushes the layer unless
    the same frame is already on top (decision 6), which is two string
    compares.  Retargeting self calls keeps a self tail call a loop, and a
    tail call to another framed fn goes to its body when its frame is in
    force ([hop_tail_calls]), so a mutual recursion loops too.

    No frame for the program entry (its clause is the launch request).  With
    nothing to frame the module is returned physically unchanged, so a
    program with no frames compiles to the same IR. *)

module SSet = Set.Make (String)

let rec iter_calls (k : string -> unit) (e : Tir.expr) : unit =
  match e with
  | Tir.EApp (f, _) -> k f.Tir.v_name
  | Tir.ELet (_, a, b) | Tir.ESeq (a, b) -> iter_calls k a; iter_calls k b
  | Tir.ELetRec (fns, b) ->
    List.iter (fun (f : Tir.fn_def) -> iter_calls k f.Tir.fn_body) fns;
    iter_calls k b
  | Tir.ECase (_, brs, d) ->
    List.iter (fun (br : Tir.branch) -> iter_calls k br.Tir.br_body) brs;
    Option.iter (iter_calls k) d
  | _ -> ()

(* The actor-spawn builtins (lib/tir/lower_actor.ml: `spawn(A)` lowers to
   [spawn(A_spawn())]; a supervise block's child to [spawn_supervised]). *)
let spawn_builtins = [ "spawn"; "spawn_supervised" ]

(** Whether [e], with the local bindings [bound] in scope, calls a function
    VALUE: an [ECallPtr], or an [EApp] whose callee is a local binding (a
    parameter, a let or case binder) rather than a top-level fn, a builtin
    or a local fn written right there (a [ELetRec] name: its body is part
    of this fn's code and is scanned with it).  The type checker proves
    nothing about what such a call runs, so it must run under the caller's
    authority. *)
let calls_value_under (bound : SSet.t) (e : Tir.expr) : bool =
  let add (v : Tir.var) b = SSet.add v.Tir.v_name b in
  let rec go bound (e : Tir.expr) =
    match e with
    | Tir.ECallPtr _ -> true
    | Tir.EApp (f, _) -> SSet.mem f.Tir.v_name bound
    | Tir.ELet (v, a, b) -> go bound a || go (add v bound) b
    | Tir.ESeq (a, b) -> go bound a || go bound b
    | Tir.ELetRec (fns, b) ->
      let bound =
        List.fold_left (fun bd (fd : Tir.fn_def) -> SSet.remove fd.Tir.fn_name bd) bound fns in
      List.exists
        (fun (fd : Tir.fn_def) -> go (List.fold_right add fd.Tir.fn_params bound) fd.Tir.fn_body)
        fns
      || go bound b
    | Tir.ECase (_, brs, d) ->
      List.exists
        (fun (br : Tir.branch) -> go (List.fold_right add br.Tir.br_vars bound) br.Tir.br_body)
        brs
      || (match d with Some d -> go bound d | None -> false)
    | _ -> false
  in
  go bound e

(** [calls_value_under] for the body [e] of a fn with params [params]. *)
let calls_fn_value (params : Tir.var list) (e : Tir.expr) : bool =
  calls_value_under
    (List.fold_left (fun b (v : Tir.var) -> SSet.add v.Tir.v_name b) SSet.empty params) e

(** The least fixpoint over direct calls to fns of [m] (a lambda or local
    fn's body counts for the fn it is written in), seeded by the fns for
    which [seed] holds. *)
let reaching (m : Tir.tir_module) ~(seed : defined:(string, unit) Hashtbl.t -> Tir.fn_def -> bool)
  : SSet.t =
  let defined = Hashtbl.create 256 in
  List.iter (fun (f : Tir.fn_def) -> Hashtbl.replace defined f.Tir.fn_name ()) m.Tir.tm_fns;
  let callees = Hashtbl.create 256 in
  let seeds =
    List.fold_left
      (fun acc (f : Tir.fn_def) ->
         let cs = ref SSet.empty in
         iter_calls (fun n -> if Hashtbl.mem defined n then cs := SSet.add n !cs) f.Tir.fn_body;
         Hashtbl.replace callees f.Tir.fn_name !cs;
         if seed ~defined f then SSet.add f.Tir.fn_name acc else acc)
      SSet.empty m.Tir.tm_fns
  in
  let rec fix reach =
    let reach' =
      Hashtbl.fold
        (fun n cs acc ->
           if SSet.mem n acc then acc
           else if SSet.exists (fun c -> SSet.mem c reach) cs then SSet.add n acc
           else acc)
        callees reach
    in
    if SSet.cardinal reach' = SSet.cardinal reach then reach else fix reach'
  in
  fix seeds

(** The fns of [m] that reach an actor spawn through direct calls. *)
let reaches_actor_spawn (m : Tir.tir_module) : SSet.t =
  reaching m ~seed:(fun ~defined f ->
      let spawns = ref false in
      iter_calls
        (fun n -> if List.mem n spawn_builtins && not (Hashtbl.mem defined n) then spawns := true)
        f.Tir.fn_body;
      !spawns)

(** The fns of [m] that reach a call of a function value through direct
    calls ([calls_fn_value]); e.g. a fn that calls [List.each] with any
    argument. *)
let reaches_indirect_call (m : Tir.tir_module) : SSet.t =
  reaching m ~seed:(fun ~defined:_ f -> calls_fn_value f.Tir.fn_params f.Tir.fn_body)

(* [e], [f]'s own body, with its direct self calls retargeted to [to_].
   Only [f]'s own code: never a lambda's or local fn's body (an [ELetRec]),
   which may escape and run outside [f]'s frame, so it must call the
   wrapper; and not under a local binder of the same name. *)
let rec retarget ~from ~to_ (e : Tir.expr) : Tir.expr =
  let go = retarget ~from ~to_ in
  match e with
  | Tir.EApp (f, args) when f.Tir.v_name = from -> Tir.EApp ({ f with Tir.v_name = to_ }, args)
  | Tir.ELet (v, a, b) ->
    Tir.ELet (v, go a, if v.Tir.v_name = from then b else go b)
  | Tir.ESeq (a, b) -> Tir.ESeq (go a, go b)
  | Tir.ELetRec (fns, b) ->
    if List.exists (fun (fd : Tir.fn_def) -> fd.Tir.fn_name = from) fns then e
    else Tir.ELetRec (fns, go b)
  | Tir.ECase (s, brs, d) ->
    Tir.ECase
      (s,
       List.map
         (fun (br : Tir.branch) ->
            if List.exists (fun (v : Tir.var) -> v.Tir.v_name = from) br.Tir.br_vars then br
            else { br with Tir.br_body = go br.Tir.br_body })
         brs,
       Option.map go d)
  | other -> other

let var name ty = { Tir.v_name = name; v_ty = ty; v_lin = Tir.Unr }

(* The frame's layer type, read off the lowered [Authority.frame_layer]
   when it has a concrete one (its spelling is the lowerer's), else the same
   spelling.  The saved authority is always the builtins' opaque
   [CapAuthRef]: the emitter releases a dropped one structurally by that
   type ([Llvm_ctx.cap_auth_release_fn]). *)
let layer_ty (m : Tir.tir_module) : Tir.ty =
  match
    List.find_opt (fun (f : Tir.fn_def) -> f.Tir.fn_name = Tir_names.frame_layer_fn_name) m.Tir.tm_fns
  with
  | Some { Tir.fn_ret_ty = Tir.TCon _ as t; _ } -> t
  | _ -> Tir.TCon ("Layer", [])

let auth_ref_ty : Tir.ty = Tir.TCon ("CapAuthRef", [])

(* [let l = layer() in let s = enter(l) in let r = inner in cap_restore(s);
   r]: the frame every wrapper and grant prologue builds. *)
let frame_around ~layer_ty ~auth_ty ~layer_name ~enter_name ~(ret_ty : Tir.ty)
    ?(names = ("$auth_l", "$auth_saved", "$auth_result", "$auth_unit")) (inner : Tir.expr)
  : Tir.expr =
  let ln, sn, rn, un = names in
  let l = var ln layer_ty in
  let s = var sn auth_ty in
  let r = var rn ret_ty in
  let u = var un Tir.TUnit in
  Tir.ELet
    ( l, Tir.EApp (var layer_name (Tir.TFn ([], layer_ty)), []),
      Tir.ELet
        ( s, Tir.EApp (var enter_name (Tir.TFn ([ layer_ty ], auth_ty)), [ Tir.AVar l ]),
          Tir.ELet
            ( r, inner,
              Tir.ELet
                ( u, Tir.EApp (var "cap_restore" (Tir.TFn ([ auth_ty ], Tir.TUnit)), [ Tir.AVar s ]),
                  Tir.EAtom (Tir.AVar r) ) ) ) )

(* [f] as a wrapper that enters a frame around a call of [body_name] with
   its own params. *)
let wrapper_of ~layer_ty ~auth_ty ~layer_name ~enter_name ~body_name (f : Tir.fn_def) : Tir.fn_def =
  let call =
    Tir.EApp
      ( var body_name
          (Tir.TFn (List.map (fun (p : Tir.var) -> p.Tir.v_ty) f.Tir.fn_params, f.Tir.fn_ret_ty)),
        List.map (fun p -> Tir.AVar p) f.Tir.fn_params )
  in
  { f with
    Tir.fn_body = frame_around ~layer_ty ~auth_ty ~layer_name ~enter_name ~ret_ty:f.Tir.fn_ret_ty call }

(** [f] as its framed wrapper, its body and its layer fn. *)
let frame_fn ~layer_ty ~auth_ty (f : Tir.fn_def) (n : Lower_state.fn_needs) : Tir.fn_def list =
  let name = f.Tir.fn_name in
  let body_name = name ^ Tir_names.auth_body_suffix in
  let layer_name = name ^ Tir_names.auth_layer_suffix in
  let body_fn =
    { f with Tir.fn_name = body_name; fn_body = retarget ~from:name ~to_:body_name f.Tir.fn_body }
  in
  let layer_fn =
    { Tir.fn_name = layer_name;
      fn_params = [];
      fn_ret_ty = layer_ty;
      fn_body =
        Tir.EApp
          ( var Tir_names.frame_layer_fn_name (Tir.TFn ([ Tir.TString; Tir.TString ], layer_ty)),
            [ Tir.ALit (March_ast.Ast.LitString n.Lower_state.fnn_name);
              Tir.ALit (March_ast.Ast.LitString n.Lower_state.fnn_text) ] );
      fn_kind = Tir.FnNormal }
  in
  let wrapper =
    wrapper_of ~layer_ty ~auth_ty ~layer_name ~enter_name:Tir_names.enter_fn_name ~body_name f in
  Provenance.record body_name ~from:name ~derived:(Provenance.Clone_of (name, "auth frame body"))
    ~pass:"auth_rt" ();
  Provenance.record layer_name ~from:name ~derived:(Provenance.Clone_of (name, "auth frame layer"))
    ~pass:"auth_rt" ();
  [ wrapper; body_fn; layer_fn ]

(* Mutual tail calls between framed fns (ocap A1.3; specs/progress/
   2026-11-26-ocap-scoped-tail-calls.md).  A call of framed [g] goes through
   [g]'s wrapper, whose restore follows the call, so a tail call from the
   body of framed [f] to [g] was not a tail call and f/g/f/g grew the stack
   one wrapper per hop.  In [f$auth], each such call in tail position
   becomes

   {v
     let l = g$auth_layer() in
     case Authority.frame_in_force(l) of
       True -> g$auth(args)        (a tail call: g's frame is in force)
       _    -> g(args)             (the wrapper enters it, as before)
   v}

   so only the first hop into each frame enters it and the recursion then
   loops.  Skipping the entry changes nothing: the authority is the
   intersection of its layers, and [g]'s is already one of them.  A granted
   package's fn is left alone: its wrapper also enters the grant, which
   this test does not look at. *)
let hop_tail_calls ~layer_ty ~(framed_names : (string, unit) Hashtbl.t) (fns : Tir.fn_def list)
  : Tir.fn_def list =
  let granted n = Hashtbl.mem Lower_state.fn_grant_tbl n in
  let counter = ref 0 in
  let hop (g : Tir.var) args =
    let gn = g.Tir.v_name in
    incr counter;
    let l = var (Printf.sprintf "$hop_l%d" !counter) layer_ty in
    let inf = var (Printf.sprintf "$hop_in%d" !counter) Tir.TBool in
    Tir.ELet
      ( l, Tir.EApp (var (gn ^ Tir_names.auth_layer_suffix) (Tir.TFn ([], layer_ty)), []),
        Tir.ELet
          ( inf,
            Tir.EApp (var Tir_names.frame_in_force_name (Tir.TFn ([ layer_ty ], Tir.TBool)),
                      [ Tir.AVar l ]),
            Tir.ECase
              ( Tir.AVar inf,
                [ { Tir.br_tag = Tir_names.synthetic_true_tag; br_vars = [];
                    br_body = Tir.EApp ({ g with Tir.v_name = gn ^ Tir_names.auth_body_suffix }, args) } ],
                Some (Tir.EApp (g, args)) ) ) )
  in
  (* [e] in tail position of [self]'s body: rewrite its tail calls. *)
  let rec tail ~self (e : Tir.expr) : Tir.expr =
    match e with
    | Tir.EApp (g, args)
      when Hashtbl.mem framed_names g.Tir.v_name && g.Tir.v_name <> self
           && not (granted g.Tir.v_name) ->
      hop g args
    | Tir.ELet (v, a, b) when v.Tir.v_name <> self -> Tir.ELet (v, a, tail ~self b)
    | Tir.ESeq (a, b) -> Tir.ESeq (a, tail ~self b)
    | Tir.ELetRec (lfns, b) -> Tir.ELetRec (lfns, tail ~self b)
    | Tir.ECase (sc, brs, d) ->
      Tir.ECase
        (sc, List.map (fun (br : Tir.branch) -> { br with Tir.br_body = tail ~self br.Tir.br_body }) brs,
         Option.map (tail ~self) d)
    | other -> other
  in
  List.map
    (fun (f : Tir.fn_def) ->
       let n = f.Tir.fn_name in
       let suffix = Tir_names.auth_body_suffix in
       let ls = String.length n and lx = String.length suffix in
       if ls > lx && String.sub n (ls - lx) lx = suffix
          && Hashtbl.mem framed_names (String.sub n 0 (ls - lx))
          && not (granted (String.sub n 0 (ls - lx))) then
         let owner = String.sub n 0 (ls - lx) in
         let body' = tail ~self:owner f.Tir.fn_body in
         if body' = f.Tir.fn_body then f else { f with Tir.fn_body = body' }
       else f)
    fns

let frames (m : Tir.tir_module) ~(needs : (string, Lower_state.fn_needs) Hashtbl.t)
  : Tir.tir_module * bool =
  if Hashtbl.length needs = 0 then (m, false)
  else begin
    let entry =
      Tir_names.entry_main_of_names (List.map (fun (f : Tir.fn_def) -> f.Tir.fn_name) m.Tir.tm_fns)
    in
    let candidates =
      List.filter
        (fun (f : Tir.fn_def) ->
           Hashtbl.mem needs f.Tir.fn_name && Some f.Tir.fn_name <> entry)
        m.Tir.tm_fns
    in
    if candidates = [] then (m, false)
    else begin
      let spawners = lazy (reaches_actor_spawn m) in
      let indirect = lazy (reaches_indirect_call m) in
      let framed =
        List.filter
          (fun (f : Tir.fn_def) ->
             let n = Hashtbl.find needs f.Tir.fn_name in
             n.Lower_state.fnn_scoped
             || SSet.mem f.Tir.fn_name (Lazy.force spawners)
             || SSet.mem f.Tir.fn_name (Lazy.force indirect))
          candidates
      in
      if framed = [] then (m, false)
      else begin
        let layer_ty = layer_ty m and auth_ty = auth_ref_ty in
        let framed_names = Hashtbl.create 8 in
        List.iter (fun (f : Tir.fn_def) -> Hashtbl.replace framed_names f.Tir.fn_name ()) framed;
        let fns =
          List.concat_map
            (fun (f : Tir.fn_def) ->
               if Hashtbl.mem framed_names f.Tir.fn_name then
                 frame_fn ~layer_ty ~auth_ty f (Hashtbl.find needs f.Tir.fn_name)
               else [ f ])
            m.Tir.tm_fns
        in
        let fns = hop_tail_calls ~layer_ty ~framed_names fns in
        ({ m with Tir.tm_fns = fns }, true)
      end
    end
  end

(* ── restrict blocks (ocap phase 5, Task 4) ───────────────────────────

   [Lower] lowers every [restrict] to a frame around its body
   ([Lower_expr.lower_restrict]):

   {v
     let l = <encl>$restrict<N>$auth_layer() in   (or a computed layer)
     let s = Authority.enter_fn(l) in
     let r = <body> in cap_restore(s); r
   v}

   For a literal restrict the type checker proves the block's reach by kind,
   as it does for a function's `needs`, so the frame is dropped by phase 4's
   rule applied to the block: kept when the scope text carries a scope, or
   the block calls an actor spawn, a fn that reaches one or a call of a
   function value, or itself calls a function value.  The frame machinery
   the block contains (a nested restrict's layer, [Authority.enter_fn],
   [Authority.restrict_layer]) is not judged: it is the frame, not the
   block's reach. *)

(** The body of a restrict frame, given what follows its layer binding, and
    that frame rebuilt around another body. *)
let restrict_frame_body (rest : Tir.expr) : (Tir.expr * (Tir.expr -> Tir.expr)) option =
  match rest with
  | Tir.ELet
      ( s, (Tir.EApp (ef, [ Tir.AVar _ ]) as enter),
        Tir.ELet (r, body, (Tir.ELet (_, Tir.EApp (cr, [ Tir.AVar s' ]), Tir.EAtom (Tir.AVar r'))
                            as tail)) )
    when ef.Tir.v_name = Tir_names.enter_fn_name && cr.Tir.v_name = "cap_restore"
         && s'.Tir.v_name = s.Tir.v_name && r'.Tir.v_name = r.Tir.v_name ->
    Some (body, fun body' -> Tir.ELet (s, enter, Tir.ELet (r, body', tail)))
  | _ -> None

let restrict_layer_fn_name = "Authority.restrict_layer"

let drop_restricts (m : Tir.tir_module) ~(sites : (string, Lower_state.restrict_site) Hashtbl.t)
  : Tir.tir_module * bool =
  if Hashtbl.length sites = 0 then (m, false)
  else begin
    let candidates =
      Hashtbl.fold
        (fun name (rs : Lower_state.restrict_site) acc ->
           if rs.Lower_state.rs_text <> None && not rs.Lower_state.rs_scoped then SSet.add name acc
           else acc)
        sites SSet.empty
    in
    if SSet.is_empty candidates then (m, true)
    else begin
      let defined = Hashtbl.create 256 in
      List.iter (fun (f : Tir.fn_def) -> Hashtbl.replace defined f.Tir.fn_name ()) m.Tir.tm_fns;
      let blockers =
        lazy (SSet.union (reaches_actor_spawn m) (reaches_indirect_call m)) in
      let machinery n =
        Hashtbl.mem sites n || n = Tir_names.enter_fn_name || n = restrict_layer_fn_name in
      let blocked n =
        (not (machinery n))
        && ((List.mem n spawn_builtins && not (Hashtbl.mem defined n))
            || SSet.mem n (Lazy.force blockers))
      in
      let droppable bound body =
        (not (calls_value_under bound body))
        && (let hit = ref false in
            iter_calls (fun n -> if blocked n then hit := true) body;
            not !hit)
      in
      let dropped = ref SSet.empty and kept = ref SSet.empty in
      let add (v : Tir.var) b = SSet.add v.Tir.v_name b in
      (* [e] with every droppable frame replaced by its body; physically [e]
         when nothing under it changed. *)
      let rec go bound (e : Tir.expr) : Tir.expr =
        match e with
        | Tir.ELet (l, Tir.EApp (lf, []), rest) when SSet.mem lf.Tir.v_name candidates ->
          (match restrict_frame_body rest with
           | Some (body, rebuild) ->
             let body' = go bound body in
             if droppable bound body' then begin
               dropped := SSet.add lf.Tir.v_name !dropped;
               body'
             end else begin
               kept := SSet.add lf.Tir.v_name !kept;
               if body' == body then e else Tir.ELet (l, Tir.EApp (lf, []), rebuild body')
             end
           | None ->
             kept := SSet.add lf.Tir.v_name !kept;
             let rest' = go (add l bound) rest in
             if rest' == rest then e else Tir.ELet (l, Tir.EApp (lf, []), rest'))
        | Tir.ELet (v, a, b) ->
          let a' = go bound a and b' = go (add v bound) b in
          if a' == a && b' == b then e else Tir.ELet (v, a', b')
        | Tir.ESeq (a, b) ->
          let a' = go bound a and b' = go bound b in
          if a' == a && b' == b then e else Tir.ESeq (a', b')
        | Tir.ELetRec (fns, b) ->
          let bound =
            List.fold_left (fun bd (fd : Tir.fn_def) -> SSet.remove fd.Tir.fn_name bd) bound fns in
          let fns' =
            List.map
              (fun (fd : Tir.fn_def) ->
                 let body' = go (List.fold_right add fd.Tir.fn_params bound) fd.Tir.fn_body in
                 if body' == fd.Tir.fn_body then fd else { fd with Tir.fn_body = body' })
              fns
          in
          let b' = go bound b in
          if b' == b && List.for_all2 ( == ) fns fns' then e else Tir.ELetRec (fns', b')
        | Tir.ECase (sc, brs, d) ->
          let brs' =
            List.map
              (fun (br : Tir.branch) ->
                 let body' = go (List.fold_right add br.Tir.br_vars bound) br.Tir.br_body in
                 if body' == br.Tir.br_body then br else { br with Tir.br_body = body' })
              brs
          in
          let d' = Option.map (go bound) d in
          let same_d = match d, d' with Some x, Some y -> x == y | _ -> true in
          if same_d && List.for_all2 ( == ) brs brs' then e else Tir.ECase (sc, brs', d')
        | other -> other
      in
      let fns =
        List.map
          (fun (f : Tir.fn_def) ->
             let body' =
               go (List.fold_right add f.Tir.fn_params SSet.empty) f.Tir.fn_body in
             if body' == f.Tir.fn_body then f else { f with Tir.fn_body = body' })
          m.Tir.tm_fns
      in
      (* A layer fn goes once no call of it is left (a body lowered twice
         keeps one if either copy kept its frame). *)
      let gone = SSet.diff !dropped !kept in
      let any_kept =
        Hashtbl.fold (fun name _ acc -> acc || not (SSet.mem name gone)) sites false in
      if SSet.is_empty gone then (m, any_kept)
      else
        ( { m with
            Tir.tm_fns =
              List.filter (fun (f : Tir.fn_def) -> not (SSet.mem f.Tir.fn_name gone)) fns },
          any_kept )
    end
  end

(* [retarget] for a restrict body: [f]'s own self calls go to [to_], except
   under a frame the body enters itself (a nested restrict or any other
   [Authority.enter_fn]), where the frame on top is not [f]'s restrict and a
   call of [f] would push it again. *)
let rec retarget_unframed ~from ~to_ (e : Tir.expr) : Tir.expr =
  let go = retarget_unframed ~from ~to_ in
  match e with
  | Tir.EApp (f, args) when f.Tir.v_name = from -> Tir.EApp ({ f with Tir.v_name = to_ }, args)
  | Tir.ELet (_, Tir.EApp (ef, _), _) when ef.Tir.v_name = Tir_names.enter_fn_name -> e
  | Tir.ELet (v, a, b) ->
    Tir.ELet (v, go a, if v.Tir.v_name = from then b else go b)
  | Tir.ESeq (a, b) -> Tir.ESeq (go a, go b)
  | Tir.ELetRec (fns, b) ->
    if List.exists (fun (fd : Tir.fn_def) -> fd.Tir.fn_name = from) fns then e
    else Tir.ELetRec (fns, go b)
  | Tir.ECase (sc, brs, d) ->
    Tir.ECase
      (sc,
       List.map
         (fun (br : Tir.branch) ->
            if List.exists (fun (v : Tir.var) -> v.Tir.v_name = from) br.Tir.br_vars then br
            else { br with Tir.br_body = go br.Tir.br_body })
         brs,
       Option.map go d)
  | other -> other

(* A fn whose whole body is a kept frame of a literal restrict, as its
   wrapper and its outlined body (ocap A1.3; specs/progress/
   2026-11-26-ocap-scoped-tail-calls.md).  The frame's restore follows the
   body, so a call in the body's tail position was not a tail call, and a
   self recursion through the block grew the native stack one frame per call
   (SIGBUS between 20,000 and 30,000 deep) although re-entering the block
   pushes nothing.  The body now lives in [f$restrict_body], whose self calls
   go there directly: that skips only a re-entry of the frame already on top
   (decision 8 says it pushes nothing), so the authority is the same and the
   recursion is a loop.  A computed restrict builds a different layer per
   entry and keeps its shape. *)
let outline_restrict_body ~(sites : (string, Lower_state.restrict_site) Hashtbl.t)
    (f : Tir.fn_def) : Tir.fn_def list =
  match f.Tir.fn_body with
  | Tir.ELet (l, (Tir.EApp (lf, []) as layer_call), rest)
    when (match Hashtbl.find_opt sites lf.Tir.v_name with
          | Some rs -> rs.Lower_state.rs_text <> None
          | None -> false) ->
    (match restrict_frame_body rest with
     | None -> [ f ]
     | Some (body, rebuild) ->
       let name = f.Tir.fn_name in
       let body_name = name ^ Tir_names.restrict_body_suffix in
       let body' = retarget_unframed ~from:name ~to_:body_name body in
       if body' = body then [ f ]
       else begin
         let call =
           Tir.EApp
             ( var body_name
                 (Tir.TFn (List.map (fun (p : Tir.var) -> p.Tir.v_ty) f.Tir.fn_params,
                           f.Tir.fn_ret_ty)),
               List.map (fun p -> Tir.AVar p) f.Tir.fn_params )
         in
         Provenance.record body_name ~from:name
           ~derived:(Provenance.Clone_of (name, "restrict frame body")) ~pass:"auth_rt" ();
         [ { f with Tir.fn_body = Tir.ELet (l, layer_call, rebuild call) };
           { f with Tir.fn_name = body_name; fn_body = body' } ]
       end)
  | _ -> [ f ]

let restricts (m : Tir.tir_module) ~(sites : (string, Lower_state.restrict_site) Hashtbl.t)
  : Tir.tir_module * bool =
  let m, kept = drop_restricts m ~sites in
  if not kept then (m, kept)
  else
    let fns = List.concat_map (outline_restrict_body ~sites) m.Tir.tm_fns in
    if List.length fns = List.length m.Tir.tm_fns then (m, kept)
    else ({ m with Tir.tm_fns = fns }, kept)

let authority_check = "Authority.check"

let is_op_builtin (n : string) : bool =
  match March_caps.Cap_ops.classify n with
  | Some (March_caps.Cap_ops.Checked _) -> true
  | _ -> false

(** The fns of [m] whose call can depend on the authority in force: they
    reach, through direct calls, a capability operation ([Authority.check],
    a [Checked] builtin), an actor spawn, or a call of a function value
    (which runs whatever it was handed, and a value made by module-level
    code runs under its caller's authority). *)
let reaches_authority (m : Tir.tir_module) : SSet.t =
  reaching m ~seed:(fun ~defined f ->
      let hit = ref (calls_fn_value f.Tir.fn_params f.Tir.fn_body) in
      if not !hit then
        iter_calls
          (fun n ->
             if n = authority_check || n = Tir_names.foreign_guard_name
             || (not (Hashtbl.mem defined n) && (is_op_builtin n || List.mem n spawn_builtins))
             then hit := true)
          f.Tir.fn_body;
      !hit)

(* An actor's glue fns that the runtime holds and calls itself (its
   dispatch, on_stop and inspect, stored by [A_spawn]; [A_spawn] itself, a
   supervisor child's respawn thunk): never turned into a capturing value
   (see [captures]). *)
let actor_glue_of (m : Tir.tir_module) : SSet.t =
  List.fold_left
    (fun acc td ->
       match td with
       | Tir.TDRecord (n, _) when Tir_names.is_actor_struct_name n ->
         let a = String.sub n 0 (String.length n - String.length Tir_names.actor_struct_suffix) in
         List.fold_left (fun s sfx -> SSet.add (a ^ sfx) s) acc
           [ Tir_names.actor_dispatch_suffix; Tir_names.actor_on_stop_suffix;
             Tir_names.actor_inspect_suffix; Tir_names.actor_spawn_suffix ]
       | _ -> acc)
    SSet.empty m.Tir.tm_types

(* ── Dependency grants (ocap phase 6, Task 4) ─────────────────────────

   Every function defined in a granted package [P] runs under [P]'s grant
   (design §10).  [Lower] tags each such fn in [Lower_state.fn_grant_tbl];
   here each becomes

   {v
     f(args)        = let l = <P>$grant$auth_layer() in
                      let s = Authority.enter_grant(l) in
                      let r = f$grant(args) in
                      cap_restore(s); r
     f$grant(args)  = the original body, its direct calls of P fns whose
                      wrappers are kept (not those in a lambda or local fn
                      it makes) retargeted to their [$grant] bodies
     <P>$grant$auth_layer() = Authority.grant_layer("<P>", "<grant text>")
   v}

   One layer fn per package: every call of it is built once per site
   ([march_cap_layer_once], the JS memo), as a function frame's is.

   Which calls enter the grant (plan decision 6): every call keeps the
   wrapper's name, so it enters the frame (calls from the app, from other
   packages, from stdlib code, including generic code that mono later
   resolves to a P impl, and every value use), except a direct call in the
   body of a P fn whose own wrapper is kept, outside any lambda: the grant
   is certainly in force there.  A dropped caller keeps its callees'
   wrapper names, so it never reaches a framed callee (one that spawns an
   actor, say) without the grant.

   When the frame is dropped (decision 7): a P fn keeps its wrapper unless
   the grant carries no scope, the checker proved the fn's transitive row
   within the grant ([fg_proven]) and the fn is in neither
   [reaches_actor_spawn] nor [reaches_indirect_call].  A dropped fn is left
   exactly as it was.

   Module-level code (decision 9): a P module-let's zero-arg init fn is a P
   fn like any other.  A lambda its initialiser makes captures nothing
   ([captures]); it gets a grant prologue instead, the same frame around its
   own body, so it runs as one of P's named functions would: under its
   caller's authority intersected with the grant. *)

(* [e] with every direct call of a fn in [targets] (a name -> body name
   map) retargeted.  Only [e]'s own code: never inside an [ELetRec] (a
   lambda or local fn, which may run after its maker returns), and not
   under a local binder of the same name. *)
(** The fns of [m] that reach, through direct calls, a call of a function
    value ([reaches_indirect_call]'s seed) or a call of an interface method
    that lowering left unresolved (generic code: mono may resolve it to an
    impl outside the package, e.g. the app's), by mono's own resolution
    rule ([Tir_names.find_iface_impls]: so [to_string(x)], which string
    interpolation lowers to, counts as Show's [show], and a qualified name
    as its unqualified method).  The grant frame's drop rule
    uses it: what such a call runs is not the package's proven code.  (The
    [needs]-clause frames keep [reaches_indirect_call].) *)
let reaches_indirect_or_dispatch (m : Tir.tir_module) : SSet.t =
  let ifaces = Lower_state.get_iface_methods () in
  reaching m ~seed:(fun ~defined f ->
      calls_fn_value f.Tir.fn_params f.Tir.fn_body
      || (let hit = ref false in
          iter_calls
            (fun n ->
               if (not (Hashtbl.mem defined n)) && Tir_names.find_iface_impls ifaces n <> None
               then hit := true)
            f.Tir.fn_body;
          !hit))

let rec retarget_set (targets : (string, string) Hashtbl.t) (e : Tir.expr) : Tir.expr =
  let go = retarget_set targets in
  let shadowed (v : Tir.var) = Hashtbl.mem targets v.Tir.v_name in
  match e with
  | Tir.EApp (f, args) -> (
    match Hashtbl.find_opt targets f.Tir.v_name with
    | Some to_ -> Tir.EApp ({ f with Tir.v_name = to_ }, args)
    | None -> e)
  | Tir.ELet (v, a, b) ->
    (* A local named like a target is not one: the rest keeps its calls. *)
    Tir.ELet (v, go a, if shadowed v then b else go b)
  | Tir.ESeq (a, b) -> Tir.ESeq (go a, go b)
  | Tir.ELetRec (fns, b) ->
    if List.exists (fun (fd : Tir.fn_def) -> Hashtbl.mem targets fd.Tir.fn_name) fns then e
    else Tir.ELetRec (fns, go b)
  | Tir.ECase (sc, brs, d) ->
    Tir.ECase
      ( sc,
        List.map
          (fun (br : Tir.branch) ->
             if List.exists shadowed br.Tir.br_vars then br
             else { br with Tir.br_body = go br.Tir.br_body })
          brs,
        Option.map go d )
  | other -> other

(* ── C code under a grant (ocap p6 final review C1) ──────────────────

   Nothing else refuses an [extern] at run time, and the checker's static
   reach under-approximates interface dispatch, so C reached under a grant
   that does not admit [IO.Foreign] (an ungranted package's impl that a
   granted package reaches through generic code) would run.  When [grants]
   builds any frame, every reference to an extern [e] (a call or a value
   use, in any fn) is retargeted to

   {v
     e$foreign(ps) = let _ = Authority.foreign_guard() in e(ps)
   v}

   [Authority.foreign_guard] panics when a grant layer in force does not
   admit [IO.Foreign]; a [needs] frame, a [restrict] and the launch grant
   never refuse there, so code outside every grant frame runs exactly as
   before.  It reaches the authority ([reaches_authority]), so a function
   value that calls C keeps the authority it was made under ([captures]): an
   app callback a granted package calls still runs C.  Without a frame no
   grant layer can be in force, and nothing is retargeted. *)

(* [e] with every reference to a name in [tbl] (an extern) that is not
   locally bound renamed to its guard wrapper. *)
let rec guard_refs (tbl : (string, string) Hashtbl.t) (bound : SSet.t) (e : Tir.expr) : Tir.expr =
  let ren (v : Tir.var) =
    if SSet.mem v.Tir.v_name bound then v
    else match Hashtbl.find_opt tbl v.Tir.v_name with
      | Some n -> { v with Tir.v_name = n }
      | None -> v
  in
  let a (x : Tir.atom) = match x with Tir.AVar v -> Tir.AVar (ren v) | _ -> x in
  let atoms = List.map a in
  let go = guard_refs tbl bound in
  let add (v : Tir.var) b = SSet.add v.Tir.v_name b in
  match e with
  | Tir.EAtom x -> Tir.EAtom (a x)
  | Tir.EApp (f, args) -> Tir.EApp (ren f, atoms args)
  | Tir.ECallPtr (f, args) -> Tir.ECallPtr (a f, atoms args)
  | Tir.ELet (v, e1, e2) -> Tir.ELet (v, go e1, guard_refs tbl (add v bound) e2)
  | Tir.ELetRec (fns, b) ->
    let bound' =
      List.fold_left (fun bd (fd : Tir.fn_def) -> SSet.add fd.Tir.fn_name bd) bound fns in
    Tir.ELetRec
      ( List.map
          (fun (fd : Tir.fn_def) ->
             { fd with
               Tir.fn_body =
                 guard_refs tbl (List.fold_right add fd.Tir.fn_params bound') fd.Tir.fn_body })
          fns,
        guard_refs tbl bound' b )
  | Tir.ECase (sc, brs, d) ->
    Tir.ECase
      ( a sc,
        List.map
          (fun (br : Tir.branch) ->
             { br with Tir.br_body = guard_refs tbl (List.fold_right add br.Tir.br_vars bound) br.Tir.br_body })
          brs,
        Option.map go d )
  | Tir.ETuple xs -> Tir.ETuple (atoms xs)
  | Tir.ERecord fs -> Tir.ERecord (List.map (fun (k, x) -> (k, a x)) fs)
  | Tir.EField (x, f) -> Tir.EField (a x, f)
  | Tir.EUpdate (x, fs) -> Tir.EUpdate (a x, List.map (fun (k, y) -> (k, a y)) fs)
  | Tir.EAlloc (t, xs) -> Tir.EAlloc (t, atoms xs)
  | Tir.EStackAlloc (t, xs) -> Tir.EStackAlloc (t, atoms xs)
  | Tir.EFree x -> Tir.EFree (a x)
  | Tir.EIncRC x -> Tir.EIncRC (a x)
  | Tir.EDecRC x -> Tir.EDecRC (a x)
  | Tir.EAtomicIncRC x -> Tir.EAtomicIncRC (a x)
  | Tir.EAtomicDecRC x -> Tir.EAtomicDecRC (a x)
  | Tir.EReuse (x, t, xs) -> Tir.EReuse (a x, t, atoms xs)
  | Tir.ESeq (e1, e2) -> Tir.ESeq (go e1, go e2)
  | Tir.EAllocHole (o, t, xs, i) -> Tir.EAllocHole (Option.map a o, t, atoms xs, i)
  | Tir.ESetField (x, i, y) -> Tir.ESetField (a x, i, a y)

(* [fns] with every extern reference retargeted to its guard wrapper, plus
   the wrappers of the externs some fn now references.  [fns] itself when no
   fn references an extern. *)
let guard_externs (externs : Tir.extern_decl list) (fns : Tir.fn_def list) : Tir.fn_def list =
  if externs = [] then fns
  else begin
    let tbl : (string, string) Hashtbl.t = Hashtbl.create 8 in
    List.iter
      (fun (ed : Tir.extern_decl) ->
         Hashtbl.replace tbl ed.Tir.ed_march_name
           (ed.Tir.ed_march_name ^ Tir_names.foreign_guard_suffix))
      externs;
    (* The wrappers referenced, by name. *)
    let used : (string, unit) Hashtbl.t = Hashtbl.create 8 in
    let fns' =
      List.map
        (fun (f : Tir.fn_def) ->
           let bound =
             List.fold_left (fun b (p : Tir.var) -> SSet.add p.Tir.v_name b) SSet.empty
               f.Tir.fn_params in
           let body = guard_refs tbl bound f.Tir.fn_body in
           (* Which wrappers [body] names: a second walk only when the body
              mentions a wrapper at all (rare: only fns that use C). *)
           let hit = ref false in
           let rec scan (e : Tir.expr) =
             let atom (x : Tir.atom) = match x with
               | Tir.AVar v -> note v.Tir.v_name
               | _ -> () in
             match e with
             | Tir.EAtom x | Tir.EField (x, _) | Tir.EFree x | Tir.EIncRC x | Tir.EDecRC x
             | Tir.EAtomicIncRC x | Tir.EAtomicDecRC x -> atom x
             | Tir.EApp (fv, xs) -> note fv.Tir.v_name; List.iter atom xs
             | Tir.ECallPtr (fv, xs) -> atom fv; List.iter atom xs
             | Tir.ELet (_, e1, e2) | Tir.ESeq (e1, e2) -> scan e1; scan e2
             | Tir.ELetRec (fds, b) ->
               List.iter (fun (fd : Tir.fn_def) -> scan fd.Tir.fn_body) fds; scan b
             | Tir.ECase (sc, brs, d) ->
               atom sc; List.iter (fun (br : Tir.branch) -> scan br.Tir.br_body) brs;
               Option.iter scan d
             | Tir.ETuple xs | Tir.EAlloc (_, xs) | Tir.EStackAlloc (_, xs) -> List.iter atom xs
             | Tir.ERecord fs -> List.iter (fun (_, x) -> atom x) fs
             | Tir.EUpdate (x, fs) -> atom x; List.iter (fun (_, y) -> atom y) fs
             | Tir.EReuse (x, _, xs) -> atom x; List.iter atom xs
             | Tir.EAllocHole (o, _, xs, _) -> Option.iter atom o; List.iter atom xs
             | Tir.ESetField (x, _, y) -> atom x; atom y
           and note n =
             if String.ends_with ~suffix:Tir_names.foreign_guard_suffix n then begin
               let e = String.sub n 0 (String.length n - String.length Tir_names.foreign_guard_suffix) in
               if Hashtbl.find_opt tbl e = Some n then begin
                 hit := true;
                 Hashtbl.replace used n ()
               end
             end
           in
           scan body;
           if !hit then { f with Tir.fn_body = body } else f)
        fns
    in
    if Hashtbl.length used = 0 then fns
    else begin
      let wrappers =
        List.filter_map
          (fun (ed : Tir.extern_decl) ->
             let name = ed.Tir.ed_march_name ^ Tir_names.foreign_guard_suffix in
             if not (Hashtbl.mem used name) then None
             else begin
               let params =
                 List.mapi (fun i t -> var (Printf.sprintf "$foreign_p%d" i) t) ed.Tir.ed_params in
               Provenance.record name ~from:ed.Tir.ed_march_name
                 ~derived:(Provenance.Clone_of (ed.Tir.ed_march_name, "extern guard"))
                 ~pass:"auth_rt" ();
               Some
                 { Tir.fn_name = name;
                   fn_params = params;
                   fn_ret_ty = ed.Tir.ed_ret;
                   fn_body =
                     Tir.ELet
                       ( var "$foreign_unit" Tir.TUnit,
                         Tir.EApp (var Tir_names.foreign_guard_name (Tir.TFn ([], Tir.TUnit)), []),
                         Tir.EApp
                           ( var ed.Tir.ed_march_name (Tir.TFn (ed.Tir.ed_params, ed.Tir.ed_ret)),
                             List.map (fun p -> Tir.AVar p) params ) );
                   fn_kind = Tir.FnNormal }
             end)
          externs
      in
      fns' @ wrappers
    end
  end

let grants (m : Tir.tir_module) ~(tbl : (string, Lower_state.fn_grant) Hashtbl.t)
  : Tir.tir_module * bool =
  if Hashtbl.length tbl = 0 then (m, false)
  else begin
    let entry =
      Tir_names.entry_main_of_names (List.map (fun (f : Tir.fn_def) -> f.Tir.fn_name) m.Tir.tm_fns)
    in
    let grant_of (f : Tir.fn_def) =
      if Some f.Tir.fn_name = entry then None else Hashtbl.find_opt tbl f.Tir.fn_name
    in
    (* A named fn value in a granted package's module-level code (say
       [let reader = File.read]) is a function value created there, so it
       must behave as one of the package's functions: it becomes an eta
       lambda made by that code ([fn (ps) -> f(ps)]), registered as a
       module-initialiser lambda, and so gets the grant prologue below.
       Without this it would hand the caller the bare fn, run under the
       caller's full authority ([captures] leaves module-level values
       alone).  Only values whose call can depend on the authority, by
       [captures]'s own test.  [m] itself (physically) when there is none. *)
    let m =
      if not (List.exists
                (fun f -> grant_of f <> None && Lower_state.is_module_init_fn f.Tir.fn_name)
                m.Tir.tm_fns)
      then m
      else begin
        let defined : (string, Tir.fn_def) Hashtbl.t = Hashtbl.create 256 in
        List.iter (fun (f : Tir.fn_def) -> Hashtbl.replace defined f.Tir.fn_name f) m.Tir.tm_fns;
        let reach = lazy (reaches_authority m) in
        let add (v : Tir.var) b = SSet.add v.Tir.v_name b in
        let actor_glue = actor_glue_of m in
        (* [captures]'s test for a value that must not run under its
           caller's authority (kept in step with its [named_value]). *)
        let named_value bound (v : Tir.var) : (Tir.ty list * Tir.ty) option =
          if SSet.mem v.Tir.v_name bound || SSet.mem v.Tir.v_name actor_glue then None
          else
            let of_ty = match v.Tir.v_ty with
              | Tir.TFn ((_ :: _ as ps), r) -> Some (ps, r)
              | _ -> None
            in
            match Hashtbl.find_opt defined v.Tir.v_name with
            | Some fd ->
              if fd.Tir.fn_params = []
              || not (v.Tir.v_name = authority_check || SSet.mem v.Tir.v_name (Lazy.force reach))
              then None
              else (match of_ty with
                  | Some (ps, r) when List.length ps = List.length fd.Tir.fn_params -> Some (ps, r)
                  | _ -> Some (List.map (fun (p : Tir.var) -> p.Tir.v_ty) fd.Tir.fn_params,
                               fd.Tir.fn_ret_ty))
            | None -> if is_op_builtin v.Tir.v_name then of_ty else None
        in
        let rewrite (f : Tir.fn_def) : Tir.fn_def =
          let host = f.Tir.fn_name in
          let changed = ref false in
          let eta (v : Tir.var) (ps, r) : Tir.var * Tir.expr =
            let name = Lower_state.fresh_nested_name ~host "grantlam" in
            Hashtbl.replace Lower_state._module_init_lambdas name ();
            Provenance.record name ~from:host
              ~derived:(Provenance.Clone_of (v.Tir.v_name, "grant eta")) ~pass:"auth_rt" ();
            let params = List.mapi (fun i t -> var (Printf.sprintf "$grant_p%d" i) t) ps in
            let fty = Tir.TFn (ps, r) in
            let fd =
              { Tir.fn_name = name;
                fn_params = params;
                fn_ret_ty = r;
                fn_body = Tir.EApp ({ v with Tir.v_ty = fty }, List.map (fun p -> Tir.AVar p) params);
                fn_kind = Tir.FnLambda }
            in
            (var (name ^ "$v") fty, Tir.ELetRec ([ fd ], Tir.EAtom (Tir.AVar (var name fty))))
          in
          let leaf bound (e : Tir.expr) : Tir.expr =
            let lets = ref [] in
            let atom (a : Tir.atom) =
              match a with
              | Tir.AVar v -> (
                match named_value bound v with
                | None -> a
                | Some sg ->
                  let x, rhs = eta v sg in
                  lets := (x, rhs) :: !lets;
                  Tir.AVar x)
              | _ -> a
            in
            let atoms = List.map atom in
            let e' =
              match e with
              | Tir.EAtom a -> Tir.EAtom (atom a)
              | Tir.EApp (fv, args) -> Tir.EApp (fv, atoms args)
              | Tir.ECallPtr (fv, args) -> Tir.ECallPtr (fv, atoms args)
              | Tir.ETuple args -> Tir.ETuple (atoms args)
              | Tir.ERecord fs -> Tir.ERecord (List.map (fun (k, a) -> (k, atom a)) fs)
              | Tir.EUpdate (r, fs) -> Tir.EUpdate (r, List.map (fun (k, a) -> (k, atom a)) fs)
              | Tir.EAlloc (t, args) -> Tir.EAlloc (t, atoms args)
              | Tir.EStackAlloc (t, args) -> Tir.EStackAlloc (t, atoms args)
              | other -> other
            in
            if !lets = [] then e
            else begin
              changed := true;
              List.fold_left (fun acc (x, rhs) -> Tir.ELet (x, rhs, acc)) e' !lets
            end
          in
          (* Module-level code only: a lambda's body runs later, inside its
             prologue, where [captures] treats it as ordinary code. *)
          let rec go bound (e : Tir.expr) : Tir.expr =
            match e with
            | Tir.ELet (v, a, b) -> Tir.ELet (v, go bound a, go (add v bound) b)
            | Tir.ESeq (a, b) -> Tir.ESeq (go bound a, go bound b)
            | Tir.ELetRec (fns, b) ->
              Tir.ELetRec
                (fns, go (List.fold_left (fun bd (fd : Tir.fn_def) -> add (var fd.Tir.fn_name Tir.TUnit) bd)
                           bound fns) b)
            | Tir.ECase (sc, brs, d) ->
              Tir.ECase
                ( sc,
                  List.map
                    (fun (br : Tir.branch) ->
                       { br with Tir.br_body = go (List.fold_right add br.Tir.br_vars bound) br.Tir.br_body })
                    brs,
                  Option.map (go bound) d )
            | other -> leaf bound other
          in
          let body = go (List.fold_right add f.Tir.fn_params SSet.empty) f.Tir.fn_body in
          if !changed then { f with Tir.fn_body = body } else f
        in
        let fns =
          List.map
            (fun (f : Tir.fn_def) ->
               if grant_of f <> None && Lower_state.is_module_init_fn f.Tir.fn_name then rewrite f
               else f)
            m.Tir.tm_fns
        in
        if List.for_all2 ( == ) fns m.Tir.tm_fns then m else { m with Tir.tm_fns = fns }
      end
    in
    let tagged = List.filter (fun f -> grant_of f <> None) m.Tir.tm_fns in
    (* Whether [e] makes a module-initialiser lambda (anywhere in it). *)
    let rec makes_init_lambda (e : Tir.expr) =
      match e with
      | Tir.ELetRec (fns, b) ->
        List.exists
          (fun (fd : Tir.fn_def) ->
             Lower_state.is_module_init_lambda fd.Tir.fn_name || makes_init_lambda fd.Tir.fn_body)
          fns
        || makes_init_lambda b
      | Tir.ELet (_, a, b) | Tir.ESeq (a, b) -> makes_init_lambda a || makes_init_lambda b
      | Tir.ECase (_, brs, d) ->
        List.exists (fun (br : Tir.branch) -> makes_init_lambda br.Tir.br_body) brs
        || (match d with Some d -> makes_init_lambda d | None -> false)
      | _ -> false
    in
    let spawners = lazy (reaches_actor_spawn m) in
    let indirect = lazy (reaches_indirect_or_dispatch m) in
    let keeps (f : Tir.fn_def) (g : Lower_state.fn_grant) =
      g.Lower_state.fg_scoped
      || (not g.Lower_state.fg_proven)
      || SSet.mem f.Tir.fn_name (Lazy.force spawners)
      || SSet.mem f.Tir.fn_name (Lazy.force indirect)
    in
    let wrapped : (string, Lower_state.fn_grant) Hashtbl.t = Hashtbl.create 16 in
    let prologued : (string, unit) Hashtbl.t = Hashtbl.create 4 in
    List.iter
      (fun (f : Tir.fn_def) ->
         let g = Option.get (grant_of f) in
         if keeps f g then Hashtbl.replace wrapped f.Tir.fn_name g;
         if makes_init_lambda f.Tir.fn_body then Hashtbl.replace prologued f.Tir.fn_name ())
      tagged;
    (* For the tests: each tagged fn, its proof bit and whether it is
       wrapped (the proof bit is read across stages, by the checker's key). *)
    if Sys.getenv_opt "MARCH_DUMP_GRANT_FRAMES" = Some "1" then
      List.iter
        (fun (f : Tir.fn_def) ->
           let g = Option.get (grant_of f) in
           Printf.eprintf "grant-frame %s pkg=%s proven=%b wrapped=%b\n%!" f.Tir.fn_name
             g.Lower_state.fg_pkg g.Lower_state.fg_proven (Hashtbl.mem wrapped f.Tir.fn_name))
        tagged;
    if Hashtbl.length wrapped = 0 && Hashtbl.length prologued = 0 then (m, false)
    else begin
      let layer_ty = layer_ty m and auth_ty = auth_ref_ty in
      (* One layer fn per package that has a frame, in first-use order. *)
      let layers : (string * Lower_state.fn_grant) list ref = ref [] in
      let layer_of (g : Lower_state.fn_grant) =
        let name = Tir_names.grant_layer_fn_of g.Lower_state.fg_pkg in
        if not (List.mem_assoc name !layers) then layers := (name, g) :: !layers;
        name
      in
      let counter = ref 0 in
      (* [e] with every module-initialiser lambda's body inside the grant
         prologue of [g]. *)
      let rec prologue (g : Lower_state.fn_grant) (e : Tir.expr) : Tir.expr =
        let go = prologue g in
        match e with
        | Tir.ELetRec (fns, b) ->
          let fns' =
            List.map
              (fun (fd : Tir.fn_def) ->
                 let body = go fd.Tir.fn_body in
                 if Lower_state.is_module_init_lambda fd.Tir.fn_name then begin
                   incr counter;
                   let k = !counter in
                   let nm s = Printf.sprintf "$grant_%s%d" s k in
                   { fd with
                     Tir.fn_body =
                       frame_around ~layer_ty ~auth_ty ~layer_name:(layer_of g)
                         ~enter_name:Tir_names.enter_grant_name ~ret_ty:fd.Tir.fn_ret_ty
                         ~names:(nm "l", nm "saved", nm "result", nm "unit") body }
                 end
                 else if body == fd.Tir.fn_body then fd
                 else { fd with Tir.fn_body = body })
              fns
          in
          Tir.ELetRec (fns', go b)
        | Tir.ELet (v, a, b) -> Tir.ELet (v, go a, go b)
        | Tir.ESeq (a, b) -> Tir.ESeq (go a, go b)
        | Tir.ECase (sc, brs, d) ->
          Tir.ECase
            ( sc,
              List.map (fun (br : Tir.branch) -> { br with Tir.br_body = go br.Tir.br_body }) brs,
              Option.map go d )
        | other -> other
      in
      (* The calls a kept P fn's body retargets: every kept fn of its own
         package. *)
      let targets_of : (string, (string, string) Hashtbl.t) Hashtbl.t = Hashtbl.create 4 in
      let targets pkg =
        match Hashtbl.find_opt targets_of pkg with
        | Some t -> t
        | None ->
          let t = Hashtbl.create 16 in
          Hashtbl.iter
            (fun n (g : Lower_state.fn_grant) ->
               if g.Lower_state.fg_pkg = pkg then
                 Hashtbl.replace t n (n ^ Tir_names.grant_body_suffix))
            wrapped;
          Hashtbl.replace targets_of pkg t;
          t
      in
      let fns =
        List.concat_map
          (fun (f : Tir.fn_def) ->
             let name = f.Tir.fn_name in
             match grant_of f with
             | None -> [ f ]
             | Some g ->
               let body =
                 if Hashtbl.mem prologued name then prologue g f.Tir.fn_body else f.Tir.fn_body in
               if Hashtbl.mem wrapped name then begin
                 let body_name = name ^ Tir_names.grant_body_suffix in
                 let body_fn =
                   { f with
                     Tir.fn_name = body_name;
                     fn_body = retarget_set (targets g.Lower_state.fg_pkg) body }
                 in
                 if Lower_state.is_module_init_fn name then
                   Lower_state.note_module_init_body body_name;
                 (* An actor handler's body keeps its declaring module. *)
                 Option.iter (fun owner -> Handler_owner.register ~fn_name:body_name ~owner)
                   (Handler_owner.owner_of name);
                 Provenance.record body_name ~from:name
                   ~derived:(Provenance.Clone_of (name, "grant frame body")) ~pass:"auth_rt" ();
                 [ wrapper_of ~layer_ty ~auth_ty ~layer_name:(layer_of g)
                     ~enter_name:Tir_names.enter_grant_name ~body_name f;
                   body_fn ]
               end
               else if body == f.Tir.fn_body then [ f ]
               else [ { f with Tir.fn_body = body } ])
          m.Tir.tm_fns
      in
      let layer_fns =
        List.rev_map
          (fun (name, (g : Lower_state.fn_grant)) ->
             { Tir.fn_name = name;
               fn_params = [];
               fn_ret_ty = layer_ty;
               fn_body =
                 Tir.EApp
                   ( var Tir_names.grant_layer_builtin_name
                       (Tir.TFn ([ Tir.TString; Tir.TString ], layer_ty)),
                     [ Tir.ALit (March_ast.Ast.LitString g.Lower_state.fg_pkg);
                       Tir.ALit (March_ast.Ast.LitString g.Lower_state.fg_text) ] );
               fn_kind = Tir.FnNormal })
          !layers
      in
      ({ m with Tir.tm_fns = guard_externs m.Tir.tm_externs fns @ layer_fns }, true)
    end
  end

(* ── Capture (Task 5) ─────────────────────────────────────────────────

   A function value runs under the authority it was made under, not the
   one in force where it is called (design §5).  [captures] makes that so
   for the values whose authority can matter: see the .mli. *)

let captures (m : Tir.tir_module) ~(has_frames : bool) ~(repl : bool) : Tir.tir_module =
  if not has_frames && not repl then m
  else begin
    let defined : (string, Tir.fn_def) Hashtbl.t = Hashtbl.create 256 in
    List.iter (fun (f : Tir.fn_def) -> Hashtbl.replace defined f.Tir.fn_name f) m.Tir.tm_fns;
    let reach = reaches_authority m in
    (* An actor's glue fns that the runtime holds and calls itself (its
       dispatch, on_stop and inspect, stored by [A_spawn]; [A_spawn] itself,
       a supervisor child's respawn thunk).  They are never wrapped: they run
       on the actor's own green thread, whose slot already holds the
       authority the actor was spawned under (Task 6), and the runtime calls
       them through borrowing trampolines ([Llvm_emit.clo_wrap_borrowed])
       without handing over a reference, so a capturing eta closure in their
       place was released once per message and underflowed. *)
    let actor_glue = actor_glue_of m in
    let counter = ref 0 in
    let fresh prefix ty =
      incr counter;
      var (Printf.sprintf "$auth_%s%d" prefix !counter) ty
    in
    let add (v : Tir.var) b = SSet.add v.Tir.v_name b in
    (* A call of [n] (not a local binding) depends on the authority. *)
    let call_depends n =
      if Hashtbl.mem defined n then SSet.mem n reach || n = authority_check
      else n = authority_check || is_op_builtin n || List.mem n spawn_builtins
    in
    (* Whether the lambda [fd], made where [bound] are the local bindings,
       must capture: its body reaches an authority-dependent call or calls a
       function value (a parameter, or a value it closes over). *)
    let lambda_depends bound (fd : Tir.fn_def) =
      let inner =
        List.fold_right add fd.Tir.fn_params (SSet.remove fd.Tir.fn_name bound) in
      calls_value_under inner fd.Tir.fn_body
      || (let hit = ref false in
          iter_calls
            (fun n -> if (not (SSet.mem n inner)) && call_depends n then hit := true)
            fd.Tir.fn_body;
          !hit)
    in
    (* Where the captured authority and helper closures are bound.  The
       capture [$c = cap_save()] is bound once at the top of the body (fn,
       lambda or local fn) that makes the captured value: the authority is
       the same anywhere in one body (a frame is entered only in a
       wrapper's own code or by a [restrict] block, whose rest is treated as
       a body of its own, and a captured lambda's own body is a body of
       its own), and binding it there keeps it in scope for as long as the
       value can be called.  Binding it inside the value's own [let]
       right-hand side would end its scope at the allocation, and a closure
       that is only called (not escaping) BORROWS its captures
       ([Borrow.closure_escapes]), so the reference would never be
       released.  A helper closure ([$bv] below) refers to the body's
       locals, so it is bound in front of the [let] whose right-hand side
       makes the value instead: [go] returns such pending lets alongside
       the expression, and they float up through right-hand sides only. *)
    let get_cap (ctx : Tir.var option ref) : Tir.var =
      match !ctx with
      | Some c -> c
      | None -> let c = fresh "cap" auth_ref_ty in ctx := Some c; c
    in
    let flush (e, pending) =
      List.fold_right (fun (x, rhs) acc -> Tir.ELet (x, rhs, acc)) pending e
    in
    (* [fd] made to run under the captured authority [$c] (from [ctx]),
       with the pending lets it needs.  [lv] is the lambda's own atom.

       A self-recursive lambda (a local `fn go(..) do .. go(..) end`) would
       lose its self tail call to the restore, so a loop would grow the
       stack.  When its own name occurs only as the callee of direct calls
       in its own code (no nested lambda or value use), its body moves to an
       uncaptured lambda [$b] whose self calls target [$b] itself, and [fd]
       only enters [$c] around one call of [$b]:

       {v
         let $bv = letrec [$b(ps) = body[go := $b]] in $b in
         letrec [go(ps') = let s = cap_enter($c) in let r = $bv(ps') in
                           cap_restore(s); r] in go
       v} *)
    let capture_lambda ctx ~host (fd : Tir.fn_def) (lv : Tir.var)
      : Tir.expr * (Tir.var * Tir.expr) list =
      let c = get_cap ctx in
      let sv = fresh "saved" auth_ref_ty in
      let r = fresh "result" fd.Tir.fn_ret_ty in
      let u = fresh "unit" Tir.TUnit in
      let enter_around (inner : Tir.expr) =
        Tir.ELet
          ( sv, Tir.EApp (var "cap_enter" (Tir.TFn ([ auth_ref_ty ], auth_ref_ty)), [ Tir.AVar c ]),
            Tir.ELet
              ( r, inner,
                Tir.ELet
                  ( u, Tir.EApp (var "cap_restore" (Tir.TFn ([ auth_ref_ty ], Tir.TUnit)), [ Tir.AVar sv ]),
                    Tir.EAtom (Tir.AVar r) ) ) )
      in
      let name = fd.Tir.fn_name in
      let self_calls = ref false in
      iter_calls (fun n -> if n = name then self_calls := true) fd.Tir.fn_body;
      let split =
        if not !self_calls then None
        else begin
          let bname = Lower_state.fresh_nested_name ~host "authbody" in
          let body' = retarget ~from:name ~to_:bname fd.Tir.fn_body in
          if Dce.StringSet.mem name (Dce.free_vars body') then None else Some (bname, body')
        end
      in
      match split with
      | None ->
        (Tir.ELetRec ([ { fd with Tir.fn_body = enter_around fd.Tir.fn_body } ],
                      Tir.EAtom (Tir.AVar lv)), [])
      | Some (bname, body') ->
        Provenance.record bname ~from:name
          ~derived:(Provenance.Clone_of (name, "auth capture body")) ~pass:"auth_rt" ();
        let fty = Tir.TFn (List.map (fun (p : Tir.var) -> p.Tir.v_ty) fd.Tir.fn_params,
                           fd.Tir.fn_ret_ty) in
        let bfd = { fd with Tir.fn_name = bname; fn_body = body' } in
        let bv = fresh "body" fty in
        let ps = List.map (fun (p : Tir.var) -> fresh "p" p.Tir.v_ty) fd.Tir.fn_params in
        let wrapper =
          { fd with
            Tir.fn_params = ps;
            fn_body = enter_around (Tir.EApp (bv, List.map (fun p -> Tir.AVar p) ps)) }
        in
        (Tir.ELetRec ([ wrapper ], Tir.EAtom (Tir.AVar lv)),
         [ (bv, Tir.ELetRec ([ bfd ], Tir.EAtom (Tir.AVar (var bname fty)))) ])
    in
    (* A named fn used as a value: its parameter and result types, when it
       is one that must capture (a fn of [m] that depends on the authority,
       or a capability builtin). *)
    let named_value bound (v : Tir.var) : (Tir.ty list * Tir.ty) option =
      if SSet.mem v.Tir.v_name bound || SSet.mem v.Tir.v_name actor_glue then None
      else
        let of_ty = match v.Tir.v_ty with
          | Tir.TFn ((_ :: _ as ps), r) -> Some (ps, r)
          | _ -> None
        in
        match Hashtbl.find_opt defined v.Tir.v_name with
        | Some fd ->
          if fd.Tir.fn_params = [] || not (call_depends v.Tir.v_name) then None
          else (match of_ty with
              | Some (ps, r) when List.length ps = List.length fd.Tir.fn_params -> Some (ps, r)
              | _ -> Some (List.map (fun (p : Tir.var) -> p.Tir.v_ty) fd.Tir.fn_params,
                           fd.Tir.fn_ret_ty))
        | None -> if is_op_builtin v.Tir.v_name then of_ty else None
    in
    (* The eta lambda [fn (ps) -> v(ps)], captured. *)
    let eta ctx ~host (v : Tir.var) (ps, r) : Tir.expr =
      let name = Lower_state.fresh_nested_name ~host "authlam" in
      Provenance.record name ~from:host
        ~derived:(Provenance.Clone_of (v.Tir.v_name, "auth capture eta")) ~pass:"auth_rt" ();
      let params = List.map (fun t -> fresh "p" t) ps in
      let fty = Tir.TFn (ps, r) in
      let fd =
        { Tir.fn_name = name;
          fn_params = params;
          fn_ret_ty = r;
          fn_body = Tir.EApp ({ v with Tir.v_ty = fty }, List.map (fun p -> Tir.AVar p) params);
          fn_kind = Tir.FnLambda }
      in
      (* No self call, so no pending lets. *)
      fst (capture_lambda ctx ~host fd (var name fty))
    in
    (* [e] (a leaf: no binders) with every named fn value among [atoms]
       replaced by a captured eta lambda bound just before it. *)
    let wrap_values ctx ~init ~host bound (e : Tir.expr) : Tir.expr =
      if init then e
      else begin
        let subst : (string * Tir.var) list ref = ref [] in
        let lets = ref [] in
        let atom (a : Tir.atom) : Tir.atom =
          match a with
          | Tir.AVar v ->
            (match List.assoc_opt v.Tir.v_name !subst with
             | Some x -> Tir.AVar x
             | None ->
               match named_value bound v with
               | None -> a
               | Some (ps, r) ->
                 let x = fresh "fnval" (Tir.TFn (ps, r)) in
                 subst := (v.Tir.v_name, x) :: !subst;
                 lets := (x, eta ctx ~host v (ps, r)) :: !lets;
                 Tir.AVar x)
          | _ -> a
        in
        let atoms = List.map atom in
        let e' =
          match e with
          | Tir.EAtom a -> Tir.EAtom (atom a)
          | Tir.EApp (f, args) -> Tir.EApp (f, atoms args)
          | Tir.ECallPtr (f, args) -> Tir.ECallPtr (f, atoms args)
          | Tir.ETuple args -> Tir.ETuple (atoms args)
          | Tir.ERecord fs -> Tir.ERecord (List.map (fun (k, a) -> (k, atom a)) fs)
          | Tir.EUpdate (r, fs) -> Tir.EUpdate (r, List.map (fun (k, a) -> (k, atom a)) fs)
          | Tir.EAlloc (t, args) -> Tir.EAlloc (t, atoms args)
          | Tir.EStackAlloc (t, args) -> Tir.EStackAlloc (t, atoms args)
          | other -> other
        in
        if !lets = [] then e
        else List.fold_left (fun acc (x, rhs) -> Tir.ELet (x, rhs, acc)) e' !lets
      end
    in
    (* [body] of a fn, lambda or local fn: rewritten, with its capture bound
       at its top when it makes a captured value. *)
    let rec process_body ~init ~host bound (body : Tir.expr) : Tir.expr =
      let ctx = ref None in
      let body' = flush (go ctx ~init ~host bound body) in
      match !ctx with
      | None -> body'
      | Some c -> Tir.ELet (c, Tir.EApp (var "cap_save" (Tir.TFn ([], auth_ref_ty)), []), body')
    and go ctx ~init ~host bound (e : Tir.expr) : Tir.expr * (Tir.var * Tir.expr) list =
      let local e = flush (go ctx ~init ~host bound e) in
      match e with
      | Tir.ELetRec ([ fd ], Tir.EAtom (Tir.AVar lv))
        when fd.Tir.fn_kind = Tir.FnLambda && lv.Tir.v_name = fd.Tir.fn_name ->
        let inner = List.fold_right add fd.Tir.fn_params (SSet.remove fd.Tir.fn_name bound) in
        let body' = process_body ~init:false ~host inner fd.Tir.fn_body in
        let fd' = if body' == fd.Tir.fn_body then fd else { fd with Tir.fn_body = body' } in
        if (not init) && (not (Lower_state.is_module_init_lambda fd.Tir.fn_name))
           && lambda_depends bound fd
        then capture_lambda ctx ~host fd' lv
        else if fd' == fd then (e, [])
        else (Tir.ELetRec ([ fd' ], Tir.EAtom (Tir.AVar lv)), [])
      | Tir.ELetRec (fns, b) ->
        let bound' =
          List.fold_left (fun bd (fd : Tir.fn_def) -> SSet.remove fd.Tir.fn_name bd) bound fns in
        let fns' =
          List.map
            (fun (fd : Tir.fn_def) ->
               let body' =
                 process_body ~init:false ~host (List.fold_right add fd.Tir.fn_params bound')
                   fd.Tir.fn_body in
               if body' == fd.Tir.fn_body then fd else { fd with Tir.fn_body = body' })
            fns
        in
        let b' = flush (go ctx ~init ~host bound' b) in
        if b' == b && List.for_all2 ( == ) fns fns' then (e, []) else (Tir.ELetRec (fns', b'), [])
      | Tir.ELet (sv, (Tir.EApp (ef, [ Tir.AVar _ ]) as a), b)
        when ef.Tir.v_name = Tir_names.enter_fn_name
             || ef.Tir.v_name = Tir_names.enter_grant_name ->
        (* A frame entered mid-body (a [restrict] block, [restricts]): a value
           made after it captures the authority it enters, so it is saved
           again right after the entry. *)
        let b' = process_body ~init ~host (add sv bound) b in
        if b' == b then (e, []) else (Tir.ELet (sv, a, b'), [])
      | Tir.ELet (v, a, b) ->
        (* The right-hand side's pending lets float in front of this let. *)
        let a', pending = go ctx ~init:(init || Lower_state.is_module_init_binder v) ~host bound a in
        let b' = flush (go ctx ~init ~host (add v bound) b) in
        if a' == a && b' == b && pending = [] then (e, [])
        else (Tir.ELet (v, a', b'), pending)
      | Tir.ESeq (a, b) ->
        let a' = local a and b' = local b in
        if a' == a && b' == b then (e, []) else (Tir.ESeq (a', b'), [])
      | Tir.ECase (sc, brs, d) ->
        let brs' =
          List.map
            (fun (br : Tir.branch) ->
               let body' =
                 flush (go ctx ~init ~host (List.fold_right add br.Tir.br_vars bound) br.Tir.br_body) in
               if body' == br.Tir.br_body then br else { br with Tir.br_body = body' })
            brs
        in
        let d' = Option.map local d in
        let same_d = match d, d' with Some x, Some y -> x == y | _ -> true in
        if same_d && List.for_all2 ( == ) brs brs' then (e, []) else (Tir.ECase (sc, brs', d'), [])
      | leaf -> (wrap_values ctx ~init ~host bound leaf, [])
    in
    let fns =
      List.map
        (fun (f : Tir.fn_def) ->
           let init = Lower_state.is_module_init_fn f.Tir.fn_name in
           let bound = List.fold_right add f.Tir.fn_params SSet.empty in
           let body' = process_body ~init ~host:f.Tir.fn_name bound f.Tir.fn_body in
           if body' == f.Tir.fn_body then f else { f with Tir.fn_body = body' })
        m.Tir.tm_fns
    in
    { m with Tir.tm_fns = fns }
  end
