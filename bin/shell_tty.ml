(* Terminal side of the shell's line editor (the pure state machine is
   lib/repl/shell_line.ml).

   Raw mode is entered ONLY while a line is being edited and left before the
   input is handled, so evaluating an input (and a Ctrl-C during it) behaves
   exactly as it did with the cooked terminal.  Restoration is guaranteed by,
   in order: [Fun.protect] around every read, an [at_exit] hook (which OCaml
   also runs on an uncaught exception), and SIGINT/SIGTERM/SIGHUP handlers
   installed for the duration of a read that restore and exit.  ISIG is
   turned off while editing so Ctrl-C arrives as byte 3 and is handled as
   "discard the line" without a signal. *)

module L = March_repl.Shell_line

let saved : Unix.terminal_io option ref = ref None

let restore () =
  match !saved with
  | None -> ()
  | Some a ->
    saved := None;
    (try Unix.tcsetattr Unix.stdin Unix.TCSADRAIN a with _ -> ())

let () = at_exit restore

let enter_raw () =
  let a = Unix.tcgetattr Unix.stdin in
  saved := Some a;
  Unix.tcsetattr Unix.stdin Unix.TCSADRAIN
    { a with Unix.c_icanon = false; c_echo = false; c_isig = false;
             c_ixon = false; c_icrnl = false; c_inlcr = false;
             c_vmin = 1; c_vtime = 0 }

(* Usable only when both ends are terminals and termios works. *)
let available () =
  Unix.isatty Unix.stdin && Unix.isatty Unix.stdout
  && (try ignore (Unix.tcgetattr Unix.stdin); true with _ -> false)

let write s =
  let n = String.length s in
  let rec go off =
    if off < n then
      match Unix.write_substring Unix.stdout s off (n - off) with
      | k -> go (off + k)
      | exception Unix.Unix_error (Unix.EINTR, _, _) -> go off
      | exception Unix.Unix_error _ -> () in
  go 0

(* SIGWINCH is 28 on Linux and macOS; OCaml's Sys has no name for it. *)
let sigwinch = 28
let resized = ref true
let width = ref 80

let query_width () =
  try
    let ic = Unix.open_process_in "stty size 2>/dev/null </dev/tty" in
    let l = try input_line ic with End_of_file -> "" in
    ignore (Unix.close_process_in ic);
    (match String.split_on_char ' ' (String.trim l) with
     | [ _; c ] -> (match int_of_string_opt c with Some c when c > 4 -> c | _ -> 80)
     | _ -> 80)
  with _ -> 80

let current_width () =
  if !resized then (resized := false; width := query_width ());
  !width

(* Bytes read but not yet consumed (a paste with several newlines). *)
let queue : char Queue.t = Queue.create ()

type result = Line of string | End_of_input

let redraw ~prompt (t : L.t) =
  let prompt_cols = L.chars prompt in
  let text, col = L.view ~width:(current_width ()) ~prompt_cols t in
  write ("\r" ^ prompt ^ text ^ "\027[K\r"
         ^ (if prompt_cols + col > 0 then Printf.sprintf "\027[%dC" (prompt_cols + col) else ""))

let with_signals f =
  let h code = Sys.Signal_handle (fun _ -> restore (); exit code) in
  let sigs = [ Sys.sigint, 130; Sys.sigterm, 143; Sys.sighup, 129 ] in
  let old = List.map (fun (s, c) -> (s, Sys.signal s (h c))) sigs in
  let old_winch =
    try Some (Sys.signal sigwinch (Sys.Signal_handle (fun _ -> resized := true)))
    with _ -> None in
  Fun.protect f ~finally:(fun () ->
      List.iter (fun (s, b) -> Sys.set_signal s b) old;
      (match old_winch with Some b -> (try Sys.set_signal sigwinch b with _ -> ()) | None -> ()))

let buf = Bytes.create 1024

(* Next byte, or [None] on EOF. [timeout]: seconds to wait; [`Timeout] if none. *)
let rec next_byte ~timeout =
  if not (Queue.is_empty queue) then `Byte (Queue.pop queue)
  else
    match
      (match timeout with
       | None -> true
       | Some s -> let r, _, _ = Unix.select [ Unix.stdin ] [] [] s in r <> [])
    with
    | false -> `Timeout
    | true ->
      (match Unix.read Unix.stdin buf 0 (Bytes.length buf) with
       | 0 -> `Eof
       | n -> for i = 0 to n - 1 do Queue.push (Bytes.get buf i) queue done;
         next_byte ~timeout
       | exception Unix.Unix_error (Unix.EINTR, _, _) ->
         if !resized then `Resized else next_byte ~timeout)
    | exception Unix.Unix_error (Unix.EINTR, _, _) ->
      if !resized then `Resized else next_byte ~timeout

(* Read one edited line.  [hist] seeds up/down recall. *)
let read_line ~prompt (hist : string array) : result =
  with_signals (fun () ->
      enter_raw ();
      Fun.protect ~finally:restore (fun () ->
          let rec loop (t : L.t) =
            redraw ~prompt t;
            (* consume everything already available, then redraw once *)
            let rec drain ~first t =
              let timeout =
                if t.L.pend <> "" then Some 0.05
                else if first then None else Some 0.0 in
              match next_byte ~timeout with
              | `Eof -> `Eof
              | `Resized -> `Go t
              | `Timeout ->
                if t.L.pend <> "" then drain ~first:false (L.timeout t) else `Go t
              | `Byte c ->
                (match L.feed t c with
                 | t, L.Continue -> drain ~first:false t
                 | t, L.Accept s -> `Accept (t, s)
                 | _, L.Interrupt -> `Interrupt
                 | _, L.Eof -> `Eof
                 | t, L.Clear -> write "\027[H\027[2J"; `Go t) in
            match drain ~first:true t with
            | `Go t -> loop t
            | `Eof -> write "\r\n"; End_of_input
            | `Interrupt -> write "\027[K^C\r\n"; loop (L.reset t)
            | `Accept (t, s) -> redraw ~prompt t; write "\r\n"; Line s in
          loop (L.create hist)))
