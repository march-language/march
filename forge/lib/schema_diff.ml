(** Schema_diff — compare actor state schemas for hot-code-reload compatibility.

    Schemas are loaded from .schemas.json files emitted by the compiler alongside
    each --hot-reload --compile-so artifact.  The forge deploy hot command uses
    this module to decide whether a hot swap requires a migrate_state function and
    whether the state change is compat-policy-safe. *)

(** [refine]: the field's refinement as a predicate over the state's bare
    field names, as @invariant is written (`(count >= 0)`). *)
type field = { name: string; ty: string; refine: string option }

(** One message constructor: a handler of the actor, or a constructor of a
    migrate_msg's old type.  [params] are the schema type strings. *)
type ctor = { cname: string; params: string list;
              refines: string option list; tag: int option }
(** [refines]: per parameter, its refinement over the positional names
    [p0], [p1], ...; [] when none is refined (or an older compiler).
    [tag]: the constructor's actor-message heap tag in that build
    ([Llvm_toplevel.actor_msg_tag_table], keyed `<Actor>_Msg.<Ctor>`);
    [None] from a compiler that predates tag recording. *)

type actor_schema = {
  compat: string;            (* "full" | "forward" | "any" *)
  invariant: string option;  (* @invariant predicate text, if any *)
  state_fields: field list;
  handlers: ctor list option;          (* DD step 6: None = an older compiler *)
  migrate_msg_from: ctor list option;  (* the old type <actor>_migrate_msg takes *)
  contracts: bool;           (* written by a compiler that records refinements *)
  unsupported: bool;         (* a refinement or @invariant it could not write down *)
  accepted: string list;     (* laws built with --accept-unproved: "state", a handler, or "*" *)
  derived: string list option;
  (* M11: Some fields = the compiler derived this build's migrate_state from
     the deployed schema, the listed fields taking their `init` values *)
  not_derived: string option;  (* why it could not, when the state changed *)
}

(** The deploy changed the actor's message type (D30, plan 6.3): a handler
    of the running version was removed, or takes different parameters.
    Adding a handler is not a change: old messages stay readable. *)
let messages_changed ~(old_h : ctor list) ~(new_h : ctor list) : bool =
  List.exists (fun o ->
      match List.find_opt (fun n -> n.cname = o.cname) new_h with
      | None -> true
      | Some n -> n.params <> o.params) old_h

(** [migrate_msg_from] names exactly the running version's handlers [old_h]:
    the same constructors with the same parameters (and refinements). The
    recorded tags are left out: whether they agree is the tag check's
    question ({!tag_check}), and a baseline from before tag recording must
    not read as a different message type. *)
let same_message_type (from : ctor list) (old_h : ctor list) : bool =
  let untagged = List.map (fun c -> { c with tag = None }) in
  untagged from = untagged old_h

(** H7, tag consistency at deploy (design
    specs/2026-11-04-lemmas-hcr-actors-choreography-design.md §3.4). A message
    is a heap cell whose constructor tag the SENDER's build chose, and the
    receiver's new build reads it. The tag is a stable function of the
    qualified constructor name, except that a key whose hash slot is taken
    probes upward, so two colliding keys can give one constructor different
    tags in two builds (which other keys are in the build decides it). *)
type tag_finding =
  | Tag_moved of { ctor : string; old_tag : int; new_tag : int }
  | Tags_unrecorded of string   (* why the tags could not be compared *)
  | Tags_agree of int           (* this many constructors compared, all equal *)

(** Compare the tags of every constructor both versions of one actor name:
    the running version's handlers [old_s] against the new build's handlers
    and its migrate_msg's old type (which takes the actor's tags by name).
    A pair where either side recorded no tag is reported once, as
    [Tags_unrecorded], never skipped silently. *)
