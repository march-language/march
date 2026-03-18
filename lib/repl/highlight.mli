val highlight : string -> Notty.I.t
(** Tokenize [src] and return a notty image with syntax coloring.
    Best-effort: on lex error, the remainder is rendered in default color. *)
