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

let derive ~(actor : string) (adef : actor_def) (sp : span)
    (old_fields : (string * string) list) : (decl * string list, string) result =
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
  if removed <> [] then Error ("it removes " ^ names removed)
  else if changed <> [] then Error ("it changes the type of " ^ names changed)
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
    match List.filter (fun (f, _) -> default f = None) added with
    | _ :: _ as bad ->
      Error ("the `init` value of " ^ names bad ^ " is not a constant")
    | [] ->
      let n s = { txt = s; span = sp } in
      let old_ty =
        TyRecord
          (List.map (fun (f, _) -> (n f, plain (List.assoc f new_fields))) old_fields)
      in
      let new_ty = TyRecord (List.map (fun (f, t) -> (n f, plain t)) new_fields) in
      let body =
        ERecord
          ( List.map
              (fun (f, _) ->
                ( n f,
                  if List.mem_assoc f old_fields then EField (EVar (n param_name), n f, sp)
                  else Option.get (default f) ))
              new_fields,
            sp )
      in
      let def =
        { fn_name = n (migrate_fn_name actor);
          fn_vis = Public;
          fn_doc = None;
          fn_attrs = [];
          fn_ret_ty = Some new_ty;
          fn_clauses =
            [ { fc_params =
                  [ FPNamed
                      { param_name = n param_name; param_ty = Some old_ty;
                        param_lin = Unrestricted } ];
                fc_guard = None; fc_body = body; fc_span = sp; fc_params_span = sp } ];
          fn_bounds = []; fn_attr_args = []; fn_needs = None }
      in
      Ok (DFn (def, sp), List.map fst added)

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
let rec expand (decls : decl list) : decl list =
  if !baseline = [] then decls
  else
    let written name =
      List.exists (function DFn (d, _) -> d.fn_name.txt = name | _ -> false) decls
    in
    List.concat_map
      (function
        | DActor (_, name, adef, sp) as d ->
          (match changed_from_baseline ~actor:name.txt adef with
           | None -> [ d ]
           | Some _ when written (migrate_fn_name name.txt) -> [ d ]
           | Some old_fields ->
             (match derive ~actor:name.txt adef sp old_fields with
              | Ok (fn, added) ->
                report := (name.txt, Derived added) :: !report;
                origins :=
                  ( migrate_fn_name name.txt,
                    List.map (fun (f : field) -> (f.fld_name.txt, f.fld_name.span))
                      adef.actor_state )
                  :: !origins;
                [ d; Desugar_derive.respan_derived_decl fn ]
              | Error why ->
                report := (name.txt, Not_derived why) :: !report;
                [ d ]))
        | DMod (nm, vis, inner, s) -> [ DMod (nm, vis, expand inner, s) ]
        | d -> [ d ])
      decls
