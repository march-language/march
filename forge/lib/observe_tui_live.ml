(** The interactive half of [forge observe]: the terminal loop over
    [Observe_tui]'s pure panels (R7 of
    specs/plans/2026-09-28-observe-recon-shell-plan.md).

    One screen, one node at a time.  A live session holds

    - one [WATCH] stream on the node's observe socket ([WATCH <sections>
      <interval_ms> 3600]): every frame is a [SNAPSHOT] envelope that feeds
      System, Load, Supervision, Names, Epochs and Crashes;
    - ad-hoc requests for the panel on screen when it needs more than the
      snapshot ([TOP] for Actors, [ACTOR <pid>], [CLUSTER]), each on its own
      short connection, so the stream is never interrupted.

    For a remote host both go through ONE ssh tunnel opened when the host is
    selected and closed when [n] moves on.  The loop is single-threaded:
    [select] on the keyboard and the stream.

    A crash dump ([run_dump]) is the same screen without the node. *)

open Notty
module T = Observe_tui

type link = { path : string; close : unit -> unit }

type target = {
  tname : string;
  connect : unit -> (link, string) result;
}

(** A local observe socket by its own path ([--socket]). *)
let target_of_socket (path : string) : target =
  { tname = path; connect = (fun () -> Ok { path; close = ignore }) }

let devnull flags = Unix.openfile "/dev/null" flags 0

(** A host's observe socket through an ssh tunnel.  ssh's own output goes to
    /dev/null: it would be drawn over the screen. *)
let target_of_host (h : Hosts.host) : target =
  { tname = h.Hosts.name;
    connect = (fun () ->
        let remote = Observe_client.socket_of h in
        let local = Cmd_deploy_hot.fresh_sock "march_observe" in
        let null_in = devnull [ Unix.O_RDONLY ] and null_out = devnull [ Unix.O_WRONLY ] in
        let pid =
          Fun.protect ~finally:(fun () -> Unix.close null_in; Unix.close null_out) (fun () ->
              Unix.create_process "ssh"
                (Array.of_list
                   ([ "ssh" ] @ Cmd_deploy_hot.ssh_config_args ()
                    @ [ "-N"; "-o"; "BatchMode=yes"; "-o"; "StrictHostKeyChecking=accept-new";
                        "-o"; "ConnectTimeout=10"; "-o"; "ExitOnForwardFailure=yes";
                        "-L"; Printf.sprintf "%s:%s" local remote; h.Hosts.ssh ]))
                null_in null_out null_out) in
        let rec wait n =
          if Sys.file_exists local then true
          else if n = 0 then false
          else (Unix.sleepf 0.1; wait (n - 1)) in
        let close () = Cmd_deploy_hot.close_tunnel pid local in
        if wait 100 then Ok { path = local; close }
        else (close (); Error (Printf.sprintf "ssh tunnel to %s did not come up" h.Hosts.ssh))) }

(* ── The stream ──────────────────────────────────────────────────────── *)

type watch = { fd : Unix.file_descr; buf : Buffer.t }

let stream_max = 3600

let start_watch (l : link) ~(interval_ms : int) : (watch, string) result =
  let fd = Unix.socket Unix.PF_UNIX Unix.SOCK_STREAM 0 in
  match Unix.connect fd (Unix.ADDR_UNIX l.path) with
  | exception Unix.Unix_error (e, _, _) ->
    Unix.close fd; Error (Unix.error_message e)
  | () ->
    let req = Printf.sprintf "WATCH %s %d %d\n" T.snapshot_sections interval_ms stream_max in
    (match Unix.write_substring fd req 0 (String.length req) with
     | exception Unix.Unix_error (e, _, _) -> Unix.close fd; Error (Unix.error_message e)
     | _ -> Ok { fd; buf = Buffer.create 65536 })

