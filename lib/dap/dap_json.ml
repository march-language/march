(** Debug Adapter Protocol message framing.

    DAP messages are JSON bodies prefixed with a `Content-Length` header and a
    blank line, exactly like LSP:

      Content-Length: 119\r\n
      \r\n
      { ...json... }

    [read_message] parses one framed message from an input channel; [write_message]
    serialises one (thread-safely, guarded by a caller-supplied mutex so the eval
    worker and the protocol loop can both emit without interleaving). *)

(** Read one framed message. Returns [None] on EOF or a malformed frame. *)
let read_message (ic : in_channel) : Yojson.Safe.t option =
  let strip_cr line =
    let n = String.length line in
    if n > 0 && line.[n - 1] = '\r' then String.sub line 0 (n - 1) else line
  in
  (* Read headers until the blank line; capture Content-Length. *)
  let rec headers len =
    match input_line ic with
    | exception End_of_file -> None
    | raw ->
      let line = strip_cr raw in
      if line = "" then Some len
      else
        let len' =
          match String.index_opt line ':' with
          | None -> len
          | Some i ->
            let key = String.trim (String.sub line 0 i) in
            let v   = String.trim (String.sub line (i + 1) (String.length line - i - 1)) in
            if String.lowercase_ascii key = "content-length"
            then (try int_of_string v with _ -> len)
            else len
        in
        headers len'
  in
  match headers (-1) with
  | None | Some (-1) -> None
  | Some n when n < 0 -> None
  | Some n ->
    let buf = Bytes.create n in
    (try
       really_input ic buf 0 n;
       Some (Yojson.Safe.from_string (Bytes.to_string buf))
     with _ -> None)

(** Write one framed message. [mtx] serialises concurrent writers. *)
let write_message (mtx : Mutex.t) (oc : out_channel) (j : Yojson.Safe.t) : unit =
  let body = Yojson.Safe.to_string j in
  Mutex.lock mtx;
  Fun.protect ~finally:(fun () -> Mutex.unlock mtx) (fun () ->
      output_string oc (Printf.sprintf "Content-Length: %d\r\n\r\n" (String.length body));
      output_string oc body;
      flush oc)
