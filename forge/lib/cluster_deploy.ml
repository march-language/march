(** [forge deploy] on the [cluster] backend: a client of the in-cluster
    control plane (distributed-deploys build step 12a; design section 9).

    Nothing here reaches a node by ssh. forge builds the patches and decides
    the rollout as it always does, writes it down as one signed release
    ([Control_release]), uploads the artifacts the release names, sends the
    release to the control API, and follows the leader's view of it until it
    completes or halts.

    {1 The control API}

    A line protocol over TCP, on every control candidate (the [[control]]
    section's label and port): the reload socket's own unsigned verbs, and

    {v
    RELEASE <size>        a release document follows; the leader answers
                          OK <seq> <digest> once it is durable on every
                          reachable candidate, or ERR <why> (stale, fork,
                          parent mismatch, bad signature, ...)
    STATUS                STATUS head:<seq> <digest> state:<s> leader:<node>
                          DECISION <text>
                          NODE <name> seq:.. healthy:.. topology:.. ...
                          END
    v}

    A candidate that is not the leader forwards [RELEASE] and [STATUS], so any
    candidate will do. Artifacts go to every candidate ([CAS_PUT], the reload
    socket's own exchange), so whichever one an agent fetches from has them. *)

let ( let* ) = Result.bind

type endpoint = { host : string; port : int }

let endpoint_of_string s =
  match String.rindex_opt s ':' with
  | Some i ->
    (match int_of_string_opt (String.sub s (i + 1) (String.length s - i - 1)) with
     | Some port -> Some { host = String.sub s 0 i; port }
     | None -> None)
  | None -> None

let show_endpoint e = Printf.sprintf "%s:%d" e.host e.port

(* ── The client ────────────────────────────────────────────────────────── *)

let connect (e : endpoint) : (Cmd_deploy_hot.conn, string) result =
  match Unix.getaddrinfo e.host (string_of_int e.port) [ Unix.AI_SOCKTYPE Unix.SOCK_STREAM ] with
  | [] -> Error (Printf.sprintf "cannot resolve %s" e.host)
  | ai :: _ ->
    let fd = Unix.socket ai.Unix.ai_family Unix.SOCK_STREAM 0 in
    (try
       Unix.setsockopt_float fd Unix.SO_RCVTIMEO 60.;
       Unix.setsockopt_float fd Unix.SO_SNDTIMEO 60.;
       Unix.connect fd ai.Unix.ai_addr;
       Ok (Cmd_deploy_hot.conn_of_fd fd)
     with Unix.Unix_error (err, _, _) ->
       Unix.close fd;
       Error (Printf.sprintf "%s: %s" (show_endpoint e) (Unix.error_message err)))

let close (c : Cmd_deploy_hot.conn) = try Unix.close c.Cmd_deploy_hot.fd with Unix.Unix_error _ -> ()

let with_conn e f =
  let* c = connect e in
  Fun.protect ~finally:(fun () -> close c) (fun () ->
      try f c with Failure m -> Error m | Unix.Unix_error (err, _, _) -> Error (Unix.error_message err))

type node_state = {
  n_name : string;
  n_seq : int;
  n_healthy : bool;
  n_topology : string;
  n_drained : int;
  n_versions : string;
  n_failed : string;
}

type status = {
  head_seq : int;
  head_digest : string;    (** "-" when no release is held *)
  state : string;          (** none | running | complete | halted | behind *)
  leader : string;
  decision : string;
  nodes : node_state list;
  notes : string list;     (** NOTE lines: gates the leader did not see pass *)
}

let field_of words key =
  let p = key ^ ":" in
  List.find_map (fun w ->
      if String.length w > String.length p && String.sub w 0 (String.length p) = p
      then Some (String.sub w (String.length p) (String.length w - String.length p)) else None)
    words

let parse_status (lines : string list) : (status, string) result =
  let words l = List.filter (fun w -> w <> "") (String.split_on_char ' ' l) in
  match lines with
  | first :: rest when String.length first >= 7 && String.sub first 0 7 = "STATUS " ->
    let w = words first in
    let head_seq, head_digest =
      match w with
      | _ :: h :: d :: _ when String.length h > 5 && String.sub h 0 5 = "head:" ->
        (Option.value ~default:0 (int_of_string_opt (String.sub h 5 (String.length h - 5))), d)
      | _ -> (0, "-")
    in
    let get k = Option.value ~default:"" (field_of w k) in
    let decision = ref "" and nodes = ref [] and notes = ref [] in
    List.iter (fun l ->
        let ws = words l in
        match ws with
        | "DECISION" :: _ -> decision := String.trim (String.sub l 8 (String.length l - 8))
        | "NOTE" :: _ -> notes := String.trim (String.sub l 5 (String.length l - 5)) :: !notes
        | "NODE" :: name :: _ ->
          nodes := { n_name = name;
                     n_seq = Option.value ~default:0 (Option.bind (field_of ws "seq") int_of_string_opt);
                     n_healthy = field_of ws "healthy" = Some "yes";
                     n_topology = Option.value ~default:"" (field_of ws "topology");
                     n_drained = Option.value ~default:0 (Option.bind (field_of ws "drained") int_of_string_opt);
                     n_versions = Option.value ~default:"" (field_of ws "versions");
                     n_failed = Option.value ~default:"-" (field_of ws "failed") } :: !nodes
        | _ -> ())
      rest;
    Ok { head_seq; head_digest; state = get "state"; leader = get "leader"; decision = !decision; nodes = List.rev !nodes; notes = List.rev !notes }
  | l :: _ -> Error l
  | [] -> Error "no answer"

(** STATUS over [conn]: the lines up to END. *)
let status_conn conn : (status, string) result =
  Cmd_deploy_hot.send_line conn "STATUS";
  let rec lines acc =
    let l = Cmd_deploy_hot.recv_line conn in
    if l = "END" || String.length l >= 3 && String.sub l 0 3 = "ERR" then List.rev (l :: acc) else lines (l :: acc)
  in
  parse_status (lines [])

(** The first endpoint that answers STATUS with the leader's view. *)
let status (eps : endpoint list) : (status, string) result =
  let rec go errs = function
    | [] -> Error (Printf.sprintf "no control node answered: %s" (String.concat "; " (List.rev errs)))
    | e :: rest ->
      (match with_conn e status_conn with
       | Ok s -> Ok s
       | Error m -> go (m :: errs) rest)
  in
  go [] eps

(** Send [body] as a release; the first endpoint that reaches a leader answers. *)
let send_release (eps : endpoint list) ~(body : string) : (string, string) result =
  let rec go errs = function
    | [] -> Error (Printf.sprintf "no control node took the release: %s" (String.concat "; " (List.rev errs)))
    | e :: rest ->
      let r =
        with_conn e (fun c ->
            Cmd_deploy_hot.send_line c (Printf.sprintf "RELEASE %d" (String.length body));
            Cmd_deploy_hot.send_binary c (Bytes.of_string body) 0 (String.length body);
            Ok (Cmd_deploy_hot.recv_line c))
      in
      (match r with
       | Ok resp when String.length resp >= 2 && String.sub resp 0 2 = "OK" -> Ok resp
       | Ok resp when resp = "ERR no_leader" -> go ((show_endpoint e ^ ": no leader")  :: errs) rest
       | Ok resp -> Error resp
       | Error m -> go (m :: errs) rest)
  in
  go [] eps

(** Upload [path] as artifact [hash] to every endpoint that lacks it. *)
let upload (eps : endpoint list) ~(hash : string) ~(path : string) : (unit, string) result =
  List.fold_left (fun acc e ->
      let* () = acc in
      match with_conn e (fun c ->
          if Cmd_deploy_hot.cas_check c hash then Ok ()
          else (Cmd_deploy_hot.cas_put c hash path; Ok ())) with
      | Ok () -> Ok ()
      | Error m ->
        (* A candidate that is down is skipped: the artifact reaches the
           others, and the leader replicates what it holds. *)
        Printf.eprintf "  warning: %s\n%!" m; Ok ())
    (Ok ()) eps

(* ── Building the release ──────────────────────────────────────────────── *)

type hot_build = {
  hb_name : string;
  hb_pools : string list;
  hb_manifest : Cmd_deploy_hot.manifest;
  hb_so : string;
  hb_old_manifest : string;
  hb_old_schemas : string;
  hb_new_schemas : string;
}

type spec = {
  env : string;
  endpoints : endpoint list;
  sk : bytes;
  pubkey : string;               (** base64, the deploy key's public half *)
  hot : hot_build list;
  topology_body : string;        (** the topology digest text *)
  push_topology : bool;
  canary : int;                  (** hosts of each pool patched first (0: all at once) *)
  canary_window_ms : int;
  rest_window_ms : int;
  work_dir : string;
  entry_path : string;
  grant_caps : string list;
  follow_s : float;              (** how long to follow the rollout *)
}

let write_tmp dir name data =
  let p = Filename.concat dir name in
  Out_channel.with_open_bin p (fun oc -> output_string oc data);
  p

let mkdir_p d =
  let rec go d =
    if not (Sys.file_exists d) then (go (Filename.dirname d); try Unix.mkdir d 0o755 with Unix.Unix_error (Unix.EEXIST, _, _) -> ())
  in
  go d

(** The release for [spec] over the leader's head. Steps: for each hot build
    a canary step and a rest step (or one step for everyone), then the
    topology. *)
let build_release (sp : spec) ~(head : status) : (Control_release.t, string) result =
  let open Control_release in
  let seq = next_seq ~now_ms:(int_of_float (Unix.gettimeofday () *. 1000.)) ~head:head.head_seq in
  mkdir_p sp.work_dir;
  let topology = March_cas.Blake3.hash_string sp.topology_body in
  let step_id = ref 0 in
  let next () = incr step_id; !step_id in
  let* parts =
    List.fold_left (fun acc hb ->
        let* acc = acc in
        let* lines =
          record_hot ~dir:(Filename.concat sp.work_dir ("rec-" ^ hb.hb_name)) ~seq ~sk:sp.sk ~pubkey:sp.pubkey
            ~old_manifest_path:hb.hb_old_manifest ~manifest:hb.hb_manifest ~so_path:hb.hb_so
            ~old_schemas_path:hb.hb_old_schemas ~new_schemas_path:hb.hb_new_schemas ~entry_path:sp.entry_path
            ~grant_caps:sp.grant_caps ()
        in
        let steps =
          if sp.canary > 0 then begin
            (* Numbered in order: OCaml evaluates a list literal's elements right to left. *)
            let first = next () in
            let second = next () in
            [ { id = first; pools = hb.hb_pools; hosts = Canary sp.canary; action = Activate hb.hb_name;
                gate = Healthy sp.canary_window_ms; batch = 0 };
              { id = second; pools = hb.hb_pools; hosts = Rest; action = Activate hb.hb_name;
                gate = (if sp.rest_window_ms > 0 then Healthy sp.rest_window_ms else No_gate); batch = 0 } ]
          end else
            [ { id = next (); pools = hb.hb_pools; hosts = All; action = Activate hb.hb_name;
                gate = (if sp.rest_window_ms > 0 then Healthy sp.rest_window_ms else No_gate); batch = 0 } ]
        in
        let build = { name = hb.hb_name; base = "-"; manifest = hb.hb_manifest.Cmd_deploy_hot.cas_hash } in
        Ok (acc @ [ (build, steps, lines) ]))
      (Ok []) sp.hot
  in
  let builds = List.map (fun (b, _, _) -> b) parts in
  let steps = List.concat_map (fun (_, s, _) -> s) parts in
  let lines = List.concat_map (fun (_, ss, ls) -> List.concat_map (fun (s : step) -> List.map (fun l -> (s.id, l)) ls) ss) parts in
  let steps, lines =
    if sp.push_topology then begin
      let id = next () in
      let (line, _) = topology_line ~seq ~sk:sp.sk ~body:sp.topology_body in
      (steps @ [ { id; pools = [ "*" ]; hosts = All; action = Topology; gate = No_gate; batch = 0 } ], lines @ [ (id, line) ])
    end else (steps, lines)
  in
  if steps = [] then Error "nothing to deploy"
  else
    Ok (sign ~sk:sp.sk
          { seq; parent = (if head.head_digest = "-" then no_parent else head.head_digest); env = sp.env; topology;
            builds; steps; lines; drain = None; signature = "" })

(* ── Following the rollout ─────────────────────────────────────────────── *)

let render_status (s : status) : string =
  let b = Buffer.create 256 in
  Printf.bprintf b "release %d (%s) on leader %s: %s\n" s.head_seq
    (if s.head_digest = "-" then "-" else String.sub s.head_digest 0 (min 12 (String.length s.head_digest)))
    s.leader s.state;
  Printf.bprintf b "  %s\n" s.decision;
  List.iter (fun n -> Printf.bprintf b "  note: %s\n" n) s.notes;
  List.iter (fun n ->
      Printf.bprintf b "  %s: release %d, %s, versions %s, topology %s%s\n" n.n_name n.n_seq
        (if n.n_healthy then "healthy" else "UNHEALTHY") n.n_versions
        (if String.length n.n_topology > 12 then String.sub n.n_topology 0 12 else n.n_topology)
        (if n.n_failed = "-" then "" else ", FAILED " ^ n.n_failed))
    s.nodes;
  Buffer.contents b

(** Poll STATUS until the release [seq] completes or halts, printing the
    leader's decision as it changes. A halted release is an error naming the
    step, the node and why; nothing is rolled back (a rollback is a new
    release). *)
let follow (eps : endpoint list) ~(seq : int) ~(timeout_s : float) : (string, string) result =
  let t0 = Unix.gettimeofday () in
  let last = ref "" in
  let rec go misses =
    if Unix.gettimeofday () -. t0 > timeout_s then Error (Printf.sprintf "release %d did not finish within %.0f s (the leader keeps working on it: `forge deploy` again follows it)" seq timeout_s)
    else match status eps with
      | Error m ->
        (* A leader change is a gap in the answers, not a failure. *)
        if misses > 30 then Error m else (Unix.sleepf 1.0; go (misses + 1))
      | Ok s ->
        if s.head_seq = seq then begin
          if s.decision <> !last then begin
            last := s.decision;
            Printf.printf "  %s\n%!" s.decision
          end;
          if s.state = "complete" then Ok (render_status s)
          else if s.state = "halted" then Error (Printf.sprintf "the release halted: %s\n%s" s.decision (render_status s))
          else (Unix.sleepf 1.0; go 0)
        end else if s.head_seq > seq then
          Error (Printf.sprintf "a newer release (%d) superseded this one before it finished" s.head_seq)
        else (Unix.sleepf 1.0; go 0)
  in
  go 0

(** The whole deploy: status, release, upload, send, follow. *)
let run (sp : spec) : (string, string) result =
  let* head = status sp.endpoints in
  Printf.printf "control plane: leader %s, head release %d\n%!" head.leader head.head_seq;
  let* release = build_release sp ~head in
  (* Artifacts first: a release must never name what a candidate cannot serve. *)
  let* () =
    List.fold_left (fun acc hb ->
        let* () = acc in
        Printf.printf "uploading %s patch (%s)\n%!" hb.hb_name hb.hb_manifest.Cmd_deploy_hot.cas_hash;
        upload sp.endpoints ~hash:hb.hb_manifest.Cmd_deploy_hot.cas_hash ~path:hb.hb_so)
      (Ok ()) sp.hot
  in
  let* () =
    if sp.push_topology then
      let p = write_tmp sp.work_dir "topology.json" sp.topology_body in
      upload sp.endpoints ~hash:release.Control_release.topology ~path:p
    else Ok ()
  in
  let body = Control_release.serialize release in
  (match Sys.getenv_opt "FORGE_RELEASE_OUT" with
   | Some f when f <> "" -> Out_channel.with_open_bin f (fun oc -> output_string oc body)
   | _ -> ());
  let* resp = send_release sp.endpoints ~body in
  Printf.printf "release accepted: %s\n%!" resp;
  follow sp.endpoints ~seq:release.Control_release.seq ~timeout_s:sp.follow_s
