(** Run-time frames for function `needs` clauses (ocap phase 4, Task 4;
    specs/plans/2026-11-15-ocap-p4-runtime-plan.md).

    The type checker already proves that every operation reached by direct
    calls under a fn [f] with `needs N` has a kind in [N].  At run time a
    frame is needed only where it cannot see:
    - the clause carries a scope (a computed target can fall outside it), or
    - [f] reaches an actor spawn: the actor's handlers are charged to the
      actor's module, not to [f], yet a worker spawned under [f] keeps [f]'s
      authority for life (the spawn copies the current authority).

    Such an [f] is rewritten to

    {v
      f(args)       = let l = f$auth_layer() in
                      let s = Authority.enter_fn(l) in
                      let r = f$auth(args) in
                      cap_restore(s); r
      f$auth(args)  = the original body, self calls to f retargeted here
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

(** The fns of [m] that reach an actor spawn through direct calls (a lambda
    or local fn's body counts for the fn it is written in): the least
    fixpoint seeded by direct calls to the spawn builtins. *)
let reaches_actor_spawn (m : Tir.tir_module) : SSet.t =
  let defined = Hashtbl.create 256 in
  List.iter (fun (f : Tir.fn_def) -> Hashtbl.replace defined f.Tir.fn_name ()) m.Tir.tm_fns;
  let callees = Hashtbl.create 256 in
  let seeds =
    List.fold_left
      (fun acc (f : Tir.fn_def) ->
         let cs = ref SSet.empty and spawns = ref false in
         iter_calls
           (fun n ->
              if List.mem n spawn_builtins && not (Hashtbl.mem defined n) then spawns := true
              else if Hashtbl.mem defined n then cs := SSet.add n !cs)
           f.Tir.fn_body;
         Hashtbl.replace callees f.Tir.fn_name !cs;
         if !spawns then SSet.add f.Tir.fn_name acc else acc)
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

(* [e] with every direct call of [from] retargeted to [to_]. *)
let rec retarget ~from ~to_ (e : Tir.expr) : Tir.expr =
  let go = retarget ~from ~to_ in
  match e with
  | Tir.EApp (f, args) when f.Tir.v_name = from -> Tir.EApp ({ f with Tir.v_name = to_ }, args)
  | Tir.ELet (v, a, b) -> Tir.ELet (v, go a, go b)
  | Tir.ESeq (a, b) -> Tir.ESeq (go a, go b)
  | Tir.ELetRec (fns, b) ->
    (* A local fn of the same name shadows [f] in its scope. *)
    if List.exists (fun (fd : Tir.fn_def) -> fd.Tir.fn_name = from) fns then e
    else
      Tir.ELetRec
        (List.map (fun (fd : Tir.fn_def) -> { fd with Tir.fn_body = go fd.Tir.fn_body }) fns, go b)
  | Tir.ECase (s, brs, d) ->
    Tir.ECase
      (s, List.map (fun (br : Tir.branch) -> { br with Tir.br_body = go br.Tir.br_body }) brs,
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
      let framed =
        List.filter
          (fun (f : Tir.fn_def) ->
             let n = Hashtbl.find needs f.Tir.fn_name in
             n.Lower_state.fnn_scoped || SSet.mem f.Tir.fn_name (Lazy.force spawners))
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
