(** Workspace support for forge: multi-member project roots. *)

(** Extract the [workspace].members list from a parsed forge.toml document.
    Returns [] when there is no [workspace] section or no members key. *)
let parse_members doc =
  let ws = Toml.get_section doc "workspace" in
  Toml.get_string_list ws "members"

(** Walk up from [start_dir] looking for a forge.toml with a [workspace]
    section.  Returns [Some root_dir] if found, [None] otherwise. *)
let find_root start_dir =
  let rec walk dir =
    let candidate = Filename.concat dir "forge.toml" in
    if Sys.file_exists candidate then begin
      let text = In_channel.with_open_text candidate (fun ic -> In_channel.input_all ic) in
      let doc  = Toml.parse text in
      let ws   = Toml.get_section doc "workspace" in
      if ws <> [] then Some dir
      else begin
        let parent = Filename.dirname dir in
        if parent = dir then None else walk parent
      end
    end else begin
      let parent = Filename.dirname dir in
      if parent = dir then None else walk parent
    end
  in
  walk start_dir

(** [members_from_root root] loads the member list from [root/forge.toml]. *)
let members_from_root root =
  let path = Filename.concat root "forge.toml" in
  if not (Sys.file_exists path) then []
  else begin
    let text = In_channel.with_open_text path (fun ic -> In_channel.input_all ic) in
    parse_members (Toml.parse text)
  end

(** Run [command] in [dir], restoring the cwd afterward. *)
let run_in_dir dir command =
  let old_cwd = Sys.getcwd () in
  Unix.chdir dir;
  Fun.protect ~finally:(fun () -> Unix.chdir old_cwd) command

(** Run [command ()] for each workspace member in [members] under [root].
    Aggregates all errors; returns Ok () iff all succeed. *)
let run_for_members ~root ~members ~package command =
  let targets = match package with
    | Some p -> if List.mem p members then [p]
                else [ (* not a member name — treat as a direct path *) p ]
    | None   -> members
  in
  let errors = List.filter_map (fun member ->
      let member_dir =
        if Filename.is_relative member then Filename.concat root member
        else member
      in
      if not (Sys.file_exists member_dir) then
        Some (Printf.sprintf "member '%s' not found at %s" member member_dir)
      else
        match run_in_dir member_dir command with
        | Ok ()   -> None
        | Error m -> Some (Printf.sprintf "[%s] %s" member m)
    ) targets
  in
  if errors = [] then Ok ()
  else Error (String.concat "\n" errors)
