val complete : string -> (string * string) list -> string list
(** [complete prefix scope] returns completion candidates for [prefix].
    [scope] is a list of [(name, type_str)] pairs from the current environment.
    Returns REPL commands if prefix starts with ':', otherwise keywords and scope names. *)
