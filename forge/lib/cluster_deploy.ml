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
    AUDIT [<n>]           AUDIT <k>, then the last k lines of this
                          candidate's audit log (JSON lines), then END
    v}

    A candidate that is not the leader forwards [RELEASE] and [STATUS], so any
    candidate will do. [AUDIT] is answered by the candidate asked: the leader
    copies each line to every candidate it reaches, and [audit] asks them all. Artifacts go to every candidate ([CAS_PUT], the reload
    socket's own exchange), so whichever one an agent fetches from has them.

    {v
    STAGE <size>          a signed release follows; OK staged <n>, or ERR <why>
                          (bad signature, older than the candidate's head)
    CAS_PUT <hash> <size> only a hash a release staged on the SAME connection
                          names (ERR not_staged), at most 64 MiB, within the
                          candidate's quota of uploads no stored release names
                          yet (ERR cas_quota); unadopted ones are collected
    v}

    The candidates' own verbs ([RELEASE_COPY], [AUDIT_COPY]) need the cluster
    handshake, which forge cannot do; forge only reads, stages, uploads and
    sends signed releases. *)

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

(** The address part of an ssh target: ["deploy@10.0.0.5:22"] is ["10.0.0.5"]
    (a bracketed IPv6 address keeps what is inside the brackets). *)
let address_of_ssh_target (target : string) : string =
  let t = match String.rindex_opt target '@' with
    | Some i -> String.sub target (i + 1) (String.length target - i - 1)
    | None -> target
  in
  if String.length t > 0 && t.[0] = '[' then
    (match String.index_opt t ']' with Some j -> String.sub t 1 (j - 1) | None -> t)
  else match String.index_opt t ':' with
    | Some i when String.rindex t ':' = i -> String.sub t 0 i
    | _ -> t

(** The control API of every candidate of [t]'s [[control]] section: each
    host carrying the candidates' label, at the control port. [override]
    (FORGE_CONTROL_ENDPOINTS, [host:port,...]) replaces them: an operator who
    reaches the control port through a tunnel, or a test. *)
let endpoints_of_topology ?override (t : Topology.t) : (endpoint list, string) result =
  match override with
  | Some s when String.trim s <> "" ->
    let words = List.filter (fun w -> w <> "") (List.map String.trim (String.split_on_char ',' s)) in
    let eps = List.filter_map endpoint_of_string words in
    if List.length eps <> List.length words then Error (Printf.sprintf "FORGE_CONTROL_ENDPOINTS: expected host:port,... (got %s)" s)
    else Ok eps
  | _ ->
    match t.Topology.control with
    | None -> Error "the topology has no [control] section: there is no control plane to deploy through"
    | Some c ->
      let hosts =
        List.concat_map (fun (p : Topology.pool) ->
            List.filter (fun (h : Topology.host) -> List.mem c.Topology.candidates h.labels) p.hosts)
          t.pools
      in
      let addrs = List.sort_uniq String.compare (List.map (fun (h : Topology.host) -> address_of_ssh_target h.host) hosts) in
      if addrs = [] then Error (Printf.sprintf "no host carries the control candidates' label \"%s\"" c.candidates)
      else Ok (List.map (fun host -> { host; port = c.control_port }) addrs)

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

(** STATUS, retried for up to [timeout] seconds: after a restart, or while a
    new leader settles, no candidate may answer for a while. *)
let status_wait ?(timeout = 120.) (eps : endpoint list) : (status, string) result =
  let t0 = Unix.gettimeofday () in
  let rec go said =
    match status eps with
    | Ok s when s.leader <> "" -> Ok s
    | r when Unix.gettimeofday () -. t0 > timeout -> (match r with Ok s -> Ok s | Error m -> Error m)
    | _ ->
      if not said then Printf.printf "waiting for the control plane to answer...\n%!";
      Unix.sleepf 1.0; go true
  in
  go false

(** What STATUS says when no candidate answers: no release, no node. *)
let no_status = { head_seq = 0; head_digest = "-"; state = "none"; leader = ""; decision = ""; nodes = []; notes = [] }

(** One candidate's audit log (its last [n] lines; all for 0). *)
let audit_conn ~n conn : (string list, string) result =
  Cmd_deploy_hot.send_line conn (if n > 0 then Printf.sprintf "AUDIT %d" n else "AUDIT");
  let first = Cmd_deploy_hot.recv_line conn in
  if String.length first < 6 || String.sub first 0 6 <> "AUDIT " then Error first
  else
    let rec lines acc =
      let l = Cmd_deploy_hot.recv_line conn in
      if l = "END" then List.rev acc else lines (l :: acc)
    in
    Ok (lines [])

(** The leader's audit log, as every candidate that answers holds it: the
    union of their lines (a candidate that was down when a line was copied
    lacks it), in time order, the last [n] of them (all for 0). An error only
    when no candidate answered. *)
let audit ?(n = 0) (eps : endpoint list) : (string list, string) result =
  let answers = List.map (fun e -> (e, with_conn e (audit_conn ~n))) eps in
  match List.filter_map (fun (_, r) -> Result.to_option r) answers with
  | [] ->
    Error (Printf.sprintf "no control node answered AUDIT: %s"
             (String.concat "; " (List.filter_map (fun (e, r) ->
                  match r with Error m -> Some (show_endpoint e ^ ": " ^ m) | Ok _ -> None) answers)))
  | lists ->
    let ts l = try Yojson.Safe.Util.(to_number (member "ts" (Yojson.Safe.from_string l))) with _ -> 0. in
    let all = List.sort_uniq compare (List.concat lists) in
    let sorted = List.stable_sort (fun a b -> compare (ts a) (ts b)) all in
    let k = List.length sorted in
    Ok (if n > 0 && k > n then List.filteri (fun i _ -> i >= k - n) sorted else sorted)

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

(** Stage [release] (its serialised, signed text) on [c]: a candidate takes an
    artifact only on a connection that first staged a signed release naming
    it, not older than the candidate's head. *)
let stage c ~(release : string) : (unit, string) result =
  Cmd_deploy_hot.send_line c (Printf.sprintf "STAGE %d" (String.length release));
  Cmd_deploy_hot.send_binary c (Bytes.of_string release) 0 (String.length release);
  let resp = Cmd_deploy_hot.recv_line c in
  if String.length resp >= 2 && String.sub resp 0 2 = "OK" then Ok ()
  else Error (Printf.sprintf "STAGE: %s" resp)

(** Upload [path] as artifact [hash] to every endpoint that lacks it, or
    holds other bytes under it, on a connection that stages [release] (which
    names [hash]) first: both verbs carry the bytes' digest, the one the
    release's ACTIVATE7 lines sign. *)
let upload (eps : endpoint list) ~(release : string) ~(hash : string) ~(path : string) : (unit, string) result =
  let digest = Cmd_deploy_hot.artifact_digest path in
  List.fold_left (fun acc e ->
      let* () = acc in
      match with_conn e (fun c ->
          let* () = stage c ~release in
          if Cmd_deploy_hot.cas_check ~digest c hash then Ok ()
          else (Cmd_deploy_hot.cas_put ~digest c hash path; Ok ())) with
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

(** The hot slots the candidates' nodes have (VERSIONS_DETAIL, relayed by
    the control API to each candidate's own reload server): the names a patch
    can reach. Empty when no candidate answered. *)
let node_slots (eps : endpoint list) : string list =
  List.concat_map (fun e ->
      match with_conn e (fun c ->
          Cmd_deploy_hot.send_line c "VERSIONS_DETAIL";
          Ok (Cmd_deploy_hot.parse_versions_detail c)) with
      | Ok slots -> List.map (fun (d : Cmd_deploy_hot.detail_slot) -> d.ds_name) slots
      | Error _ -> [])
    eps
  |> List.sort_uniq String.compare

(** [old_manifest_path] restricted to the functions that are slots on the
    nodes, written under [dir]: what the recorder answers ABI_QUERY with, so a
    release activates what [forge deploy hot] would activate on a real node
    (a changed function with no slot is not reachable by a hot patch). Not
    every function of a manifest is a slot (the control plane's own wiring,
    spliced into the entry module, has none), and a release recorded against
    one the nodes cannot take is refused by every node as a whole batch
    ([commit_partial_failure]). The manifest as it is when
    the nodes' slots are unknown or none of them is in it (a build no
    candidate runs). *)
let restrict_manifest ~(slots : string list) ~(dir : string) (old_manifest_path : string) : string =
  match In_channel.with_open_bin old_manifest_path In_channel.input_all with
  | exception Sys_error _ -> old_manifest_path
  | text ->
    let set = Hashtbl.create 64 in
    List.iter (fun n -> Hashtbl.replace set n ()) slots;
    let lines = String.split_on_char '\n' text in
    let name l = match String.index_opt l ' ' with Some i -> String.sub l 0 i | None -> l in
    let is_fn l = l <> "" && l.[0] <> '#' in
    let kept = List.filter (fun l -> not (is_fn l) || Hashtbl.mem set (name l)) lines in
    if slots = [] || not (List.exists is_fn kept) then old_manifest_path
    else begin
      mkdir_p dir;
      let p = Filename.concat dir (Filename.basename old_manifest_path ^ ".slots") in
      Out_channel.with_open_bin p (fun oc -> output_string oc (String.concat "\n" kept));
      p
    end

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
  let slots = if sp.hot = [] then [] else node_slots sp.endpoints in
  let* parts =
    List.fold_left (fun acc hb ->
        let* acc = acc in
        let dir = Filename.concat sp.work_dir ("rec-" ^ hb.hb_name) in
        let* lines =
          record_hot ~dir ~seq ~sk:sp.sk ~pubkey:sp.pubkey
            ~old_manifest_path:(restrict_manifest ~slots ~dir hb.hb_old_manifest) ~manifest:hb.hb_manifest ~so_path:hb.hb_so
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

(** The step a decision line is about ("step 2: ..."), if any. *)
let step_of_decision (d : string) : int option =
  try Scanf.sscanf d "step %d:" (fun n -> Some n) with _ -> None

(** Poll STATUS until the release [seq] completes or halts, printing the
    leader's decision as it changes, each under the step it is about when
    [steps] describes them (a step's [Control_release.show_step]). A halted
    release is an error naming the step, the node and why; nothing is rolled
    back (a rollback is a new release). *)
let follow ?(steps : Control_release.step list = []) (eps : endpoint list) ~(seq : int) ~(timeout_s : float)
  : (string, string) result =
  let t0 = Unix.gettimeofday () in
  let last = ref "" and last_step = ref 0 in
  let total = List.length steps in
  (* Every step up to [n] gets its line once, in order, including the ones
     a poll did not catch (begun and done between two polls). *)
  let announce n =
    while !last_step < n do
      incr last_step;
      match List.find_opt (fun (st : Control_release.step) -> st.id = !last_step) steps with
      | Some st ->
        Printf.printf "  step %d of %d: %s%s\n%!" !last_step total (Control_release.show_step st)
          (if !last_step < n then " (done)" else "")
      | None -> ()
    done
  in
  let rec go misses =
    if Unix.gettimeofday () -. t0 > timeout_s then Error (Printf.sprintf "release %d did not finish within %.0f s (the leader keeps working on it: `forge deploy --status` follows it)" seq timeout_s)
    else match status eps with
      | Error m ->
        (* A leader change is a gap in the answers, not a failure. *)
        if misses > 30 then Error m else (Unix.sleepf 1.0; go (misses + 1))
      | Ok s ->
        if s.head_seq = seq then begin
          if s.decision <> !last then begin
            last := s.decision;
            (match step_of_decision s.decision with
             | Some n -> announce n
             | None -> if s.state = "complete" then announce (total + 1));
            Printf.printf "    %s\n%!" s.decision;
            List.iter (fun n -> Printf.printf "    note: %s\n%!" n) s.notes
          end;
          if s.state = "complete" then Ok (render_status s)
          else if s.state = "halted" then Error (Printf.sprintf "the release halted: %s\n%s" s.decision (render_status s))
          else (Unix.sleepf 1.0; go 0)
        end else if s.head_seq > seq then
          Error (Printf.sprintf "a newer release (%d) superseded this one before it finished" s.head_seq)
        else (Unix.sleepf 1.0; go 0)
  in
  go 0

(** The release for [sp] over the leader's current head, and that head. *)
let prepare (sp : spec) : (status * Control_release.t, string) result =
  let* head = status_wait sp.endpoints in
  Printf.printf "control plane: leader %s, head release %d\n%!" head.leader head.head_seq;
  let* release = build_release sp ~head in
  Ok (head, release)

(** Upload every artifact [release] names to every candidate that lacks it:
    a release must never name what a candidate cannot serve. *)
let upload_artifacts (sp : spec) (release : Control_release.t) : (unit, string) result =
  let body = Control_release.serialize release in
  let upload = upload ~release:body in
  let* () =
    List.fold_left (fun acc hb ->
        let* () = acc in
        Printf.printf "uploading the %s patch (%s)\n%!" hb.hb_name hb.hb_manifest.Cmd_deploy_hot.cas_hash;
        upload sp.endpoints ~hash:hb.hb_manifest.Cmd_deploy_hot.cas_hash ~path:hb.hb_so)
      (Ok ()) sp.hot
  in
  if sp.push_topology then begin
    Printf.printf "uploading the topology (%s)\n%!" release.Control_release.topology;
    let p = write_tmp sp.work_dir "topology.json" sp.topology_body in
    upload sp.endpoints ~hash:release.Control_release.topology ~path:p
  end else Ok ()

(** Send [release] and follow it to its end. *)
let send_and_follow (sp : spec) (release : Control_release.t) : (string, string) result =
  let body = Control_release.serialize release in
  (match Sys.getenv_opt "FORGE_RELEASE_OUT" with
   | Some f when f <> "" -> Out_channel.with_open_bin f (fun oc -> output_string oc body)
   | _ -> ());
  let* resp = send_release sp.endpoints ~body in
  Printf.printf "release %d accepted (%s)\n%!" release.Control_release.seq resp;
  follow ~steps:release.Control_release.steps sp.endpoints ~seq:release.Control_release.seq ~timeout_s:sp.follow_s

(** The whole deploy: status, release, upload, send, follow. *)
let run (sp : spec) : (string, string) result =
  let* (_, release) = prepare sp in
  let* () = upload_artifacts sp release in
  send_and_follow sp release
