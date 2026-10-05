(** [forge diagnose]'s findings: a fixed list of checks over two observe
    [SNAPSHOT] envelopes taken a window apart (design section 5.3; R3 of
    specs/plans/2026-09-28-observe-recon-shell-plan.md).

    The same findings, with the same ids and thresholds, are written in March
    in stdlib/diagnose.march for a program to run on itself. Both are tested
    against forge/test/fixtures/diagnose (each fixture's expected ids are in
    its expected.txt), so the two cannot drift silently. Change a threshold
    here and there together. *)

type severity = Warning | Critical

type finding = {
  id : string;
  severity : severity;
  rows : Yojson.Safe.t list;  (** what triggered it *)
  next : string;              (** what to look at next *)
}

let severity_name = function Warning -> "warning" | Critical -> "critical"

(* ── Reading the envelopes ────────────────────────────────────────────── *)

let member k = function `Assoc kv -> (match List.assoc_opt k kv with Some v -> v | None -> `Null) | _ -> `Null
let int_of = function `Int n -> n | `Float f -> int_of_float f | _ -> 0
let num_of = function `Int n -> float_of_int n | `Float f -> f | _ -> 0.0
let list_of = function `List xs -> xs | _ -> []
let str_of = function `String s -> s | _ -> ""

type snap = { at_ms : int; data : Yojson.Safe.t }

let snap_of (env : Yojson.Safe.t) = { at_ms = int_of (member "at_ms" env); data = member "data" env }

let section s name = member name s.data
let actors s = list_of (member "actors" (section s "actors"))
let waiting a = int_of (member "mbox" a) + int_of (member "held" a)
let pid a = int_of (member "pid" a)

(* ── The findings ────────────────────────────────────────────────────── *)

(* 1. An actor's waiting work grew across the window (to at least 10);
   critical when one actor holds over half of a node queue of 100 or more. *)
let mailbox_growth b a =
  let before p = match List.find_opt (fun r -> pid r = p) (actors b) with
    | Some r -> waiting r | None -> 0 in
  let grew =
    List.filter_map (fun r ->
        let d = waiting r - before (pid r) in
        if d > 0 && waiting r >= 10 then Some (r, d) else None) (actors a)
    |> List.sort (fun (_, x) (_, y) -> compare y x)
  in
  if grew = [] then []
  else
    let queued = int_of (member "queued_messages" (section a "mem")) in
    let hog = List.exists (fun (r, _) -> queued >= 100 && 2 * waiting r > queued) grew in
    [ { id = "mailbox.growth"; severity = (if hog then Critical else Warning);
        rows = List.map (fun (r, d) ->
            `Assoc [ "pid", `Int (pid r); "mbox", `Int (waiting r); "delta", `Int d;
                     "names", member "names" r ]) (List.filteri (fun i _ -> i < 5) grew);
        next = "forge observe ACTORS mbox 20, then ACTOR <pid> for the deepest" } ]

(* 2. Actors at their limit under a drop policy while the node dropped. *)
let mailbox_over_limit b a =
  let dropped s = int_of (member "msgs_dropped" (section s "sched")) in
  let at_limit =
    List.filter (fun r ->
        let lim = int_of (member "mbox_limit" r) in
        let pol = str_of (member "mbox_policy" r) in
        lim > 0 && waiting r >= lim && (pol = "drop_new" || pol = "drop_old")) (actors a)
  in
  if at_limit = [] || dropped a <= dropped b then []
  else [ { id = "mailbox.over_limit"; severity = Warning;
           rows = List.map (fun r -> `Assoc [ "pid", `Int (pid r); "limit", member "mbox_limit" r;
                                              "policy", member "mbox_policy" r ]) at_limit;
           next = "the node dropped messages: raise the limit or shed load upstream" } ]

(* Per scheduler over the window: (id, idle ms, wall ms). The checks compare
   by integer cross-multiplication (utilisation = 1 - idle/wall), exactly as
   stdlib/diagnose.march does, so the two never disagree at a boundary. *)
let windows b a =
  let wall = a.at_ms - b.at_ms in
  if wall <= 0 then []
  else
    let idle s = List.map (fun t -> (int_of (member "id" t), int_of (member "idle_ms" t)))
        (list_of (member "threads" (section s "sched"))) in
    let ib = idle b in
    List.filter_map (fun (id, i1) ->
        Option.map (fun i0 -> (id, i1 - i0, wall)) (List.assoc_opt id ib)) (idle a)

let over95 (_, i, w) = 100 * i < 5 * w
let over80 (_, i, w) = 100 * i < 20 * w
let under20 (_, i, w) = 100 * i > 80 * w

(* 3. A scheduler over 95% with work queued; or one over 80% while another
   is under 20%. *)
let sched_findings b a =
  let u = windows b a in
  let runq = int_of (member "runq" (section a "sched")) in
  let row (id, i, w) =
    `Assoc [ "scheduler", `Int id;
             "utilisation", `Float (Float.max 0.0 (Float.min 1.0 (1.0 -. float_of_int i /. float_of_int w))) ] in
  let hot = List.filter over95 u in
  let saturated =
    if hot <> [] && runq > 0 then
      [ { id = "sched.saturated"; severity = Warning; rows = List.map row hot;
          next = "forge observe TOP slices 10 1000: who is using the CPU" } ]
    else [] in
  let imbalance =
    if List.length u >= 2 && List.exists over80 u && List.exists under20 u then
      [ { id = "sched.idle_imbalance"; severity = Warning; rows = List.map row u;
          next = "one scheduler carries the load: look for pinned actors or one hot actor" } ]
    else [] in
  saturated @ imbalance

(* 4. A supervisor whose children crashed 3+ times: critical within the last
   minute, warning within the last hour (the crash ring's at_ms). *)
let crash_loop _b a =
  let now = a.at_ms in
  let entries = list_of (member "crashes" (section a "crashes")) in
  let count_within ms =
    List.fold_left (fun acc e ->
        let sup = member "supervisor" e in
        if sup = `Null || now - int_of (member "at_ms" e) > ms then acc
        else
          let k = int_of sup in
          (k, 1 + (try List.assoc k acc with Not_found -> 0)) :: List.remove_assoc k acc)
      [] entries
  in
  let looping ms = List.filter (fun (_, n) -> n >= 3) (count_within ms) in
  let rows l = List.map (fun (s, n) -> `Assoc [ "supervisor", `Int s; "crashes", `Int n ]) l in
  match looping 60_000, looping 3_600_000 with
  | (_ :: _ as l), _ ->
    [ { id = "crash.loop"; severity = Critical; rows = rows l;
        next = "forge observe CRASHES 20, then ACTOR <supervisor>" } ]
  | [], (_ :: _ as l) ->
    [ { id = "crash.loop"; severity = Warning; rows = rows l;
        next = "forge observe CRASHES 20, then ACTOR <supervisor>" } ]
  | [], [] -> []

(* 5. Live heap objects up more than 10% with the actor count flat (±5%). *)
let rc_climb b a =
  let objs s = member "live_objects" (section s "mem") in
  let acts s = int_of (member "actors" (section s "mem")) in
  match objs b, objs a with
  | `Null, _ | _, `Null -> []   (* no gauge (the interpreter) *)
  | v0, v1 ->
    let o0 = int_of v0 and o1 = int_of v1 in
    let a0 = acts b and a1 = acts a in
    if o0 >= 1000 && o1 * 10 > o0 * 11 && abs (a1 - a0) * 20 <= max a0 1 then
      [ { id = "rc.climb"; severity = Warning;
          rows = [ `Assoc [ "live_objects_before", `Int o0; "live_objects_after", `Int o1;
                            "actors", `Int a1 ] ];
          next = "heap objects climb with no new actors: a leak; compare SNAPSHOT mem over minutes" } ]
    else []

(* 6. A draining epoch; and units pinned two or more epochs behind current. *)
let epoch_findings _b a =
  let e = section a "epochs" in
  let cur = int_of (member "current" e) in
  let pins = list_of (member "pins" e) in
  let row p = `Assoc [ "epoch", member "epoch" p; "pins", member "pins" p ] in
  let draining = List.filter (fun p -> member "draining" p = `Bool true) pins in
  let old = List.filter (fun p -> int_of (member "epoch" p) <= cur - 2 && int_of (member "pins" p) > 0) pins in
  (if draining = [] then [] else
     [ { id = "epoch.stuck"; severity = Warning; rows = List.map row draining;
         next = "forge hot-reload status: an old epoch is still draining" } ])
  @ (if old = [] then [] else
       [ { id = "epoch.old_units"; severity = Warning; rows = List.map row old;
           next = "units still run code two or more deploys old: ACTORS epoch 20" } ])

(* ── Running them ────────────────────────────────────────────────────── *)

let probes = [ "mailbox.growth"; "mailbox.over_limit"; "sched.saturated"; "sched.idle_imbalance";
               "crash.loop"; "rc.climb"; "epoch.stuck"; "epoch.old_units" ]

(* What cannot be checked, so a finding's absence is never read as health. *)
let unavailable = [
  "cluster.suspect", "no cluster section yet (observe plan R1.3)";
  "names.lost", "global-registry Lost events are not recorded";
]

let partial = [
  "mailbox.over_limit", "per-actor dropped counts are not tracked; the node total is used";
]

(** All findings over a before/after pair of [SNAPSHOT] envelopes. *)
let run ~(before : Yojson.Safe.t) ~(after : Yojson.Safe.t) : finding list =
  let b = snap_of before and a = snap_of after in
  List.concat [ mailbox_growth b a; mailbox_over_limit b a; sched_findings b a;
                crash_loop b a; rc_climb b a; epoch_findings b a ]

(** 0 nothing found, 1 warnings only, 2 at least one critical. (3, could not
    connect, is decided by the caller.) *)
let exit_code (fs : finding list) =
  if List.exists (fun f -> f.severity = Critical) fs then 2
  else if fs <> [] then 1 else 0

(** The [march.diagnose/1] envelope. *)
let to_json ~node ~window_ms (fs : finding list) : Yojson.Safe.t =
  `Assoc [
    "proto", `String "march.diagnose/1";
    "node", `String node;
    "window_ms", `Int window_ms;
    "findings", `List (List.map (fun f ->
        `Assoc [ "id", `String f.id; "severity", `String (severity_name f.severity);
                 "rows", `List f.rows; "next", `String f.next ]) fs);
    "coverage", `Assoc [
      "ran", `List (List.map (fun p -> `String p) probes);
      "unavailable", `Assoc (List.map (fun (k, v) -> (k, `String v)) unavailable);
      "partial", `Assoc (List.map (fun (k, v) -> (k, `String v)) partial);
    ];
  ]

(** "id/severity" for each finding, sorted: the form expected.txt uses. *)
let ids (fs : finding list) =
  List.map (fun f -> f.id ^ "/" ^ severity_name f.severity) fs |> List.sort compare