(** Bytes from the stream; the complete lines it ended with, in order.
    [`Eof] when the node closed it (finished, or gone). *)
let read_watch (w : watch) : [ `Lines of string list | `Eof ] =
  let tmp = Bytes.create 262144 in
  match Unix.read w.fd tmp 0 (Bytes.length tmp) with
  | exception Unix.Unix_error ((Unix.EINTR | Unix.EAGAIN), _, _) -> `Lines []
  | exception Unix.Unix_error _ -> `Eof
  | 0 -> `Eof
  | n ->
    Buffer.add_subbytes w.buf tmp 0 n;
    let s = Buffer.contents w.buf in
    let parts = String.split_on_char '\n' s in
    let rec split acc = function
      | [] -> List.rev acc, ""
      | [ last ] -> List.rev acc, last
      | l :: rest -> split (l :: acc) rest in
    let lines, rest = split [] parts in
    Buffer.clear w.buf;
    Buffer.add_string w.buf rest;
    `Lines (List.filter (fun l -> l <> "") lines)

(* ── State ───────────────────────────────────────────────────────────── *)

type st = {
  targets : target array;
  mutable ti : int;
  mutable link : link option;
  mutable watch : watch option;
  mutable retry_at : float;
  mutable snap : Yojson.Safe.t;
  mutable top : Yojson.Safe.t;       (** latest TOP reply, [`Null] before the first *)
  mutable actor : Yojson.Safe.t;     (** latest ACTOR reply *)
  mutable cluster : Yojson.Safe.t;
  mutable panel : T.panel;
  mutable sort : string;
  mutable sel : int;
  mutable actor_pid : int option;
  mutable history : float list;      (** mean busy fraction per frame *)
  mutable prev_idle : (int * int) option;   (** at_ms, summed idle_ms of the last frame *)
  mutable status : string;
  mutable frames : int;
  mutable dirty : bool;
  mutable quit : bool;
  interval_ms : int;
  dump : T.dump option;
}

let history_keep = 240

let note_frame (s : st) (reply : Yojson.Safe.t) =
  s.snap <- reply;
  s.frames <- s.frames + 1;
  let threads = T.jl (T.jm "threads" (T.section "sched" reply)) in
  let idle = List.fold_left (fun a t -> a + T.ji (T.jm "idle_ms" t)) 0 threads in
  let at = T.at_ms reply and n = List.length threads in
  (match s.prev_idle with
   | Some (pat, pidle) when at > pat && n > 0 ->
     let busy = 1.0 -. float_of_int (idle - pidle) /. float_of_int ((at - pat) * n) in
     let busy = Float.max 0. (Float.min 1. busy) in
     let h = s.history @ [ busy ] in
     let drop = List.length h - history_keep in
     s.history <- (if drop > 0 then List.filteri (fun i _ -> i >= drop) h else h)
   | _ -> ());
  s.prev_idle <- Some (at, idle);
  s.dirty <- true

let ask (s : st) (request : string) : Yojson.Safe.t =
  match s.link with
  | None -> `Null
  | Some l ->
    (match Observe_client.query_socket l.path request with
     | Ok r -> r
     | Error m -> s.status <- request ^ ": " ^ m; `Null)

(** The reply a panel asks beyond the stream, for what is on screen now. *)
let refresh_extra (s : st) =
  if s.dump = None then begin
    match T.request_of ~sort:s.sort ~pid:s.actor_pid s.panel with
    | None -> ()
    | Some req ->
      let r = ask s req in
      (match s.panel with
       | T.Actors -> s.top <- r
       | T.Actor -> s.actor <- r
       | T.Cluster -> s.cluster <- r
       | _ -> ());
      s.dirty <- true
  end

let drop_connection (s : st) =
  (match s.watch with Some w -> (try Unix.close w.fd with Unix.Unix_error _ -> ()) | None -> ());
  s.watch <- None;
  (match s.link with Some l -> l.close () | None -> ());
  s.link <- None

let connect_target (s : st) : (unit, string) result =
  drop_connection s;
  let t = s.targets.(s.ti) in
  match t.connect () with
  | Error _ as e -> e
  | Ok l ->
    s.link <- Some l;
    (match start_watch l ~interval_ms:s.interval_ms with
     | Error m -> l.close (); s.link <- None; Error m
     | Ok w -> s.watch <- Some w; Ok ())

