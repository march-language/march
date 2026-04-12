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

(** Net depth of unmatched bracket/paren/brace characters, skipping over
    string literals (double-quoted) and line comments (--).
    Positive means we are inside an unclosed delimiter. *)
let bracket_depth buf =
  let n = String.length buf in
  let depth = ref 0 in
  let i = ref 0 in
  while !i < n do
    let c = buf.[!i] in
    (* Line comment: skip to end of line *)
    if c = '-' && !i + 1 < n && buf.[!i + 1] = '-' then begin
      while !i < n && buf.[!i] <> '\n' do incr i done
    end
    (* String literal: skip to closing double-quote, handling backslash escapes *)
    else if c = '"' then begin
      incr i;
      while !i < n && buf.[!i] <> '"' do
        if buf.[!i] = '\\' then incr i;
        incr i
      done;
      incr i
    end
    else begin
      (match c with
       | '(' | '[' | '{' -> incr depth
       | ')' | ']' | '}' -> decr depth
       | _ -> ());
      incr i
    end
  done;
  !depth

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
    [->] (lambda or match arm arrow), [|>] (pipe forward), binary operators
    [++]/[+]/[-]/[*]/[/], or keywords [then]/[else]. *)
let ends_with_continuation buf =
  let l = last_non_blank_line buf in
  let n = String.length l in
  if n = 0 then false
  else begin
    (* Trailing -> (lambda/match arrow) but not |> *)
    let trailing_arrow =
      n >= 2 && l.[n-1] = '>' && l.[n-2] = '-' in
    (* Trailing |> (pipe forward) *)
    let trailing_pipe =
      n >= 2 && l.[n-1] = '>' && l.[n-2] = '|' in
    (* Trailing = but not ==, !=, <=, >= *)
    let trailing_eq =
      l.[n-1] = '='
      && not (n >= 2 &&
              (l.[n-2] = '=' || l.[n-2] = '!' || l.[n-2] = '<' || l.[n-2] = '>')) in
    (* Trailing binary operators that imply a right operand follows *)
    let trailing_binop =
      (n >= 2 && l.[n-1] = '+' && l.[n-2] = '+')  (* ++ *)
      || (l.[n-1] = '+' && (n < 2 || l.[n-2] <> '+'))  (* + but not ++ *)
      || (l.[n-1] = '-' && (n < 2 || (l.[n-2] <> '-' && l.[n-2] <> '>')))  (* - but not -- or -> *)
      || l.[n-1] = '*'
      || (l.[n-1] = '/' && (n < 2 || l.[n-2] <> '/')) in  (* / but not // *)
    (* Trailing keyword: then or else *)
    let trailing_kw =
      let words = String.split_on_char ' ' (String.trim l) in
      match List.rev words with
      | w :: _ -> w = "then" || w = "else"
      | []     -> false
    in
    trailing_arrow || trailing_pipe || trailing_eq || trailing_binop || trailing_kw
  end

(** True when [buf] appears syntactically complete (safe to submit). *)
let is_complete buf =
  do_end_depth buf <= 0
  && bracket_depth buf <= 0
  && not (ends_with_with buf)
  && not (starts_with_pipe buf)
  && not (ends_with_continuation buf)
