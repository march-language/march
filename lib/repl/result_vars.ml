(** Magic result variable history: v, v(1), v(2), ...
    Stores string representations of values and their type strings for display.
    The ring buffer holds up to [max_history] entries. Index 0 = most recent. *)

let max_history = 100

type entry = {
  val_str  : string;
  type_str : string;
  eval_val : March_eval.Eval.value;
}

type t = {
  entries         : entry array;
  mutable size    : int;
  mutable head    : int;  (* index of the most recent entry in the ring *)
}

let empty_entry = {
  val_str  = "";
  type_str = "";
  eval_val = March_eval.Eval.VUnit;
}

let create () =
  { entries = Array.make max_history empty_entry; size = 0; head = 0 }

(** Push a new result onto the history. *)
let push h value type_str =
  let val_str = March_eval.Eval.value_to_string value in
  let next = (h.head + 1) mod max_history in
  h.entries.(next) <- { val_str; type_str; eval_val = value };
  h.head <- next;
  if h.size < max_history then h.size <- h.size + 1

(** Push using string representations only (for testing). *)
let push_strings h val_str type_str =
  let next = (h.head + 1) mod max_history in
  h.entries.(next) <- { val_str; type_str; eval_val = March_eval.Eval.VUnit };
  h.head <- next;
  if h.size < max_history then h.size <- h.size + 1

(** [get h n] returns the entry at index n (0 = most recent).
    Returns None if out of bounds. *)
let get h n =
  if n < 0 || n >= h.size then None
  else
    let idx = ((h.head - n) + max_history * 2) mod max_history in
    Some h.entries.(idx)

let length h = h.size
