(* The interpreter's answer to an observe request line: the same envelope and
   field names as the compiled runtime's observe verbs
   (runtime/march_observe_snapshot.c), built from [Eval_runtime.actor_registry],
   so the [observe_query] builtin, and [Recon] above it, run on both backends
   (R3 of specs/plans/2026-09-28-observe-recon-shell-plan.md).

   The interpreter is single-threaded and delivers eagerly, so most numbers are
   small or absent: mailboxes are usually empty, there is one "scheduler", no
   code epochs, no memory gauges ([null]), and no crash ring (CRASHES lists the
   dead actors whose death was a crash, newest pid first). A windowed SCHED or
   TOP is refused as it is for any in-process caller on the compiled side
   ("windowed_in_process"). *)

open Eval_runtime

(* ── A small JSON writer ───────────────────────────────────────────────── *)

let str b s =
  Buffer.add_char b '"';
  String.iter (fun c ->
      match c with
      | '"' -> Buffer.add_string b "\\\""
      | '\\' -> Buffer.add_string b "\\\\"
      | '\n' -> Buffer.add_string b "\\n"
      | '\r' -> Buffer.add_string b "\\r"
      | '\t' -> Buffer.add_string b "\\t"
      | c when Char.code c < 0x20 -> Buffer.add_string b (Printf.sprintf "\\u%04x" (Char.code c))
      | c -> Buffer.add_char b c) s;
  Buffer.add_char b '"'

let int b n = Buffer.add_string b (string_of_int n)
let bool b v = Buffer.add_string b (if v then "true" else "false")
let null b = Buffer.add_string b "null"

(* An object from (key, writer) pairs. *)
let obj b fields =
  Buffer.add_char b '{';
  List.iteri (fun i (k, w) ->
      if i > 0 then Buffer.add_char b ',';
      str b k; Buffer.add_char b ':'; w b) fields;
  Buffer.add_char b '}'

let arr b items w =
  Buffer.add_char b '[';
  List.iteri (fun i x -> if i > 0 then Buffer.add_char b ','; w b x) items;
  Buffer.add_char b ']'

(* ── Rows ──────────────────────────────────────────────────────────────── *)

let live () =
  Hashtbl.fold (fun pid inst acc -> if inst.ai_alive then (pid, inst) :: acc else acc)
    actor_registry []
  |> List.sort (fun (a, _) (b, _) -> compare a b)

let names_of pid =
  Hashtbl.fold (fun name p acc -> if p = pid then name :: acc else acc) named_registry []
  |> List.sort compare

let children_of pid =
  Hashtbl.fold (fun p inst acc ->
      if inst.ai_alive && inst.ai_supervisor = Some pid then p :: acc else acc)
    actor_registry []
  |> List.sort compare

let crashed pid =
  match Hashtbl.find_opt actor_registry pid with
  | Some { ai_alive = false; ai_terminal_reason = Crash _; _ } -> true
  | _ -> false

let policy_name = function
  | 1 -> "drop_new" | 2 -> "drop_old" | 3 -> "block" | _ -> "unbounded"

let mbox inst = Queue.length inst.ai_mailbox

(* Crash "ring": dead actors that crashed, newest pid first. *)
let crash_entries () =
  Hashtbl.fold (fun pid inst acc ->
      if crashed pid then (pid, inst) :: acc else acc) actor_registry []
  |> List.sort (fun (a, _) (b, _) -> compare b a)

let row b (pid, inst) =
  let parent = match inst.ai_supervisor with Some p -> fun b -> int b p | None -> null in
  let child_crashes =
    List.length (List.filter (fun (_, i) -> i.ai_supervisor = Some pid) (crash_entries ()))
  in
  obj b [
    "pid", (fun b -> int b pid);
    "type", (fun b -> str b inst.ai_name);
    "names", (fun b -> arr b (names_of pid) str);
    "status", (fun b -> str b "waiting");
    "mbox", (fun b -> int b (mbox inst));
    "user_mbox", (fun b -> int b (mbox inst));
    "held", (fun b -> int b 0);
    "mbox_limit", (fun b -> int b (max 0 inst.ai_mbox_limit));
    "mbox_policy", (fun b -> str b (policy_name inst.ai_mbox_policy));
    "code_epoch", (fun b -> int b 1);
    "cap_epoch", (fun b -> int b inst.ai_epoch);
    "sched", null;
    "pinned", (fun b -> bool b false);
    "draining", (fun b -> bool b inst.ai_draining);
    "parent", parent;
    "children", (fun b -> int b (List.length (children_of pid)));
    "spawned_by", null;
    "slices", (fun b -> int b inst.ai_slices);
    "msgs_in", (fun b -> int b inst.ai_msgs_in);
    "msgs_out", (fun b -> int b inst.ai_msgs_out);
    "crashes", (fun b -> int b 0);
    "child_crashes", (fun b -> int b child_crashes);
    "idle_ms", null;
  ]

(* ── Verbs ─────────────────────────────────────────────────────────────── *)

exception Bad of string

let words args = String.split_on_char ' ' args |> List.filter (fun w -> w <> "")

