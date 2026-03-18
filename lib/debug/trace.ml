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

(** Show where we are in the trace. *)
let show_where (ctx : Eval.debug_ctx) : string =
  let total = ctx.dc_trace.Eval.rb_size in
  if total = 0 then "No frames recorded yet."
  else
    match current_frame ctx with
    | None   -> Printf.sprintf "Frame %d of %d (out of range)" ctx.dc_pos total
    | Some f ->
      let sp = f.tf_span in
      Printf.sprintf "Frame %d of %d | %s:%d:%d | depth %d"
        ctx.dc_pos total
        sp.March_ast.Ast.file sp.March_ast.Ast.start_line
        sp.March_ast.Ast.start_col f.tf_depth

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
