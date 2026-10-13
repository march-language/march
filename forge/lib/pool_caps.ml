(** The widening gate for a pool's derived capabilities (distributed-deploys
    plan D22, D26; build step 7).

    A pool whose [caps] the topology leaves out gets them derived by the
    compiler from what its hook and roles reach ([Topology_run.compiler_derived],
    [march --topology ... --emit-core-ast]'s [topology] object). Derived must
    not mean unchecked: a code change that makes a pool reach a new capability
    is a widening, and goes through the same monotonicity gate as a hot
    deploy's function and role caps:

    - [forge deploy hot] stops before building unless every widened cap is
      authorized by a [--grant-cap] (a plain capability name, matched by
      subsumption exactly as for function caps: [--grant-cap IO.FileSystem]
      covers a widening to [IO.FileWrite]). A grant is not scoped to a pool:
      it authorizes that capability for every pool that widens to it;
    - [forge deploy --plan] marks it and [forge deploy] blocks the pool
      ([Deploy_plan.classify], since build step 10b);
    - [forge build] warns.

    {1 The baseline}

    What was deployed is [.forge/deploy/<env>/derived.json], the file
    [forge deploy] (ssh and cluster backends) already records on a complete
    deploy: [{ "<pool>": { "caps": [...], "initiates": [...] } }]. A
    [forge deploy hot] that completes on every server writes it too, so the
    two commands share one baseline per environment ([<env>] is the
    [--env] name, ["default"] without one). *)

type derived = Deploy_plan.derived

(* ── The file ─────────────────────────────────────────────────────────── *)

let derived_of_json j : derived option =
  let module U = Yojson.Safe.Util in
  try
    Some (List.map (fun (pool, v) ->
        (pool, (List.map U.to_string (U.to_list (U.member "caps" v)),
                List.map U.to_string (U.to_list (U.member "initiates" v)))))
        (U.to_assoc j))
  with _ -> None

let derived_json (d : derived) : Yojson.Safe.t =
  `Assoc (List.map (fun (pool, (caps, inits)) ->
      (pool, `Assoc [ ("caps", `List (List.map (fun s -> `String s) caps));
                      ("initiates", `List (List.map (fun s -> `String s) inits)) ])) d)

let baseline_file ~root env = Filename.concat (Reconcile.deploy_dir ~root env) "derived.json"

let read_file path : derived option =
  if not (Sys.file_exists path) then None
  else match Yojson.Safe.from_file path with
    | j -> derived_of_json j
    | exception _ -> None

let read_baseline ~root env = read_file (baseline_file ~root env)

let record ~root env (d : derived) =
  let path = baseline_file ~root env in
  Reconcile.mkdir_p (Filename.dirname path);
  Yojson.Safe.to_file path (derived_json d)

(* ── The comparison ───────────────────────────────────────────────────── *)

type widening = {
  w_pool     : string;
  w_prior    : string list;               (** the pool's caps as last deployed *)
  w_added    : string list;               (** caps no prior cap subsumes *)
  w_granted  : (string * string) list;    (** (cap, the --grant-cap covering it) *)
  w_ungranted : string list;              (** what still stops the deploy *)
}

(** Every pool of [current] whose derived caps widen relative to [prior]. A
    pool absent from [prior] widens by all of its caps (new code is new
    authority), as [Deploy_plan.classify] counts it. Narrowing is always
    allowed and is not reported here. *)
let widenings ~(prior : derived) ~(current : derived) ~(grant_caps : string list) : widening list =
  let norm = March_caps.Cap_lattice.normalize in
  List.filter_map (fun (pool, (caps, _)) ->
      let before = match List.assoc_opt pool prior with Some (c, _) -> norm c | None -> [] in
      match Cmd_deploy_hot.compute_cap_widening ~prior:before ~new_caps:(norm caps) with
      | [] -> None
      | added ->
        let ungranted = Cmd_deploy_hot.filter_granted_widening ~widening:added ~grant_caps in
        let granted =
          List.filter_map (fun c ->
              if List.mem c ungranted then None
              else
                Option.map (fun g -> (c, g))
                  (List.find_opt (fun g -> March_caps.Cap_lattice.cap_subsumes g c) grant_caps))
            added
        in
        Some { w_pool = pool; w_prior = before; w_added = added; w_granted = granted; w_ungranted = ungranted })
    current

let env_label env = match env with Some e -> "env " ^ e | None -> "the default environment"
let env_flag env = match env with Some e -> " --env " ^ e | None -> ""

(** The refusal, in the shape of [Cmd_deploy_hot.print_widening_diagnostic]:
    one block per pool that still has an ungranted widening. *)
let refusal_text ?env (ws : widening list) : string =
  let b = Buffer.create 256 in
  let ws = List.filter (fun w -> w.w_ungranted <> []) ws in
  List.iter (fun w ->
      Printf.bprintf b "error: hot deploy would widen pool %s's derived capabilities (D26)\n" w.w_pool;
      Printf.bprintf b "  last deployed caps:    %s   (%s)\n"
        (if w.w_prior = [] then "(none)" else String.concat ", " w.w_prior) (env_label env);
      List.iter (fun c -> Printf.bprintf b "  new version adds:      %s\n" c) w.w_ungranted)
    ws;
  let caps = List.sort_uniq String.compare (List.concat_map (fun w -> w.w_ungranted) ws) in
  if caps <> [] then begin
    Printf.bprintf b "  A hot deploy may only narrow authority. To authorize this widening, re-run with:\n";
    Printf.bprintf b "      forge deploy hot%s %s\n" (env_flag env)
      (String.concat " " (List.map (fun c -> "--grant-cap " ^ c) caps))
  end;
  Buffer.contents b

let granted_lines (ws : widening list) : string list =
  List.concat_map (fun w ->
      List.map (fun (c, g) ->
          Printf.sprintf "  granted widening: pool %s gains %s (via --grant-cap %s)" w.w_pool c g)
        w.w_granted)
    ws

(* ── The gates ────────────────────────────────────────────────────────── *)

let default_derive (proj : Project.project) = Topology_run.compiler_derived proj

(** [forge deploy hot]'s gate, run after [Topology.gate] (which writes the
    digest the derivation reads) and before anything is built. [Ok record]:
    the deploy may go ahead, and [record ()] after it completes on every
    server makes this version's derived caps the next baseline. Without a
    topology.toml it is a no-op. With no baseline yet it is permissive (as the
    function-caps gate is on a first deploy). When a baseline exists but the
    caps cannot be derived, it refuses: the gate never passes blind. *)