let int_word w = match int_of_string_opt w with Some n when n >= 0 -> n | _ -> raise (Bad "bad_args")

let sort_key = function
  | "mbox" -> (fun (_, i) -> - (mbox i))
  | "status" -> (fun (_, i) -> - (mbox i))
  | "epoch" | "pid" -> (fun _ -> 0)
  | _ -> raise (Bad "bad_args")

let actors b args =
  let sort, limit = match words args with
    | [] -> "mbox", 100
    | [ w ] -> (match int_of_string_opt w with Some n -> "mbox", n | None -> w, 100)
    | [ s; n ] -> s, int_word n
    | _ -> raise (Bad "bad_args")
  in
  if limit < 1 || limit > 10000 then raise (Bad "bad_args");
  let key = sort_key sort in
  let rows = live () in
  let sorted = List.stable_sort (fun a c -> compare (key a, fst a) (key c, fst c)) rows in
  let shown = List.filteri (fun i _ -> i < limit) sorted in
  obj b [
    "total", (fun b -> int b (List.length rows));
    "shown", (fun b -> int b (List.length shown));
    "sort", (fun b -> str b sort);
    "actors", (fun b -> arr b shown row);
  ]

let kind_of = function Normal -> "Normal" | Killed -> "Killed" | Crash _ -> "Crash"

let actor b args =
  let pid = match words args with [ w ] -> int_word w | _ -> raise (Bad "bad_args") in
  match Hashtbl.find_opt actor_registry pid with
  | None -> raise (Bad "not_found")
  | Some inst ->
    obj b [
      "pid", (fun b -> int b pid);
      "alive", (fun b -> bool b inst.ai_alive);
      "cap_epoch", (fun b -> int b inst.ai_epoch);
      "actor", (fun b -> if inst.ai_alive then row b (pid, inst) else null b);
      "children", (fun b -> arr b (if inst.ai_alive then children_of pid else []) int);
      "spawned", (fun b -> arr b [] int);
      "supervisor", null;
      (* Death KIND only, never the message (C7). *)
      "terminal", (fun b ->
          if inst.ai_alive then null b
          else obj b [ "kind", (fun b -> str b (kind_of inst.ai_terminal_reason)) ]);
    ]

let rec tree_node b depth (pid, inst) =
  obj b [
    "pid", (fun b -> int b pid);
    "type", (fun b -> str b inst.ai_name);
    "names", (fun b -> arr b (names_of pid) str);
    "status", (fun b -> str b "waiting");
    "mbox", (fun b -> int b (mbox inst));
    "link", (fun b -> if depth = 0 then null b else str b "supervised");
    "children", (fun b ->
        let kids = List.filter_map (fun p ->
            Option.map (fun i -> (p, i)) (Hashtbl.find_opt actor_registry p)) (children_of pid) in
        arr b (if depth >= 63 then [] else kids) (tree_node_d (depth + 1)));
  ]
and tree_node_d d b x = tree_node b d x

let tree b args =
  if words args <> [] then raise (Bad "bad_args");
  let rows = live () in
  let has_kids pid = children_of pid <> [] in
  let roots = List.filter (fun (p, i) -> i.ai_supervisor = None && has_kids p) rows in
  let unsup = List.filter (fun (p, i) -> i.ai_supervisor = None && not (has_kids p)) rows in
  obj b [
    "total", (fun b -> int b (List.length rows));
    "roots", (fun b -> arr b roots (tree_node_d 0));
    "unsupervised", (fun b -> arr b (List.map fst unsup) int);
    "truncated", (fun b -> bool b false);
  ]

let names b args =
  if words args <> [] then raise (Bad "bad_args");
  let alive p = match Hashtbl.find_opt actor_registry p with Some i -> i.ai_alive | None -> false in
  let entries =
    Hashtbl.fold (fun n p acc -> if alive p then (n, p) :: acc else acc) named_registry []
    |> List.sort compare
  in
  obj b [ "names", (fun b -> arr b entries (fun b (n, p) ->
      obj b [ "name", (fun b -> str b n); "pid", (fun b -> int b p) ])) ]

let mem b args =
  if words args <> [] then raise (Bad "bad_args");
  let rows = live () in
  obj b [
    "rss_bytes", null; "peak_rss_bytes", null; "live_objects", null;
    "stacks_recycled", (fun b -> int b 0);
    "queued_messages", (fun b -> int b (List.fold_left (fun a (_, i) -> a + mbox i) 0 rows));
    "actors", (fun b -> int b (List.length rows));
  ]

let sched b args =
  (match words args with
   | [] | [ "0" ] -> ()
   | [ w ] -> ignore (int_word w); raise (Bad "windowed_in_process")
   | _ -> raise (Bad "bad_args"));
  obj b [
    "schedulers", (fun b -> int b 1); "window_ms", null;
    "threads", (fun b -> arr b [] int);
    "utilisation", null; "lifetime_utilisation", null;
    "live_procs", (fun b -> int b (List.length (live ())));
    "msgs_dropped", (fun b -> int b !dropped_messages_count);
  ]

