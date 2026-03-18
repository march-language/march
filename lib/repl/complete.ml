(** Tab completion engine for the March REPL.
    Context-aware: commands, keywords, scope names, type names, constructors. *)

let repl_commands = [":quit"; ":q"; ":env"; ":help"; ":type"; ":clear"; ":reset"; ":load"; ":save"]

let keywords = [
  "fn"; "do"; "end"; "let"; "match"; "with"; "if"; "then"; "else";
  "mod"; "actor"; "type"; "pub"; "use"; "impl"; "interface"; "sig";
  "spawn"; "send"; "on"; "state"; "init"; "respond"; "when"; "as";
  "linear"; "affine"; "extern"; "loop"; "protocol"; "unsafe"
]

let starts_with prefix s =
  let pl = String.length prefix and sl = String.length s in
  pl <= sl && String.sub s 0 pl = prefix

(** [complete prefix scope] returns completions for [prefix].
    [scope] is a list of [(name, type_str)] from the current environment. *)
let complete prefix scope =
  if String.length prefix > 0 && prefix.[0] = ':' then
    List.filter (starts_with prefix) repl_commands
  else
    let kw_matches    = List.filter (starts_with prefix) keywords in
    let scope_matches = List.filter_map (fun (name, _ty) ->
      if starts_with prefix name then Some name else None
    ) scope in
    let seen = Hashtbl.create 16 in
    List.filter (fun s ->
      if Hashtbl.mem seen s then false
      else (Hashtbl.add seen s (); true)
    ) (scope_matches @ kw_matches)
