(** Line editor for the remote shell's interactive prompt (bin/shell_cmd.ml).

    Pure: bytes in, state out; no I/O except the explicit history-file
    functions at the bottom. The terminal side (raw mode, reads, redraw) lives
    in bin/shell_tty.ml.

    This is deliberately not [Input]/[History]: those are the full-screen
    notty REPL's, work on byte offsets (so a multibyte char takes several
    cursor steps), are multi-line, and drive a TUI rather than one inline
    line.

    The cursor is a BYTE offset kept on a UTF-8 character boundary; a
    multibyte char is one column step. Double-width chars are counted as one
    column.

    NB: OCaml's ['\ddd'] escapes are DECIMAL: '\001' is ^A, '\011' is ^K. *)

type t = {
  buf   : string;
  cur   : int;            (* byte offset into [buf], always on a char boundary *)
  hist  : string array;   (* oldest .. newest *)
  hpos  : int;            (* index into [hist]; [Array.length hist] = the line being typed *)
  saved : string;         (* the line being typed, while browsing history *)
  pend  : string;         (* an incomplete escape sequence or UTF-8 char *)
}

type event =
  | Continue
  | Accept of string      (* Enter: the line (not yet recorded in history) *)
  | Interrupt             (* Ctrl-C: discard the line, new prompt *)
  | Eof                   (* Ctrl-D on an empty line *)
  | Clear                 (* Ctrl-L: clear the screen, then redraw *)

let create hist =
  { buf = ""; cur = 0; hist; hpos = Array.length hist; saved = ""; pend = "" }

(* A fresh line with the same history. *)
let reset t = create t.hist

let is_cont c = Char.code c land 0xC0 = 0x80

let prev_boundary s i =
  let i = ref (max 0 (i - 1)) in
  while !i > 0 && is_cont s.[!i] do decr i done;
  !i

let next_boundary s i =
  let n = String.length s in
  let i = ref (min n (i + 1)) in
  while !i < n && is_cont s.[!i] do incr i done;
  !i

let is_space c = c = ' ' || c = '\t'

let word_left s i =
  let i = ref i in
  while !i > 0 && is_space s.[!i - 1] do decr i done;
  while !i > 0 && not (is_space s.[!i - 1]) do decr i done;
  !i

let word_right s i =
  let n = String.length s in
  let i = ref i in
  while !i < n && is_space s.[!i] do incr i done;
  while !i < n && not (is_space s.[!i]) do incr i done;
  !i

let insert t str =
  { t with
    buf = String.sub t.buf 0 t.cur ^ str
          ^ String.sub t.buf t.cur (String.length t.buf - t.cur);
    cur = t.cur + String.length str }

(* delete bytes [a, b), cursor to [a] *)
let kill_range t a b =
  { t with
    buf = String.sub t.buf 0 a ^ String.sub t.buf b (String.length t.buf - b);
    cur = a }

let set_line t s = { t with buf = s; cur = String.length s }

let move t cur = { t with cur }

let hist_prev t =
  if t.hpos = 0 then t
  else
    let saved = if t.hpos = Array.length t.hist then t.buf else t.saved in
    let hpos = t.hpos - 1 in
    set_line { t with hpos; saved } t.hist.(hpos)

let hist_next t =
  let n = Array.length t.hist in
  if t.hpos >= n then t
  else
    let hpos = t.hpos + 1 in
    set_line { t with hpos } (if hpos = n then t.saved else t.hist.(hpos))

let backspace t =
  if t.cur = 0 then t else kill_range t (prev_boundary t.buf t.cur) t.cur

let delete t =
  if t.cur >= String.length t.buf then t
  else kill_range t t.cur (next_boundary t.buf t.cur)

(* A CSI/SS3 sequence, once its final byte arrived. [params] is the bytes
   between the introducer and the final byte. Unknown sequences are dropped. *)
