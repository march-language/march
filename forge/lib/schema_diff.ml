(** Schema_diff — compare actor state schemas for hot-code-reload compatibility.

    Schemas are loaded from .schemas.json files emitted by the compiler alongside
    each --hot-reload --compile-so artifact.  The forge deploy hot command uses
    this module to decide whether a hot swap requires a migrate_state function and
    whether the state change is compat-policy-safe. *)

type field = { name: string; ty: string }

(** One message constructor: a handler of the actor, or a constructor of a
    migrate_msg's old type.  [params] are the schema type strings. *)
type ctor = { cname: string; params: string list }

type actor_schema = {
  compat: string;            (* "full" | "forward" | "any" *)
  invariant: string option;  (* @invariant predicate text, if any *)
  state_fields: field list;
  handlers: ctor list option;          (* DD step 6: None = an older compiler *)
  migrate_msg_from: ctor list option;  (* the old type <actor>_migrate_msg takes *)
}

let find_sub (hay : string) (needle : string) : int option =
  let hl = String.length hay and nl = String.length needle in
  let rec go i = if i + nl > hl then None
    else if String.sub hay i nl = needle then Some i else go (i + 1) in
  go 0

(** Parse a one-line constructor list as the compiler writes it:
    [[{"name":"Add","params":["Int"]}, {"name":"Show","params":[]}]]. *)
let parse_ctor_list (line : string) : ctor list =
  let len = String.length line in
  let rec go pos acc =
    match String.index_from_opt line pos '{' with
    | None -> List.rev acc
    | Some b ->
      let e = match String.index_from_opt line b '}' with Some e -> e | None -> len - 1 in
      let chunk = String.sub line b (e - b + 1) in
      let cname = match String.split_on_char '"' chunk with
        | _ :: "name" :: _ :: n :: _ -> n | _ -> "" in
      let params =
        match find_sub chunk "\"params\":[" with
        | None -> []
        | Some i ->
          let start = i + String.length "\"params\":[" in
          let stop = match String.index_from_opt chunk start ']' with
            | Some j -> j | None -> String.length chunk in
          let inner = String.sub chunk start (stop - start) in
          List.filteri (fun k _ -> k mod 2 = 1) (String.split_on_char '"' inner)
      in
      go (e + 1) (if cname = "" then acc else { cname; params } :: acc)
  in
  go 0 []

(** The deploy changed the actor's message type (D30, plan 6.3): a handler
    of the running version was removed, or takes different parameters.
    Adding a handler is not a change: old messages stay readable. *)
let messages_changed ~(old_h : ctor list) ~(new_h : ctor list) : bool =
  List.exists (fun o ->
      match List.find_opt (fun n -> n.cname = o.cname) new_h with
      | None -> true
      | Some n -> n.params <> o.params) old_h

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
    let current_handlers : ctor list option ref = ref None in
    let current_mm_from : ctor list option ref = ref None in
    let in_fields = ref false in
    let starts_with p l = String.length l >= String.length p
                          && String.sub l 0 (String.length p) = p in
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
                                 && name <> "handlers" && name <> "migrate_msg_from"
                                 && name <> "name" && name <> "ty" ->
              if !current_actor <> "" then
                schemas := (!current_actor,
                  { compat = !current_compat;
                    invariant = !current_invariant;
                    state_fields = List.rev !current_fields;
                    handlers = !current_handlers;
                    migrate_msg_from = !current_mm_from }) :: !schemas;
              current_actor := name;
              current_compat := "full";
              current_invariant := None;
              current_fields := [];
              current_handlers := None;
              current_mm_from := None
            | _ -> ())
          end;
          (* Detect "compat": "value" *)
          if llen > 10 && String.sub line 0 9 = "\"compat\":" then begin
            (match String.split_on_char '"' line with
            | _ :: "compat" :: _ :: v :: _ -> current_compat := v
            | _ -> ())
          end;
          (* Detect "invariant": "value" — extract between the first '"'
             after ':' and the last '"' on the line, so embedded characters
             written by %S (e.g. escaped operators) don't break the parse. *)
          if llen > 13 && String.sub line 0 12 = "\"invariant\":" then begin
            (try
              let after_colon = String.index line ':' + 1 in
              let first_q = String.index_from line after_colon '"' + 1 in
              let last_q  = String.rindex line '"' in
              if first_q <= last_q then
                current_invariant := Some (String.sub line first_q (last_q - first_q))
            with Not_found -> ())
          end;
          if starts_with "\"handlers\":" line then
            current_handlers := Some (parse_ctor_list line);
          if starts_with "\"migrate_msg_from\":" line then
            current_mm_from := Some (parse_ctor_list line);
          (* Detect state_fields array start; also scan for inline field entries
             on the same line (e.g. "state_fields": [{"name":"x","ty":"Y"}]) *)
          if llen >= 15 && String.sub line 0 15 = "\"state_fields\":" then begin
            in_fields := true;
            (* Scan rest of line for any {…} field objects *)
            let rec scan_for_entries pos =
              match String.index_from_opt line pos '{' with
              | None -> ()
              | Some brace ->
                (match String.split_on_char '"' (String.sub line brace (llen - brace)) with
                 | _ :: "name" :: _ :: n :: _ :: "ty" :: _ :: t :: _ when n <> "" ->
                   current_fields := { name = n; ty = t } :: !current_fields
                 | _ -> ());
                scan_for_entries (brace + 1)
            in
            scan_for_entries 0
          end;
          (* Detect field entry on its own line: {"name":"x","ty":"Int"} *)
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
          state_fields = List.rev !current_fields;
          handlers = !current_handlers;
          migrate_msg_from = !current_mm_from }) :: !schemas;
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
