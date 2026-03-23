(** Shared mutable buffer for multi-error parser recovery.
    The parser grammar writes errors here via [collect_parse_error];
    callers read them out via [take_parse_errors]. *)

let _parse_errors : (string * string option * Lexing.position) list ref = ref []

(** Collect one parse error.  No-ops once we hit the cap of 20. *)
let collect_parse_error msg hint pos =
  if List.length !_parse_errors < 20 then
    _parse_errors := (msg, hint, pos) :: !_parse_errors

(** Return all collected errors (oldest first) and clear the buffer. *)
let take_parse_errors () =
  let errs = List.rev !_parse_errors in
  _parse_errors := [];
  errs
