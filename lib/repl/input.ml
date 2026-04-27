(** Readline-style input state machine over notty key events. Pure: no I/O. *)

type input_action =
  | Noop
  | Redraw
  | Submit of string
  | EOF
  | Complete
  | HistoryPrev
  | HistoryNext
  | HistorySearch

type state = {
  buffer        : string;
  cursor        : int;
  kill_ring     : string list;
  history_pos   : int;
  multiline_buf : string list;
}

let empty = {
  buffer = ""; cursor = 0; kill_ring = []; history_pos = -1; multiline_buf = []
}

let full_buffer s =
  let lines = List.rev (s.buffer :: s.multiline_buf) in
  String.concat "\n" lines

let insert_at s str =
  let b = s.buffer and c = s.cursor in
  let n = String.length str in
  { s with
    buffer = String.sub b 0 c ^ str ^ String.sub b c (String.length b - c);
    cursor = c + n }

let delete_back s =
  if s.cursor = 0 then s
  else
    let b = s.buffer and c = s.cursor in
    { s with
      buffer = String.sub b 0 (c - 1) ^ String.sub b c (String.length b - c);
      cursor = c - 1 }

let delete_forward s =
  let b = s.buffer and c = s.cursor and len = String.length s.buffer in
  if c >= len then s
  else
    { s with buffer = String.sub b 0 c ^ String.sub b (c + 1) (len - c - 1) }

let word_start_left s =
  let b = s.buffer and c = s.cursor in
  let i = ref (c - 1) in
  while !i > 0 && b.[!i - 1] = ' ' do decr i done;
  while !i > 0 && b.[!i - 1] <> ' ' do decr i done;
  !i

let word_end_right s =
  let b = s.buffer and c = s.cursor and len = String.length s.buffer in
  let i = ref c in
  while !i < len && b.[!i] = ' ' do incr i done;
  while !i < len && b.[!i] <> ' ' do incr i done;
  !i

(** Replace the word surrounding the cursor with [completion].
    Word start: scan left from cursor to first space (or buffer start).
    Word end: scan right from cursor to first space (or buffer end).
    No space-skipping — spaces are hard boundaries. *)
let complete_replace s completion =
  let b = s.buffer and c = s.cursor in
  let len = String.length b in
  let ws = ref c in
  while !ws > 0 && b.[!ws - 1] <> ' ' do decr ws done;
  let we = ref c in
  while !we < len && b.[!we] <> ' ' do incr we done;
  let new_buf = String.sub b 0 !ws ^ completion ^ String.sub b !we (len - !we) in
  let new_cur = !ws + String.length completion in
  { s with buffer = new_buf; cursor = new_cur }

let push_kill s killed =
  let ring = killed :: (if List.length s.kill_ring >= 8
                        then List.filteri (fun i _ -> i < 7) s.kill_ring
                        else s.kill_ring) in
  { s with kill_ring = ring }

let handle_key s key =
  match key with
  (* Printable unicode (non-ASCII) *)
  | (`Uchar uc, _mods) ->
    let str =
      let b = Buffer.create 4 in
      Buffer.add_utf_8_uchar b uc;
      Buffer.contents b
    in
    (insert_at s str, Redraw)

  (* Printable ASCII characters (notty guarantees these are not control chars) *)
  | (`ASCII c, _mods) when Char.code c >= 32 && Char.code c < 127 ->
    (insert_at s (String.make 1 c), Redraw)

  (* Arrow keys — mods list may contain `Meta for alt+arrow *)
  | (`Arrow `Left, mods) when List.mem `Meta mods ->
    ({ s with cursor = word_start_left s }, Redraw)
  | (`Arrow `Right, mods) when List.mem `Meta mods ->
    ({ s with cursor = word_end_right s }, Redraw)
  | (`Arrow `Left, _)  -> ({ s with cursor = max 0 (s.cursor - 1) }, Redraw)
  | (`Arrow `Right, _) -> ({ s with cursor = min (String.length s.buffer) (s.cursor + 1) }, Redraw)
  | (`Arrow `Up, _)    -> (s, HistoryPrev)
  | (`Arrow `Down, _)  -> (s, HistoryNext)

  | (`Home, _) -> ({ s with cursor = 0 }, Redraw)
  | (`End, _)  -> ({ s with cursor = String.length s.buffer }, Redraw)

  | (`Backspace, _) -> (delete_back s, Redraw)
  | (`Delete, _)    -> (delete_forward s, Redraw)

  | (`Tab, _) -> (s, Complete)

  | (`Enter, _) ->
    let full = full_buffer s in
    if Multiline.is_complete full then
      ({ empty with kill_ring = s.kill_ring }, Submit full)
    else
      ({ s with buffer = ""; cursor = 0;
                multiline_buf = s.buffer :: s.multiline_buf }, Redraw)

  | (`Escape, _) -> (s, Noop)

  (* Control keys arrive as ASCII control characters:
     Ctrl+A = \x01, Ctrl+B = \x02, ... Ctrl+Z = \x1a *)
  | (`ASCII '\x01', _) -> (* Ctrl+A: move to beginning of line *)
    ({ s with cursor = 0 }, Redraw)

  | (`ASCII '\x05', _) -> (* Ctrl+E: move to end of line *)
    ({ s with cursor = String.length s.buffer }, Redraw)

  | (`ASCII '\x02', _) -> (* Ctrl+B: move back one char *)
    ({ s with cursor = max 0 (s.cursor - 1) }, Redraw)

  | (`ASCII '\x06', _) -> (* Ctrl+F: move forward one char *)
    ({ s with cursor = min (String.length s.buffer) (s.cursor + 1) }, Redraw)

  | (`ASCII '\x17', _) -> (* Ctrl+W: kill word backward *)
    let start = word_start_left s in
    let killed = String.sub s.buffer start (s.cursor - start) in
    let s' = push_kill s killed in
    let s' = { s' with
      buffer = String.sub s.buffer 0 start
               ^ String.sub s.buffer s.cursor (String.length s.buffer - s.cursor);
      cursor = start } in
    (s', Redraw)

  | (`ASCII '\x0b', _) -> (* Ctrl+K: kill to end of line *)
    let killed = String.sub s.buffer s.cursor (String.length s.buffer - s.cursor) in
    let s' = push_kill s killed in
    ({ s' with buffer = String.sub s.buffer 0 s.cursor }, Redraw)

  | (`ASCII '\x15', _) -> (* Ctrl+U: kill to beginning of line *)
    let s' = push_kill s s.buffer in
    ({ s' with buffer = ""; cursor = 0 }, Redraw)

  | (`ASCII '\x19', _) -> (* Ctrl+Y: yank from kill ring *)
    (match s.kill_ring with
     | []     -> (s, Noop)
     | k :: _ -> (insert_at s k, Redraw))

  | (`ASCII '\x03', _) -> (* Ctrl+C: quit unconditionally *)
    (s, EOF)

  | (`ASCII '\x04', _) -> (* Ctrl+D: EOF if empty, else delete forward *)
    if s.buffer = "" && s.multiline_buf = []
    then (s, EOF)
    else (delete_forward s, Redraw)

  | (`ASCII '\x0c', _) -> (* Ctrl+L: redraw *)
    (s, Redraw)

  | (`ASCII '\x12', _) -> (* Ctrl+R: reverse history search *)
    (s, HistorySearch)

  | _ -> (s, Noop)