let tag_check ~(old_s : actor_schema) ~(new_s : actor_schema) : tag_finding list =
  let new_ctors =
    Option.value ~default:[] new_s.handlers @ Option.value ~default:[] new_s.migrate_msg_from in
  match old_s.handlers with
  | None ->
    if new_ctors = [] then []
    else [ Tags_unrecorded "the running version's schema predates handler recording, \
                            so its actor-message tags are unknown" ]
  | Some old_h ->
    let pairs = List.filter_map (fun (o : ctor) ->
        Option.map (fun n -> (o, n)) (List.find_opt (fun (n : ctor) -> n.cname = o.cname) new_ctors))
        old_h in
    let moved = List.filter_map (fun ((o : ctor), (n : ctor)) ->
        match o.tag, n.tag with
        | Some ot, Some nt when ot <> nt -> Some (Tag_moved { ctor = o.cname; old_tag = ot; new_tag = nt })
        | _ -> None) pairs in
    let old_missing = List.exists (fun ((o : ctor), _) -> o.tag = None) pairs in
    let new_missing = List.exists (fun (_, (n : ctor)) -> n.tag = None) pairs in
    moved
    @ (if old_missing then
         [ Tags_unrecorded "the running version's schema predates actor-message tag \
                            recording, so a tag moved by a hash-collision probe cannot \
                            be detected" ]
       else if new_missing then
         [ Tags_unrecorded "this build's schema records no actor-message tags" ]
       else if moved = [] && pairs <> [] then [ Tags_agree (List.length pairs) ]
       else [])

(** The refusal text for a moved tag, the same in forge and
    `march --check-migration`. *)
let tag_moved_message ~(actor : string) ~ctor ~old_tag ~new_tag : string =
  Printf.sprintf
    "%s.%s's actor-message tag moved: the running version tags it 0x%08x, this build \
     0x%08x. Tags are a hash of the qualified name %s_Msg.%s, and a name whose hash \
     slot another constructor holds probes to the next free one, so a hash collision \
     in one of the two builds moved it; a message the running version built would be \
     read as another constructor or dropped. A restart deploys it safely; a hot \
     deploy cannot."
    actor ctor old_tag new_tag actor ctor

