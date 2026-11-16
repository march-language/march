(** Hot-reload H3: migration is a simulation, for `@compat(simulation)` actors.

    Design: specs/2026-11-04-lemmas-hcr-actors-choreography-design.md, §3.4
    "H3. Migration is a simulation", with M3 (handlers as reflected
    functions) as the machinery.  The law: handling a message on the deployed
    code and then migrating gives the same state as migrating first and
    handling it on the new code.  It is what makes the deploy marker's
    position harmless: a message queued around it ends in the same state
    whichever side handles it.  Many correct deploys are not simulations on
    purpose (they change what a handler does), so it is opt-in:
    `@compat(simulation)` (the `full` shape policy, plus this law).

    Where the deployed handlers come from (the design's open question 2): a
    `--hot-reload` build of a `@compat(simulation)` actor writes each
    handler's body, as source, into the `.schemas.json` sidecar (`"steps"`);
    the driver parses the deployed sidecar's steps into [baseline] before
    desugar.  This pass then adds, per message both builds handle with the
    same parameters,

      @[hcr_logic] fn <a>__old_step__<M>(state : Old, p…) : Old do <deployed body> end
      @[hcr_logic] fn <a>__new_step__<M>(state : New, p…) : New do <this body> end
      @[lemma] fn <a>_simulates__<M>(old_state : Old, p…)
        : {Unit | <a>__new_step__<M>(<a>_migrate_state(old_state), p…)
                  == <a>_migrate_state(<a>__old_step__<M>(old_state, p…))} do () end

    (with no `migrate_state` and an unchanged state, the identity).  The step
    functions are the handlers as functions of the state (M3): a call in
    statement position is dropped (a send or reply is another actor's
    business, as for the inductive invariant).  Everything generated is
    erased before anything runs ([Lemma_erase]: lemmas and `hcr_logic`).

    Carried only when both bodies stay inside a grammar that typechecks the
    same in any build: literals, `state` and its fields, the parameters,
    `let`, `if`, record literals and updates, the arithmetic, comparison and
    boolean operators, `++`, list and option constructors, and calls of
    standard-library modules.  Anything else (a call of the program's own
    function, which the deployed build may have defined differently; a
    `match` on a user type) is reported, never generated: [report] says why,
    and `--guarantees` prints it as `not checked`. *)

open March_ast.Ast

(** One deployed handler: its message, parameter names and body. *)
type step = { msg : string; params : string list; body : expr }

(** The deployed build's state fields (name, type) and handler steps, per
    actor.  Filled by the driver from the deployed `.schemas.json`; empty
    when no deploy is known. *)
type deployed = { fields : (string * ty) list; steps : step list }

let baseline : (string * deployed) list ref = ref []

type outcome =
  | Checked of string        (** the lemma generated, by name *)
  | New_handler              (** no deployed message can name it *)
  | Not_checked of string    (** why not *)

(** Per `@compat(simulation)` actor, per message: what this pass did. Reset
    by the driver with [baseline]. *)
let report : (string * (string * outcome) list) list ref = ref []

let compat = "simulation"

let last_segment s =
  match String.rindex_opt s '.' with
  | Some i -> String.sub s (i + 1) (String.length s - i - 1)
  | None -> s

let operators =
  [ "+"; "-"; "*"; "/"; "%"; "=="; "!="; "<"; "<="; ">"; ">="; "&&"; "||"; "not"; "negate"; "++"
  ; "+."; "-."; "*."; "/." ]

let stdlib_modules = [ "List"; "Option"; "Result"; "String"; "Int"; "Float"; "Map"; "Set"; "Math" ]

let safe_ctors = [ "Some"; "None"; "Ok"; "Err"; "Nil"; "Cons"; "True"; "False" ]

(* A call in statement position (a send, a reply, a print) is dropped: the
   state a handler returns does not depend on it. *)
let rec drop_stmts (e : expr) : expr =
  match e with
  | EBlock (es, sp) ->
    let rec go = function
      | [] -> []
      | [ last ] -> [ drop_stmts last ]
      | EApp _ :: rest -> go rest
      | st :: rest -> st :: go rest
    in
    (match go es with [ e ] -> e | es -> EBlock (es, sp))
  | EIf (c, t, f, sp) -> EIf (c, drop_stmts t, drop_stmts f, sp)
  | e -> e

(* Why [e] is not carried, or [None]. *)
let rec uncarried ~(bound : string list) (e : expr) : string option =
  let all es = List.find_map (uncarried ~bound) es in
  match e with
  | ELit _ -> None
  | EVar v ->
    if List.mem v.txt bound then None
    else Some (Printf.sprintf "it reads `%s`, which is not the state or a parameter" v.txt)
  | EField (r, _, _) -> uncarried ~bound r
  | ERecord (fs, _) -> all (List.map snd fs)
  | ERecordUpdate (r, fs, _) -> all (r :: List.map snd fs)
  | EIf (c, t, f, _) -> all [ c; t; f ]
  | ETuple (es, _) -> all es
  | ECon (c, es, _) ->
    if List.mem (last_segment c.txt) safe_ctors then all es
    else Some (Printf.sprintf "it builds `%s`, which the deployed build may define differently" c.txt)
  | EApp (EVar f, args, _) when List.mem f.txt operators -> all args
  | EApp (EVar f, args, _) -> (
    match String.index_opt f.txt '.' with
    | Some i when List.mem (String.sub f.txt 0 i) stdlib_modules -> all args
    | _ ->
      Some
        (Printf.sprintf "it calls `%s`, which the deployed build may define differently" f.txt))
  | EBlock (es, _) ->
    let rec go bound = function
      | [] -> None
      | ELet ({ bind_pat = PatVar n; bind_expr; _ }, _) :: rest -> (
        match uncarried ~bound bind_expr with
        | Some _ as why -> why
        | None -> go (n.txt :: bound) rest)
      | e :: rest -> (match uncarried ~bound e with Some _ as why -> why | None -> go bound rest)
    in
    go bound es
  | EMatch _ -> Some "it uses `match`, which is not carried across builds yet"
  | _ -> Some "it uses a construct that is not carried across builds"

(* Does [e] read [x]?  Over the carried grammar ([uncarried] accepted it),
   so every binding form is a block `let`. *)
let rec reads (x : string) (e : expr) : bool =
  match e with
  | EVar v -> v.txt = x
  | EField (r, _, _) -> reads x r
  | ERecord (fs, _) -> List.exists (fun (_, v) -> reads x v) fs
  | ERecordUpdate (r, fs, _) -> reads x r || List.exists (fun (_, v) -> reads x v) fs
  | EIf (c, t, f, _) -> reads x c || reads x t || reads x f
  | ETuple (es, _) | ECon (_, es, _) -> List.exists (reads x) es
  | EApp (f, args, _) -> reads x f || List.exists (reads x) args
  | EBlock (es, _) ->
    let rec go = function
      | [] -> false
      | ELet ({ bind_pat = PatVar n; bind_expr; _ }, _) :: rest ->
        reads x bind_expr || (n.txt <> x && go rest)
      | e :: rest -> reads x e || go rest
    in
    go es
  | ELet (b, _) -> reads x b.bind_expr
  | _ -> false

(* A span of its own per generated node: reflection keys call sites and
   units by span. *)
let fresh_span (base : span) : unit -> span =
  let k = ref 0 in
  fun () ->
    incr k;
    { base with end_col = base.end_col + 1000 + !k }

let rec plain (t : ty) : ty =
  match t with
  | TyRefine (t, _, _) -> plain t
  | TyCon (n, args) -> TyCon (n, List.map plain args)
  | TyTuple ts -> TyTuple (List.map plain ts)
  | TyRecord fs -> TyRecord (List.map (fun (f, t) -> (f, plain t)) fs)
  | TyLinear (l, t) -> TyLinear (l, plain t)
  | t -> t

let lower s = String.lowercase_ascii s

(* Every name a generated function or lemma declares, so a user declaration
   of one suppresses it. *)
let generated_names ~(actor : string) (m : string) =
  let a = lower actor in
  [ a ^ "__old_step__" ^ m; a ^ "__new_step__" ^ m; a ^ "_simulates__" ^ m ]

let for_actor ~(declared : string -> bool) ~(sp : span) (actor : string) (adef : actor_def)
    (dep : deployed) : decl list * (string * outcome) list =
  let a = lower actor in
  let span = fresh_span sp in
  let nm s = { txt = s; span = span () } in
  let new_fields = List.map (fun (f : field) -> (f.fld_name.txt, plain f.fld_ty)) adef.actor_state in
  let field_set fs = List.sort compare (List.map fst fs) in
  let migrate = a ^ "_migrate_state" in
  let mig =
    if declared migrate then Ok (fun e -> EApp (EVar (nm migrate), [ e ], span ()))
    else if field_set dep.fields = field_set new_fields then Ok (fun e -> e)
    else Error "the state changed and there is no migrate_state"
  in
  let rec_ty fs = TyRecord (List.map (fun (f, t) -> (nm f, t)) fs) in
  let old_ty = rec_ty dep.fields and new_ty = rec_ty new_fields in
  let migrate_msg = declared (a ^ "_migrate_msg") in
  List.fold_right
    (fun (h : actor_handler) (decls, outs) ->
      let m = h.ah_msg.txt in
      let skip why = (decls, (m, Not_checked why) :: outs) in
      match List.find_opt (fun s -> s.msg = m) dep.steps with
      | None -> (decls, (m, New_handler) :: outs)
      | Some st ->
        if migrate_msg then skip "the message type changed (migrate_msg): not carried yet"
        else if List.length st.params <> List.length h.ah_params then
          skip "its parameters changed"
        else if List.exists declared (generated_names ~actor m) then
          skip "a declaration already has a generated name"
        else
          match mig with
          | Error why -> skip why
          | Ok mig ->
            let new_params = List.map (fun (p : param) -> p.param_name.txt) h.ah_params in
            let old_body = drop_stmts st.body and new_body = drop_stmts h.ah_body in
            (match
               uncarried ~bound:("state" :: st.params) old_body,
               uncarried ~bound:("state" :: new_params) new_body
             with
             | Some why, _ -> skip ("the deployed handler: " ^ why)
             | None, Some why -> skip ("this handler: " ^ why)
             | None, None ->
               (* The deployed step's parameters are renamed to this
                  handler's, so one parameter list serves all three. *)
               let rename =
                 List.combine st.params new_params |> List.filter (fun (o, n) -> o <> n)
               in
               let rec ren (e : expr) : expr =
                 match e with
                 | EVar v -> (
                   match List.assoc_opt v.txt rename with Some n -> EVar { v with txt = n } | None -> e)
                 | EField (r, f, s) -> EField (ren r, f, s)
                 | ERecord (fs, s) -> ERecord (List.map (fun (f, x) -> (f, ren x)) fs, s)
                 | ERecordUpdate (r, fs, s) -> ERecordUpdate (ren r, List.map (fun (f, x) -> (f, ren x)) fs, s)
                 | EIf (c, t, f, s) -> EIf (ren c, ren t, ren f, s)
                 | ETuple (es, s) -> ETuple (List.map ren es, s)
                 | ECon (c, es, s) -> ECon (c, List.map ren es, s)
                 | EApp (f, args, s) -> EApp (f, List.map ren args, s)
                 | EBlock (es, s) -> EBlock (List.map ren es, s)
                 | ELet (b, s) -> ELet ({ b with bind_expr = ren b.bind_expr }, s)
                 | e -> e
               in
               (* A step parameter its body no longer reads (the reply
                  channel, once `Actor.reply` is dropped) is named `_…`: the
                  unused-binding lint must never fire, or offer a fix, on
                  generated code.  The lemma passes arguments by position. *)
               let params ?body () =
                 List.map
                   (fun (p : param) ->
                     let n = p.param_name.txt in
                     let n = match body with Some b when not (reads n b) -> "_" ^ n | _ -> n in
                     FPNamed { p with param_ty = Option.map plain p.param_ty; param_name = nm n })
                   h.ah_params
               in
               let state_p ty = FPNamed { param_name = nm "state"; param_ty = Some ty; param_lin = Unrestricted } in
               let fn ~name ~attrs ~ret ps body =
                 DFn
                   ( { fn_name = nm name; fn_vis = Private; fn_doc = None; fn_attrs = attrs;
                       fn_ret_ty = Some ret;
                       fn_clauses =
                         [ { fc_params = ps; fc_guard = None; fc_body = body; fc_span = span ();
                             fc_params_span = span () } ];
                       fn_bounds = []; fn_attr_args = []; fn_needs = None },
                     span () )
               in
               let old_step = a ^ "__old_step__" ^ m and new_step = a ^ "__new_step__" ^ m in
               let lemma = a ^ "_simulates__" ^ m in
               let args () = List.map (fun n -> EVar (nm n)) new_params in
               let call f xs = EApp (EVar (nm f), xs, span ()) in
               let s () = EVar (nm "old_state") in
               let theorem =
                 call "=="
                   [ call new_step (mig (s ()) :: args ()); mig (call old_step (s () :: args ())) ]
               in
               let lemma_d =
                 DFn
                   ( { fn_name = nm lemma; fn_vis = Private; fn_doc = None; fn_attrs = [ "lemma" ];
                       fn_ret_ty = Some (TyRefine (TyCon (nm "Unit", []), Some (nm "_"), theorem));
                       fn_clauses =
                         [ { fc_params =
                               FPNamed { param_name = nm "old_state"; param_ty = Some old_ty; param_lin = Unrestricted }
                               :: params ();
                             fc_guard = None; fc_body = ETuple ([], span ()); fc_span = span ();
                             fc_params_span = span () } ];
                       fn_bounds = []; fn_attr_args = []; fn_needs = None },
                     span () )
               in
               let old_body = ren old_body in
               let state_p ty body =
                 if reads "state" body then state_p ty
                 else FPNamed { param_name = nm "_state"; param_ty = Some ty; param_lin = Unrestricted }
               in
               ( fn ~name:old_step ~attrs:[ "hcr_logic" ] ~ret:old_ty
                   (state_p old_ty old_body :: params ~body:old_body ()) old_body
                 :: fn ~name:new_step ~attrs:[ "hcr_logic" ] ~ret:new_ty
                      (state_p new_ty new_body :: params ~body:new_body ()) new_body
                 :: lemma_d :: decls,
                 (m, Checked lemma) :: outs )))
    adef.actor_handlers ([], [])

let rec expand (ds : decl list) : decl list =
  let declared name =
    List.exists (function DFn (fd, _) -> fd.fn_name.txt = name | _ -> false) ds
  in
  let extra =
    List.concat_map
      (function
        | DActor (_, name, adef, sp) when adef.actor_compat = compat -> (
          match List.find_opt (fun (n, _) -> last_segment n = name.txt) !baseline with
          | None ->
            report := (name.txt, []) :: !report;
            []
          | Some (_, dep) ->
            let decls, outs = for_actor ~declared ~sp name.txt adef dep in
            report := (name.txt, outs) :: !report;
            decls)
        | _ -> [])
      ds
  in
  List.map (function DMod (n, v, inner, sp) -> DMod (n, v, expand inner, sp) | d -> d) ds @ extra
