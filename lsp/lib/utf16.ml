(** UTF-8 (March byte columns) <-> UTF-16 (LSP character) conversion,
    plus a per-document line-start index.

    March spans use byte columns (pos_cnum - pos_bol).
    LSP Position.character counts UTF-16 code units.
    These differ on any line containing a non-ASCII character. *)

type doc = {
  src : string;
  line_starts : int array;  (** byte offset of the start of each 0-indexed line *)
}

let build (src : string) : doc =
  let starts = ref [0] in
  String.iteri (fun i c -> if c = '\n' then starts := (i + 1) :: !starts) src;
  { src; line_starts = Array.of_list (List.rev !starts) }

let line_count (d : doc) = Array.length d.line_starts

let line_start (d : doc) (line : int) : int =
  if line < 0 then 0
  else if line >= Array.length d.line_starts then String.length d.src
  else d.line_starts.(line)

let line_end (d : doc) (line : int) : int =
  if line + 1 < Array.length d.line_starts then d.line_starts.(line + 1) - 1
  else String.length d.src

(* Byte length of the UTF-8 codepoint starting at byte [i]. Malformed lead
   bytes are treated as length 1 so conversion never loops forever. *)
let utf8_len (src : string) (i : int) : int =
  let c = Char.code src.[i] in
  if c < 0x80 then 1
  else if c < 0xE0 then 2
  else if c < 0xF0 then 3
  else 4

(* UTF-16 units a codepoint of byte-length [len] contributes: a 4-byte UTF-8
   sequence (> U+FFFF) needs a surrogate pair = 2 units; otherwise 1. *)
let utf16_units_of_len = function 4 -> 2 | _ -> 1

(** Byte column within [line] for a given UTF-16 [utf16_char] column. *)
let lsp_char_to_byte_col (d : doc) ~line ~utf16_char : int =
  let ls = line_start d line and le = line_end d line in
  let rec loop byte_i units =
    if units >= utf16_char || byte_i >= le then byte_i - ls
    else
      let len = utf8_len d.src byte_i in
      loop (byte_i + len) (units + utf16_units_of_len len)
  in
  if utf16_char <= 0 then 0 else loop ls 0

(** UTF-16 character column for a given byte column within [line]. *)
let byte_col_to_lsp_char (d : doc) ~line ~byte_col : int =
  let ls = line_start d line and le = line_end d line in
  let target = min (ls + byte_col) le in
  let rec loop byte_i units =
    if byte_i >= target then units
    else
      let len = utf8_len d.src byte_i in
      loop (byte_i + len) (units + utf16_units_of_len len)
  in
  loop ls 0
