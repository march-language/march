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

(** A debug request ([--state], [--crashes-full]): signed with the deploy
    key, so it is built here rather than taken from the positional words. *)
type debug = No_debug | State of { pid : int; timeout_ms : int } | Crashes_full of int option

(** The longest [--state --timeout-ms] forge allows: the client reads the
    reply with a 10 s socket timeout ([Remote.connect_with_timeout]), so a
    node waiting its own maximum of 10 s would answer just after forge gave
    up, and the user would see a socket error instead of ["timeout"]. *)
let max_state_timeout_ms = 8000

let debug_request (d : debug) : (string option, string) result =
  match d with
  | No_debug -> Ok None
  | State { timeout_ms; _ } when timeout_ms < 0 || timeout_ms > max_state_timeout_ms ->
    Error (Printf.sprintf
             "observe: --timeout-ms must be between 0 and %d (forge waits at most 10 s for a reply)"
             max_state_timeout_ms)
  | State _ | Crashes_full _ ->
    match Cmd_hot_reload.read_sk_raw () with
    | Error m -> Error ("observe: " ^ m)
    | Ok sk ->
      let now_ms = int_of_float (Unix.gettimeofday () *. 1000.) in
      let nonce = Observe_client.fresh_nonce () in
      let verb, fields = match d with
        | State { pid; timeout_ms } ->
          "STATE", [ Printf.sprintf "pid:%d" pid; Printf.sprintf "timeout_ms:%d" timeout_ms ]
        | Crashes_full n ->
          "CRASHES_FULL", (match n with Some n -> [ Printf.sprintf "n:%d" n ] | None -> [])
        | No_debug -> assert false in
      Ok (Some (Observe_client.signed_request ~sk ~nonce ~now_ms verb fields))

(** Run one request; every target's reply is printed (one line each with
    [~json]).  The result is an error if any target failed. *)
let run ?(debug = No_debug) ~(socket : string option) ~(env : string) ~(json : bool)
    ~(words : string list) ~(sections : string list) () : (unit, string) result =
  let request =
    match debug_request debug with
    | Error _ as e -> e
    | Ok (Some _) when words <> [] || sections <> [] ->
      Error "observe: give --state or --crashes-full alone, without a request or --section"
    | Ok (Some r) -> Ok r
    | Ok None -> request_of ~words ~sections in
  let explain = if debug = No_debug then Fun.id else Observe_client.explain_debug_error in
  match request with
  | Error _ as e -> e
  | Ok request ->
    match socket with
    | Some path ->
      Result.map (print_reply ~json) (Observe_client.query_socket path request)
      |> Result.map_error explain
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
                | Error m -> Some (h.Hosts.name ^ ": " ^ explain m)) hosts
            in
            if failures = [] then Ok () else Error (String.concat "; " failures)

(* ── forge diagnose ──────────────────────────────────────────────────── *)

(** [forge diagnose]: two SNAPSHOTs [window_ms] apart from each target, the
    findings of [Diagnose] over them, the [march.diagnose/1] envelope printed
    per target. Returns the exit code: 0 nothing found, 1 warnings, 2 a
    critical finding, 3 a target could not be reached (the worst over all
    targets). [dump] writes the raw before/after pair (the fixture format of
    forge/test/fixtures/diagnose) for the first target. *)
