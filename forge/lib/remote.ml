(** Running things on a host over ssh (distributed-deploys plan, build step
    10b: the ssh reconciler backend and [forge host init]).

    Two operations, both one ssh invocation:
    - [exec host script]: run a POSIX shell script on the host
      ([ssh <target> sh -s], the script on stdin), capturing its output;
    - [with_socket host f]: reach the host's reload socket through an ssh
      tunnel ([Cmd_deploy_hot.open_tunnel]) for the duration of [f].

    A [transport] bundles them so the reconciler and [host init] can run
    against something other than ssh: [local] runs scripts with this
    machine's [sh] and connects to [host.socket] directly, which is how the
    forge tests drive the ssh backend without an sshd (a container test
    covers the real thing).

    {1 ssh options}

    [FORGE_SSH_CONFIG=<file>] adds [-F <file>] to every ssh forge starts
    (tunnels included): a test points it at a config naming a container's
    port and key. Scripts run with [BatchMode=yes] (no password prompt that
    would hang a deploy) and [StrictHostKeyChecking=accept-new]. *)

let ssh_config_args = Cmd_deploy_hot.ssh_config_args

(** The argv prefix for a non-interactive ssh to [target]. *)
let ssh_argv target =
  [ "ssh" ] @ ssh_config_args ()
  @ [ "-o"; "BatchMode=yes"; "-o"; "StrictHostKeyChecking=accept-new"; "-o"; "ConnectTimeout=15"; target ]

type result = { rc : int; out : string; err : string }

let read_all path = try In_channel.with_open_bin path In_channel.input_all with Sys_error _ -> ""

(** Run [argv] with [input] on stdin; capture stdout and stderr. *)
let run_capture (argv : string list) ~(input : string) : result =
  let tmp suffix = Filename.temp_file "forge-remote-" suffix in
  let inp = tmp ".in" and out = tmp ".out" and err = tmp ".err" in
  Out_channel.with_open_bin inp (fun oc -> output_string oc input);
  let cmd =
    Printf.sprintf "%s < %s > %s 2> %s"
      (String.concat " " (List.map Filename.quote argv))
      (Filename.quote inp) (Filename.quote out) (Filename.quote err)
  in
  let rc = Sys.command cmd in
  let r = { rc; out = read_all out; err = read_all err } in
  List.iter (fun f -> try Sys.remove f with Sys_error _ -> ()) [ inp; out; err ];
  r

type transport = {
  kind : string;
  exec : Hosts.host -> string -> result;
  (** Run a shell script on the host. *)
  with_socket : 'a. Hosts.host -> (Cmd_deploy_hot.conn -> ('a, string) Stdlib.result) -> ('a, string) Stdlib.result;
  (** Connect to the host's reload socket for the duration of [f]. *)
  tunnel : bool;
  (** Whether [Cmd_deploy_hot.run] reaches [host.socket] through an ssh
      tunnel ([true]) or directly ([false], the local transport). *)
}

let connect_with_timeout ?(timeout = 10.0) path =
  let fd = Unix.socket Unix.PF_UNIX Unix.SOCK_STREAM 0 in
  (try
     Unix.setsockopt_float fd Unix.SO_RCVTIMEO timeout;
     Unix.setsockopt_float fd Unix.SO_SNDTIMEO timeout;
     Unix.connect fd (Unix.ADDR_UNIX path)
   with e -> (try Unix.close fd with _ -> ()); raise e);
  fd

let use_socket path (f : Cmd_deploy_hot.conn -> ('a, string) Stdlib.result) : ('a, string) Stdlib.result =
  match connect_with_timeout path with
  | exception Unix.Unix_error (e, fn, _) -> Error (Printf.sprintf "%s: %s" fn (Unix.error_message e))
  | fd ->
    Fun.protect ~finally:(fun () -> try Unix.close fd with Unix.Unix_error _ -> ())
      (fun () ->
         try f (Cmd_deploy_hot.conn_of_fd fd) with
         | Failure m -> Error m
         | Unix.Unix_error (e, fn, _) -> Error (Printf.sprintf "%s: %s" fn (Unix.error_message e)))

let ssh : transport =
  { kind = "ssh";
    exec = (fun (h : Hosts.host) script -> run_capture (ssh_argv h.Hosts.ssh @ [ "sh -s" ]) ~input:script);
    with_socket = (fun (h : Hosts.host) f ->
        let local = Cmd_deploy_hot.fresh_sock "march_reconcile" in
        let (pid, _) = Cmd_deploy_hot.open_tunnel ~ssh_host:h.Hosts.ssh ~remote_socket:h.Hosts.socket
            ~local_socket:local in
        Fun.protect ~finally:(fun () -> Cmd_deploy_hot.close_tunnel pid local)
          (fun () -> use_socket local f));
    tunnel = true }

(** Scripts run by this machine's [sh]; [host.socket] is a local path. *)
let local : transport =
  { kind = "local";
    exec = (fun _ script -> run_capture [ "sh"; "-s" ] ~input:script);
    with_socket = (fun (h : Hosts.host) f -> use_socket h.Hosts.socket f);
    tunnel = false }

(** A shell word: single-quoted, with embedded quotes escaped. *)
let sh_quote s = Filename.quote s

(** Copy the local file [local] to [remote] on the host (mode [mode]),
    atomically: streamed over the ssh connection's stdin into a temp file
    beside [remote], then renamed. [$SUDO] as in the reconciler's scripts;
    [sudo] is never used for a relocated (test) layout. *)
let upload (t : transport) (h : Hosts.host) ~(sudo : bool) ~local ~remote ~mode : (unit, string) Stdlib.result =
  match In_channel.with_open_bin local In_channel.input_all with
  | exception Sys_error m -> Error m
  | data ->
    let q = sh_quote remote in
    let script =
      (if sudo then "set -e; if [ \"$(id -u)\" = 0 ]; then SUDO=; else SUDO='sudo -n'; fi; " else "set -e; SUDO=; ")
      ^ Printf.sprintf "$SUDO mkdir -p %s; tmp=$($SUDO mktemp %s.XXXXXX); $SUDO tee \"$tmp\" >/dev/null; \
                        $SUDO chmod %o \"$tmp\"; $SUDO mv -f \"$tmp\" %s; echo uploaded"
        (sh_quote (Filename.dirname remote)) q mode q
    in
    let r =
      if t.kind = "ssh" then run_capture (ssh_argv h.Hosts.ssh @ [ "sh -c " ^ sh_quote script ]) ~input:data
      else run_capture [ "sh"; "-c"; script ] ~input:data
    in
    if r.rc = 0 then Ok () else Error (Printf.sprintf "upload to %s failed (exit %d): %s" remote r.rc (String.trim r.err))
