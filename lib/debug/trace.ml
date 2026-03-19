(** March debugger — trace navigation.

    Manages the cursor (dc_pos) into the trace ring buffer.
    All cursor values are logical indices: 0 = most recent frame. *)

module Eval = March_eval.Eval

(** Move cursor back by [n] frames. Returns new cursor position.
    Clamps at oldest frame. *)
let back (ctx : Eval.debug_ctx) (n : int) : int =
  let max_pos = ctx.dc_trace.Eval.rb_size - 1 in
  let new_pos = min (ctx.dc_pos + n) max_pos in
  ctx.dc_pos <- new_pos;
  new_pos

(** Move cursor forward by [n] frames (toward more recent). Returns new position.
    Clamps at 0 (most recent). *)
let forward (ctx : Eval.debug_ctx) (n : int) : int =
  let new_pos = max (ctx.dc_pos - n) 0 in
  ctx.dc_pos <- new_pos;
  new_pos

(** Return the frame at the current cursor position, if any. *)
let current_frame (ctx : Eval.debug_ctx) : Eval.trace_frame option =
  Eval.ring_get ctx.dc_trace ctx.dc_pos

(** Format a trace frame for display. *)
let format_frame (i : int) (f : Eval.trace_frame) : string =
  let result_s = match f.tf_result with
    | Some v -> Eval.value_to_string v
    | None   -> (match f.tf_exn with
                | Some s -> Printf.sprintf "<exception: %s>" s
                | None   -> "<no result>")
  in
  let sp = f.tf_span in
  Printf.sprintf "Frame %d | %s:%d:%d | depth %d | result: %s"
    i sp.March_ast.Ast.file sp.March_ast.Ast.start_line
    sp.March_ast.Ast.start_col f.tf_depth result_s

(** Show last [n] trace frames (most recent first). Returns list of formatted strings. *)
let show_trace (ctx : Eval.debug_ctx) (n : int) : string list =
  let count = min n ctx.dc_trace.Eval.rb_size in
  List.init count (fun i ->
    match Eval.ring_get ctx.dc_trace i with
    | None   -> Printf.sprintf "Frame %d: <empty>" i
    | Some f -> format_frame i f)

(** Read [n] lines of context around [target_line] (1-indexed) from [file].
    Returns formatted lines with a [→] marker on the target line. *)
let source_context (file : string) (target_line : int) (n : int) : string list =
  try
    let ic   = open_in file in
    let acc  = ref [] in
    (try while true do acc := input_line ic :: !acc done with End_of_file -> ());
    close_in ic;
    let arr   = Array.of_list (List.rev !acc) in
    let len   = Array.length arr in
    let lo    = max 0 (target_line - 1 - n) in
    let hi    = min (len - 1) (target_line - 1 + n) in
    List.init (hi - lo + 1) (fun i ->
      let lineno = lo + i + 1 in
      let marker = if lineno = target_line then "→" else " " in
      Printf.sprintf "%s %4d │ %s" marker lineno arr.(lo + i))
  with _ -> []

(** Show where we are in the trace, including surrounding source lines. *)
let show_where (ctx : Eval.debug_ctx) : string list =
  let total = ctx.dc_trace.Eval.rb_size in
  if total = 0 then ["No frames recorded yet."]
  else
    match current_frame ctx with
    | None   -> [Printf.sprintf "Frame %d of %d (out of range)" ctx.dc_pos total]
    | Some f ->
      let sp     = f.tf_span in
      let header = Printf.sprintf "Frame %d of %d | %s:%d:%d | depth %d"
        ctx.dc_pos total
        sp.March_ast.Ast.file sp.March_ast.Ast.start_line
        sp.March_ast.Ast.start_col f.tf_depth
      in
      header :: source_context sp.March_ast.Ast.file sp.March_ast.Ast.start_line 2

(** Jump to an absolute frame index. Clamps to valid range. Returns new position. *)
let goto (ctx : Eval.debug_ctx) (n : int) : int =
  let max_pos = ctx.dc_trace.Eval.rb_size - 1 in
  let new_pos = max 0 (min n max_pos) in
  ctx.dc_pos <- new_pos;
  new_pos

(** Diff the env at the current frame vs the env [n] frames earlier.
    Returns formatted diff lines.  [baseline_names] are names to exclude
    (stdlib / pre-debug session names). *)
let diff_frames (ctx : Eval.debug_ctx) (n : int) (baseline_names : string list) : string list =
  let cur_pos = ctx.dc_pos in
  let ref_pos = min (cur_pos + n) (ctx.dc_trace.Eval.rb_size - 1) in
  match Eval.ring_get ctx.dc_trace cur_pos, Eval.ring_get ctx.dc_trace ref_pos with
  | None, _ | _, None -> ["(no frames to compare)"]
  | Some cur_f, Some ref_f ->
    let filter env =
      let seen = Hashtbl.create 16 in
      List.filter_map (fun (name, v) ->
        if List.mem name baseline_names || Hashtbl.mem seen name then None
        else begin Hashtbl.add seen name (); Some (name, v) end
      ) env
    in
    let cur_env = filter cur_f.Eval.tf_env in
    let ref_env = filter ref_f.Eval.tf_env in
    let lines = ref [] in
    (* Bindings in current frame *)
    List.iter (fun (name, cur_v) ->
      match List.assoc_opt name ref_env with
      | None ->
        lines := (Printf.sprintf "  + %s = %s" name (Eval.value_to_string cur_v)) :: !lines
      | Some ref_v ->
        let cv = Eval.value_to_string cur_v in
        let rv = Eval.value_to_string ref_v in
        if cv <> rv then
          lines := (Printf.sprintf "  ~ %s : %s -> %s" name rv cv) :: !lines
    ) cur_env;
    (* Bindings only in reference frame (dropped) *)
    List.iter (fun (name, ref_v) ->
      if not (List.mem_assoc name cur_env) then
        lines := (Printf.sprintf "  - %s = %s" name (Eval.value_to_string ref_v)) :: !lines
    ) ref_env;
    if !lines = [] then ["(no changes)"]
    else List.rev !lines