let run_diagnose ~(socket : string option) ~(env : string) ~(json : bool)
    ~(window_ms : int) ~(dump : string option) () : int =
  let targets : (string * (string -> (Yojson.Safe.t, string) result)) list =
    match socket with
    | Some path -> [ (path, Observe_client.query_socket path) ]
    | None ->
      match Project.load () with
      | Error m -> Printf.eprintf "error: %s\n%!" m; []
      | Ok proj ->
        match proj.Project.hot_reload with
        | None -> Printf.eprintf "error: no host: give --socket, or add a [hot-reload] section\n%!"; []
        | Some hr ->
          match hosts_of hr ~env with
          | Error m -> Printf.eprintf "error: %s\n%!" m; []
          | Ok hs -> List.map (fun h -> (h.Hosts.name, Observe_client.query Remote.ssh h)) hs
  in
  if targets = [] then 3
  else
    let dumped = ref false in
    List.fold_left (fun worst (name, ask) ->
        let code =
          match ask "SNAPSHOT" with
          | Error m -> Printf.eprintf "%s: %s\n%!" name m; 3
          | Ok before ->
            Unix.sleepf (float_of_int window_ms /. 1000.);
            match ask "SNAPSHOT" with
            | Error m -> Printf.eprintf "%s: %s\n%!" name m; 3
            | Ok after ->
              (match dump with
               | Some file when not !dumped ->
                 dumped := true;
                 Yojson.Safe.to_file file (`Assoc [ "before", before; "after", after ])
               | _ -> ());
              let fs = Diagnose.run ~before ~after in
              let node = match after with
                | `Assoc kv -> (match List.assoc_opt "node" kv with Some (`String n) -> n | _ -> name)
                | _ -> name in
              print_reply ~json (Diagnose.to_json ~node ~window_ms ~before ~after fs);
              Diagnose.exit_code fs
        in
        max worst code) 0 targets

(* ── forge top and forge status ──────────────────────────────────────── *)

let jm k = function `Assoc kv -> (match List.assoc_opt k kv with Some v -> v | None -> `Null) | _ -> `Null
let ji = function `Int n -> n | `Float f -> int_of_float f | _ -> 0
let jl = function `List xs -> xs | _ -> []
let js = function `String s -> s | _ -> ""

(** A node's one-line figures from a [SNAPSHOT mem,sched,crashes,actors]
    data object: what [forge status] prints and [forge top]'s header shows. *)
type summary = {
  actors : int;
  queued : int;
  rss_mb : int option;
  utilisation : float option;   (** lifetime, all schedulers *)
  crashes_hour : int;
  deepest : (int * string * int) option;  (** pid, name or type, waiting *)
}

let summary_of (data : Yojson.Safe.t) ~(now_ms : int) : summary =
  let mem = jm "mem" data and sched = jm "sched" data in
  let crashes = jl (jm "crashes" (jm "crashes" data)) in
  let rows = jl (jm "actors" (jm "actors" data)) in
  let waiting r = ji (jm "mbox" r) + ji (jm "held" r) in
  let label r = match jl (jm "names" r) with
    | `String n :: _ -> n
    | _ -> (match jm "type" r with `String t -> t | _ -> "?") in
  let deepest = List.fold_left (fun acc r ->
      match acc with
      | Some (_, _, w) when w >= waiting r -> acc
      | _ when waiting r = 0 -> acc
      | _ -> Some (ji (jm "pid" r), label r, waiting r)) None rows in
  { actors = ji (jm "actors" mem);
    queued = ji (jm "queued_messages" mem);
    rss_mb = (match jm "rss_bytes" mem with `Null -> None | v -> Some (ji v / 1_048_576));
    utilisation = (match jm "lifetime_utilisation" sched with
        | `Float f -> Some f | `Int n -> Some (float_of_int n) | _ -> None);
    crashes_hour = List.length (List.filter (fun e ->
        now_ms - ji (jm "at_ms" e) <= 3_600_000) crashes);
    deepest }

let summary_line (s : summary) : string =
  Printf.sprintf "actors %d, queued %d%s%s, crashes (1h) %d%s"
    s.actors s.queued
    (match s.rss_mb with Some m -> Printf.sprintf ", rss %d MB" m | None -> "")
    (match s.utilisation with Some u -> Printf.sprintf ", busy %.0f%%" (100. *. u) | None -> "")
    s.crashes_hour
    (match s.deepest with
     | Some (pid, name, w) -> Printf.sprintf ", deepest mailbox %s (pid %d) %d" name pid w
     | None -> "")

let summary_json (s : summary) : Yojson.Safe.t =
  `Assoc [
    "actors", `Int s.actors; "queued", `Int s.queued;
    "rss_mb", (match s.rss_mb with Some m -> `Int m | None -> `Null);
    "utilisation", (match s.utilisation with Some u -> `Float u | None -> `Null);
    "crashes_hour", `Int s.crashes_hour;
    "deepest", (match s.deepest with
        | Some (pid, name, w) -> `Assoc [ "pid", `Int pid; "name", `String name; "waiting", `Int w ]
        | None -> `Null);
  ]

let summary_request = "SNAPSHOT mem,sched,crashes,actors"

let reply_summary (reply : Yojson.Safe.t) : summary =
  summary_of (Observe_client.data_of reply) ~now_ms:(ji (jm "at_ms" reply))

(** One [forge top] frame from a [TOP] reply and a summary. *)
let render_top ~(node : string) ~(sort : string) ~(window_ms : int option)
    (s : summary) (top : Yojson.Safe.t) : string =
  let b = Buffer.create 2048 in
  Printf.bprintf b "%s  %s\n" node (summary_line s);
  Printf.bprintf b "sorted by %s%s\n\n" sort
    (match window_ms with Some w -> Printf.sprintf " over %d ms" w | None -> "");
  Printf.bprintf b "%8s  %-20s %-18s %-9s %8s %10s\n" "PID" "NAME" "TYPE" "STATUS" "MBOX" (String.uppercase_ascii sort);
  List.iter (fun r ->
      let name = match jl (jm "names" r) with `String n :: _ -> n | _ -> "" in
      let typ = match jm "type" r with `String t -> t | _ -> "" in
      let clip n s = if String.length s > n then String.sub s 0 n else s in
      Printf.bprintf b "%8d  %-20s %-18s %-9s %8d %10d\n"
        (ji (jm "pid" r)) (clip 20 name) (clip 18 typ) (js (jm "status" r))
        (ji (jm "mbox" r)) (ji (jm "value" r)))
    (jl (jm "top" (Observe_client.data_of top)));
  Buffer.contents b

let counter_sort s = List.mem s [ "slices"; "msgs_in"; "msgs_out" ]

(** [forge top]: one target, redrawn until interrupted ([once]: one frame,
    no screen control, for scripts). Counter sorts rank the change over the
    window, which is also the refresh; others refresh every
    max(1 s, 4 x the snapshot's cost). *)
let run_top ~(socket : string option) ~(env : string) ~(sort : string) ~(n : int)
    ~(window_ms : int) ~(once : bool) () : (unit, string) result =
  let target =
    match socket with
    | Some path -> Ok (path, Observe_client.query_socket path)
    | None ->
      match Project.load () with
      | Error m -> Error m
      | Ok proj ->
        match proj.Project.hot_reload with
        | None -> Error "observe: no host to observe: give --socket, or add a [hot-reload] section to forge.toml"
        | Some hr ->
          match hosts_of hr ~env with
          | Error _ as e -> e
          | Ok (h :: _) -> Ok (h.Hosts.name, Observe_client.query Remote.ssh h)
          | Ok [] -> Error "observe: no host"
  in
  match target with
  | Error _ as e -> e
  | Ok (name, ask) ->
    let windowed = counter_sort sort in
    let top_req = Printf.sprintf "TOP %s %d%s" sort n
        (if windowed then " " ^ string_of_int window_ms else "") in
    let rec loop () =
      match ask top_req with
      | Error _ as e -> e
      | Ok top ->
        match ask summary_request with
        | Error _ as e -> e
        | Ok snap ->
          let node = js (jm "node" snap) in
          let frame = render_top ~node:(if node = "" then name else node) ~sort
              ~window_ms:(if windowed then Some window_ms else None) (reply_summary snap) top in
          if once then (print_string frame; Ok ())
          else begin
            print_string ("\027[H\027[2J" ^ frame);
            flush stdout;
            if not windowed then begin
              let took = float_of_int (ji (jm "took_us" snap)) /. 1e6 in
              Unix.sleepf (Float.max 1.0 (4.0 *. took))
            end;
            loop ()
          end
    in
    loop ()

(** [forge status]: with a topology, its node report followed by each node's
    observe summary; otherwise the summary of each forge.toml [hot-reload]
    host (or of [--socket]). *)
let run_status ~(socket : string option) ~(env : string) ~(json : bool) () : (unit, string) result =
  let summarise name ask =
    match ask summary_request with
    | Ok reply -> (name, Ok (reply_summary reply))
    | Error m -> (name, Error m)
  in
  let print_all (topology_text : string option) results =
    if json then
      print_endline (Yojson.Safe.to_string (`Assoc [
          "proto", `String "march.status/1";
          "topology", (match topology_text with Some t -> `String t | None -> `Null);
          "nodes", `List (List.map (fun (name, r) ->
              `Assoc [ "name", `String name;
                       (match r with
                        | Ok s -> ("observe", summary_json s)
                        | Error m -> ("error", `String m)) ]) results) ]))
    else begin
      Option.iter print_string topology_text;
      List.iter (fun (name, r) ->
          match r with
          | Ok s -> Printf.printf "%s: %s\n" name (summary_line s)
          | Error m -> Printf.printf "%s: observe unavailable (%s)\n" name m) results
    end
  in
  match socket with
  | Some path -> print_all None [ summarise path (Observe_client.query_socket path) ]; Ok ()
  | None ->
    match Project.load () with
    | Error m -> Error m
    | Ok proj ->
      let root = proj.Project.root in
      if Sys.file_exists (Filename.concat root "topology.toml") then
        match Reconcile.status_nodes ?env:(if env = "" then None else Some env) ~root () with
        | Error m -> Error m
        | Ok (nodes, text) ->
          let results = List.filter_map (fun (st : Reconcile.node_status) ->
              let nd = st.Reconcile.node in
              match nd.Reconcile.socket with
              | None -> None
              | Some sock ->
                let h = { Hosts.name = nd.Reconcile.name; ssh = nd.Reconcile.host; socket = sock;
                          pubkey = ""; labels = nd.Reconcile.labels } in
                let transport = if nd.Reconcile.host = "" then Remote.local else Remote.ssh in
                Some (summarise nd.Reconcile.name (Observe_client.query transport h))) nodes in
          print_all (Some text) results; Ok ()
      else
        match proj.Project.hot_reload with
        | None -> Error "status: no topology.toml and no [hot-reload] section; give --socket"
        | Some hr ->
          match hosts_of hr ~env with
          | Error _ as e -> e
          | Ok hosts ->
            print_all None (List.map (fun h ->
                summarise h.Hosts.name (Observe_client.query Remote.ssh h)) hosts);
            Ok ()
