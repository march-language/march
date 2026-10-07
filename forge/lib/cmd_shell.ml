(** [forge shell] / [forge rpc]: a remote shell on a running node (R6 of
    specs/plans/2026-09-28-observe-recon-shell-plan.md; design §6.9).

    forge does not compile anything itself.  It finds the project's entry and
    MARCH_LIB_PATH exactly as [forge build] does, reaches the node's shell
    socket ([<reload socket>.shell]) directly or through an ssh tunnel, and
    runs [march --shell] against it: [march] typechecks the project once and
    compiles each input into a signed fragment the node runs
    (bin/shell_cmd.ml, runtime/march_shell.c).  The deploy key is the one
    [forge deploy hot] signs with (~/.march/ed25519_secret.key). *)

(** The hosts' shell sockets: [--socket] (a reload socket path on this
    machine), else the forge.toml [hot-reload] hosts. *)
let target ~(socket : string option) ~(env : string) (proj : Project.project)
  : (Hosts.host, string) result =
  match socket with
  | Some path ->
    Ok { Hosts.name = "local"; ssh = ""; socket = path; pubkey = ""; labels = [] }
  | None ->
    match proj.Project.hot_reload with
    | None -> Error "shell: no node: give --socket, or add a [hot-reload] section to forge.toml"
    | Some hr ->
      match Cmd_observe.hosts_of hr ~env with
      | Error m -> Error m
      | Ok [ h ] -> Ok h
      | Ok hs ->
        Error (Printf.sprintf "shell: %d hosts match; pick one with --env (%s)"
                 (List.length hs) (String.concat ", " (List.map (fun h -> h.Hosts.name) hs)))

(** Run [march --shell] on [h]'s shell socket.  [inputs]: a file of inputs
    (forge rpc), else the terminal. *)
let run_on ~(proj : Project.project) ~(h : Hosts.host) ~(timeout_ms : int)
    ~(inputs : string option) : int =
  match Project.entry proj with
  | Error m -> prerr_endline ("shell: " ^ m); 1
  | Ok entry ->
    let lib_env = Cmd_build.lib_path_env proj in
    let with_socket f =
      if h.Hosts.ssh = "" then f (h.Hosts.socket ^ ".shell")
      else begin
        let local = Cmd_deploy_hot.fresh_sock "march_shell" in
        let (pid, _) = Cmd_deploy_hot.open_tunnel ~ssh_host:h.Hosts.ssh
            ~remote_socket:(h.Hosts.socket ^ ".shell") ~local_socket:local in
        Fun.protect ~finally:(fun () -> Cmd_deploy_hot.close_tunnel pid local)
          (fun () -> f local)
      end in
    with_socket (fun sock ->
        let cmd =
          Printf.sprintf "%smarch --shell %s --shell-timeout-ms %d%s %s"
            lib_env (Filename.quote sock) timeout_ms
            (match inputs with Some f -> " --shell-inputs " ^ Filename.quote f | None -> "")
            (Filename.quote entry) in
        match Sys.command cmd with
        | n -> n)

let shell ~(socket : string option) ~(env : string) ~(timeout_ms : int) () : int =
  match Project.load () with
  | Error m -> prerr_endline m; 1
  | Ok proj ->
    match target ~socket ~env proj with
    | Error m -> prerr_endline m; 1
    | Ok h -> run_on ~proj ~h ~timeout_ms ~inputs:None

(** One input, printed, exit 0 when it ran and 1 otherwise. *)
let rpc ~(socket : string option) ~(env : string) ~(timeout_ms : int) (expr : string) : int =
  if String.contains expr '\n' then (prerr_endline "rpc: one line of input"; 1)
  else
    match Project.load () with
    | Error m -> prerr_endline m; 1
    | Ok proj ->
      match target ~socket ~env proj with
      | Error m -> prerr_endline m; 1
      | Ok h ->
        let f = Filename.temp_file "forge_rpc" ".txt" in
        Out_channel.with_open_bin f (fun oc -> output_string oc (expr ^ "\n"));
        Fun.protect ~finally:(fun () -> try Sys.remove f with _ -> ())
          (fun () -> run_on ~proj ~h ~timeout_ms ~inputs:(Some f))
