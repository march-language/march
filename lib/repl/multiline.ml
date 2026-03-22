(** Multi-line input completion heuristics for the REPL.
    Migrated from bin/main.ml. *)

(** Count exact whole-word occurrences of [tok] in [buf]. *)
let count_token tok buf =
  let words = Str.split (Str.regexp "[^a-zA-Z0-9_']") buf in
  List.length (List.filter (( = ) tok) words)


(** Net depth of open blocks: do openers minus end closers.
    Positive means we are inside an unclosed block.
    Known limitation: tokens inside string literals are miscounted. *)
let do_end_depth buf =
  count_token "do" buf - count_token "end" buf

(** Last non-blank line in [buf], trimmed. *)
let last_non_blank_line buf =
  let lines = String.split_on_char '\n' buf in
  match List.rev (List.filter (fun l -> String.trim l <> "") lines) with
  | []     -> ""
  | l :: _ -> String.trim l

(** True if the last non-blank line ends with the token "with" (record update)
    or is a match opener ending in "do".  Both forms require more input. *)
let ends_with_with buf =
  let l = last_non_blank_line buf in
  let words = String.split_on_char ' ' (String.trim l) in
  match List.rev words with
  | "with" :: _ -> true
  | _            -> false

(** True if the last non-blank line starts with '|' (match arm continuation). *)
let starts_with_pipe buf =
  let l = last_non_blank_line buf in
  String.length l > 0 && l.[0] = '|'

(** True if the last non-blank line ends with a token that implies the
    expression continues on the next line: trailing [=] (let/fn binding),
    [->] (lambda or match arm arrow), or keywords [then]/[else]. *)
let ends_with_continuation buf =
  let l = last_non_blank_line buf in
  let n = String.length l in
  if n = 0 then false
  else begin
    (* Trailing -> *)
    let trailing_arrow = n >= 2 && l.[n-1] = '>' && l.[n-2] = '-' in
    (* Trailing = but not ==, !=, <=, >= *)
    let trailing_eq =
      l.[n-1] = '='
      && not (n >= 2 &&
              (l.[n-2] = '=' || l.[n-2] = '!' || l.[n-2] = '<' || l.[n-2] = '>')) in
    (* Trailing keyword: then or else *)
    let trailing_kw =
      let words = String.split_on_char ' ' (String.trim l) in
      match List.rev words with
      | w :: _ -> w = "then" || w = "else"
      | []     -> false
    in
    trailing_arrow || trailing_eq || trailing_kw
  end

(** True when [buf] appears syntactically complete (safe to submit). *)
let is_complete buf =
  do_end_depth buf <= 0
  && not (ends_with_with buf)
  && not (starts_with_pipe buf)
  && not (ends_with_continuation buf)
