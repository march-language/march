(** [forge observe]: one request to a node's observe socket, its reply
    envelope printed as JSON (R1.4 of
    specs/plans/2026-09-28-observe-recon-shell-plan.md; the TUI is R7).

    Targets, in order: [--socket PATH] (a local observe socket, as set by
    MARCH_OBSERVE_SOCKET), else the forge.toml [hot-reload] hosts ([--env]
    picks the [[hot-reload.env]] entries of that name, as for
    [forge hot-reload status]), reached over ssh at ["<reload socket>.observe"].

    The request is the positional words ([ACTORS mbox 20], [ACTOR 42], ...),
    or [SNAPSHOT] with the [--section]s given, or [SNAPSHOT] alone. *)

(** The request line: explicit words win; otherwise SNAPSHOT, narrowed by
    any sections. *)
let request_of ~(words : string list) ~(sections : string list) : (string, string) result =
  match words, sections with
  | [], [] -> Ok "SNAPSHOT"
  | [], ss -> Ok ("SNAPSHOT " ^ String.concat "," ss)
  | w :: _ as ws, [] -> Ok (String.concat " " (String.uppercase_ascii w :: List.tl ws))
  | _ :: _, _ :: _ -> Error "observe: give a request or --section, not both"

(** The hosts [forge observe] queries for this project, optionally only the
    [[hot-reload.env]] entries named [env]. *)
let hosts_of (hr : Project.hot_reload_config) ~(env : string) : (Hosts.host list, string) result =
  let all =
    if hr.Project.hr_envs <> [] then List.map Hosts.of_hot_reload_env hr.Project.hr_envs
    else Option.to_list (Hosts.of_flat_config hr)
  in
  let picked = if env = "" then all else List.filter (fun h -> h.Hosts.name = env) all in
  match picked with
  | [] when env <> "" -> Error (Printf.sprintf "observe: no [[hot-reload.env]] named %s" env)
  | [] -> Error "observe: no host to observe: give --socket, or set [hot-reload] ssh_host in forge.toml"
  | hs -> Ok hs

let print_reply ~json (reply : Yojson.Safe.t) =
  print_endline (if json then Yojson.Safe.to_string reply else Yojson.Safe.pretty_to_string reply)

(** Run one request; every target's reply is printed (one line each with
    [~json]).  The result is an error if any target failed. *)
let run ~(socket : string option) ~(env : string) ~(json : bool)
    ~(words : string list) ~(sections : string list) () : (unit, string) result =
  match request_of ~words ~sections with
  | Error _ as e -> e
  | Ok request ->
    match socket with
    | Some path ->
      Result.map (print_reply ~json) (Observe_client.query_socket path request)
    | None ->
      match Project.load () with
      | Error m -> Error m
      | Ok proj ->
        match proj.Project.hot_reload with
        | None -> Error "observe: no host to observe: give --socket, or add a [hot-reload] section to forge.toml"
        | Some hr ->
          match hosts_of hr ~env with
          | Error _ as e -> e
          | Ok hosts ->
            let failures = List.filter_map (fun h ->
                match Observe_client.query Remote.ssh h request with
                | Ok reply -> print_reply ~json reply; None
                | Error m -> Some (h.Hosts.name ^ ": " ^ m)) hosts
            in
            if failures = [] then Ok () else Error (String.concat "; " failures)