let epochs b args =
  if words args <> [] then raise (Bad "bad_args");
  obj b [ "current", (fun b -> int b 1); "pins", (fun b -> arr b [] int);
          "slots", (fun b -> arr b [] int); "counters", (fun b -> obj b []) ]

let crashes b args =
  let want = match words args with
    | [] -> 20
    | [ w ] -> let n = int_word w in if n < 1 || n > 256 then raise (Bad "bad_args") else n
    | _ -> raise (Bad "bad_args")
  in
  let all = crash_entries () in
  let shown = List.filteri (fun i _ -> i < want) all in
  obj b [
    "total", (fun b -> int b (List.length all));
    "crashes", (fun b -> arr b shown (fun b (pid, inst) ->
        obj b [
          "seq", (fun b -> int b pid); "kind", (fun b -> str b "crash");
          "pid", (fun b -> int b pid); "type", (fun b -> str b inst.ai_name);
          "code_epoch", (fun b -> int b 1);
          "supervisor", (fun b -> match inst.ai_supervisor with Some p -> int b p | None -> null b);
          "restart", (fun b -> int b 0); "at_ms", (fun b -> int b 0);
        ]));
  ]

let top b args =
  match words args with
  | attr :: n :: rest ->
    let want = int_word n in
    if want < 1 || want > 10000 then raise (Bad "bad_args");
    let windowed = List.mem attr [ "slices"; "msgs_in"; "msgs_out" ] in
    if not (windowed || attr = "mbox" || attr = "crashes") then raise (Bad "bad_args");
    (match rest with
     | [] | [ "0" ] when windowed -> ()   (* cumulative *)
     | [] -> ()
     | [ w ] when windowed -> ignore (int_word w); raise (Bad "windowed_in_process")
     | _ -> raise (Bad "bad_args"));
    (* A windowed attribute without a window: its cumulative value. *)
    let value (pid, i) = match attr with
      | "mbox" -> mbox i
      | "crashes" -> List.length (List.filter (fun (_, c) -> c.ai_supervisor = Some pid) (crash_entries ()))
      | "slices" -> i.ai_slices | "msgs_in" -> i.ai_msgs_in | _ -> i.ai_msgs_out
    in
    let rows = live () in
    let ranked = List.stable_sort (fun a c -> compare (- value a, fst a) (- value c, fst c)) rows in
    let shown = List.filteri (fun k _ -> k < want) ranked in
    obj b [
      "attr", (fun b -> str b attr); "window_ms", null;
      "total", (fun b -> int b (List.length rows));
      "top", (fun b -> arr b shown (fun b ((pid, i) as r) ->
          obj b [ "pid", (fun b -> int b pid); "value", (fun b -> int b (value r));
                  "type", (fun b -> str b i.ai_name);
                  "names", (fun b -> arr b (names_of pid) str);
                  "status", (fun b -> str b "waiting"); "mbox", (fun b -> int b (mbox i)) ]));
    ]
  | _ -> raise (Bad "bad_args")

let sections = [ "actors"; "tree"; "names"; "sched"; "mem"; "epochs"; "crashes" ]

let snapshot b args =
  let wanted =
    String.split_on_char ',' args |> List.concat_map (String.split_on_char ' ')
    |> List.filter (fun w -> w <> "")
  in
  List.iter (fun w -> if not (List.mem w sections) then raise (Bad "bad_args")) wanted;
  let wanted = if wanted = [] then sections else wanted in
  let section name f = if List.mem name wanted then Some (name, fun b -> f b "") else None in
  obj b (List.filter_map Fun.id [
      section "names" names; section "mem" mem; section "actors" actors;
      section "tree" tree; section "sched" sched; section "epochs" epochs;
      section "crashes" crashes ])

let verbs = [
  "PING", (fun b _ -> str b "pong");
  "ACTORS", actors; "ACTOR", actor; "TREE", tree; "NAMES", names;
  "MEM", mem; "SCHED", sched; "EPOCHS", epochs; "CRASHES", crashes;
  "TOP", top; "SNAPSHOT", snapshot;
]

(** The reply envelope for one request line, as a JSON string. *)
let query (line : string) : string =
  let line = String.trim line in
  let verb, args = match String.index_opt line ' ' with
    | Some i -> String.sub line 0 i, String.sub line (i + 1) (String.length line - i - 1)
    | None -> line, ""
  in
  let b = Buffer.create 512 in
  let envelope k =
    obj b ([ "proto", (fun b -> str b "march.observe/1");
             "node", (fun b -> str b "interpreter");
             "at_ms", (fun b -> int b (int_of_float (Unix.gettimeofday () *. 1000.)));
             "took_us", (fun b -> int b 0);
             "truncated", (fun b -> bool b false) ] @ k)
  in
  (match List.assoc_opt verb verbs with
   | None -> envelope [ "error", (fun b -> str b "unknown_verb") ]
   | Some f ->
     let data = Buffer.create 512 in
     (match f data args with
      | () -> envelope [ "data", (fun b -> Buffer.add_buffer b data) ]
      | exception Bad code -> envelope [ "error", (fun b -> str b code) ]));
  Buffer.contents b
