(** [forge observe]'s panels (R7 of specs/plans/2026-09-28-observe-recon-shell-plan.md,
    design §5.1): one pure function per panel from a node's reply to a
    [Notty.image], so the tests render fixtures to text with no terminal, and
    the same code draws the live screen ([Observe_tui_live]) and a crash dump.

    {1 Inputs}

    A panel renders a {e reply}: the observe envelope
    [{"proto":"march.observe/1","node":…,"at_ms":…,"data":…}]. Which verb
    produced it is the panel's business ([request_of]):

    - System, Load, Supervision, Names, Epochs, Crashes read sections of a
      [SNAPSHOT] reply ([mem], [sched], [tree], [names], [epochs], [crashes],
      [actors]);
    - Actors reads a [TOP] reply (the ranking on the node, with supervision
      columns) or, when there is none (a crash dump), the snapshot's [actors]
      section ranked here;
    - Actor reads an [ACTOR <pid>] reply;
    - Cluster reads a [CLUSTER] reply.

    {1 Adding a panel}

    The Trace panel (R8) is one constructor in [panel] and one case in each of
    [title], [live_only], [request_of] and [render]; nothing else in this file
    or in [Observe_tui_live] enumerates the panels (they use [all_panels]). *)

open Notty

let jm = Cmd_observe.jm
let ji = Cmd_observe.ji
let jl = Cmd_observe.jl
let js = Cmd_observe.js

type panel = System | Load | Actors | Actor | Supervision | Names | Epochs | Cluster | Crashes

(** Left to right on the tab line; the position + 1 is the key that opens it. *)
let all_panels = [ System; Load; Actors; Actor; Supervision; Names; Epochs; Cluster; Crashes ]

let title = function
  | System -> "System" | Load -> "Load" | Actors -> "Actors" | Actor -> "Actor"
  | Supervision -> "Supervision" | Names -> "Names" | Epochs -> "Epochs"
  | Cluster -> "Cluster" | Crashes -> "Crashes"

let panel_of_string s =
  List.find_opt (fun p -> String.lowercase_ascii (title p) = String.lowercase_ascii s) all_panels

(** Panels a crash dump cannot fill: they need a question asked of a live node. *)
let live_only = function
  | Actor | Cluster -> true
  | System | Load | Actors | Supervision | Names | Epochs | Crashes -> false

(** The SNAPSHOT sections the stream carries: everything the snapshot-fed
    panels read. *)
let snapshot_sections = "mem,sched,epochs,crashes,tree,names,actors"