let reply_of_panel (s : st) : Yojson.Safe.t =
  match s.panel with
  | T.Actors -> if s.top <> `Null then s.top else s.snap
  | T.Actor -> s.actor
  | T.Cluster -> s.cluster
  | _ -> s.snap

let ctx_of (s : st) ~(w : int) ~(h : int) : T.ctx =
  { T.width = w; height = h; sort = s.sort; selected = s.sel; history = s.history; dump = s.dump <> None }

let selectable (s : st) =
  let ctx = ctx_of s ~w:120 ~h:40 in
  T.selectable ~ctx s.panel (reply_of_panel s)

(* ── Drawing ─────────────────────────────────────────────────────────── *)

let draw (term : Notty_unix.Term.t) (s : st) =
  let w, h = Notty_unix.Term.size term in
  let w = max 40 w and h = max 8 h in
  let tabs = List.mapi (fun i p ->
      let label = Printf.sprintf " %d %s " (i + 1) (T.title p) in
      let attr =
        if p = s.panel then A.(st reverse ++ st bold)
        else if s.dump <> None && T.live_only p then T.dim
        else A.empty in
      I.string attr label) T.all_panels in
  let node =
    match s.dump with
    | Some d -> T.dump_banner d
    | None ->
      Printf.sprintf "%s%s   node %d/%d   frame %d   every %d ms"
        (let n = T.js (T.jm "node" s.snap) in if n = "" then "" else n ^ "  ")
        s.targets.(s.ti).tname (s.ti + 1) (Array.length s.targets) s.frames s.interval_ms in
  let area_h = h - 3 in
  let ctx = ctx_of s ~w ~h:area_h in
  let body = T.render ~ctx s.panel (reply_of_panel s) in
  let sel_line = T.header_lines s.panel + s.sel in
  let top = if T.header_lines s.panel > 0 && sel_line >= area_h - 1 then sel_line - (area_h - 2) else 0 in
  let top = min top (max 0 (I.height body - 1)) in
  let body = I.vsnap ~align:`Top area_h (I.vcrop top 0 body) in
  let footer =
    "q quit  1-9/Tab panel  Up/Down/PgUp/PgDn select  Enter open actor  s sort  n next node  r refresh" in
  let status = if s.status = "" then footer else s.status in
  let img = I.vcat [
      I.hcat tabs;
      I.string T.dim (T.fit w node);
      body;
      I.string (if s.status = "" then T.dim else T.warn) (T.fit w status);
    ] in
  Notty_unix.Term.image term (I.hsnap ~align:`Left w img)

(* ── Keys ────────────────────────────────────────────────────────────── *)

let panel_at i = List.nth_opt T.all_panels i

let switch_panel (s : st) (p : T.panel) =
  s.panel <- p; s.sel <- 0; s.status <- ""; s.dirty <- true;
  refresh_extra s

let clamp_sel (s : st) =
  let n = List.length (selectable s) in
  s.sel <- max 0 (min s.sel (max 0 (n - 1)))

let move_sel (s : st) d =
  s.sel <- s.sel + d; clamp_sel s; s.dirty <- true

let open_actor (s : st) =
  match List.nth_opt (selectable s) s.sel with
  | Some pid when pid >= 0 ->
    s.actor_pid <- Some pid;
    switch_panel s T.Actor
  | _ -> ()

let next_target (s : st) =
  if s.dump = None && Array.length s.targets > 1 then begin
    let prev = s.ti in
    s.ti <- (s.ti + 1) mod Array.length s.targets;
    s.snap <- `Null; s.top <- `Null; s.actor <- `Null; s.cluster <- `Null;
    s.history <- []; s.prev_idle <- None; s.frames <- 0; s.actor_pid <- None;
    s.status <- Printf.sprintf "connecting to %s..." s.targets.(s.ti).tname;
    s.dirty <- true;
    (match connect_target s with
     | Ok () -> s.status <- ""
     | Error m ->
       s.status <- Printf.sprintf "%s: %s (n tries the next node)" s.targets.(s.ti).tname m;
       if Array.length s.targets = 1 then s.ti <- prev)
  end else if s.dump = None then s.status <- "only one node to observe (give several with --env)"

let handle_key (s : st) (ev : [ Unescape.event | `Resize of (int * int) | `End ]) =
  match ev with
  | `Key (`ASCII 'q', []) | `Key (`Escape, []) | `Key (`ASCII 'C', [ `Ctrl ]) -> s.quit <- true
  | `Key (`ASCII c, []) when c >= '1' && c <= '9' ->
    (match panel_at (Char.code c - Char.code '1') with Some p -> switch_panel s p | None -> ())
  | `Key (`Tab, []) ->
    let rec idx i = function [] -> 0 | p :: r -> if p = s.panel then i else idx (i + 1) r in
    let n = List.length T.all_panels in
    (match panel_at ((idx 0 T.all_panels + 1) mod n) with Some p -> switch_panel s p | None -> ())
  | `Key (`ASCII 'n', []) -> next_target s
  | `Key (`ASCII 'r', []) -> s.status <- ""; refresh_extra s; s.dirty <- true
  | `Key (`ASCII 's', []) when s.panel = T.Actors ->
    s.sort <- T.next_sort s.sort; s.sel <- 0; refresh_extra s; s.dirty <- true
  | `Key (`Arrow `Down, []) | `Key (`ASCII 'j', []) -> move_sel s 1
  | `Key (`Arrow `Up, []) | `Key (`ASCII 'k', []) -> move_sel s (-1)
  | `Key (`Page `Down, []) -> move_sel s 10
  | `Key (`Page `Up, []) -> move_sel s (-10)
  | `Key (`Home, []) -> s.sel <- 0; s.dirty <- true
  | `Key (`End, []) -> s.sel <- max_int / 2; clamp_sel s; s.dirty <- true
  | `Key (`Enter, []) -> open_actor s
  | `Resize _ -> s.dirty <- true
  | `End -> s.quit <- true
  | _ -> ()

