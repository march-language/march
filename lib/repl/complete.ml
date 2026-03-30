(** Tab completion engine for the March REPL.
    Context-aware: commands, keywords, scope names, type names, constructors,
    and qualified module members (e.g. Map.get, Result.Ok). *)

let repl_commands = [":quit"; ":q"; ":env"; ":help"; ":type"; ":inspect"; ":i"; ":clear"; ":reset"; ":load"; ":reload"; ":doc"; ":set"; ":save"]

let keywords = [
  "fn"; "do"; "end"; "let"; "match"; "with"; "if"; "then"; "else";
  "mod"; "actor"; "type"; "pub"; "use"; "impl"; "interface"; "sig";
  "spawn"; "send"; "on"; "state"; "init"; "respond"; "when"; "as";
  "linear"; "affine"; "extern"; "loop"; "protocol"; "unsafe"
]

let starts_with prefix s =
  let pl = String.length prefix and sl = String.length s in
  pl <= sl && String.sub s 0 pl = prefix

(** Collect known module names from the scope (entries containing dots)
    and from stdlib files on disk. *)
let known_module_names scope =
  let from_scope = List.filter_map (fun (name, _) ->
    match String.index_opt name '.' with
    | Some i -> Some (String.sub name 0 i)
    | None -> None
  ) scope in
  let from_stdlib = match March_modules.Module_registry.find_stdlib_dir () with
    | None -> []
    | Some dir ->
      (try
         Array.to_list (Sys.readdir dir)
         |> List.filter_map (fun entry ->
           if Filename.check_suffix entry ".march" then
             let base = Filename.chop_suffix entry ".march" in
             let parts = String.split_on_char '_' base in
             Some (String.concat "" (List.map String.capitalize_ascii parts))
           else None)
       with _ -> [])
  in
  let seen = Hashtbl.create 32 in
  List.filter (fun s ->
    if Hashtbl.mem seen s then false
    else (Hashtbl.add seen s (); true)
  ) (from_scope @ from_stdlib)

(** Complete qualified names: when prefix is "Mod." or "Mod.ge", suggest
    public exports of the module. *)
let complete_qualified prefix scope =
  match String.index_opt prefix '.' with
  | None -> []
  | Some dot_pos ->
    let mod_name = String.sub prefix 0 dot_pos in
    let member_prefix = String.sub prefix (dot_pos + 1) (String.length prefix - dot_pos - 1) in
    (* First check scope for "Mod.member" entries *)
    let from_scope = List.filter_map (fun (name, _) ->
      if starts_with prefix name then Some name else None
    ) scope in
    (* Then check module registry *)
    let from_registry = match March_modules.Module_registry.ensure_loaded mod_name with
      | None -> []
      | Some exports ->
        let open March_modules.Module_registry in
        List.filter_map (fun entry ->
          if entry.ex_public && starts_with member_prefix entry.ex_name then
            Some (mod_name ^ "." ^ entry.ex_name)
          else None
        ) exports.me_entries
    in
    let seen = Hashtbl.create 16 in
    List.filter (fun s ->
      if Hashtbl.mem seen s then false
      else (Hashtbl.add seen s (); true)
    ) (from_scope @ from_registry)

(** [complete prefix scope] returns completions for [prefix].
    [scope] is a list of [(name, type_str)] from the current environment. *)
let complete prefix scope =
  if String.length prefix > 0 && prefix.[0] = ':' then
    List.filter (starts_with prefix) repl_commands
  else if String.contains prefix '.' then
    (* Qualified completion: "Map.ge" → ["Map.get"] *)
    complete_qualified prefix scope
  else
    let kw_matches    = List.filter (starts_with prefix) keywords in
    let scope_matches = List.filter_map (fun (name, _ty) ->
      if starts_with prefix name then Some name else None
    ) scope in
    (* Also suggest module names when prefix starts uppercase *)
    let mod_matches =
      if String.length prefix > 0 && prefix.[0] >= 'A' && prefix.[0] <= 'Z' then
        List.filter_map (fun mod_name ->
          if starts_with prefix mod_name then Some (mod_name ^ ".") else None
        ) (known_module_names scope)
      else []
    in
    let seen = Hashtbl.create 16 in
    List.filter (fun s ->
      if Hashtbl.mem seen s then false
      else (Hashtbl.add seen s (); true)
    ) (scope_matches @ mod_matches @ kw_matches)
