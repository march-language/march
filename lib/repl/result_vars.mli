type entry = {
  val_str  : string;
  type_str : string;
  eval_val : March_eval.Eval.value;
}

type t

val create : unit -> t

(** [push h value type_str] records a new result. *)
val push : t -> March_eval.Eval.value -> string -> unit

(** [push_strings h val_str type_str] records a result using raw strings (for testing). *)
val push_strings : t -> string -> string -> unit

(** [get h n] returns the entry at index n (0 = most recent). None if out of bounds. *)
val get : t -> int -> entry option

val length : t -> int