(* ── Loops ───────────────────────────────────────────────────────────── *)

let on_lines (s : st) (lines : string list) =
  List.iter (fun line ->
      match Observe_client.parse_reply line with
      | Ok reply ->
        note_frame s reply
      | Error m ->
        s.status <- m; s.dirty <- true) lines;
  if lines <> [] then begin
    refresh_extra s;
    clamp_sel s
  end

let make_state ~targets ~interval_ms ~panel ~dump =
  { targets; ti = 0; link = None; watch = None; retry_at = 0.; snap = `Null; top = `Null; actor = `Null;
    cluster = `Null; panel; sort = "mbox"; sel = 0; actor_pid = None; history = []; prev_idle = None;
    status = ""; frames = 0; dirty = true; quit = false; interval_ms; dump }

let loop (term : Notty_unix.Term.t) (s : st) =
  let in_fd, _ = Notty_unix.Term.fds term in
  while not s.quit do
    if s.dirty then (draw term s; s.dirty <- false);
    let fds = in_fd :: (match s.watch with Some w -> [ w.fd ] | None -> []) in
    (match Unix.select fds [] [] 0.25 with
     | exception Unix.Unix_error (Unix.EINTR, _, _) -> s.dirty <- true
     | ready, _, _ ->
       if List.mem in_fd ready then begin
         s.status <- "";
         handle_key s (Notty_unix.Term.event term);
         while Notty_unix.Term.pending term && not s.quit do
           handle_key s (Notty_unix.Term.event term)
         done;
         s.dirty <- true
       end;
       (match s.watch with
        | Some w when List.mem w.fd ready ->
          (match read_watch w with
           | `Lines ls -> on_lines s ls
           | `Eof ->
             (* The stream ran its 3600 frames, or the node went away: reconnect. *)
             (try Unix.close w.fd with Unix.Unix_error _ -> ());
             s.watch <- None;
             s.retry_at <- Unix.gettimeofday () +. 1.0)
        | _ -> ()));
    (* A dropped stream is reopened (the node restarts, a stream's 3600 frames end). *)
    if s.watch = None && s.dump = None && Unix.gettimeofday () >= s.retry_at then begin
      (match s.link with
       | Some l ->
         (match start_watch l ~interval_ms:s.interval_ms with
          | Ok w -> s.watch <- Some w; s.status <- ""
          | Error m -> s.status <- "stream: " ^ m ^ " (retrying)"; s.retry_at <- Unix.gettimeofday () +. 2.0)
       | None -> s.retry_at <- Unix.gettimeofday () +. 2.0);
      s.dirty <- true
    end
  done

let with_terminal (f : Notty_unix.Term.t -> unit) =
  let term = Notty_unix.Term.create () in
  Fun.protect ~finally:(fun () -> Notty_unix.Term.release term) (fun () -> f term)

let interactive () = Unix.isatty Unix.stdin && Unix.isatty Unix.stdout

(** Live: [targets] cycled with [n].  Fails before taking over the terminal
    if the first target cannot be reached. *)
let run_live ~(targets : target list) ~(interval_ms : int) ~(panel : T.panel) : (unit, string) result =
  if targets = [] then Error "observe: no node to observe"
  else if not (interactive ()) then Error "observe: the interactive view needs a terminal (use --json, or --panel NAME for text)"
  else begin
    let s = make_state ~targets:(Array.of_list targets) ~interval_ms ~panel ~dump:None in
    match connect_target s with
    | Error m -> Error (Printf.sprintf "observe: %s: %s" s.targets.(0).tname m)
    | Ok () ->
      Fun.protect ~finally:(fun () -> drop_connection s) (fun () ->
          with_terminal (fun term -> refresh_extra s; loop term s));
      Ok ()
  end

(** A crash dump on the same screen. *)
let run_dump ~(file : string) ~(panel : T.panel) : (unit, string) result =
  match T.load_dump file with
  | Error m -> Error ("observe: " ^ m)
  | Ok d ->
    if not (interactive ()) then Error "observe: the interactive view needs a terminal (use --panel NAME for text)"
    else begin
      let s = make_state ~targets:[| target_of_socket file |] ~interval_ms:0 ~panel ~dump:(Some d) in
      s.snap <- d.T.reply;
      s.frames <- 1;
      with_terminal (fun term -> loop term s);
      Ok ()
    end
