(** Derived state migrations (lemmas design §3.3, M11).

    Most state changes are mechanical: the new build adds a field and gives it
    a value.  When the deployed build's schema is known ([baseline]) and an
    actor's state differs from it only by ADDED fields whose `init` values
    are constants, this pass writes the `<actor>_migrate_state` the user
    would have written, right after the actor:

      actor Counter do
        state { count : Int, history : List(Int) }
        init { count: 0, history: [] }
        ...
      end

      -- generated, for a deployed `state { count : Int }`
      fn counter_migrate_state(migrate_old__ : { count : Int })
          : { count : Int, history : List(Int) } do
        { count: migrate_old__.count, history: [] }
      end

    Two rules, each proved once in the compiler's test suite
    (test_refinecheck, suite `hcr-derived-migration`):

    - KEEP: a field the deployed build had, with the same type, is copied.
      Its value satisfied the deployed refinement, which [Hcr_baseline]
      makes a hypothesis of the parameter, so an unchanged or weaker
      refinement proves.
    - ADD: a field the deployed build did not have takes its `init` value.
      That is what a freshly spawned actor starts with, so it is checked
      against the field's refinement like any other record field.

    The generated function is an ordinary `<actor>_migrate_state`: the
    refinement checker, the counterexample search and the live-data check
    (Desugar_migrate_check) all run on it.  A derivation is therefore never
    trusted beyond what those establish: a tightened refinement on a kept
    field is still refused, with the counterexample.

    Nothing is derived, and the deploy gate asks for a hand-written
    migration as before, when
    - the user wrote `<actor>_migrate_state`,
    - a deployed field was removed or changed type (dropping or converting
      data needs judgement; a rename looks like one of each),
    - an added field's `init` value is not a constant (it reads an `init`
      parameter, or `init` is not a record literal).

    [report] says what happened per actor, for the `.schemas.json` sidecar
    and through it forge's deploy plan. *)

open March_ast.Ast

(** Deployed state layout per actor: (field, schema type string), in the
    deployed order.  Filled by the driver from the deployed `.schemas.json`;
    empty means no deploy is known and nothing is derived. *)
let baseline : (string * (string * string) list) list ref = ref []

type outcome =
  | Derived of string list  (** the added fields, each taking its `init` value *)
  | Not_derived of string   (** why the user has to write the migration *)

(** What this pass decided for each actor whose state differs from the
    baseline, by actor name.  Reset by the driver before each desugar. *)
let report : (string * outcome) list ref = ref []

(** For each derived function, where each state field is declared, so a
    diagnostic about generated code can point at what the user wrote.
    Reset with [report]. *)
let origins : (string * (string * span) list) list ref = ref []

let param_name = "migrate_old__"

(** Derived rollbacks (todo 2026-11-08-hcr-derive-rollback-state).

    A derived add-only migration has a mechanical reverse: copy back every
    kept field, drop the added ones.  This pass writes it as
    `<actor>_rollback_state` (unless the user wrote one), so [Desugar_rollback]
    generates the round-trip lemma and the build PROVES rolling back loses
    nothing.  The sidecar then records the shape that rollback returns to
    ([rollbacks], `"rollback_derived"`).

    The payoff is the rollback deploy itself: redeploying the old source
    finds a state that only LOST fields, which a derivation otherwise refuses
    ("it removes …", since dropping live data needs judgement).  When the
    deployed build recorded a proved derived rollback to exactly the new
    state's fields ([rollback_baseline]), the dropped fields are precisely
    the ones that deploy added, and the migration is derived as that
    rollback: copy the kept fields, drop the rest ([drops]). *)