let csi t params final =
  let n = String.length t.buf in
  match params, final with
  | ("" | "1"), 'A' -> hist_prev t
  | ("" | "1"), 'B' -> hist_next t
  | ("" | "1"), 'C' -> move t (next_boundary t.buf t.cur)
  | ("" | "1"), 'D' -> move t (prev_boundary t.buf t.cur)
  | ("1;5" | "1;3"), 'C' -> move t (word_right t.buf t.cur)
  | ("1;5" | "1;3"), 'D' -> move t (word_left t.buf t.cur)
  | _, 'H' -> move t 0
  | _, 'F' -> move t n
  | ("1" | "7"), '~' -> move t 0
  | ("4" | "8"), '~' -> move t n
  | "3", '~' -> delete t
  | _ -> t

let utf8_len c =
  let c = Char.code c in
  if c >= 0xF0 && c <= 0xF4 then 4
  else if c >= 0xE0 && c < 0xF0 then 3
  else if c >= 0xC2 && c <= 0xDF then 2
  else 0   (* stray continuation or invalid lead *)

(* Handle a byte with nothing pending. *)
let plain t c =
  match c with
  | '\r' | '\n' -> (t, Accept t.buf)
  | '\027' -> ({ t with pend = "\027" }, Continue)
  | '\003' -> (t, Interrupt)
  | '\004' -> if t.buf = "" then (t, Eof) else (delete t, Continue)
  | '\001' -> (move t 0, Continue)
  | '\005' -> (move t (String.length t.buf), Continue)
  | '\002' -> (move t (prev_boundary t.buf t.cur), Continue)
  | '\006' -> (move t (next_boundary t.buf t.cur), Continue)
  | '\016' -> (hist_prev t, Continue)                                (* ^P *)
  | '\014' -> (hist_next t, Continue)                                (* ^N *)
  | '\012' -> (t, Clear)                                             (* ^L *)
  | '\021' -> (kill_range t 0 t.cur, Continue)                       (* ^U *)
  | '\011' -> (kill_range t t.cur (String.length t.buf), Continue)   (* ^K *)
  | '\023' -> (kill_range t (word_left t.buf t.cur) t.cur, Continue) (* ^W *)
  | '\127' | '\008' -> (backspace t, Continue)
  | c when Char.code c < 32 -> (t, Continue)   (* tab, ^Z, ... : ignored *)
  | c when Char.code c < 0x80 -> (insert t (String.make 1 c), Continue)
  | c ->
    if utf8_len c = 0 then (t, Continue)
    else ({ t with pend = String.make 1 c }, Continue)

let feed t c =
  let p = t.pend in
  if p = "" then plain t c
  else if p.[0] = '\027' then begin
    let t = { t with pend = "" } in
    let l = String.length p in
    if l = 1 then
      (match c with
       | '[' | 'O' -> ({ t with pend = "\027" ^ String.make 1 c }, Continue)
       | 'b' -> (move t (word_left t.buf t.cur), Continue)   (* Alt-b *)
       | 'f' -> (move t (word_right t.buf t.cur), Continue)  (* Alt-f *)
       | _ -> (t, Continue))                                  (* unknown: drop *)
    else
      let code = Char.code c in
      if code >= 0x40 && code <= 0x7E then
        (csi t (String.sub p 2 (l - 2)) c, Continue)
      else if code >= 0x20 && code <= 0x3F && l < 16 then
        ({ t with pend = p ^ String.make 1 c }, Continue)
      else (t, Continue)                                      (* malformed: drop *)
  end else begin
    (* inside a multibyte char *)
    if is_cont c then begin
      let p = p ^ String.make 1 c in
      if String.length p = utf8_len p.[0] then
        (insert { t with pend = "" } p, Continue)
      else ({ t with pend = p }, Continue)
    end else
      (* not a continuation: the partial char is invalid; drop it, reprocess *)
      plain { t with pend = "" } c
  end

(* Nothing more arrived after the pending bytes: a lone ESC is the Escape key
   (ignored); a truncated sequence is dropped. *)
let timeout t = { t with pend = "" }