(** The sort keys of the Actors panel, in the order [s] cycles them. [TOP]
    ranks on the node; counters are cumulative here (a window would hold the
    node's connection thread for its length on every refresh). *)
let sorts = [ "mbox"; "stack"; "crashes"; "slices"; "msgs_in"; "msgs_out" ]

let next_sort s =
  let rec go = function
    | a :: (b :: _) when a = s -> b
    | _ :: rest -> go rest
    | [] -> List.hd sorts in
  go sorts

(** What a live panel asks the node, besides the stream: [None] when the
    snapshot already holds it. *)
let request_of ~(sort : string) ~(pid : int option) = function
  | Actors -> Some (Printf.sprintf "TOP %s 100" sort)
  | Actor -> Option.map (Printf.sprintf "ACTOR %d") pid
  | Cluster -> Some "CLUSTER"
  | System | Load | Supervision | Names | Epochs | Crashes -> None

(* ── Context and small helpers ───────────────────────────────────────── *)

type ctx = {
  width : int;
  height : int;
  sort : string;
  selected : int;          (** row index in the panel's selectable list *)
  history : float list;    (** mean scheduler busy fraction per frame, oldest first *)
  dump : bool;             (** rendering a crash dump: ages are against the dump *)
}

let default_ctx = { width = 120; height = 40; sort = "mbox"; selected = 0; history = []; dump = false }

let dim = A.(fg lightblack)
let bold = A.(st bold)
let warn = A.(fg yellow)
let crit = A.(fg red ++ st bold)
let good = A.(fg green)

(** Controls and anything else a terminal would act on, replaced: a panel
    shows names and panic text taken from the node. *)
let clean (s : string) : string =
  String.map (fun c -> if Char.code c < 0x20 || Char.code c = 0x7f then '?' else c) s

let fit n s =
  let s = clean s in
  if String.length s <= n then s else if n <= 1 then String.sub s 0 (max 0 n) else String.sub s 0 (n - 1) ^ "~"

let line attr s = (attr, s)

(** Lines to an image [width] wide; a selected line is reversed. *)
let image_of_lines ~(width : int) ?(selected_line : int option) (lines : (A.t * string) list) : image =
  let rows = List.mapi (fun i (attr, s) ->
      let attr = if Some i = selected_line then A.(attr ++ st reverse) else attr in
      let s = fit width s in
      let s = if Some i = selected_line then s ^ String.make (max 0 (width - String.length s)) ' ' else s in
      if s = "" then I.void 0 1 else I.string attr s) lines in
  I.vcat rows

let kv ~(w : int) k v = Printf.sprintf "%-*s %s" w k v

let human_bytes n =
  let f = float_of_int n in
  if n < 1024 then Printf.sprintf "%d B" n
  else if n < 1024 * 1024 then Printf.sprintf "%.1f KiB" (f /. 1024.)
  else if n < 1024 * 1024 * 1024 then Printf.sprintf "%.1f MiB" (f /. 1048576.)
  else Printf.sprintf "%.2f GiB" (f /. 1073741824.)

let age_text ms =
  if ms < 0 then "in the future"
  else if ms < 1000 then Printf.sprintf "%d ms" ms
  else if ms < 60_000 then Printf.sprintf "%d s" (ms / 1000)
  else if ms < 3_600_000 then Printf.sprintf "%d min" (ms / 60_000)
  else Printf.sprintf "%.1f h" (float_of_int ms /. 3_600_000.)

let utc_text at_ms =
  if at_ms <= 0 then "-"
  else
    let t = Unix.gmtime (float_of_int at_ms /. 1000.) in
    Printf.sprintf "%04d-%02d-%02d %02d:%02d:%02d UTC" (t.Unix.tm_year + 1900) (t.Unix.tm_mon + 1)
      t.Unix.tm_mday t.Unix.tm_hour t.Unix.tm_min t.Unix.tm_sec

let data_of (reply : Yojson.Safe.t) = Observe_client.data_of reply
let section name reply = jm name (data_of reply)
let at_ms reply = ji (jm "at_ms" reply)
let names_of r = List.filter_map (function `String s -> Some s | _ -> None) (jl (jm "names" r))
let label r = match names_of r with n :: _ -> n | [] -> js (jm "type" r)
let opt_int = function `Null -> None | `Int n -> Some n | `Float f -> Some (int_of_float f) | _ -> None
let opt_float = function `Float f -> Some f | `Int n -> Some (float_of_int n) | _ -> None

(** A dumb-terminal text rendering of [img], trailing blanks trimmed: what the
    tests compare and [forge observe --panel] prints. *)
let text_of_image (img : image) : string =
  let w = I.width img and h = I.height img in
  let b = Buffer.create 1024 in
  Render.to_buffer b Cap.dumb (0, 0) (w, h) img;
  let raw = Buffer.contents b in
  let ls = String.split_on_char '\n' raw in
  let rtrim s =
    let n = ref (String.length s) in
    while !n > 0 && (s.[!n - 1] = ' ' || s.[!n - 1] = '\r') do decr n done;
    String.sub s 0 !n in
  String.concat "\n" (List.map rtrim ls) ^ "\n"

let unavailable ~(width : int) (what : string) : image =
  image_of_lines ~width [ line dim what ]

(* ── Panels ──────────────────────────────────────────────────────────── *)

let render_system (c : ctx) (reply : Yojson.Safe.t) : image =
  let mem = section "mem" reply and sched = section "sched" reply and ep = section "epochs" reply in
  let crashes = section "crashes" reply in
  let w = 18 in
  let now = at_ms reply in
  let hour = List.length (List.filter (fun e -> now - ji (jm "at_ms" e) <= 3_600_000)
                            (jl (jm "crashes" crashes))) in
  let summary = Cmd_observe.summary_of (data_of reply) ~now_ms:now in
  let rss = match opt_int (jm "rss_bytes" mem) with Some n -> human_bytes n | None -> "-" in
  let lines = [
    line bold (Cmd_observe.summary_line summary);
    line dim "";
    line A.empty (kv ~w "node" (let n = js (jm "node" reply) in if n = "" then "-" else n));
    line A.empty (kv ~w (if c.dump then "dumped at" else "sampled at") (utc_text now));
    line A.empty (kv ~w "actors" (Printf.sprintf "%d   queued messages %d" (ji (jm "actors" mem))
                                    (ji (jm "queued_messages" mem))));
    line A.empty (kv ~w "memory" (Printf.sprintf "rss %s   peak %s   live heap objects %d" rss
                                    (human_bytes (ji (jm "peak_rss_bytes" mem))) (ji (jm "live_objects" mem))));
    line A.empty (kv ~w "schedulers" (Printf.sprintf "%d   run queue %d   live procs %d"
                                        (ji (jm "schedulers" sched)) (ji (jm "runq" sched))
                                        (ji (jm "live_procs" sched))));
    line A.empty (kv ~w "code epoch" (if ep = `Null then "-" else string_of_int (ji (jm "current" ep))));
    line A.empty (kv ~w "hot-reload slots" (string_of_int (List.length (jl (jm "slots" ep)))));
    line (if hour > 0 then warn else A.empty)
      (kv ~w "crashes" (Printf.sprintf "%d in the last hour, %d in the ring" hour
                          (List.length (jl (jm "crashes" crashes)))));
    line A.empty (kv ~w "reply cost" (Printf.sprintf "%d us%s" (ji (jm "took_us" reply))
                                        (if Observe_client.truncated reply then "   TRUNCATED" else "")));
  ] in
  image_of_lines ~width:c.width lines

let bar ~(width : int) (f : float) : string =
  let f = Float.max 0. (Float.min 1. f) in
  let filled = int_of_float (Float.round (f *. float_of_int width)) in
  "[" ^ String.make filled '#' ^ String.make (width - filled) '.' ^ "]"

let spark_chars = [| "_"; "."; "o"; "O"; "0" |]

(** One character per frame, taller for busier. *)
let sparkline (vals : float list) : string =
  String.concat "" (List.map (fun v ->
      let i = int_of_float (Float.round (Float.max 0. (Float.min 1. v) *. 4.)) in
      spark_chars.(i)) vals)

let render_load (c : ctx) (reply : Yojson.Safe.t) : image =
  let sched = section "sched" reply and mem = section "mem" reply in
  let threads = jl (jm "threads" sched) in
  let hdr = Printf.sprintf "%-5s %-24s %6s %12s %12s %10s" "SCHED" "BUSY (since start)" "" "IDLE ms" "DISPATCHES" "IDLE POLLS" in
  let rows = List.map (fun t ->
      let u = match opt_float (jm "utilisation" t) with Some u -> Some u | None -> opt_float (jm "lifetime_utilisation" t) in
      let b, pct = match u with
        | Some u -> bar ~width:20 u, Printf.sprintf "%3.0f%%" (100. *. u)
        | None -> bar ~width:20 0., "  -" in
      line A.empty (Printf.sprintf "S%-4d %-24s %6s %12d %12d %10d" (ji (jm "id" t)) b pct
                      (ji (jm "idle_ms" t)) (ji (jm "dispatches" t)) (ji (jm "idle_polls" t)))) threads in
  let hist = match c.history with
    | [] -> []
    | h ->
      let n = max 1 (c.width - 24) in
      let h = if List.length h > n then List.filteri (fun i _ -> i >= List.length h - n) h else h in
      [ line A.empty (Printf.sprintf "mean busy per frame  %s" (sparkline h)) ] in
  let g k = string_of_int (ji (jm k sched)) in
  let lines =
    line bold hdr :: rows
    @ [ line dim "" ]
    @ hist
    @ [ line A.empty (Printf.sprintf "run queue %s   live procs %s   spawned %s   timers %s"
                        (g "runq") (g "live_procs") (g "procs_spawned") (g "timers"));
        line (if ji (jm "msgs_dropped" sched) > 0 then warn else A.empty)
          (Printf.sprintf "messages dropped %s   stack failures %s   stacks recycled %s"
             (g "msgs_dropped") (g "stack_failures") (g "stacks_recycled"));
        line A.empty (Printf.sprintf "awaiting free: procs %s, metas %s   freed: procs %s, metas %s"
                        (g "procs_awaiting_free") (g "metas_awaiting_free") (g "procs_freed") (g "metas_freed"));
        line A.empty (Printf.sprintf "heap objects live %d   queued messages %d" (ji (jm "live_objects" mem))
                        (ji (jm "queued_messages" mem))) ] in
  image_of_lines ~width:c.width lines

(** The Actors rows as [TOP] rows: a [TOP] reply as it is; otherwise the
    snapshot's [actors] rows, ranked by [sort] here. *)
let actor_rows (c : ctx) (reply : Yojson.Safe.t) : Yojson.Safe.t list =
  match jm "top" (data_of reply) with
  | `List rows -> rows
  | _ ->
    let rows = jl (jm "actors" (section "actors" reply)) in
    let value r = match c.sort with
      | "stack" -> ji (jm "stack_bytes" r)
      | "crashes" -> ji (jm "crashes" r) + ji (jm "child_crashes" r)
      | "slices" -> ji (jm "slices" r)
      | "msgs_in" -> ji (jm "msgs_in" r)
      | "msgs_out" -> ji (jm "msgs_out" r)
      | _ -> ji (jm "mbox" r) + ji (jm "held" r) in
    let as_top r =
      let link = match jm "parent" r, jm "spawned_by" r with
        | `Int _, _ -> "supervised" | _, `Int _ -> "spawned" | _ -> "none" in
      match r with
      | `Assoc kv ->
        `Assoc (("value", `Int (value r)) :: ("link", `String link)
                :: List.filter (fun (k, _) -> k <> "mbox" && k <> "link") kv
                @ [ "mbox", `Int (ji (jm "mbox" r) + ji (jm "held" r)) ])
      | v -> v in
    List.map as_top rows
    |> List.stable_sort (fun a b ->
        let c = compare (ji (jm "value" b)) (ji (jm "value" a)) in
        if c <> 0 then c else compare (ji (jm "pid" a)) (ji (jm "pid" b)))

let pids_of_rows rows = List.map (fun r -> ji (jm "pid" r)) rows

let render_actors (c : ctx) (reply : Yojson.Safe.t) : image =
  let rows = actor_rows c reply in
  if rows = [] then unavailable ~width:c.width "no actors"
  else
    let total = match jm "total" (data_of reply) with `Int n -> n | _ -> List.length rows in
    let head = [ line dim (Printf.sprintf "ranked by %s (s cycles: %s)   showing %d of %d"
                             c.sort (String.concat " " sorts) (List.length rows) total);
                 line bold (Cmd_observe.top_header c.sort) ] in
    let body = List.map (fun r -> line A.empty (Cmd_observe.top_row_line r)) rows in
    image_of_lines ~width:c.width ~selected_line:(List.length head + c.selected) (head @ body)

let render_actor (c : ctx) (reply : Yojson.Safe.t) : image =
  let d = data_of reply in
  match d with
  | `Null -> unavailable ~width:c.width "no actor selected: press Enter on a row in Actors, Supervision or Crashes"
  | _ ->
    let a = jm "actor" d in
    let w = 14 in
    let pid = ji (jm "pid" d) in
    let alive = jm "alive" d = `Bool true in
    let pids l = String.concat " " (List.map (fun v -> string_of_int (ji v)) l) in
    let sup = jm "supervisor" d in
    let head = [ line bold (Printf.sprintf "actor %d  %s" pid (if alive then "alive" else "dead")) ] in
    let body =
      if a = `Null then
        [ line dim "not running" ]
        @ (match jm "terminal" d with
            | `Assoc _ as t -> [ line A.empty (kv ~w "died" (js (jm "kind" t))) ]
            | _ -> [])
      else
        [ line A.empty (kv ~w "type" (let t = js (jm "type" a) in if t = "" then "-" else t));
          line A.empty (kv ~w "names" (match names_of a with [] -> "-" | l -> String.concat ", " l));
          line A.empty (kv ~w "status" (js (jm "status" a)));
          line A.empty (kv ~w "mailbox" (Printf.sprintf "%d queued (%d user), %d held, limit %d (%s)"
                                           (ji (jm "mbox" a)) (ji (jm "user_mbox" a)) (ji (jm "held" a))
                                           (ji (jm "mbox_limit" a)) (js (jm "mbox_policy" a))));
          line A.empty (kv ~w "traffic" (Printf.sprintf "in %d, out %d, dispatches %d" (ji (jm "msgs_in" a))
                                           (ji (jm "msgs_out" a)) (ji (jm "slices" a))));
          line A.empty (kv ~w "stack" (human_bytes (ji (jm "stack_bytes" a))));
          line A.empty (kv ~w "code epoch" (Printf.sprintf "%d (capability epoch %d)" (ji (jm "code_epoch" a))
                                              (ji (jm "cap_epoch" d))));
          line A.empty (kv ~w "scheduler" (match opt_int (jm "sched" a) with Some s -> string_of_int s | None -> "-"));
          line A.empty (kv ~w "pinned" (Printf.sprintf "%b   draining %b" (jm "pinned" a = `Bool true)
                                          (jm "draining" a = `Bool true)));
          line (if ji (jm "crashes" a) + ji (jm "child_crashes" a) > 0 then warn else A.empty)
            (kv ~w "crashes (1h)" (Printf.sprintf "own %d, children's %d" (ji (jm "crashes" a))
                                     (ji (jm "child_crashes" a))));
          line A.empty (kv ~w "supervised by" (match opt_int (jm "parent" a) with
              | Some p -> string_of_int p | None ->
                (match opt_int (jm "spawned_by" a) with Some p -> Printf.sprintf "nobody (spawned by %d)" p | None -> "nobody")));
          line A.empty (kv ~w "children" (match jl (jm "children" d) with [] -> "-" | l -> pids l));
          line A.empty (kv ~w "spawned" (match jl (jm "spawned" d) with [] -> "-" | l -> pids l)) ]
        @ (match sup with
            | `Assoc _ ->
              [ line A.empty (kv ~w "restart policy"
                                (Printf.sprintf "%s, %d of %d restarts within %d s" (js (jm "strategy" sup))
                                   (ji (jm "restarts_held" sup)) (ji (jm "max_restarts" sup))
                                   (ji (jm "window_secs" sup)))) ]
            | _ -> [])
        @ [ line dim "" ;
            line dim "state and message queue need the debug tier: forge observe --state PID" ] in
    image_of_lines ~width:c.width (head @ body)

(** The supervision tree flattened to (depth, node) lines, depth-first. *)
let rec flatten_tree depth (n : Yojson.Safe.t) : (int * Yojson.Safe.t) list =
  (depth, n) :: List.concat_map (flatten_tree (depth + 1)) (jl (jm "children" n))

let tree_nodes (reply : Yojson.Safe.t) : (int * Yojson.Safe.t) list =
  List.concat_map (flatten_tree 0) (jl (jm "roots" (section "tree" reply)))

let render_supervision (c : ctx) (reply : Yojson.Safe.t) : image =
  let tree = section "tree" reply in
  let nodes = tree_nodes reply in
  let actors = jl (jm "actors" (section "actors" reply)) in
  let find pid = List.find_opt (fun a -> ji (jm "pid" a) = pid) actors in
  if tree = `Null then unavailable ~width:c.width "no tree in this reply"
  else
    let line_of (depth, n) =
      let pid = ji (jm "pid" n) in
      let crashes = match find pid with
        | Some a -> ji (jm "crashes" a) + ji (jm "child_crashes" a)
        | None -> 0 in
      let indent = String.make (2 * depth) ' ' ^ (if depth > 0 then "+- " else "") in
      let kids = List.length (jl (jm "children" n)) in
      let name = match names_of n with [] -> "" | l -> " [" ^ String.concat "," l ^ "]" in
      let typ = js (jm "type" n) in
      let attr = if crashes > 0 then warn else A.empty in
      attr, Printf.sprintf "%s%d %s%s   %s  mbox %d%s%s" indent pid (if typ = "" then "?" else typ) name
        (js (jm "status" n)) (ji (jm "mbox" n))
        (if kids > 0 then Printf.sprintf "  %d kids" kids else "")
        (if crashes > 0 then Printf.sprintf "  crashes(1h) %d" crashes else "")
    in
    let unsup = jl (jm "unsupervised" tree) in
    let head = [ line dim (Printf.sprintf "%d actors; trees below, supervisors first" (ji (jm "total" tree))) ] in
    let foot =
      (if unsup = [] then []
       else [ line dim "";
              line dim (Printf.sprintf "%d actors with no supervisor and no children (see Actors): %s%s"
                          (List.length unsup)
                          (String.concat " " (List.filteri (fun i _ -> i < 12) (List.map (fun v -> string_of_int (ji v)) unsup)))
                          (if List.length unsup > 12 then " ..." else "")) ])
      @ (if jm "truncated" tree = `Bool true then [ line warn "tree truncated by the node's size cap" ] else []) in
    if nodes = [] && unsup = [] then unavailable ~width:c.width "no actors"
    else
      image_of_lines ~width:c.width ~selected_line:(List.length head + c.selected)
        (head @ List.map line_of nodes @ foot)

let render_names (c : ctx) (reply : Yojson.Safe.t) : image =
  let names = jl (jm "names" (section "names" reply)) in
  let names = List.sort (fun a b -> compare (js (jm "name" a)) (js (jm "name" b))) names in
  if names = [] then unavailable ~width:c.width "no registered names"
  else
    image_of_lines ~width:c.width
      (line bold (Printf.sprintf "%-32s %8s" "NAME" "PID")
       :: List.map (fun n -> line A.empty (Printf.sprintf "%-32s %8d" (fit 32 (js (jm "name" n))) (ji (jm "pid" n)))) names)

let render_epochs (c : ctx) (reply : Yojson.Safe.t) : image =
  let ep = section "epochs" reply in
  if ep = `Null then unavailable ~width:c.width "no epochs section in this reply"
  else
    let now = at_ms reply in
    let pins = jl (jm "pins" ep) and slots = jl (jm "slots" ep) in
    let ctr = jm "counters" ep in
    let g k = string_of_int (ji (jm k ctr)) in
    let lines =
      [ line bold (Printf.sprintf "current epoch %d" (ji (jm "current" ep))); line dim "";
        line bold (Printf.sprintf "%-8s %8s  %s" "EPOCH" "PINS" "STATE") ]
      @ (if pins = [] then [ line dim "(no epoch is pinned)" ] else
           List.map (fun p ->
               let st = (if jm "current" p = `Bool true then "current" else "")
                        ^ (if jm "draining" p = `Bool true then " draining" else "") in
               line (if jm "draining" p = `Bool true then warn else A.empty)
                 (Printf.sprintf "%-8d %8d  %s" (ji (jm "epoch" p)) (ji (jm "pins" p)) (String.trim st))) pins)
      @ [ line dim "";
          line bold (Printf.sprintf "%-5s %-34s %-14s %6s  %s" "SLOT" "NAME" "IMPL" "EPOCH" "ACTIVATED") ]
      @ (if slots = [] then [ line dim "(no hot-reload slots: this node was not built with --hot-reload)" ] else
           List.map (fun s ->
               let h = match jm "impl_hash" s with `String h -> fit 12 h | _ -> "-" in
               let act = ji (jm "activated_at_ms" s) in
               line A.empty (Printf.sprintf "%-5d %-34s %-14s %6d  %s" (ji (jm "id" s)) (fit 34 (js (jm "name" s)))
                               h (ji (jm "epoch" s))
                               (if act > 0 && now > 0 then age_text (now - act) ^ " ago" else "-"))) slots)
      @ [ line dim "";
          line A.empty (Printf.sprintf "deferred %s  converted %s  dropped %s  killed %s  stopped %s  advances %s  early %s  forced %s"
                          (g "deferred") (g "converted") (g "dropped") (g "killed") (g "stopped")
                          (g "advances") (g "early") (g "forced"));
          line A.empty (Printf.sprintf "markers live %s  lost %s" (g "markers_live") (g "markers_lost")) ] in
    image_of_lines ~width:c.width lines

let rec scalar_text (v : Yojson.Safe.t) : string =
  match v with
  | `String s -> s | `Int n -> string_of_int n | `Float f -> Printf.sprintf "%g" f
  | `Bool b -> string_of_bool b | `Null -> "-"
  | `List l -> "[" ^ String.concat "," (List.map scalar_text l) ^ "]"
  | `Assoc kv -> String.concat " " (List.map (fun (k, v) -> k ^ "=" ^ scalar_text v) kv)
  | _ -> "?"

let render_cluster (c : ctx) (reply : Yojson.Safe.t) : image =
  match data_of reply with
  | `Null -> unavailable ~width:c.width "no cluster section: this node does not publish one (ClusterNode not started, or an older node)"
  | `Assoc kv when List.assoc_opt "available" kv = Some (`Bool false) ->
    unavailable ~width:c.width "cluster: not available (ClusterNode has not started on this node)"
  | d ->
    let members = jl (jm "members" d) in
    let others = match d with
      | `Assoc kv -> List.filter (fun (k, _) -> k <> "members") kv
      | _ -> [] in
    let lines =
      List.map (fun (k, v) -> line dim (Printf.sprintf "%s: %s" k (scalar_text v))) others
      @ (if members = [] then [ line dim "no members" ] else
           line bold (Printf.sprintf "%d members" (List.length members))
           :: List.map (fun m ->
               let st = js (jm "state" m) in
               line (if st = "suspect" || st = "dead" then warn else A.empty) (scalar_text m)) members) in
    image_of_lines ~width:c.width lines

(** The crash ring rows, newest first.  A crash dump carries the message
    text beside them ([crashes_full]); the observe tier never does. *)
let crash_entries (reply : Yojson.Safe.t) : Yojson.Safe.t list =
  jl (jm "crashes" (section "crashes" reply))

let render_crashes (c : ctx) (reply : Yojson.Safe.t) : image =
  let es = crash_entries reply in
  let total = ji (jm "total" (section "crashes" reply)) in
  let now = at_ms reply in
  if es = [] then unavailable ~width:c.width "no crashes recorded"
  else
    let has_msg = List.exists (fun e -> jm "message" e <> `Null) es in
    let msg_w = max 10 (c.width - 70) in
    let head = [ line dim (Printf.sprintf "%d shown of %d recorded%s" (List.length es) total
                             (if has_msg then "" else "   (message text is not on the observe tier: forge observe --crashes-full)"));
                 line bold (Printf.sprintf "%5s %-9s %6s %-16s %10s %7s %10s %s" "SEQ" "KIND" "PID" "TYPE" "SUPERVISOR"
                              "RESTART" "AGE" (if has_msg then "MESSAGE" else "")) ] in
    let row e =
      let kind = js (jm "kind" e) in
      let attr = if kind = "panic" then crit else if now - ji (jm "at_ms" e) <= 60_000 then warn else A.empty in
      attr, Printf.sprintf "%5d %-9s %6s %-16s %10s %7d %10s %s" (ji (jm "seq" e)) kind
        (match jm "pid" e with `Int p -> string_of_int p | _ -> "-")
        (fit 16 (let t = js (jm "type" e) in if t = "" then "-" else t))
        (match opt_int (jm "supervisor" e) with Some s when s >= 0 -> string_of_int s | _ -> "-")
        (ji (jm "restart" e))
        (if now > 0 then age_text (now - ji (jm "at_ms" e)) else "-")
        (match jm "message" e with `String m -> fit msg_w m | _ -> "") in
    image_of_lines ~width:c.width ~selected_line:(List.length head + c.selected) (head @ List.map row es)

(** Render [panel] from [reply] ([`Null] when nothing has arrived).
    [selected] is meaningful for Actors, Supervision and Crashes. *)
let render ?(ctx = default_ctx) (p : panel) (reply : Yojson.Safe.t) : image =
  if reply = `Null then unavailable ~width:ctx.width "waiting for the node..."
  else if ctx.dump && live_only p then
    unavailable ~width:ctx.width
      (Printf.sprintf "%s is live-only: a crash dump holds no answer to a question asked of the node" (title p))
  else
    match p with
    | System -> render_system ctx reply
    | Load -> render_load ctx reply
    | Actors -> render_actors ctx reply
    | Actor -> render_actor ctx reply
    | Supervision -> render_supervision ctx reply
    | Names -> render_names ctx reply
    | Epochs -> render_epochs ctx reply
    | Cluster -> render_cluster ctx reply
    | Crashes -> render_crashes ctx reply

(** Lines above the first selectable row of [p]: where the selection sits on screen. *)
let header_lines = function
  | Actors -> 2 | Supervision -> 1 | Crashes -> 2
  | System | Load | Actor | Names | Epochs | Cluster -> 0

(** The pids the rows of [p] stand for, in row order: what [selected]
    indexes and Enter opens in the Actor panel. *)
let selectable ?(ctx = default_ctx) (p : panel) (reply : Yojson.Safe.t) : int list =
  match p with
  | Actors -> pids_of_rows (actor_rows ctx reply)
  | Supervision -> List.map (fun (_, n) -> ji (jm "pid" n)) (tree_nodes reply)
  | Crashes -> List.map (fun e -> match jm "pid" e with `Int p -> p | _ -> -1) (crash_entries reply)
  | System | Load | Actor | Names | Epochs | Cluster -> []

(* ── Crash dump files ────────────────────────────────────────────────── *)

(** A crash dump ([MARCH_CRASH_DUMP], runtime/march_observe_snapshot.c):
    the SNAPSHOT envelope plus the crash ring with message text. *)
type dump = {
  reason : string;
  dumped_at_ms : int;
  pid : int;
  reply : Yojson.Safe.t;   (** the snapshot, with message text merged into its crashes *)
}

let dump_proto = "march.observe.dump/1"

(** Parse a dump file's text.  The crash ring's messages are merged into the
    snapshot's [crashes] entries by [seq], so a panel sees one list. *)
let parse_dump (text : string) : (dump, string) result =
  match Yojson.Safe.from_string text with
  | exception Yojson.Json_error m -> Error ("crash dump is not valid JSON: " ^ m)
  | `Assoc kv as d ->
    if List.assoc_opt "proto" kv <> Some (`String dump_proto) then
      Error (Printf.sprintf "not a crash dump (no \"proto\":\"%s\")" dump_proto)
    else begin
      match jm "snapshot" d with
      | `Assoc skv as snap when List.mem_assoc "data" skv ->
        let full = jl (jm "crashes_full" d) in
        let msg_of seq = List.find_map (fun e ->
            if ji (jm "seq" e) = seq then (match jm "message" e with `String m -> Some m | _ -> None) else None) full in
        let merge_entry e = match e with
          | `Assoc ekv ->
            (match msg_of (ji (jm "seq" e)) with
             | Some m -> `Assoc (List.filter (fun (k, _) -> k <> "message") ekv @ [ "message", `String m ])
             | None -> e)
          | e -> e in
        let data = jm "data" snap in
        let crashes = jm "crashes" data in
        (* The ring is the source of truth; the snapshot's section may be absent or capped. *)
        let ring = if full <> [] then full else jl (jm "crashes" crashes) in
        let crashes' = `Assoc [ "total", (match jm "crashes_total" d with `Int n -> `Int n | _ -> `Int (List.length ring));
                                "crashes", `List (List.map merge_entry ring) ] in
        let data' = match data with
          | `Assoc dkv -> `Assoc (List.filter (fun (k, _) -> k <> "crashes") dkv @ [ "crashes", crashes' ])
          | v -> v in
        let snap' = `Assoc (List.filter (fun (k, _) -> k <> "data") skv @ [ "data", data' ]) in
        Ok { reason = js (jm "reason" d); dumped_at_ms = ji (jm "at_ms" d); pid = ji (jm "pid" d); reply = snap' }
      | _ -> Error "crash dump has no usable snapshot (the node's reply was truncated or missing)"
    end
  | _ -> Error "crash dump is not a JSON object"

let load_dump (file : string) : (dump, string) result =
  match In_channel.with_open_bin file In_channel.input_all with
  | exception Sys_error m -> Error m
  | text -> Result.map_error (fun m -> file ^ ": " ^ m) (parse_dump text)

(** The one line a dump's screens carry at the top. *)
let dump_banner (d : dump) : string =
  Printf.sprintf "CRASH DUMP  reason: %s  pid %d  at %s  (live-only panels are greyed)" d.reason d.pid
    (utc_text d.dumped_at_ms)

(** A single panel as text, for [forge observe --panel] and tests. *)
let panel_text ?(ctx = default_ctx) (p : panel) (reply : Yojson.Safe.t) : string =
  text_of_image (render ~ctx p reply)
