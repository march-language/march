(** Doctest extraction from March doc strings.

    Recognises interactive-session style examples embedded in doc comments:

      march> Option.is_some(Some(42))
      true

    Multi-line expressions use [...> ] continuation lines:

      march> List.map(
      ...>   [1, 2, 3],
      ...>   fn x -> x + 1)
      [2, 3, 4]

    Panic expectations use [** panic: message] as the expected line:

      march> Option.unwrap(None)
      ** panic: Option.unwrap called on None

    The standard indentation is 4 spaces, which is stripped before matching
    the prompt prefixes.  Any leading whitespace beyond 4 spaces is kept
    (relevant for multi-line continuation bodies). *)

(** What a doctest example expects to happen. *)
type expected =
  | ExpectOutput of string  (** Expected [value_to_string] output *)
  | ExpectPanic  of string  (** Expected panic message (stripped of "panic: " prefix) *)
  | ExpectNothing           (** No expected output specified — just check it doesn't crash *)

(** A single extracted doctest example. *)
type example = {
  ex_source   : string;    (** The March expression text, possibly multi-line *)
  ex_expected : expected;  (** What the example expects *)
}

(* ------------------------------------------------------------------ *)
(* Extraction                                                          *)
(* ------------------------------------------------------------------ *)

(** Strip up to [n] leading spaces from [s].
    If [s] has fewer than [n] leading spaces, strips only those present. *)
let strip_indent n s =
  let len = String.length s in
  let rec count i =
    if i >= n || i >= len || s.[i] <> ' ' then i
    else count (i + 1)
  in
  let start = count 0 in
  String.sub s start (len - start)

(** Return [true] if [s] starts with [prefix]. *)
let starts_with prefix s =
  let plen = String.length prefix in
  String.length s >= plen && String.sub s 0 plen = prefix

(** Extract the suffix of [s] after [prefix].
    Assumes [starts_with prefix s] is true. *)
let after prefix s =
  String.sub s (String.length prefix) (String.length s - String.length prefix)

(** Extract all doctest examples from [doc]. *)
let extract doc =
  let prompt       = "march> " in
  let cont         = "...> "   in
  let panic_prefix = "** panic: " in

  let examples  = ref [] in
  (* true while we have a started example awaiting expected output *)
  let active    = ref false in
  let cur_src   = Buffer.create 64 in

  (* Flush the current buffered example with the given expected value.
     Resets [active] and [cur_src]. *)
  let flush expected =
    if !active then begin
      let src = String.trim (Buffer.contents cur_src) in
      if src <> "" then
        examples := { ex_source = src; ex_expected = expected } :: !examples;
      Buffer.clear cur_src;
      active := false
    end
  in

  let lines = String.split_on_char '\n' doc in
  List.iter (fun raw_line ->
    (* Strip 4 spaces of standard doc-comment indent *)
    let line    = strip_indent 4 raw_line in
    let trimmed = String.trim line in
    if starts_with prompt line then begin
      (* New example — flush any previous one without expected output *)
      flush ExpectNothing;
      Buffer.add_string cur_src (after prompt line);
      active := true
    end else if !active && starts_with cont line then begin
      (* Continuation line — append to current expression *)
      Buffer.add_char cur_src '\n';
      Buffer.add_string cur_src (after cont line)
    end else if !active then begin
      if trimmed = "" then
        ()  (* blank line between expression and expected output — skip *)
      else begin
        (* Non-blank, non-continuation line → expected output *)
        let expected =
          if starts_with panic_prefix trimmed then
            ExpectPanic (after panic_prefix trimmed)
          else
            ExpectOutput trimmed
        in
        flush expected
      end
    end
    (* else: Idle — not in a doctest block, ignore *)
  ) lines;
  (* Flush any trailing open example *)
  flush ExpectNothing;
  List.rev !examples
