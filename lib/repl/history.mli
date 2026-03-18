type t

val create : max_size:int -> t

val add : t -> string -> unit
(** Add an entry. Ignores blank lines and duplicates of the most recent entry. *)

val prev : t -> string option
(** Navigate one step older. Returns None if at the oldest entry. *)

val next : t -> string option
(** Navigate one step newer. Returns None if already at the bottom. *)

val reset_pos : t -> unit
(** Reset navigation to bottom (call after submitting or adding a new entry). *)

val save : t -> string -> unit
(** Save history to file (NUL-separated entries). Silently ignores errors. *)

val load : t -> string -> unit
(** Load history from file. Silently ignores missing/unreadable files. *)