(** Search backward from current position for a frame where [pred env] returns true.
    On success moves cursor to that frame and returns [Some new_pos].
    On failure returns [None] and leaves cursor unchanged. *)
let find_frame (ctx : Eval.debug_ctx) (pred : Eval.env -> bool) : int option =
  let n = ctx.dc_trace.Eval.rb_size in
  let start = ctx.dc_pos + 1 in  (* start searching one frame behind current *)
  let result = ref None in
  let i = ref start in
  while !i < n && !result = None do
    (match Eval.ring_get ctx.dc_trace !i with
     | Some f ->
       (try if pred f.Eval.tf_env then result := Some !i
        with _ -> ())
     | None -> ());
    incr i
  done;
  (match !result with
   | Some idx -> ctx.dc_pos <- idx
   | None -> ());
  !result

(** Summary of all actors with message counts. *)
let actors_summary (ctx : Eval.debug_ctx) : string list =
  if ctx.dc_actor_log = [] then ["(no actor messages recorded)"]
  else begin
    let counts = Hashtbl.create 8 in
    List.iter (fun (evt : Eval.actor_msg_event) ->
      let key = (evt.ame_pid, evt.ame_actor_name) in
      let n = try Hashtbl.find counts key with Not_found -> 0 in
      Hashtbl.replace counts key (n + 1)
    ) ctx.dc_actor_log;
    let entries = Hashtbl.fold (fun (pid, name) count acc ->
      (pid, name, count) :: acc
    ) counts [] in
    let entries = List.sort (fun (a, _, _) (b, _, _) -> compare a b) entries in
    List.map (fun (pid, name, count) ->
      Printf.sprintf "  PID %d (%s): %d message%s"
        pid name count (if count = 1 then "" else "s")
    ) entries
  end

(** Per-actor message history for [pid].
    Optionally, if [goto_msg] is Some n, jump to the trace frame of message n. *)
let actor_history (ctx : Eval.debug_ctx) (pid : int) (goto_msg : int option) : string list =
  let events = List.filter (fun e -> e.Eval.ame_pid = pid) ctx.dc_actor_log in
  if events = [] then
    [Printf.sprintf "(no messages recorded for PID %d)" pid]
  else begin
    (match goto_msg with
     | Some n when n >= 1 && n <= List.length events ->
       let evt = List.nth events (n - 1) in
       ctx.dc_pos <- max 0 evt.Eval.ame_frame_idx
     | _ -> ());
    List.mapi (fun i (evt : Eval.actor_msg_event) ->
      let state_after_s = match evt.ame_state_after with
        | Some s -> Eval.value_to_string s
        | None   -> "<exception>"
      in
      Printf.sprintf "  Msg %3d: %-24s  state: %s -> %s"
        (i + 1)
        (Eval.value_to_string evt.ame_msg)
        (Eval.value_to_string evt.ame_state_before)
        state_after_s
    ) events
  end

(** Save the trace to a file using Marshal. *)
let save_trace (ctx : Eval.debug_ctx) (path : string) : (unit, string) result =
  try
    let oc = open_out_bin path in
    Marshal.to_channel oc ctx.dc_trace [];
    close_out oc;
    Ok ()
  with Sys_error msg -> Error msg

(** Load a trace from a file, replacing the context's trace contents.
    The loaded trace's array is copied element-by-element to fit the
    existing ring buffer capacity. *)
let load_trace (ctx : Eval.debug_ctx) (path : string) : (unit, string) result =
  try
    let ic = open_in_bin path in
    let t : Eval.trace_frame Eval.ring = Marshal.from_channel ic in
    close_in ic;
    let dst = ctx.dc_trace in
    let copy_size = min t.Eval.rb_size dst.Eval.rb_cap in
    Array.blit t.Eval.rb_arr 0 dst.Eval.rb_arr 0
      (min (Array.length t.Eval.rb_arr) (Array.length dst.Eval.rb_arr));
    dst.Eval.rb_head <- t.Eval.rb_head mod dst.Eval.rb_cap;
    dst.Eval.rb_size <- copy_size;
    ctx.dc_pos <- 0;
    Ok ()
  with
  | Sys_error msg -> Error msg
  | _ -> Error "invalid trace file (may be from a different compiler version)"

(** Show call stack: frames at each depth level up to current position. *)
let show_stack (ctx : Eval.debug_ctx) : string list =
  let stack = Hashtbl.create 8 in
  let n = ctx.dc_trace.Eval.rb_size in
  for i = ctx.dc_pos to n - 1 do
    match Eval.ring_get ctx.dc_trace i with
    | None -> ()
    | Some f ->
      if not (Hashtbl.mem stack f.tf_depth) then
        Hashtbl.replace stack f.tf_depth f
  done;
  let depths = Hashtbl.fold (fun d _ acc -> d :: acc) stack [] in
  let depths = List.sort compare depths in
  List.map (fun d ->
    let f = Hashtbl.find stack d in
    let sp = f.tf_span in
    let marker = if d = (match current_frame ctx with
                         | Some f2 -> f2.tf_depth | None -> -1)
                 then "  <-- here"
                 else "" in
    Printf.sprintf "  %d: %s:%d:%d%s"
      d sp.March_ast.Ast.file sp.March_ast.Ast.start_line
      sp.March_ast.Ast.start_col marker
  ) depths
