(** Actor-declaration lowering: [lower_actor] and its glue (Wave 3 Task 9:
    split out of [Lower]).

    Moved verbatim from lower.ml's "Actor lowering" section. [lower_actor]
    calls [Lower_match.lower_expr] (forwarding to lower.ml's [lower_expr] via
    the forward ref) strictly ONE WAY — no cycle, since nothing in
    lower.ml's [lower_expr] calls back into [lower_actor]. *)

module Ast = March_ast.Ast

(** Lower an actor declaration to TIR type defs + function defs.

    For actor [Name] with state fields [f1:T1, ..., fn:Tn] (alphabetical) and
    handlers [on H1(p...) body1, ...], we generate:

    Types:
      TDVariant("Name_Msg", [(H1, param_tys_1); ...])    -- in handler decl order
      TDRecord ("Name_Actor", [("$d_dispatch",TPtr TUnit);
                               ("$e_alive",TBool); f1:T1; ...fn:Tn])
                                                          -- $d_dispatch first, $e_alive second
                                                          -- (prefixed so alphabetical sort matches
                                                          --  alloc/reuse order & C runtime layout)
                                                          -- then state fields alphabetically

    Functions:
      Name_Hi(actor:ptr, p...) → Unit   -- one per handler
      Name_dispatch(actor:ptr, msg:ptr) → Unit
      Name_spawn() → ptr
*)
let lower_actor (env : Lower_state.env) ~hot_reload (name : string) (actor : Ast.actor_def) : Tir.type_def list * Tir.fn_def list =
  (* State fields sorted alphabetically (matches TRecord ordering) *)
  let state_fields_sorted : (string * Tir.ty) list =
    List.sort (fun (a, _) (b, _) -> String.compare a b)
      (List.map (fun (f : Ast.field) -> (f.fld_name.txt, Lower_types.lower_ty f.fld_ty))
         actor.actor_state)
  in
  (* In hot_reload mode, state lives in a separate heap record.
     state_type_name is the TIR name for that record. *)
  let state_type_name = name ^ Tir_names.actor_state_suffix in

  (* ── 1. Message variant type ─────────────────────────────── *)
  let msg_type_name = name ^ Tir_names.actor_msg_suffix in
  let msg_ctors : (string * Tir.ty list) list =
    List.map (fun (h : Ast.actor_handler) ->
        let param_tys = List.map (fun (p : Ast.param) ->
            match p.param_ty with Some t -> Lower_types.lower_ty t | None -> Lower_types.unknown_ty
          ) h.ah_params in
        (h.ah_msg.txt, param_tys)
      ) actor.actor_handlers
  in
  let msg_variant = Tir.TDVariant (msg_type_name, msg_ctors) in

  (* ── 2. Actor struct type ────────────────────────────────── *)
  let actor_type_name = name ^ Tir_names.actor_struct_suffix in
  (* Layout order: $d_dispatch (field 0), $e_alive (field 1), state fields (fields 2+)
     Names are prefixed so alphabetical sort ($d < $e < $f < letters) in llvm_emit.ml's
     get_record_fields matches the alloc/reuse arg order and the C runtime's
     hardcoded word indices (a[2]=dispatch, a[3]=alive).
     In hot_reload mode: field 2 is $f_state (ptr to state record) → a[4]=state ptr. *)
  let actor_struct_fields : (string * Tir.ty) list =
    if hot_reload then
      [(Tir_names.actor_dispatch_field, Tir.TPtr Tir.TUnit);
       (Tir_names.actor_alive_field, Tir.TBool);
       (Tir_names.actor_state_field, Tir.TCon (state_type_name, []))]
    else
      [(Tir_names.actor_dispatch_field, Tir.TPtr Tir.TUnit); (Tir_names.actor_alive_field, Tir.TBool)]
      @ state_fields_sorted
  in
  let actor_record = Tir.TDRecord (actor_type_name, actor_struct_fields) in

  (* ── 3. Handler functions ────────────────────────────────── *)
  (* For handler "Hi" with params [(p1,T1);...]:
       fn Name_Hi(actor: ptr, p1:T1, ...) : Unit =
         let $sf1 = EField(actor, "sf1")    -- load each state field
         ...
         let state = ERecord [(sf1, $sf1); ...]
         let $result = <body>
         let $nf1 = EField($result, "sf1")  -- extract new state fields
         ...
         ESeq(EReuse(actor, Name_Actor, [$d_dispatch, $e_alive, $nf1, ...]), EAtom(unit))
  *)
  let actor_var (n : string) (ty : Tir.ty) : Tir.var =
    { Tir.v_name = n; v_ty = ty; v_lin = Tir.Unr }
  in
  (* Using TCon(actor_type_name) (not TPtr TUnit) so that EField accesses on
     the actor pointer resolve field indices correctly via field_map lookups.
     All TCon → ptr in llvm_ty, so the LLVM function signatures are unaffected. *)
  (* Mark actor param as Lin so Perceus won't add incrc for field loads.
     The actor is uniquely owned — FBIP can safely mutate it in-place.
     Fields $d_dispatch (index 0) and $e_alive (index 1) must stay first in
     alphabetical sort order so that GEP indices match the C runtime layout. *)
  let actor_param = { Tir.v_name = "$actor";
                      v_ty = Tir.TCon (actor_type_name, []);
                      v_lin = Tir.Lin } in
  let actor_atom  = Tir.AVar actor_param in

  let lower_handler (h : Ast.actor_handler) : Tir.fn_def =
    let fn_name = name ^ "_" ^ h.ah_msg.txt in

    (* Handler params (after the implicit $actor) *)
    let params : Tir.var list =
      actor_param ::
      List.map (fun (p : Ast.param) ->
          { Tir.v_name = p.param_name.txt;
            v_ty = (match p.param_ty with Some t -> Lower_types.lower_ty t | None -> Lower_types.unknown_ty);
            v_lin = Tir.Unr }
        ) h.ah_params
    in

    (* Load each state field from actor struct and let-bind it.
       Build the continuation bottom-up: first build inner body, wrap in lets. *)

    (* Step 1: lower the handler body (uses `state` variable) *)
    let body_tir = Lower_match.lower_expr env h.ah_body in

    let state_ty = Tir.TCon (name ^ Tir_names.actor_state_suffix, []) in
    (* Step 2: let $result = body_tir *)
    let result_var = actor_var "$result" state_ty in

    (* Step 3: load new state fields from $result *)
    let new_field_vars : (string * Tir.var) list =
      List.map (fun (fname, fty) ->
          let v = actor_var ("$nf_" ^ fname) fty in
          (fname, v)
        ) state_fields_sorted
    in

    (* Step 4: build EReuse args: $d_dispatch, $e_alive, then new state fields *)
    let dispatch_var = actor_var "$d_dispatch_v" (Tir.TPtr Tir.TUnit) in
    let alive_var    = actor_var "$e_alive_v" Tir.TBool in
    (* In hot_reload mode, a separate state ptr var ($f_state_v) holds the state record *)
    let state_ptr_var = actor_var "$f_state_v" (Tir.TCon (state_type_name, [])) in

    (* Build the innermost expression: ESeq(EReuse(...), unit) *)
    let reuse_expr =
      if hot_reload then
        (* Two-level reuse: first update state record in-place, then write new ptr into actor *)
        let new_state_var = actor_var "$new_state" (Tir.TCon (state_type_name, [])) in
        Tir.ELet (new_state_var,
          Tir.EReuse (Tir.AVar state_ptr_var, Tir.TCon (state_type_name, []),
                      List.map (fun (_, v) -> Tir.AVar v) new_field_vars),
          Tir.ESeq (
            Tir.EReuse (actor_atom, Tir.TCon (actor_type_name, []),
                        [Tir.AVar dispatch_var; Tir.AVar alive_var; Tir.AVar new_state_var]),
            Tir.EAtom (Tir.ALit (Ast.LitAtom "unit"))))
      else
        let reuse_args : Tir.atom list =
          [Tir.AVar dispatch_var; Tir.AVar alive_var]
          @ List.map (fun (_, v) -> Tir.AVar v) new_field_vars
        in
        Tir.ESeq (
          Tir.EReuse (actor_atom, Tir.TCon (actor_type_name, []), reuse_args),
          Tir.EAtom (Tir.ALit (Ast.LitAtom "unit")))
    in

    (* Wrap: let $nf_fi = EField($result, fi) for each state field *)
    let inner_with_new_fields =
      List.fold_right (fun (fname, nfv) acc ->
          Tir.ELet (nfv, Tir.EField (Tir.AVar result_var, fname), acc)
        ) new_field_vars reuse_expr
    in

    (* Wrap: let $result = body *)
    let inner_with_result =
      Tir.ELet (result_var, body_tir, inner_with_new_fields)
    in

    (* Wrap: let state = ERecord [(fname, AVar load_var); ...] *)
    let state_field_vars : (string * Tir.var) list =
      List.map (fun (fname, fty) ->
          (fname, actor_var ("$sf_" ^ fname) fty)
        ) state_fields_sorted
    in
    let state_record_fields : (string * Tir.atom) list =
      List.map (fun (fname, v) -> (fname, Tir.AVar v)) state_field_vars
    in
    let state_var = actor_var "state" state_ty in
    let inner_with_state =
      Tir.ELet (state_var, Tir.ERecord state_record_fields, inner_with_result)
    in

    (* Wrap: let $sf_fi = EField(actor/$f_state_v, fi) for each state field.
       In hot_reload mode, first load the state ptr from actor, then load fields from it. *)
    let inner_with_state_loads =
      if hot_reload then
        Tir.ELet (state_ptr_var, Tir.EField (actor_atom, Tir_names.actor_state_field),
          List.fold_right (fun (fname, sfv) acc ->
              Tir.ELet (sfv, Tir.EField (Tir.AVar state_ptr_var, fname), acc)
            ) state_field_vars inner_with_state)
      else
        List.fold_right (fun (fname, sfv) acc ->
            Tir.ELet (sfv, Tir.EField (actor_atom, fname), acc)
          ) state_field_vars inner_with_state
    in

    (* Wrap: let $e_alive_v = EField(actor, "$e_alive") *)
    let inner_with_alive =
      Tir.ELet (alive_var, Tir.EField (actor_atom, Tir_names.actor_alive_field), inner_with_state_loads)
    in

    (* Wrap: let $d_dispatch_v = EField(actor, "$d_dispatch") *)
    let full_body =
      Tir.ELet (dispatch_var, Tir.EField (actor_atom, Tir_names.actor_dispatch_field), inner_with_alive)
    in

    { Tir.fn_name; fn_params = params; fn_ret_ty = Tir.TUnit; fn_body = full_body;
      (* Actor message-handler glue: a regular top-level fn (called only via
         the dispatch ECase below), not a lifted lambda/join-point/apply
         wrapper — no RC/codegen consumer sniffs actor fn names for fn_kind
         purposes, so FnNormal is the honest label (set per plan guidance:
         "actor glue ... FnNormal with a comment"). *)
      fn_kind = Tir.FnNormal }
  in

  let handler_fns = List.map lower_handler actor.actor_handlers in

  (* ── 4. Dispatch function ────────────────────────────────── *)
  (* fn Name_dispatch(actor:ptr, msg:ptr) : Unit =
       ECase(AVar msg_as_msg_type, [
         {br_tag=H1; br_vars=[p1,...]; br_body=EApp(Name_H1, [actor, p1,...])};
         ...
       ], None)
  *)
  let msg_var = actor_var "$msg" (Tir.TCon (msg_type_name, [])) in
  let dispatch_branches : Tir.branch list =
    List.map (fun (h : Ast.actor_handler) ->
        (* Prefix each branch variable with the handler name to avoid name collisions
           when multiple handlers have parameters with the same name (e.g. both
           Increment(n) and Decrement(n) would otherwise both define %n.addr). *)
        let br_vars : Tir.var list =
          List.map (fun (p : Ast.param) ->
              { Tir.v_name = "$" ^ h.ah_msg.txt ^ "_" ^ p.param_name.txt;
                v_ty = (match p.param_ty with Some t -> Lower_types.lower_ty t | None -> Lower_types.unknown_ty);
                v_lin = Tir.Unr }
            ) h.ah_params
        in
        let handler_fn_var : Tir.var = {
          v_name = name ^ "_" ^ h.ah_msg.txt;
          v_ty = Tir.TFn (
            [Tir.TPtr Tir.TUnit] @ List.map (fun v -> v.Tir.v_ty) br_vars,
            Tir.TUnit);
          v_lin = Tir.Unr
        } in
        let call_args : Tir.atom list =
          actor_atom :: List.map (fun v -> Tir.AVar v) br_vars
        in
        { Tir.br_tag = h.ah_msg.txt;
          br_vars;
          br_body = Tir.EApp (handler_fn_var, call_args) }
      ) actor.actor_handlers
  in
  (* Default (drop) arm — finding-19 memory-safety fix.
     `send` does not gate a message by its target actor (a deferred type-system
     gap), so a message meant for a DIFFERENT actor can land in this actor's
     mailbox.  Its <Actor>_Msg type is forced Boxed with a GLOBALLY-unique tag
     (Repr.repr_of_ty / Llvm_toplevel.build_ctor_info), so a foreign message
     carries a tag that matches NONE of this actor's dispatch branches and lands
     here.  Return unit and drop it — byte-for-byte the interpreter's silent
     foreign-message drop (eval.ml `No handler for this message tag`), instead of
     misrouting its payload into the first handler at the wrong type.  The
     scrutinee ($msg) is not referenced in this arm, so Perceus inserts the
     dec_rc that releases the dropped message's heap cell (no leak). *)
  let dispatch_default = Tir.EAtom (Tir.ALit (Ast.LitAtom "unit")) in
  let dispatch_fn : Tir.fn_def = {
    fn_name   = name ^ Tir_names.actor_dispatch_suffix;
    fn_params = [actor_param; msg_var];
    fn_ret_ty = Tir.TUnit;
    fn_body   = Tir.ECase (Tir.AVar msg_var, dispatch_branches, Some dispatch_default);
    fn_kind   = Tir.FnNormal;  (* actor glue — see lower_handler's comment *)
  } in

  (* ── 5. Spawn function ───────────────────────────────────── *)
  (* fn Name_spawn() : ptr =
       let $init_state = <lowered init expr>
       let $sf1 = EField($init_state, "sf1")
       ...
       let $actor = EAlloc(Name_Actor, [AVar dispatch_fn_ptr, true, $sf1, ...])
       EAtom($actor)
  *)
  let dispatch_fn_ptr_var : Tir.var = {
    v_name = name ^ Tir_names.actor_dispatch_suffix;
    v_ty   = Tir.TFn ([Tir.TPtr Tir.TUnit; Tir.TPtr Tir.TUnit], Tir.TUnit);
    v_lin  = Tir.Unr;
  } in
  let state_ty = Tir.TCon (name ^ Tir_names.actor_state_suffix, []) in
  let init_var = actor_var "$init_state" state_ty in
  let init_field_vars : (string * Tir.var) list =
    List.map (fun (fname, fty) ->
        (fname, actor_var ("$init_" ^ fname) fty)
      ) state_fields_sorted
  in
  (* In hot_reload mode, pass $init_state directly as the state ptr ($f_state).
     In normal mode, unpack each state field and pass them individually. *)
  let alloc_args : Tir.atom list =
    if hot_reload then
      [Tir.AVar dispatch_fn_ptr_var; Tir.ALit (Ast.LitBool true); Tir.AVar init_var]
    else
      [Tir.AVar dispatch_fn_ptr_var; Tir.ALit (Ast.LitBool true)]
      @ List.map (fun (_, v) -> Tir.AVar v) init_field_vars
  in
  let alloc_expr = Tir.EAlloc (Tir.TCon (actor_type_name, []), alloc_args) in
  let actor_result_var = actor_var "$spawned" (Tir.TPtr Tir.TUnit) in
  let spawn_inner =
    Tir.ELet (actor_result_var, alloc_expr, Tir.EAtom (Tir.AVar actor_result_var))
  in
  (* For a supervised field, spawn its declared child actor now (the
     supervisor struct doesn't exist yet — that's fine, spawning doesn't
     need it) and bind $init_<fname> to the child's pid_index Int instead
     of loading it from `init`. The child's raw pointer is also bound
     ($sup_child_ptr_<fname>) and stays in lexical scope all the way past
     the EAlloc below, for wrap_sup (below) to register against $spawned. *)
  let supervised_child_name (fname : string) : string option =
    match actor.actor_supervise with
    | None -> None
    | Some sc ->
      List.find_opt (fun (sf : Ast.supervise_field) -> sf.Ast.sf_name.txt = fname) sc.Ast.sc_fields
      |> Option.map (fun sf -> match sf.Ast.sf_ty with
          | Ast.TyCon (n, []) -> n.txt
          | _ -> failwith ("supervise field " ^ fname ^ ": child type must be a bare actor name"))
  in
  let spawn_with_fields =
    if hot_reload then
      spawn_inner
    else
      List.fold_right (fun (fname, ifv) acc ->
          match supervised_child_name fname with
          | None -> Tir.ELet (ifv, Tir.EField (Tir.AVar init_var, fname), acc)
          | Some child_actor_name ->
            let child_spawn_var : Tir.var = {
              v_name = child_actor_name ^ Tir_names.actor_spawn_suffix;
              v_ty   = Tir.TFn ([], Tir.TPtr Tir.TUnit);
              v_lin  = Tir.Unr;
            } in
            let march_spawn_var : Tir.var = { v_name = "spawn"; v_ty = Tir.TPtr Tir.TUnit; v_lin = Tir.Unr } in
            let pid_index_of_var : Tir.var = { v_name = "pid_index_of"; v_ty = Tir.TInt; v_lin = Tir.Unr } in
            let raw_var = actor_var ("$sup_child_raw_" ^ fname) (Tir.TPtr Tir.TUnit) in
            let child_ptr_var = actor_var ("$sup_child_ptr_" ^ fname) (Tir.TPtr Tir.TUnit) in
            Tir.ELet (raw_var, Tir.EApp (child_spawn_var, []),
              Tir.ELet (child_ptr_var, Tir.EApp (march_spawn_var, [Tir.AVar raw_var]),
                Tir.ELet (ifv, Tir.EApp (pid_index_of_var, [Tir.AVar child_ptr_var]),
                  acc)))
        ) init_field_vars spawn_inner
  in
  (* ── 5b. Supervision registration ───────────────────────────────── *)
  (* If this actor declares a supervise block, call march_register_supervisor
     from the spawn function body so the runtime knows the supervision strategy.
     Encoding: OneForOne=0, OneForAll=1, RestForOne=2. *)
  let strategy_int (s : Ast.restart_strategy) : int =
    match s with
    | Ast.OneForOne  -> 0
    | Ast.OneForAll  -> 1
    | Ast.RestForOne -> 2
  in
  let mk_reg_sup_call (spawned_atom : Tir.atom) (sc : Ast.supervise_config) : Tir.expr =
    let reg_sup_var : Tir.var = {
      v_name = "register_supervisor";
      v_ty   = Tir.TFn ([Tir.TPtr Tir.TUnit; Tir.TInt; Tir.TInt; Tir.TInt], Tir.TUnit);
      v_lin  = Tir.Unr;
    } in
    Tir.EApp (reg_sup_var, [
      spawned_atom;
      Tir.ALit (Ast.LitInt (strategy_int sc.Ast.sc_strategy));
      Tir.ALit (Ast.LitInt sc.Ast.sc_max_restarts);
      Tir.ALit (Ast.LitInt sc.Ast.sc_window_secs);
    ])
  in
  (* Wrap the spawn body: after allocating the actor, register supervision if needed. *)
  let spawn_body_with_sup =
    match actor.actor_supervise with
    | None -> Tir.ELet (init_var, Lower_match.lower_expr env actor.actor_init, spawn_with_fields)
    | Some sc ->
      let field_word_idx (fname : string) : int =
        let rec find i = function
          | [] -> failwith ("supervise field " ^ fname ^ " not found in actor state")
          | (n, _) :: _ when n = fname -> i
          | _ :: rest -> find (i + 1) rest
        in find 0 state_fields_sorted
      in
      let mk_reg_child_calls (sup_atom : Tir.atom) (rest : Tir.expr) : Tir.expr =
        List.fold_right (fun (sf : Ast.supervise_field) acc ->
            let fname = sf.Ast.sf_name.txt in
            let child_actor_name = match sf.Ast.sf_ty with
              | Ast.TyCon (n, []) -> n.txt
              | _ -> failwith ("supervise field " ^ fname ^ ": child type must be a bare actor name")
            in
            let child_ptr_var = actor_var ("$sup_child_ptr_" ^ fname) (Tir.TPtr Tir.TUnit) in
            let child_spawn_fn_var : Tir.var = {
              v_name = child_actor_name ^ Tir_names.actor_spawn_suffix;
              v_ty   = Tir.TFn ([], Tir.TPtr Tir.TUnit);
              v_lin  = Tir.Unr;
            } in
            let reg_child_var : Tir.var = {
              v_name = "register_supervisor_child";
              v_ty   = Tir.TFn ([Tir.TPtr Tir.TUnit; Tir.TPtr Tir.TUnit; Tir.TPtr Tir.TUnit; Tir.TInt], Tir.TUnit);
              v_lin  = Tir.Unr;
            } in
            Tir.ELet ({ v_name = "$reg_child_" ^ fname; v_ty = Tir.TUnit; v_lin = Tir.Unr },
              Tir.EApp (reg_child_var, [
                sup_atom; Tir.AVar child_ptr_var; Tir.AVar child_spawn_fn_var;
                Tir.ALit (Ast.LitInt (field_word_idx fname));
              ]),
              acc)
          ) sc.Ast.sc_fields rest
      in
      (* Replace the final EAtom($spawned) with:
           let $reg_sup_result = register_supervisor($spawned, strat, max, window) in
           <one register_supervisor_child call per declared child> in
           EAtom($spawned)
         We thread the $spawned var through by wrapping the full body. *)
      let rec wrap_sup (e : Tir.expr) : Tir.expr =
        match e with
        | Tir.ELet (v, Tir.EAlloc (ty, args), rest) when v.Tir.v_name = "$spawned" ->
          (* After allocating, call march_spawn, then register_supervisor, then return *)
          Tir.ELet (v, Tir.EAlloc (ty, args),
            Tir.ELet ({ v_name = "$sup_reg"; v_ty = Tir.TUnit; v_lin = Tir.Unr },
              mk_reg_sup_call (Tir.AVar v) sc,
              mk_reg_child_calls (Tir.AVar v) rest))
        | Tir.ELet (v, rhs, body) -> Tir.ELet (v, rhs, wrap_sup body)
        | other -> other
      in
      Tir.ELet (init_var, Lower_match.lower_expr env actor.actor_init, wrap_sup spawn_with_fields)
  in
  let spawn_fn : Tir.fn_def = {
    fn_name   = name ^ Tir_names.actor_spawn_suffix;
    fn_params = [];
    fn_ret_ty = Tir.TPtr Tir.TUnit;
    fn_body   = spawn_body_with_sup;
    fn_kind   = Tir.FnNormal;  (* actor glue — see lower_handler's comment *)
  } in

  (* Also register a state record type so EField accesses on the init state
     record resolve the correct field indices (needed when there are multiple
     state fields). *)
  let state_record = Tir.TDRecord (name ^ Tir_names.actor_state_suffix, state_fields_sorted) in

  let type_defs = [state_record; msg_variant; actor_record] in
  let fn_defs   = handler_fns @ [dispatch_fn; spawn_fn] in
  (type_defs, fn_defs)
