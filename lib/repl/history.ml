(** Input history: ring buffer with Up/Down navigation and NUL-separated file persistence. *)

type t = {
  entries          : string array;
  max_size         : int;
  mutable count    : int;
  mutable write_at : int;   (* next write position in ring *)
  mutable nav_pos  : int;   (* -1 = at bottom (not navigating), >=0 = navigating *)
}

let create ~max_size =
  { entries = Array.make max_size ""; max_size; count = 0; write_at = 0; nav_pos = -1 }

(** Add an entry. Ignores blank lines and exact duplicates of the most recent entry. *)
let add h entry =
  if String.trim entry = "" then ()
  else begin
    let most_recent =
      if h.count = 0 then None
      else
        let idx = ((h.write_at - 1) + h.max_size) mod h.max_size in
        Some h.entries.(idx)
    in
    if most_recent = Some entry then ()
    else begin
      h.entries.(h.write_at) <- entry;
      h.write_at <- (h.write_at + 1) mod h.max_size;
      if h.count < h.max_size then h.count <- h.count + 1;
      h.nav_pos <- -1
    end
  end

(** Navigate one step older (Up arrow). Returns None if already at oldest. *)
let prev h =
  if h.count = 0 then None
  else
    let next_pos =
      if h.nav_pos = -1 then 0
      else h.nav_pos + 1
    in
    if next_pos >= h.count then None
    else begin
      h.nav_pos <- next_pos;
      let idx = ((h.write_at - 1 - next_pos) + h.max_size * 2) mod h.max_size in
      Some h.entries.(idx)
    end

(** Navigate one step newer (Down arrow). Returns None if already at bottom. *)
let next h =
  if h.nav_pos <= 0 then begin
    h.nav_pos <- -1;
    None
  end else begin
    h.nav_pos <- h.nav_pos - 1;
    let idx = ((h.write_at - 1 - h.nav_pos) + h.max_size * 2) mod h.max_size in
    Some h.entries.(idx)
  end

(** Reset navigation position to bottom (when starting fresh input). *)
let reset_pos h = h.nav_pos <- -1

(** Save history to file. Entries separated by NUL bytes, oldest first. *)
let save h path =
  let entries =
    let acc = ref [] in
    for i = 0 to h.count - 1 do
      let idx = ((h.write_at - 1 - i) + h.max_size * 2) mod h.max_size in
      acc := h.entries.(idx) :: !acc
    done;
    !acc
  in
  let content = String.concat "\x00" entries in
  (try
    let oc = open_out path in
    output_string oc content;
    close_out oc
  with Sys_error _ -> ())  (* silently ignore save failures *)

(** Load history from file (NUL-separated). Adds entries oldest-first. *)
let load h path =
  match (try
    let ic = open_in path in
    let n  = in_channel_length ic in
    let b  = Bytes.create n in
    really_input ic b 0 n;
    close_in ic;
    Some (Bytes.to_string b)
  with _ -> None) with
  | None -> ()
  | Some content ->
    let parts = String.split_on_char '\x00' content in
    List.iter (fun entry ->
      if entry <> "" then add h entry
    ) parts