(** What the DEPLOYED build's derived rollback returns to: the field names it
    keeps, and the parsed types of the fields it drops (the driver parses
    them from the sidecar; a drop-only migration's parameter must be the
    deployed record's full type). *)
type deployed_rollback = {
  keeps : string list;
  drops_tys : (string * ty) list;
  moves : (string * string) list;
  (** (field returned to, deployed field copied into it) for a rollback that
      undoes a rename: the reverse of a migrate clause's bare `old.f` copy *)
}

let rollback_baseline : (string * deployed_rollback) list ref = ref []

(** This build's derived rollbacks: actor -> the field names it returns to.
    Reset with [report]. *)
let rollbacks : (string * string list) list ref = ref []

(** This build's drop-only migrations (the deployed build's rollback):
    actor -> the fields dropped.  Reset with [report]. *)
let drops : (string * string list) list ref = ref []

(** This build's derived rollbacks that undo a rename: actor -> (field
    returned to, field of this build's state copied into it).  Reset with
    [report]. *)
let rollback_moves : (string * (string * string) list) list ref = ref []

(** Migrate clauses (todo 2026-11-06-hcr-derive-field-rename).

    `migrate old -> { total: old.count }` on the actor names the part of a
    deploy's migration that is not mechanical.  The derived
    `<actor>_migrate_state` takes the clause's fields from it and everything
    else by the KEEP and ADD rules.  A third rule, COPY, needs no code: a bare
    `old.f` reads the parameter, which [Hcr_baseline] gives the deployed
    refinement of [f] as a hypothesis, exactly as KEEP's copy does; any other
    expression is checked like a written migration.

    A deployed field the clause reads may be removed (its value moved); one
    nothing reads still refuses the derivation, since dropping live data
    needs judgement.  A field whose type changed must be given by the clause.

    When every deployed field comes back by a bare copy (KEEP, or a COPY under
    a new name), the migration has a mechanical reverse, derived as
    `<actor>_rollback_state` like an add-only one's and proved by the
    round-trip lemma.

    [clause_fields]: actor -> the fields the clause gave.  [moves]: actor ->
    (new field, deployed field) bare copies under a different name, from a
    clause or from a rollback deploy that undoes one.  Both reset with
    [report]. *)
let clause_fields : (string * string list) list ref = ref []

(** `--hcr-drop Actor.field` (forge deploy hot --drop, todo
    2026-11-15-hcr-deploy-drop-consent): removed fields a derived migration
    may drop although nothing reads them.  Set by the driver's flag, never
    reset (it is the build's input).  [consented]: actor -> the fields this
    build's derivation dropped by that consent, for the image's schemas
    (`migrate_drops_consented`, which the server audits).  Reset with
    [report]. *)
let consented_drops : string list ref = ref []
let consented : (string * string list) list ref = ref []
let moves : (string * (string * string) list) list ref = ref []

(** The parsed types of the deployed fields, per actor: what a removed or
    converted field's parameter type is spelled with (the driver parses the
    schema strings, which desugar cannot).  A field missing here (a type
    whose schema string does not parse back) refuses a derivation that
    needs it. *)
let baseline_tys : (string * (string * ty) list) list ref = ref []

(** Field names [binder.f] that [e] reads. *)
let reads (binder : string) (e : expr) : string list =
  let acc = ref [] in
  ignore
    (Interface_laws.map_expr
       (fun e ->
         (match e with
          | EField (EVar v, f, _) when v.txt = binder -> acc := f.txt :: !acc
          | _ -> ());
         e)
       e);
  List.sort_uniq compare !acc

(** The clause's (binder, fields), when it is well-formed ([check_clause]
    reported it otherwise). *)
let clause_of (adef : actor_def) : (string * (string * expr) list) option =
  match adef.actor_migrate with
  | Some (b, ERecord (fs, _)) -> Some (b.txt, List.map (fun ((n : name), e) -> (n.txt, e)) fs)
  | _ -> None

module Err = March_errors.Errors

(** A clause that cannot mean anything is an error with or without a
    deployed baseline: its body must be a record literal of state fields,
    each given once. *)
let check_clause errors ~(actor : string) (adef : actor_def) : unit =
  match adef.actor_migrate with
  | None -> ()
  | Some (_, ERecord (fs, _)) ->
    let state = List.map (fun (f : field) -> f.fld_name.txt) adef.actor_state in
    let seen = Hashtbl.create 8 in
    List.iter
      (fun ((n : name), _) ->
        if not (List.mem n.txt state) then
          Err.error ~code:Err.Code.migrate_clause_invalid errors ~span:n.span
            (Printf.sprintf "the migrate clause gives `%s`, which is not a state field of `%s`" n.txt actor)
        else if Hashtbl.mem seen n.txt then
          Err.error ~code:Err.Code.migrate_clause_invalid errors ~span:n.span
            (Printf.sprintf "the migrate clause gives `%s` twice" n.txt)
        else Hashtbl.replace seen n.txt ())
      fs
  | Some (b, _) ->
    Err.error ~code:Err.Code.migrate_clause_invalid errors ~span:b.span
      "a migrate clause's body is a record literal of the new state's fields \
       that move or convert data, e.g. `migrate old -> { total: old.count }`"

let rollback_fn_name actor = String.lowercase_ascii actor ^ "_rollback_state"
let rollback_param = "rollback_new__"

let last_segment s =
  match String.rindex_opt s '.' with
  | Some i -> String.sub s (i + 1) (String.length s - i - 1)
  | None -> s

let migrate_fn_name actor = String.lowercase_ascii actor ^ "_migrate_state"

exception Unrenderable

(** The schema type string the driver writes for a field of this type
    (`ty_to_schema_str` over the lowered type), for the types whose spelling
    the two agree on.  Anything else raises, and the field counts as changed,
    so a doubt never derives. *)
let rec schema_str (t : ty) : string =
  match t with
  | TyCon (n, []) -> n.txt
  | TyCon (n, args) -> n.txt ^ "(" ^ String.concat "," (List.map schema_str args) ^ ")"
  | TyTuple ts -> "(" ^ String.concat "," (List.map schema_str ts) ^ ")"
  | TyLinear (_, t) | TyRefine (t, _, _) -> schema_str t
  | _ -> raise Unrenderable

(** [t] without refinements, as a migration's signature is written. *)
let rec plain (t : ty) : ty =
  match t with
  | TyRefine (t, _, _) -> plain t
  | TyCon (n, args) -> TyCon (n, List.map plain args)
  | TyTuple ts -> TyTuple (List.map plain ts)
  | TyRecord fs -> TyRecord (List.map (fun (f, t) -> (f, plain t)) fs)
  | TyLinear (l, t) -> TyLinear (l, plain t)
  | t -> t

(** [e] reads nothing but literals, constructors and calls of named
    functions: no `init` parameter, no local.  A function called here must be
    IO-free, which the migrate-function capability check enforces on the
    generated function as on a written one. *)
let rec constant ~(bound : string list) (e : expr) : bool =
  match e with
  | ELit _ -> true
  | ECon (_, xs, _) | ETuple (xs, _) -> List.for_all (constant ~bound) xs
  | ERecord (fs, _) -> List.for_all (fun (_, x) -> constant ~bound x) fs
  | EApp (EVar f, xs, _) ->
    (not (List.mem f.txt bound)) && List.for_all (constant ~bound) xs
  | _ -> false

(** A one-parameter function [name(param : arg_ty) : ret_ty = body]. *)
let mk_fn ~(name : string) ~(param : string) (sp : span) (arg_ty : ty) (ret_ty : ty) (body : expr) : decl =
  let n s = { txt = s; span = sp } in
  DFn
    ( { fn_name = n name; fn_vis = Public; fn_doc = None; fn_attrs = [];
        fn_ret_ty = Some ret_ty;
        fn_clauses =
          [ { fc_params =
                [ FPNamed { param_name = n param; param_ty = Some arg_ty; param_lin = Unrestricted } ];
              fc_guard = None; fc_body = body; fc_span = sp; fc_params_span = sp } ];
        fn_bounds = []; fn_attr_args = []; fn_needs = None },
      sp )

(** Where a field of the migrated state comes from. *)
type source =
  | Keep             (** the deployed field of the same name and type, copied *)
  | Copy of string   (** the clause's bare `old.g`, [g] of the same type *)
  | Clause           (** any other clause expression *)
  | Init             (** an added field's `init` value *)

(** A derived migration: the function, the added fields that take their
    `init` values, and the reverse when there is one (field returned to ->
    the new field copied back into it, and the deployed record type). *)
type derived = {
  fn : decl;
  added : string list;
  sources : (string * source) list;
  reverse : ((string * string) list * ty) option;
}

let derive ~(actor : string) (adef : actor_def) (sp : span)
    (old_fields : (string * string) list) : (derived, string) result =
  let new_fields =
    List.map (fun (f : field) -> (f.fld_name.txt, f.fld_ty)) adef.actor_state in
  let str t = try Some (schema_str t) with Unrenderable -> None in
  let removed =
    List.filter (fun (f, _) -> not (List.mem_assoc f new_fields)) old_fields in
  let changed =
    List.filter
      (fun (f, old_ty) ->
        match List.assoc_opt f new_fields with
        | Some t -> str t <> Some old_ty
        | None -> false)
      old_fields
  in
  let added = List.filter (fun (f, _) -> not (List.mem_assoc f old_fields)) new_fields in
  let names fs = String.concat ", " (List.map fst fs) in
  let n s = { txt = s; span = sp } in
  let new_ty = TyRecord (List.map (fun (f, t) -> (n f, plain t)) new_fields) in
  let deployed_tys =
    Option.value ~default:[]
      (List.find_map (fun (a, r) -> if last_segment a = actor then Some r else None) !baseline_tys)
  in
  (* The deployed record type: a field this build still has with the same
     type is spelled as declared; any other from the parsed schema. *)
  let old_ty_with (fallback : string -> ty option) : ty option =
    let fs =
      List.map
        (fun (f, old_s) ->
          match List.assoc_opt f new_fields with
          | Some t when str t = Some old_s -> Some (n f, plain t)
          | _ -> Option.map (fun t -> (n f, plain t)) (fallback f))
        old_fields
    in
    if List.for_all Option.is_some fs then Some (TyRecord (List.map Option.get fs)) else None
  in
  let deployed_rb =
    List.find_map (fun (a, r) -> if last_segment a = actor then Some r else None) !rollback_baseline
  in
  let clause = clause_of adef in
  let rb_move f = match deployed_rb with Some rb -> List.assoc_opt f rb.moves | None -> None in
  match deployed_rb with
  | Some rb
    when clause = None && removed <> [] && changed = []
         && List.sort compare (List.map fst new_fields) = List.sort compare rb.keeps
         && List.for_all
              (fun (f, t) ->
                match rb_move f with
                | Some g -> List.assoc_opt g old_fields = str t && str t <> None
                | None -> false)
              added
         && List.for_all (fun (f, _) -> List.mem_assoc f rb.drops_tys) removed ->
    (* The rollback deploy: the deployed build proved its derived rollback
       to exactly this state, so this migration IS that rollback: kept
       fields copied, renamed ones copied back, the rest dropped. *)
    (match old_ty_with (fun f -> List.assoc_opt f rb.drops_tys) with
     | None -> Error ("the deployed type of " ^ names removed ^ " could not be read")
     | Some old_ty ->
       let src f = match rb_move f with Some g when List.mem_assoc f added -> g | _ -> f in
       let body =
         ERecord (List.map (fun (f, _) -> (n f, EField (EVar (n param_name), n (src f), sp))) new_fields, sp)
       in
       let moved = List.filter_map (fun (f, _) -> if src f <> f then Some (f, src f) else None) new_fields in
       let sources = List.map (fun (f, _) -> (f, if src f <> f then Copy (src f) else Keep)) new_fields in
       drops :=
         (actor, List.filter (fun g -> not (List.exists (fun (_, s) -> s = g) moved)) (List.map fst removed))
         :: !drops;
       if moved <> [] then moves := (actor, moved) :: !moves;
       Ok
         { fn = mk_fn ~name:(migrate_fn_name actor) ~param:param_name sp old_ty new_ty body;
           added = []; sources; reverse = None })
  | _ ->
    let binder, given = match clause with Some (b, fs) -> (b, fs) | None -> (param_name, []) in
    let read = List.concat_map (fun (_, e) -> reads binder e) given in
    let consents f = List.mem (actor ^ "." ^ f) !consented_drops in
    let unread = List.filter (fun (f, _) -> not (List.mem f read) && not (consents f)) removed in
    let dropped_by_consent =
      List.filter_map (fun (f, _) -> if List.mem f read || not (consents f) then None else Some f) removed in
    let unconverted = List.filter (fun (f, _) -> not (List.mem_assoc f given)) changed in
    if unread <> [] then
      Error
        ("it removes " ^ names unread
         ^ (if clause = None then "" else ", which the migrate clause does not read"))
    else if unconverted <> [] then
      Error
        ("it changes the type of " ^ names unconverted
         ^ (if clause = None then "" else ", which the migrate clause does not give"))
    else
      let bound = List.map (fun (p : param) -> p.param_name.txt) adef.actor_init_params in
      let init_fields =
        match adef.actor_init with
        | ERecord (fs, _) -> Some (List.map (fun ((n : name), e) -> (n.txt, e)) fs)
        | _ -> None
      in
      let default f =
        match Option.bind init_fields (List.assoc_opt f) with
        | Some e when constant ~bound e -> Some e
        | _ -> None
      in
      let from_init = List.filter (fun (f, _) -> not (List.mem_assoc f given)) added in
      match List.filter (fun (f, _) -> default f = None) from_init with
      | _ :: _ as bad -> Error ("the `init` value of " ^ names bad ^ " is not a constant")
      | [] ->
        match old_ty_with (fun f -> List.assoc_opt f deployed_tys) with
        | None ->
          Error
            ("the deployed type of "
             ^ names (List.filter (fun (f, s) -> match List.assoc_opt f new_fields with
                 | Some t -> str t <> Some s | None -> true) old_fields)
             ^ " could not be read")
        | Some old_ty ->
          let source (f, t) =
            match List.assoc_opt f given with
            | Some (EField (EVar v, g, _)) when v.txt = binder && List.assoc_opt g.txt old_fields = str t && str t <> None ->
              Copy g.txt
            | Some _ -> Clause
            | None -> if List.mem_assoc f old_fields then Keep else Init
          in
          let sources = List.map (fun ft -> (fst ft, source ft)) new_fields in
          let body =
            ERecord
              ( List.map
                  (fun (f, _) ->
                    ( n f,
                      match List.assoc f sources with
                      | Keep -> EField (EVar (n binder), n f, sp)
                      | Init -> Option.get (default f)
                      | Copy _ | Clause -> List.assoc f given ))
                  new_fields,
                sp )
          in
          (* The reverse exists when every deployed field comes back by a
             bare copy: field returned to -> the new field copied into it. *)
          let back =
            List.map
              (fun (g, _) ->
                ( g,
                  List.find_map
                    (fun (f, s) -> match s with
                      | Keep when f = g -> Some f
                      | Copy h when h = g -> Some f
                      | _ -> None)
                    sources ))
              old_fields
          in
          let reverse =
            if List.for_all (fun (_, f) -> f <> None) back && List.exists (fun (_, s) -> s <> Keep) sources
            then Some (List.map (fun (g, f) -> (g, Option.get f)) back, old_ty)
            else None
          in
          if dropped_by_consent <> [] then consented := (actor, dropped_by_consent) :: !consented;
          Ok
            { fn = mk_fn ~name:(migrate_fn_name actor) ~param:binder sp old_ty new_ty body;
              added = List.map fst from_init; sources; reverse }

(** The reverse of a derived migration whose every deployed field came back
    by a bare copy: copy each one back from the field it went to (the same
    name for a kept field, the new name for a renamed one), drop the rest. *)
let derive_rollback ~(actor : string) (adef : actor_def) (sp : span)
    (back : (string * string) list) (old_ty : ty) : decl =
  let n s = { txt = s; span = sp } in
  let new_ty =
    TyRecord (List.map (fun (f : field) -> (n f.fld_name.txt, plain f.fld_ty)) adef.actor_state) in
  let body =
    ERecord (List.map (fun (g, f) -> (n g, EField (EVar (n rollback_param), n f, sp))) back, sp) in
  mk_fn ~name:(rollback_fn_name actor) ~param:rollback_param sp new_ty old_ty body

(** The rename suggestion (todo 2026-11-15-hcr-migrate-clause-suggestion).
    A deploy that removes exactly one field and adds exactly one of the same
    type, changing nothing else, may be a rename: (removed, added).  Only a
    guess, so the clause is offered as a fix the programmer chooses
    ([Maybe_incorrect]: an editor offers it, `forge fix --only
    migrate_rename_suggested` applies it), never applied on its own. *)
let rename_guess (adef : actor_def) (old_fields : (string * string) list) : (string * string) option =
  let str t = try Some (schema_str t) with Unrenderable -> None in
  let new_fields = List.map (fun (f : field) -> (f.fld_name.txt, str f.fld_ty)) adef.actor_state in
  let removed = List.filter (fun (f, _) -> not (List.mem_assoc f new_fields)) old_fields in
  let added = List.filter (fun (f, _) -> not (List.mem_assoc f old_fields)) new_fields in
  let changed =
    List.filter (fun (f, s) -> match List.assoc_opt f new_fields with
      | Some t -> t <> Some s | None -> false) old_fields
  in
  match removed, added, changed with
  | [ (g, s) ], [ (f, Some t) ], [] when s = t -> Some (g, f)
  | _ -> None

let clause_text ~gone ~added = Printf.sprintf "migrate old -> { %s: old.%s }" added gone

(* The last line of [e], for the expression forms an `init` is written
   with; [None] when it cannot be told, and then no edit is offered. *)
let end_line (e : expr) : int option =
  match e with
  | ERecord (_, sp) | EBlock (_, sp) | EApp (_, _, sp) | ECon (_, _, sp)
  | ERecordUpdate (_, _, sp) | ETuple (_, sp) | EIf (_, _, _, sp) | EMatch (_, _, sp) ->
    if sp.end_line > 0 then Some sp.end_line else None
  | EVar n -> if n.span.end_line > 0 then Some n.span.end_line else None
  | _ -> None

let suggest_clause errors ~(actor : name) ~(sp : span) (adef : actor_def) ~gone ~added : unit =
  let message =
    Printf.sprintf
      "`%s` removes `%s` and adds `%s` of the same type; if `%s` renames `%s`, a migrate \
       clause moves the running data: `%s`"
      actor.txt gone added added gone (clause_text ~gone ~added)
  in
  match end_line adef.actor_init with
  | Some line ->
    let indent = String.make (sp.start_col + 2) ' ' in
    Err.warning_with_fix ~tier:Err.Maybe_incorrect ~code:Err.Code.migrate_rename_suggested errors
      ~span:actor.span ~fix:(Err.FInsert { after_line = line; text = indent ^ clause_text ~gone ~added })
      message
  | None -> Err.warning ~code:Err.Code.migrate_rename_suggested errors ~span:actor.span message

(** The deployed layout of [actor], when it differs from the new one. *)
let changed_from_baseline ~(actor : string) (adef : actor_def)
  : (string * string) list option =
  match
    List.find_opt (fun (name, _) -> last_segment name = actor) !baseline
  with
  | None -> None
  | Some (_, old_fields) ->
    let now =
      List.map
        (fun (f : field) ->
          (f.fld_name.txt, try Some (schema_str f.fld_ty) with Unrenderable -> None))
        adef.actor_state
    in
    (* The schema lists fields sorted by name, whatever order they were
       declared in; compare as sets. *)
    let sorted l = List.sort compare l in
    if sorted (List.map (fun (f, t) -> (f, Some t)) old_fields) = sorted now then None
    else Some old_fields

(** [decls] with a derived `<actor>_migrate_state` after every actor that
    needs one and has none, recursing into nested modules. *)
let rec expand ?errors (decls : decl list) : decl list =
  (match errors with
   | Some errors ->
     List.iter (function DActor (_, name, adef, _) -> check_clause errors ~actor:name.txt adef | _ -> ()) decls
   | None -> ());
  if !baseline = [] then
    List.map (function DMod (nm, vis, inner, s) -> DMod (nm, vis, expand ?errors inner, s) | d -> d) decls
  else
    let written name =
      List.exists (function DFn (d, _) -> d.fn_name.txt = name | _ -> false) decls
    in
    List.concat_map
      (function
        | DActor (_, name, adef0, sp) as d ->
          (* A clause reading a field the deployed build does not have was
             written for an earlier deploy (it stays in the source after
             that deploy): warn, and derive as if it were not there. *)
          let adef =
            match clause_of adef0, List.find_opt (fun (a, _) -> last_segment a = name.txt) !baseline with
            | Some (binder, given), Some (_, deployed) ->
              (match
                 List.filter (fun f -> not (List.mem_assoc f deployed))
                   (List.sort_uniq compare (List.concat_map (fun (_, e) -> reads binder e) given))
               with
               | [] -> adef0
               | stale ->
                 (match errors, adef0.actor_migrate with
                  | Some errors, Some (b, _) ->
                    Err.warning ~code:Err.Code.migrate_clause_invalid errors ~span:b.span
                      (Printf.sprintf
                         "the migrate clause reads %s, which the deployed build's state does not \
                          have: it was written for an earlier deploy and is ignored; delete it"
                         (String.concat ", " (List.map (Printf.sprintf "`%s`") stale)))
                  | _ -> ());
                 { adef0 with actor_migrate = None })
            | _ -> adef0
          in
          (match changed_from_baseline ~actor:name.txt adef with
           | None -> [ d ]
           | Some _ when written (migrate_fn_name name.txt) -> [ d ]
           | Some old_fields ->
             (match derive ~actor:name.txt adef sp old_fields with
              | Ok r ->
                let actor = name.txt in
                report := (actor, Derived r.added) :: !report;
                let field_spans =
                  List.map (fun (f : field) -> (f.fld_name.txt, f.fld_name.span)) adef.actor_state in
                (* A field the clause gives is reported at the clause's
                   expression for it, not at its declaration. *)
                let clause_spans =
                  match adef.actor_migrate with
                  | Some (_, ERecord (fs, _)) -> List.map (fun ((n : name), _) -> (n.txt, n.span)) fs
                  | _ -> []
                in
                let spans =
                  List.map (fun (f, s) -> (f, Option.value ~default:s (List.assoc_opt f clause_spans))) field_spans in
                origins := (migrate_fn_name actor, spans) :: !origins;
                (match List.filter_map (fun (f, s) -> match s with Copy _ | Clause -> Some f | _ -> None) r.sources with
                 | [] -> ()
                 | fs when clause_of adef <> None -> clause_fields := (actor, fs) :: !clause_fields
                 | _ -> ());
                (match List.filter_map (fun (f, s) -> match s with Copy g when g <> f -> Some (f, g) | _ -> None) r.sources with
                 | [] -> ()
                 | ms when clause_of adef <> None -> moves := (actor, ms) :: !moves
                 | _ -> ());
                (* The reverse, when every deployed field came back by a bare
                   copy (an add-only derivation, a rename): not for a drop-only
                   one, which IS a rollback. *)
                let rollback =
                  match r.reverse with
                  | Some (back, old_ty) when not (written (rollback_fn_name actor)) ->
                    rollbacks := (actor, List.map fst back) :: !rollbacks;
                    (match List.filter (fun (g, f) -> g <> f) back with
                     | [] -> ()
                     | ms -> rollback_moves := (actor, ms) :: !rollback_moves);
                    origins := (rollback_fn_name actor, field_spans) :: !origins;
                    [ Desugar_derive.respan_derived_decl (derive_rollback ~actor adef sp back old_ty) ]
                  | _ -> []
                in
                d :: Desugar_derive.respan_derived_decl r.fn :: rollback
              | Error why ->
                let why =
                  match adef.actor_migrate, rename_guess adef old_fields with
                  | None, Some (gone, added) ->
                    Printf.sprintf "%s (if `%s` renames it, add `%s` to the actor)" why added
                      (clause_text ~gone ~added)
                  | _ -> why
                in
                report := (name.txt, Not_derived why) :: !report;
                (* The clause exists only to derive this migration: say why
                   it did not, at the clause, rather than first at the deploy
                   gate.  A warning, since a build need not be a deploy. *)
                (match errors, adef.actor_migrate with
                 | Some errors, Some (b, _) ->
                   Err.warning ~code:Err.Code.migrate_clause_invalid errors ~span:b.span
                     (Printf.sprintf
                        "the migrate clause does not derive `%s` against the deployed build: %s"
                        (migrate_fn_name name.txt) why)
                 | Some errors, None ->
                   (match rename_guess adef old_fields with
                    | Some (gone, added) -> suggest_clause errors ~actor:name ~sp adef ~gone ~added
                    | None -> ())
                 | None, _ -> ());
                [ d ]))
        | DMod (nm, vis, inner, s) -> [ DMod (nm, vis, expand ?errors inner, s) ]
        | d -> [ d ])
      decls
