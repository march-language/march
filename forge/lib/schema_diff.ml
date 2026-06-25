(** Schema_diff — compare actor state schemas for hot-code-reload compatibility.

    Schemas are loaded from .schemas.json files emitted by the compiler alongside
    each --hot-reload --compile-so artifact.  The forge deploy hot command uses
    this module to decide whether a hot swap requires a migrate_state function and
    whether the state change is compat-policy-safe. *)

type field = { name: string; ty: string }

type actor_schema = {
  compat: string;            (* "full" | "forward" | "any" *)
  invariant: string option;  (* @invariant predicate text, if any *)
  state_fields: field list;
}

type field_change =
  | FieldAdded   of field
  | FieldRemoved of field
  | FieldTypeChanged of { name: string; old_ty: string; new_ty: string }

type actor_diff = {
  actor: string;
  changes: field_change list;
}

(** Parse a .schemas.json file.  Returns an association list from actor name to
    schema.  Returns [] when the file does not exist (first deploy) or is
    unreadable. *)
let parse_schemas_file (path : string) : (string * actor_schema) list =
  if not (Sys.file_exists path) then []
  else begin
    let ic = open_in path in
    let content = In_channel.input_all ic in
    close_in ic;
    let schemas = ref [] in
    let current_actor = ref "" in
    let current_compat = ref "full" in
    let current_invariant : string option ref = ref None in
    let current_fields : field list ref = ref [] in
    let in_fields = ref false in
    List.iter (fun line ->
        let line = String.trim line in
        let llen = String.length line in
        if llen = 0 then ()
        else begin
          (* Detect actor key: "ActorName": { — first char is '"', not in a fields array *)
          if line.[0] = '"' && not !in_fields then begin
            (match String.split_on_char '"' line with
            | "" :: name :: _ when name <> "compat" && name <> "invariant"
                                 && name <> "state_fields"
                                 && name <> "name" && name <> "ty" ->
              if !current_actor <> "" then
                schemas := (!current_actor,
                  { compat = !current_compat;
                    invariant = !current_invariant;
                    state_fields = List.rev !current_fields }) :: !schemas;
              current_actor := name;
              current_compat := "full";
              current_invariant := None;
              current_fields := []
            | _ -> ())
          end;
          (* Detect "compat": "value" *)
          if llen > 10 && String.sub line 0 9 = "\"compat\":" then begin
            (match String.split_on_char '"' line with
            | _ :: "compat" :: _ :: v :: _ -> current_compat := v
            | _ -> ())
          end;
          (* Detect "invariant": "value" *)
          if llen > 13 && String.sub line 0 12 = "\"invariant\":" then begin
            (* The value is a JSON string; extract between the first pair of
               quotes after the colon.  Split on '"' gives:
               ["\"invariant\": "; ""; " "; "<value>"; ...] *)
            (match String.split_on_char '"' line with
            | _ :: "invariant" :: _ :: v :: _ -> current_invariant := Some v
            | _ -> ())
          end;
          (* Detect state_fields array start *)
          if llen >= 15 && String.sub line 0 15 = "\"state_fields\":" then
            in_fields := true;
          (* Detect field entry: {"name":"x","ty":"Int"} *)
          if !in_fields && llen > 0 && line.[0] = '{' then begin
            (match String.split_on_char '"' line with
            | _ :: "name" :: _ :: n :: _ :: "ty" :: _ :: t :: _ when n <> "" ->
              current_fields := { name = n; ty = t } :: !current_fields
            | _ -> ())
          end;
          (* Detect end of fields array *)
          if !in_fields && (line = "]" || (llen > 0 && line.[llen - 1] = ']')) then
            in_fields := false
        end
      ) (String.split_on_char '\n' content);
    if !current_actor <> "" then
      schemas := (!current_actor,
        { compat = !current_compat;
          invariant = !current_invariant;
          state_fields = List.rev !current_fields }) :: !schemas;
    List.rev !schemas
  end

(** Diff old and new schemas for a single actor.  Returns the list of changes. *)
let diff_actor (old_s : actor_schema) (new_s : actor_schema) : field_change list =
  let old_map = List.map (fun f -> (f.name, f.ty)) old_s.state_fields in
  let new_map = List.map (fun f -> (f.name, f.ty)) new_s.state_fields in
  let removed = List.filter_map (fun (name, ty) ->
      if not (List.mem_assoc name new_map) then Some (FieldRemoved { name; ty })
      else None) old_map in
  let added = List.filter_map (fun (name, ty) ->
      if not (List.mem_assoc name old_map) then Some (FieldAdded { name; ty })
      else None) new_map in
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
