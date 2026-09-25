(* Process supervision. See procs.mli for the contract. *)

type log_sink = {
  dir : string;
  follow : (string -> unit) option;
}

let default_log_sink ~root =
  { dir = Filename.concat (Filename.concat root ".forge") "run"; follow = None }

(* With [follow], output reaches the log through a pipe that forge drains and
   tees; otherwise the child writes the log file directly, so the log is
   complete however the child ends. *)
type tee = {
  fd : Unix.file_descr;          (* read end of the child's stdout/stderr pipe *)
  log : out_channel;
  partial : Buffer.t;            (* the current unterminated line *)
  emit : string -> unit;
  mutable eof : bool;
}

type proc = {
  p_name : string;
  p_pid : int;                   (* also the process-group id: setsid *)
  p_log : string;
  mutable p_status : Unix.process_status option;
  mutable p_stopping : bool;     (* [stop] asked it to exit *)
  p_tee : tee option;
}

let name p = p.p_name
let pid p = p.p_pid
let log_path p = p.p_log
let status p = p.p_status

let rec mkdir_p d =
  if not (Sys.file_exists d) then begin
    mkdir_p (Filename.dirname d);
    try Unix.mkdir d 0o755 with Unix.Unix_error (Unix.EEXIST, _, _) -> ()
  end

let merged_env (extra : (string * string) list) : string array =
  let overridden entry =
    match String.index_opt entry '=' with
    | Some i -> List.mem_assoc (String.sub entry 0 i) extra
    | None -> false
  in
  let base = List.filter (fun e -> not (overridden e)) (Array.to_list (Unix.environment ())) in
  Array.of_list (base @ List.map (fun (k, v) -> k ^ "=" ^ v) extra)

(* Fork + setsid + execvpe rather than [Unix.create_process_env]: the child
   must lead its own process group, and create_process_env cannot do that.
   Still no shell: argv goes straight to execvpe. *)
let spawn ~name ~env ~argv ~log =
  if Array.length argv = 0 then invalid_arg "Procs.spawn: empty argv";
  mkdir_p log.dir;
  let log_path = Filename.concat log.dir (name ^ ".log") in
  let log_fd =
    Unix.openfile log_path [ Unix.O_WRONLY; Unix.O_CREAT; Unix.O_TRUNC; Unix.O_CLOEXEC ] 0o644
  in
  let pipe = match log.follow with
    | None -> None
    | Some _ -> Some (Unix.pipe ~cloexec:true ())
  in
  let child_out = match pipe with Some (_, w) -> w | None -> log_fd in
  let envv = merged_env env in
  let devnull = Unix.openfile "/dev/null" [ Unix.O_RDONLY; Unix.O_CLOEXEC ] 0 in
  flush stdout; flush stderr;
  match Unix.fork () with
  | 0 ->
    (try
       ignore (Unix.setsid ());
       Unix.dup2 ~cloexec:false devnull Unix.stdin;
       Unix.dup2 ~cloexec:false child_out Unix.stdout;
       Unix.dup2 ~cloexec:false child_out Unix.stderr;
       Unix.execvpe argv.(0) argv envv
     with e ->
       let msg = Printf.sprintf "forge: cannot run %s: %s\n" argv.(0)
           (match e with
            | Unix.Unix_error (err, _, _) -> Unix.error_message err
            | e -> Printexc.to_string e) in
       ignore (Unix.write_substring Unix.stderr msg 0 (String.length msg));
       Unix._exit 127)
  | child ->
    Unix.close devnull;
    let tee =
      match pipe, log.follow with
      | Some (r, w), Some emit ->
        Unix.close w;
        Unix.close log_fd;
        Some { fd = r; log = open_out_gen [ Open_wronly; Open_append ] 0o644 log_path;
               partial = Buffer.create 256; emit; eof = false }
      | _ -> Unix.close log_fd; None
    in
    { p_name = name; p_pid = child; p_log = log_path; p_status = None;
      p_stopping = false; p_tee = tee }

(* ── Output pumping (follow mode only) ─────────────────────────────── *)

let emit_lines p (t : tee) ~final =
  let s = Buffer.contents t.partial in
  let lines = String.split_on_char '\n' s in
  let rec go = function
    | [] -> ()
    | [ last ] ->
      Buffer.clear t.partial;
      if final then (if last <> "" then t.emit (Printf.sprintf "[%s] %s\n" p.p_name last))
      else Buffer.add_string t.partial last
    | l :: rest -> t.emit (Printf.sprintf "[%s] %s\n" p.p_name l); go rest
  in
  go lines

let read_chunk p (t : tee) =
  let buf = Bytes.create 4096 in
  match Unix.read t.fd buf 0 4096 with
  | 0 ->
    t.eof <- true;
    emit_lines p t ~final:true;
    close_out t.log;
    Unix.close t.fd
  | n ->
    output t.log buf 0 n;
    flush t.log;
    Buffer.add_subbytes t.partial buf 0 n;
    emit_lines p t ~final:false
  | exception Unix.Unix_error ((Unix.EINTR | Unix.EAGAIN), _, _) -> ()

(* Move whatever output is ready, waiting at most [timeout] seconds for some.
   Without any followed proc this is just a short sleep. *)
let pump procs ~timeout =
  let open_tees = List.filter_map (fun p ->
      match p.p_tee with Some t when not t.eof -> Some (p, t) | _ -> None) procs in
  if open_tees = [] then
    (try Unix.sleepf timeout with Unix.Unix_error (Unix.EINTR, _, _) -> ())
  else
    match Unix.select (List.map (fun (_, t) -> t.fd) open_tees) [] [] timeout with
    | (ready, _, _) ->
      List.iter (fun (p, t) -> if List.mem t.fd ready then read_chunk p t) open_tees
    | exception Unix.Unix_error (Unix.EINTR, _, _) -> ()

(* Read a followed proc's pipe to EOF: every line it wrote reaches the log. *)
let drain p =
  match p.p_tee with
  | Some t -> while not t.eof do read_chunk p t done
  | None -> ()

(* ── Reaping ───────────────────────────────────────────────────────── *)

let rec waitpid flags pid =
  try Unix.waitpid flags pid
  with Unix.Unix_error (Unix.EINTR, _, _) -> waitpid flags pid

(* Non-blocking: record the status if the proc has exited. *)
let reap p =
  if p.p_status = None then
    match waitpid [ Unix.WNOHANG ] p.p_pid with
    | (0, _) -> ()
    | (_, st) -> p.p_status <- Some st; drain p
    | exception Unix.Unix_error (Unix.ECHILD, _, _) ->
      p.p_status <- Some (Unix.WEXITED 255)

let tick = 0.02

let wait_any procs =
  let rec loop () =
    let running = List.filter (fun p -> p.p_status = None) procs in
    if running = [] then None
    else begin
      List.iter reap running;
      match List.find_opt (fun p -> p.p_status <> None) running with
      | Some p -> Some (p, Option.get p.p_status)
      | None -> pump procs ~timeout:tick; loop ()
    end
  in
  loop ()

let wait_all ~timeout procs =
  let deadline = Unix.gettimeofday () +. timeout in
  let rec loop () =
    List.iter reap procs;
    if List.for_all (fun p -> p.p_status <> None) procs then true
    else if Unix.gettimeofday () >= deadline then false
    else (pump procs ~timeout:tick; loop ())
  in
  loop ()

(* ── Stopping ──────────────────────────────────────────────────────── *)

let signal_group p sg =
  (* The group first (the child and anything it started); the pid alone if
     the group is already gone. ESRCH means there is nothing left to signal. *)
  try Unix.kill (- p.p_pid) sg
  with Unix.Unix_error _ -> (try Unix.kill p.p_pid sg with Unix.Unix_error _ -> ())

let stop p ~grace_ms =
  reap p;
  if p.p_status = None then begin
    p.p_stopping <- true;
    signal_group p Sys.sigterm;
    if not (wait_all ~timeout:(float_of_int grace_ms /. 1000.) [ p ]) then begin
      signal_group p Sys.sigkill;
      let (_, st) = waitpid [] p.p_pid in
      p.p_status <- Some st;
      drain p
    end
  end

let stop_all procs ~grace_ms =
  List.iter (fun p -> stop p ~grace_ms) (List.rev procs)

(* ── Supervision ───────────────────────────────────────────────────── *)

let supervise ?(fail_fast = false) ~grace_ms procs =
  let interrupted = ref false in
  let handler = Sys.Signal_handle (fun _ -> interrupted := true) in
  let old_int = Sys.signal Sys.sigint handler in
  let old_term = Sys.signal Sys.sigterm handler in
  Fun.protect
    ~finally:(fun () ->
        Sys.set_signal Sys.sigint old_int;
        Sys.set_signal Sys.sigterm old_term)
    (fun () ->
       let rec loop () =
         List.iter reap procs;
         let unexpected =
           List.exists (fun p -> p.p_status <> None && not p.p_stopping) procs in
         if !interrupted || (fail_fast && unexpected) then stop_all procs ~grace_ms
         else if List.exists (fun p -> p.p_status = None) procs then begin
           pump procs ~timeout:tick;
           loop ()
         end
       in
       loop ();
       List.map (fun p -> (p.p_name, Option.get p.p_status)) procs)

(* Every socket stays bound until all [n] ports are read, so one call never
   hands out the same port twice: bind-read-close one at a time lets the kernel
   give the just-closed port straight back (seen on Linux CI, where two pools
   of one [forge run --processes] both got the same port and one failed to bind). *)
let free_ports n =
  let socks = ref [] in
  Fun.protect ~finally:(fun () -> List.iter Unix.close !socks) (fun () ->
      List.init n (fun _ ->
          let s = Unix.socket Unix.PF_INET Unix.SOCK_STREAM 0 in
          socks := s :: !socks;
          Unix.setsockopt s Unix.SO_REUSEADDR true;
          Unix.bind s (Unix.ADDR_INET (Unix.inet_addr_loopback, 0));
          match Unix.getsockname s with
          | Unix.ADDR_INET (_, port) -> port
          | Unix.ADDR_UNIX _ -> failwith "Procs.free_ports: not an inet socket"))

let free_port () = List.hd (free_ports 1)

let string_of_status = function
  | Unix.WEXITED n -> Printf.sprintf "exited %d" n
  | Unix.WSIGNALED s -> Printf.sprintf "killed by signal %d" s
  | Unix.WSTOPPED s -> Printf.sprintf "stopped by signal %d" s
