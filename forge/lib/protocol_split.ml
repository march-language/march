(** Expand/contract (D21, distributed-deploys build step 9, item 6).

    A compatible protocol change (rule one: a `choose` gains a branch) is safe
    only when every role that RECEIVES that choice runs the new version before
    the role that MAKES it does (plan 6.4). When the chooser and a receiver
    are in different builds, one deploy does it, receivers' builds first.
    When one build holds both (a replicated monolith, 4.2), no order inside
    one deploy can do it, so the change becomes two deploys:

    1. {b expand}: every build, compiled with [--protocol-expand P:label]. The
       receivers run the new protocol; the chooser keeps offering and
       initiating under the PREVIOUS fingerprint (its sessions form with old
       and new receivers alike, which both accept that fingerprint) and its
       generated [choose_<label>] refuses to run, so nothing picks the new
       branch while an old receiver could still be in a session.
    2. {b contract}: the plain new build. Every receiver already runs the new
       version, so the chooser may now choose the new branch.

    [plan] is what `forge deploy --plan` calls (step 10b's classifier is not
    on main yet; this is its entry point for protocol changes). It reads
    only the protocol versions and which roles each build contains, so it is
    pure and testable without a cluster. *)

module E = March_desugar.Desugar_endpoints

(** One protocol's change: its previous and new versions. *)
type change = { old_ : E.version; new_ : E.version }

(** A build (a pool's binary, or the monolith's one) and the roles it
    contains, as "Protocol.Role". *)
type build = { b_name : string; b_roles : string list }

type deploy = {
  d_label  : string;          (** "expand", "contract", or "deploy" *)
  d_builds : string list;     (** in rollout order *)
  d_flags  : string list;     (** extra compiler flags for this deploy's builds *)
  d_why    : string;
}

type verdict =
  | Unchanged                           (** no protocol changed its fingerprint *)
  | One of deploy                       (** one deploy, receivers' builds first *)
  | Split of deploy * deploy            (** expand, then contract (D21) *)
  | Breaking of string list             (** per protocol, why it is not rule one *)

let holds (b : build) proto role = List.mem (proto ^ "." ^ role) b.b_roles

(** The expand flag for one protocol's changed choice. *)
let expand_flag ~proto ~label = Printf.sprintf "--protocol-expand %s:%s" proto label

(** Order [builds] so every build holding a receiver of a changed choice
    comes before any build holding its chooser; stable otherwise. *)
let receivers_first (compat : (string * string * string list) list) (builds : build list) : string list =
  let is_chooser b = List.exists (fun (p, c, _) -> holds b p c) compat in
  let first, later = List.partition (fun b -> not (is_chooser b)) builds in
  List.map (fun b -> b.b_name) (first @ later)

let plan (changes : change list) (builds : build list) : verdict =
  let verdicts =
    List.filter_map
      (fun c ->
         match E.compare_versions ~old_:c.old_ ~new_:c.new_ with
         | E.Same -> None
         | E.Compatible { chooser; label; receivers } -> Some (c.new_.v_proto, Ok (chooser, label, receivers))
         | E.Incompatible why -> Some (c.new_.v_proto, Error why))
      changes
  in
  match verdicts with
  | [] -> Unchanged
  | _ ->
    let broken = List.filter_map (fun (p, v) -> match v with Error w -> Some (p ^ ": " ^ w) | Ok _ -> None) verdicts in
    if broken <> [] then Breaking broken
    else begin
      let compat = List.filter_map (fun (p, v) -> match v with Ok (c, l, r) -> Some (p, c, l, r) | Error _ -> None) verdicts in
      (* A protocol needs the split when some build holds its chooser and
         one of its receivers. *)
      let needs_split (p, c, _, rs) =
        List.exists (fun b -> holds b p c && List.exists (fun r -> holds b p r) rs) builds
      in
      let split = List.filter needs_split compat in
      let all = List.map (fun b -> b.b_name) builds in
      if split = [] then
        One
          { d_label = "deploy";
            d_builds = receivers_first (List.map (fun (p, c, _, rs) -> (p, c, rs)) compat) builds;
            d_flags = [];
            d_why =
              String.concat "; "
                (List.map
                   (fun (p, c, l, _) ->
                      Printf.sprintf "%s: `choose by %s` gained `%s`; the builds that receive it go first" p c l)
                   compat) }
      else
        let names = String.concat ", " (List.map (fun (p, c, l, _) -> Printf.sprintf "%s (`choose by %s` gained `%s`)" p c l) split) in
        Split
          ( { d_label = "expand";
              d_builds = all;
              d_flags = List.map (fun (p, _, l, _) -> expand_flag ~proto:p ~label:l) split;
              d_why =
                "one build both makes and receives a changed choice in " ^ names
                ^ ": receivers take the new version while the chooser stays on the previous fingerprint \
                   and does not pick the new branch" },
            { d_label = "contract";
              d_builds = all;
              d_flags = [];
              d_why = "every receiver runs the new version; the chooser may now pick the new branch" } )
    end

(** The changes recorded in [root]/.forge/protocols (`--emit-protocols`):
    each protocol whose file keeps a previous version. *)
let changes_of_dir (dir : string) : change list =
  let files =
    if Sys.file_exists dir && Sys.is_directory dir then
      List.sort compare (List.filter (fun f -> Filename.check_suffix f ".json") (Array.to_list (Sys.readdir dir)))
    else []
  in
  List.filter_map
    (fun f ->
       let path = Filename.concat dir f in
       match In_channel.with_open_bin path In_channel.input_all |> E.baseline_of_string with
       | Ok { current; previous = Some prev } -> Some { old_ = prev; new_ = current }
       | Ok _ | Error _ -> None
       | exception Sys_error _ -> None)
    files

let render (v : verdict) : string =
  let dep d =
    Printf.sprintf "  %s: %s%s\n    %s" d.d_label (String.concat " -> " d.d_builds)
      (if d.d_flags = [] then "" else " [" ^ String.concat " " d.d_flags ^ "]") d.d_why
  in
  match v with
  | Unchanged -> "protocols: unchanged"
  | Breaking ws -> "protocols: breaking change (offer both fingerprints while it rolls out)\n" ^ String.concat "\n" (List.map (fun w -> "  " ^ w) ws)
  | One d -> "protocols: one deploy\n" ^ dep d
  | Split (a, b) -> "protocols: two deploys (expand/contract, D21)\n" ^ dep a ^ "\n" ^ dep b

(** The builds of a topology app: one per pool, holding the roles it serves
    and the ones its code initiates (written, else derived: [pool_roles]). *)
let builds_of_topology ~(index : Topology.index) (t : Topology.t) : build list =
  List.map (fun (p : Topology.pool) -> { b_name = p.pool_name; b_roles = Topology.pool_roles index t p }) t.pools

(** A project with no topology is one binary holding every role: the
    monolith case, where every compatible change splits. *)
let monolith_build ~(name : string) (changes : change list) : build =
  { b_name = name;
    b_roles = List.concat_map (fun c -> List.map (fun r -> c.new_.v_proto ^ "." ^ r) c.new_.v_roles) changes }

(** The whole plan for the project at [root], as `forge deploy --plan` will
    ask for it: the changes `.forge/protocols` records since the previous
    build, over the topology's pools (or one build named [name]). *)
let plan_project ~(root : string) ~(name : string) : verdict =
  let changes = changes_of_dir (Filename.concat root (Filename.concat ".forge" "protocols")) in
  let builds =
    if Topology.exists ~root then
      match Topology.load ~root () with
      | Ok t -> builds_of_topology ~index:(Topology.index_project ~root) t
      | Error _ -> [ monolith_build ~name changes ]
    else [ monolith_build ~name changes ]
  in
  plan changes builds
