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
    compares.  Retargeting self calls keeps a self tail call a loop; mutual
    tail recursion between framed fns grows the stack by one wrapper per hop
    (deferred, decision 7).

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
  let l = var "$auth_l" layer_ty in
  let s = var "$auth_saved" auth_ty in
  let r = var "$auth_result" f.Tir.fn_ret_ty in
  let u = var "$auth_unit" Tir.TUnit in
  let wrapper_body =
    Tir.ELet
      ( l, Tir.EApp (var layer_name (Tir.TFn ([], layer_ty)), []),
        Tir.ELet
          ( s, Tir.EApp (var Tir_names.enter_fn_name (Tir.TFn ([ layer_ty ], auth_ty)), [ Tir.AVar l ]),
            Tir.ELet
              ( r,
                Tir.EApp
                  ( var body_name
                      (Tir.TFn (List.map (fun (p : Tir.var) -> p.Tir.v_ty) f.Tir.fn_params,
                                f.Tir.fn_ret_ty)),
                    List.map (fun p -> Tir.AVar p) f.Tir.fn_params ),
                Tir.ELet
                  ( u, Tir.EApp (var "cap_restore" (Tir.TFn ([ auth_ty ], Tir.TUnit)), [ Tir.AVar s ]),
                    Tir.EAtom (Tir.AVar r) ) ) ) )
  in
  let wrapper = { f with Tir.fn_body = wrapper_body } in
  Provenance.record body_name ~from:name ~derived:(Provenance.Clone_of (name, "auth frame body"))
    ~pass:"auth_rt" ();
  Provenance.record layer_name ~from:name ~derived:(Provenance.Clone_of (name, "auth frame layer"))
    ~pass:"auth_rt" ();
  [ wrapper; body_fn; layer_fn ]

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
        ({ m with Tir.tm_fns = fns }, true)
      end
    end
  end

(* ── Capture (Task 5) ─────────────────────────────────────────────────

   A function value runs under the authority it was made under, not the
   one in force where it is called (design §5).  [captures] makes that so
   for the values whose authority can matter: see the .mli. *)

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
             if n = authority_check
             || (not (Hashtbl.mem defined n) && (is_op_builtin n || List.mem n spawn_builtins))
             then hit := true)
          f.Tir.fn_body;
      !hit)

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
    let actor_glue =
      List.fold_left
        (fun acc td ->
           match td with
           | Tir.TDRecord (n, _) when Tir_names.is_actor_struct_name n ->
             let a =
               String.sub n 0 (String.length n - String.length Tir_names.actor_struct_suffix) in
             List.fold_left (fun s sfx -> SSet.add (a ^ sfx) s) acc
               [ Tir_names.actor_dispatch_suffix; Tir_names.actor_on_stop_suffix;
                 Tir_names.actor_inspect_suffix; Tir_names.actor_spawn_suffix ]
           | _ -> acc)
        SSet.empty m.Tir.tm_types
    in
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
       wrapper's own code, and a captured lambda's own body is a body of
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
