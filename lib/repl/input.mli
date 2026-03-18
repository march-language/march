type input_action =
  | Noop
  | Redraw
  | Submit of string
  | EOF
  | Complete
  | HistoryPrev
  | HistoryNext
  | HistorySearch

type state = {
  buffer        : string;
  cursor        : int;
  kill_ring     : string list;
  history_pos   : int;
  multiline_buf : string list;
}

val empty : state
val handle_key : state -> Notty.Unescape.key -> state * input_action
val full_buffer : state -> string
val insert_at : state -> string -> state
val complete_replace : state -> string -> state
(** Replace the word at/around the cursor with [completion].
    Word boundaries are nearest spaces (or buffer start/end). *)