let deploy_gate ?(derive = default_derive) ~(proj : Project.project) ~(env : string option)
    ~(grant_caps : string list) () : (unit -> unit, string) result =
  let root = proj.Project.root in
  if not (Topology.exists ~root) then Ok (fun () -> ())
  else
    let prior = read_baseline ~root env in
    match derive proj, prior with
    | Error m, None ->
      Printf.eprintf "warning: derived pool caps unavailable: %s\n%!" m;
      Ok (fun () -> ())
    | Error m, Some _ ->
      Error (Printf.sprintf
               "derived pool caps unavailable (%s), so the pool widening gate (D26) cannot compare them with \
                the last deploy to %s: deploy aborted" m (env_label env))
    | Ok current, None ->
      Printf.printf
        "NOTE: no recorded derived pool caps for %s — the pool widening gate is permissive for this deploy (first deploy).\n%!"
        (env_label env);
      Ok (fun () -> record ~root env current)
    | Ok current, Some prior ->
      let ws = widenings ~prior ~current ~grant_caps in
      List.iter (fun l -> print_endline l) (granted_lines ws);
      if List.exists (fun w -> w.w_ungranted <> []) ws then begin
        prerr_string (refusal_text ?env ws);
        flush stderr;
        Error "pool capability widening — deploy aborted"
      end else Ok (fun () -> record ~root env current)

(** The environments with a recorded baseline, by [.forge/deploy/<env>]. *)
let recorded_envs ~root : string option list =
  let d = Filename.concat (Filename.concat root ".forge") "deploy" in
  match Sys.readdir d with
  | names ->
    List.filter_map (fun n ->
        if Sys.file_exists (Filename.concat (Filename.concat d n) "derived.json")
        then Some (if n = Reconcile.env_key None then None else Some n) else None)
      (List.sort String.compare (Array.to_list names))
  | exception Sys_error _ -> []

(** [forge build]'s warnings: one line per pool whose derived caps widen
    relative to each environment's last recorded deploy. Runs the derivation
    only when some baseline exists. *)
let build_warnings ?(derive = default_derive) ~(proj : Project.project) () : string list =
  let root = proj.Project.root in
  if not (Topology.exists ~root) then []
  else
    match recorded_envs ~root with
    | [] -> []
    | envs ->
      match derive proj with
      | Error _ -> []
      | Ok current ->
        List.concat_map (fun env ->
            match read_baseline ~root env with
            | None -> []
            | Some prior ->
              List.map (fun w ->
                  Printf.sprintf
                    "warning: pool %s's derived caps widen since the last deploy to %s: adds %s; \
                     deploying it needs %s"
                    w.w_pool (env_label env) (String.concat ", " w.w_added)
                    (String.concat " " (List.map (fun c -> "--grant-cap " ^ c) w.w_added)))
                (widenings ~prior ~current ~grant_caps:[]))
          envs