(** The laws of [laws] ("Actor.law" or "Actor") that the new build's
    schemas do not carry in [accepted_unproved].  forge deploys an override
    only when the patch carries it, because the signed image is what the
    server's audit line copies. *)
let unembedded_overrides (schemas : (string * actor_schema) list) (laws : string list)
  : string list =
  List.filter (fun law ->
      let actor, rest = match String.index_opt law '.' with
        | Some i -> String.sub law 0 i, String.sub law (i + 1) (String.length law - i - 1)
        | None -> law, "*" in
      match List.assoc_opt actor schemas with
      | Some s -> not (List.mem rest s.accepted || List.mem "*" s.accepted)
      | None -> true) laws

type field_change =
  | FieldAdded   of field
  | FieldRemoved of field
  | FieldTypeChanged of { name: string; old_ty: string; new_ty: string }

type actor_diff = {
  actor: string;
  changes: field_change list;
}

(** Decode both compiler sidecars and compact server responses. Malformed metadata
    is an error, never an empty baseline. *)
let parse_schemas_json (json : Yojson.Safe.t) : (string * actor_schema) list =
  let open Yojson.Safe.Util in
  let ctors value = value |> to_list |> List.map (fun c ->
      { cname = c |> member "name" |> to_string;
        params = c |> member "params" |> to_list |> List.map to_string;
        refines = (match member "refines" c with
            | `Null -> []
            | v -> v |> to_list |> List.map to_string_option);
        tag = (match member "tag" c with `Int t -> Some t | _ -> None) }) in
  let flag key j = match member key j with `Bool b -> b | _ -> false in
  let optional key decode j = match member key j with
    | `Null -> None | value -> Some (decode value) in
  json |> to_assoc |> List.map (fun (actor, j) ->
      let compat = match member "compat" j with
        | `Null -> "full" | v -> to_string v in
      let state_fields = member "state_fields" j |> to_list |> List.map (fun f ->
          { name = f |> member "name" |> to_string;
            ty = f |> member "ty" |> to_string;
            refine = f |> member "refine" |> to_string_option }) in
      actor, { compat; state_fields;
               invariant = optional "invariant" to_string j;
               handlers = optional "handlers" ctors j;
               migrate_msg_from = optional "migrate_msg_from" ctors j;
               contracts = (match member "contracts" j with `Null -> false | _ -> true);
               unsupported = flag "refine_unsupported" j || flag "invariant_unsupported" j;
               accepted = (match member "accepted_unproved" j with
                   | `Null -> [] | v -> v |> to_list |> List.map to_string);
               derived = optional "migrate_derived"
                   (fun v -> v |> to_list |> List.map to_string) j;
               not_derived = optional "migrate_not_derived" to_string j })

let parse_schemas_file path =
  if not (Sys.file_exists path) then []
  else
    try parse_schemas_json (Yojson.Safe.from_file path) with
    | Yojson.Json_error m | Sys_error m -> failwith ("invalid schema file " ^ path ^ ": " ^ m)
    | Yojson.Safe.Util.Type_error (m, _) -> failwith ("invalid schema file " ^ path ^ ": " ^ m)

(** Diff old and new schemas for a single actor.  Returns the list of changes. *)
let diff_actor (old_s : actor_schema) (new_s : actor_schema) : field_change list =
  let old_map = List.map (fun f -> (f.name, f.ty)) old_s.state_fields in
  let new_map = List.map (fun f -> (f.name, f.ty)) new_s.state_fields in
  let removed = List.filter_map (fun f ->
      if not (List.mem_assoc f.name new_map) then Some (FieldRemoved f)
      else None) old_s.state_fields in
  let added = List.filter_map (fun f ->
      if not (List.mem_assoc f.name old_map) then Some (FieldAdded f)
      else None) new_s.state_fields in
  let changed = List.filter_map (fun (name, old_ty) ->
      match List.assoc_opt name new_map with
      | Some new_ty when new_ty <> old_ty ->
        Some (FieldTypeChanged { name; old_ty; new_ty })
      | _ -> None) old_map in
  removed @ added @ changed

(** Check whether [changes] are compatible with [compat_policy].
    Returns [Ok ()] or [Error msg] where msg explains the violation. *)
let check_compat (compat : string) (changes : field_change list) : (unit, string) result =
  if changes = [] then Ok ()
  else match compat with
  | "any" -> Ok ()
  | "forward" ->
    let bad = List.filter (function
        | FieldAdded _ -> false
        | FieldRemoved _ | FieldTypeChanged _ -> true) changes in
    if bad = [] then Ok ()
    else
      let desc = List.filter_map (function
          | FieldRemoved f -> Some (Printf.sprintf "field removed: %s" f.name)
          | FieldTypeChanged c ->
            Some (Printf.sprintf "type changed: %s (%s → %s)" c.name c.old_ty c.new_ty)
          | FieldAdded _ -> None) bad in
      Error (Printf.sprintf "@compat(forward) violated: %s" (String.concat ", " desc))
  | _ (* "full" default *) ->
    let desc = List.map (function
        | FieldAdded f -> Printf.sprintf "field added: %s : %s" f.name f.ty
        | FieldRemoved f -> Printf.sprintf "field removed: %s" f.name
        | FieldTypeChanged c ->
          Printf.sprintf "type changed: %s (%s → %s)" c.name c.old_ty c.new_ty)
      changes in
    Error (Printf.sprintf "@compat(full) violated: %s — provide migrate_state or add @compat(any)"
             (String.concat ", " desc))

(** What to add to a refusal for a missing migrate_state: why the compiler
    did not derive one, when the new build's schema says. *)
let not_derived_note (new_schemas : (string * actor_schema) list) (actor : string) : string =
  match List.assoc_opt actor new_schemas with
  | Some { not_derived = Some why; _ } -> Printf.sprintf " (not derived: %s)" why
  | _ -> ""

(** The line announcing a derived migration, when [actor]'s was. *)
let derived_note (new_schemas : (string * actor_schema) list) (actor : string) : string option =
  match List.assoc_opt actor new_schemas with
  | Some { derived = Some added; _ } ->
    Some (Printf.sprintf "actor %s: migrate_state derived from the running version's state (%s)"
            actor
            (match added with
             | [] -> "every field kept"
             | fs -> "adds " ^ String.concat ", " fs ^ " from init"))
  | _ -> None

(** Compute diffs for all actors appearing in both old and new schemas. *)
let diff_schemas
    (old_schemas : (string * actor_schema) list)
    (new_schemas : (string * actor_schema) list) : actor_diff list =
  List.filter_map (fun (actor, new_s) ->
      match List.assoc_opt actor old_schemas with
      | None -> None
      | Some old_s ->
        let changes = diff_actor old_s new_s in
        if changes = [] then None
        else Some { actor; changes }
    ) new_schemas

(** Returns true if changes require a migrate_state function to be present. *)
let requires_migration (changes : field_change list) : bool =
  changes <> []
