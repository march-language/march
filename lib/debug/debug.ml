(** March debugger — core helpers.

    Provides [make_debug_ctx] for creating the debug context,
    [restore_actors] for replay setup, and [get_frame] convenience wrapper. *)

module Eval = March_eval.Eval

(** Default trace buffer size. Overridable via MARCH_DEBUG_TRACE_SIZE. *)
let default_trace_size () =
  match Sys.getenv_opt "MARCH_DEBUG_TRACE_SIZE" with
  | Some s -> (try int_of_string s with _ -> 100_000)
  | None   -> 100_000

(** Create a fresh debug context with an empty trace buffer. *)
let make_debug_ctx ~on_dbg : Eval.debug_ctx =
  { Eval.dc_trace      = Eval.ring_create (default_trace_size ());
    dc_pos             = 0;
    dc_enabled         = true;
    dc_depth           = 0;
    dc_on_dbg          = Some on_dbg;
    dc_actor_log       = [] }

(** Install [ctx] as the active debug context. *)
let install ctx =
  Eval.debug_ctx := Some ctx

(** Remove the active debug context (no tracing overhead). *)
let uninstall () =
  Eval.debug_ctx := None

(** [get_frame ctx i] returns frame at logical index i (0 = most recent). *)
let get_frame (ctx : Eval.debug_ctx) (i : int) : Eval.trace_frame option =
  Eval.ring_get ctx.dc_trace i

(** Total frames recorded. *)
let frame_count (ctx : Eval.debug_ctx) : int =
  ctx.dc_trace.Eval.rb_size