let feed_string t s =
  let t = ref t and evs = ref [] in
  String.iter (fun c ->
      let t', e = feed !t c in
      t := t'; if e <> Continue then evs := e :: !evs) s;
  (!t, List.rev !evs)

(* ---------- display ---------- *)

let chars s =
  let n = ref 0 in
  String.iter (fun c -> if not (is_cont c) then incr n) s;
  !n

(* byte offset of the [k]th char of [s] (clamped) *)
let byte_of_char s k =
  let n = String.length s in
  let i = ref 0 and seen = ref 0 in
  while !i < n && !seen < k do i := next_boundary s !i; incr seen done;
  !i

(** What to draw after the prompt on a terminal [width] columns wide whose
    prompt takes [prompt_cols]: the visible slice of the line and the cursor's
    column within it. A line too long for one row scrolls horizontally, so the
    cursor never reaches the last column and nothing wraps. *)
let view ~width ~prompt_cols t =
  let avail = max 1 (width - prompt_cols - 1) in
  let total = chars t.buf in
  let ci = chars (String.sub t.buf 0 t.cur) in
  if total <= avail then (t.buf, ci)
  else
    let start = if ci < avail then 0 else ci - avail + 1 in
    let a = byte_of_char t.buf start in
    let b = byte_of_char t.buf (start + avail) in
    (String.sub t.buf a (b - a), ci - start)

(* ---------- history ---------- *)

let default_cap = 1000

(** Whether an accepted line belongs in history, and its stored form. *)
let history_entry line =
  let l = String.trim line in
  if l = "" || l = ":quit" || l = ":q" then None else Some l

(** [record hist line]: the new history and whether [line] was added.
    Skips blank lines, [:quit]/[:q], and a line identical to the newest. *)
let record ?(cap = default_cap) hist line =
  match history_entry line with
  | None -> (hist, false)
  | Some l ->
    let n = Array.length hist in
    if n > 0 && hist.(n - 1) = l then (hist, false)
    else
      let h = Array.append hist [| l |] in
      let n = Array.length h in
      ((if n > cap then Array.sub h (n - cap) cap else h), true)

let read_lines path =
  match open_in_bin path with
  | exception Sys_error _ -> []
  | ic ->
    let rec go acc =
      match input_line ic with
      | l -> go (if String.trim l = "" then acc else l :: acc)
      | exception End_of_file -> List.rev acc in
    let r = go [] in
    close_in ic; r

let write_file path lines =
  let tmp = path ^ ".tmp" in
  let fd = Unix.openfile tmp [ Unix.O_WRONLY; Unix.O_CREAT; Unix.O_TRUNC ] 0o600 in
  let oc = Unix.out_channel_of_descr fd in
  List.iter (fun l -> output_string oc l; output_char oc '\n') lines;
  close_out oc;
  Unix.rename tmp path

(** Load the history file (missing file = empty). If it holds more than [cap]
    entries it is rewritten to the last [cap]. Never raises. *)
let load ?(cap = default_cap) path =
  try
    let lines = read_lines path in
    let n = List.length lines in
    let lines =
      if n > cap then begin
        let kept = List.filteri (fun i _ -> i >= n - cap) lines in
        (try write_file path kept with _ -> ());
        kept
      end else lines in
    if lines <> [] then (try Unix.chmod path 0o600 with _ -> ());
    Array.of_list lines
  with _ -> [||]

let rec mkdir_p dir =
  if not (Sys.file_exists dir) then begin
    mkdir_p (Filename.dirname dir);
    (try Unix.mkdir dir 0o700 with Unix.Unix_error (Unix.EEXIST, _, _) -> ())
  end

(** Append one entry (creating the file 0600 and its directory 0700). Never raises. *)
let append path line =
  try
    mkdir_p (Filename.dirname path);
    let fd = Unix.openfile path [ Unix.O_WRONLY; Unix.O_APPEND; Unix.O_CREAT ] 0o600 in
    let s = line ^ "\n" in
    ignore (Unix.write_substring fd s 0 (String.length s));
    Unix.close fd
  with _ -> ()

(** [~/.march/shell_history], or [None] when HOME is unset. *)
let default_path () =
  match Sys.getenv_opt "HOME" with
  | Some h when h <> "" -> Some (Filename.concat (Filename.concat h ".march") "shell_history")
  | _ -> None
