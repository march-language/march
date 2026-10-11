(** The command-line drivers for [forge observe]'s interactive and text views
    and for reading crash dumps (R7 of
    specs/plans/2026-09-28-observe-recon-shell-plan.md).

    - [run_live]: the TUI on one or several nodes ([n] cycles);
    - [run_panel]: one panel of a live node as text, for scripts and logs;
    - [run_dump]: a crash dump ([MARCH_CRASH_DUMP]) in the same panels, as
      the TUI on a terminal, as text otherwise;
    - [run_diagnose_dump]: the diagnose findings over a crash dump. *)

module T = Observe_tui
module L = Observe_tui_live

(** The nodes to observe: [--socket], else the forge.toml [hot-reload] hosts
    ([--env] narrows them), each reached through its own ssh tunnel. *)
let targets_of ~(socket : string option) ~(env : string) : (L.target list, string) result =
  match socket with
  | Some path -> Ok [ L.target_of_socket path ]
  | None ->
    match Project.load () with
    | Error m -> Error m
    | Ok proj ->
      match proj.Project.hot_reload with
      | None -> Error "observe: no host to observe: give --socket, or add a [hot-reload] section to forge.toml"
      | Some hr -> Result.map (List.map L.target_of_host) (Cmd_observe.hosts_of hr ~env)

let parse_panel (name : string) : (T.panel, string) result =
  match T.panel_of_string name with
  | Some p -> Ok p
  | None ->
    Error (Printf.sprintf "observe: no panel %S (panels: %s)" name
             (String.concat ", " (List.map (fun p -> String.lowercase_ascii (T.title p)) T.all_panels)))

let terminal_width () =
  match Sys.getenv_opt "COLUMNS" with
  | Some c -> (match int_of_string_opt c with Some n when n >= 40 -> n | _ -> 170)
  | None -> 170

let run_live ~(socket : string option) ~(env : string) ~(interval_ms : int) ~(panel : string) :
  (unit, string) result =
  if interval_ms < 250 then Error "observe: --interval must be at least 250 ms (the node's WATCH floor)"
  else
    match parse_panel panel with
    | Error _ as e -> e
    | Ok p ->
      match targets_of ~socket ~env with
      | Error _ as e -> e
      | Ok targets -> L.run_live ~targets ~interval_ms ~panel:p

(** One panel of one live target as text: the snapshot sections it reads
    plus the request it needs ([TOP], [CLUSTER]; [ACTOR] needs [--pid]). *)
let run_panel ~(socket : string option) ~(env : string) ~(panel : string) ~(sort : string)
    ~(pid : int option) : (unit, string) result =
  match parse_panel panel with
  | Error _ as e -> e
  | Ok T.Actor when pid = None -> Error "observe: --panel actor needs --pid N"
  | Ok p ->
    match targets_of ~socket ~env with
    | Error _ as e -> e
    | Ok targets ->
      let many = List.length targets > 1 in
      let one (t : L.target) =
        let fail m = Error (Printf.sprintf "%s: %s" t.L.tname m) in
        match t.L.connect () with
        | Error m -> fail m
        | Ok link ->
          Fun.protect ~finally:link.L.close (fun () ->
              let ask = Observe_client.query_socket link.L.path in
              let reply =
                match T.request_of ~sort ~pid p with
                | None -> ask ("SNAPSHOT " ^ T.snapshot_sections)
                | Some req ->
                  (match ask req with
                   | Error _ when p = T.Cluster -> Ok (`Assoc [ "data", `Null ])   (* an older node: no CLUSTER *)
                   | r -> r) in
              match reply with
              | Error m -> fail m
              | Ok reply ->
                if many then Printf.printf "== %s ==\n" t.L.tname;
                let ctx = { T.default_ctx with T.width = terminal_width (); sort } in
                print_string (T.panel_text ~ctx p reply);
                Ok ()) in
      List.fold_left (fun acc t -> match acc with Error _ -> acc | Ok () -> one t) (Ok ()) targets

(** A crash dump: [--json] the merged snapshot, [--panel] one panel as text,
    a terminal the TUI, otherwise every panel the dump can fill, as text. *)
let run_dump ~(file : string) ~(panel : string option) ~(sort : string) ~(json : bool) : (unit, string) result =
  match T.load_dump file with
  | Error m -> Error ("observe: " ^ m)
  | Ok d ->
    let ctx = { T.default_ctx with T.width = terminal_width (); dump = true; sort } in
    match panel with
    | Some name ->
      (match parse_panel name with
       | Error _ as e -> e
       | Ok p -> print_string (T.panel_text ~ctx p d.T.reply); Ok ())
    | None when json -> print_endline (Yojson.Safe.pretty_to_string d.T.reply); Ok ()
    | None when L.interactive () -> L.run_dump ~file ~panel:T.System
    | None ->
      print_endline (T.dump_banner d);
      List.iter (fun p ->
          if not (T.live_only p) then begin
            Printf.printf "\n== %s ==\n" (T.title p);
            print_string (T.panel_text ~ctx p d.T.reply)
          end) T.all_panels;
      Ok ()

(** [forge diagnose --from-dump FILE]: the findings over the dump's snapshot
    (one point in time, so the checks that compare two snapshots find
    nothing; the crash ring, mailbox and scheduler state checks do).
    Prints the [march.diagnose/1] envelope, with the dump's reason; returns
    the exit code as [forge diagnose] does (3: unreadable). *)
let run_diagnose_dump ~(file : string) ~(json : bool) : int =
  match T.load_dump file with
  | Error m -> Printf.eprintf "diagnose: %s\n%!" m; 3
  | Ok d ->
    let reply = d.T.reply in
    let fs = Diagnose.run ~before:reply ~after:reply in
    let node = match T.js (T.jm "node" reply) with "" -> file | n -> n in
    let env = Diagnose.to_json ~node ~window_ms:0 ~before:reply ~after:reply fs in
    let env = match env with
      | `Assoc kv ->
        `Assoc (kv @ [ "dump", `Assoc [ "reason", `String d.T.reason; "at_ms", `Int d.T.dumped_at_ms;
                                        "pid", `Int d.T.pid ] ])
      | v -> v in
    Cmd_observe.print_reply ~json env;
    Diagnose.exit_code fs
