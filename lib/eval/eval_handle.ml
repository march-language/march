(** Handle boxes for the interpreter: the [handle_*] half of
    runtime/march_handle.c (ocap phase 2, Task 2 of
    specs/plans/2026-11-10-ocap-p2-handles-plan.md).

    A handle is a [VHandle] over a mutable [handle_cell] that every copy of
    the value shares, so closing through one copy closes them all.  Same
    contract as the compiled box:
    - [handle_enter(h, kind)] returns the raw value, or -1 when the box is
      closed.  A kind mismatch, or a value that is not a box, is fatal.
      TCP_BORROWED (4) satisfies an expected TCP (3).
    - [handle_close(h)] is true for the call that closed it, false after.
      It releases the raw resource, once.
    - [handle_detach(h)] closes the box WITHOUT releasing and hands back the
      raw value (-1 when already closed).
    - An unclosed box is released when the OCaml GC collects it
      ([Gc.finalise]), so release timing differs from the compiled binary's
      (which releases when the last reference is dropped).  No parity test
      may depend on when a dropped handle is released.

    Simpler engine, one difference: the interpreter keeps no in-flight count.
    [handle_leave] is a no-op and [handle_close] releases at once; the
    compiled box defers the release to the last [handle_leave].  The
    interpreter runs one use at a time, so a close cannot land while another
    use of the same box is inside its raw call.  (This simplification was
    reviewed and accepted for ocap phase 2, Task 2.)

    The per-kind release functions are registered by [Eval_builtins] (which
    owns the raw closers, [file_close], [tcp_close], ...) through
    [set_releaser]; a kind with none registered releases nothing. *)

open Eval_types
open Eval_prim

(* Kind constants, as runtime/march_runtime.h's MARCH_HANDLE_* (and the
   stdlib's literals). *)
let kind_file = 1
let kind_dir = 2
let kind_tcp = 3
let kind_tcp_borrowed = 4
let kind_listener = 5
let kind_udp = 6
let kind_tls = 7
let kind_tls_ctx = 8
let kind_process = 9

(** The type name a box of [kind] renders as; march_handle_kind_name. *)
let kind_name (kind : int) : string =
  match kind with
  | 1 -> "File.Handle"
  | 2 -> "File.Dir"
  | 3 | 4 -> "Socket"
  | 5 -> "Listener"
  | 6 -> "Udp.UdpSocket"
  | 7 -> "Tls.TlsConn"
  | 8 -> "Tls.TlsCtx"
  | 9 -> "Process"
  | _ -> "Handle?"

(** `#<Socket>`, `#<Socket closed>`: never the descriptor. *)
let to_string (c : handle_cell) : string =
  Printf.sprintf "#<%s%s>" (kind_name c.h_kind) (if c.h_closed then " closed" else "")

(** kind -> release (raw, aux). *)
let releasers : (int, value -> value -> unit) Hashtbl.t = Hashtbl.create 16

let set_releaser (kind : int) (f : value -> value -> unit) : unit =
  Hashtbl.replace releasers kind f

(** Release the raw resource unless that has happened already. *)
let release_once (c : handle_cell) : unit =
  if not c.h_released then begin
    c.h_released <- true;
    c.h_release ()
  end

let finalise (c : handle_cell) : unit =
  (* A finaliser must not raise: a closer's error is dropped, as the
     compiled destructor drops it. *)
  try release_once c with _ -> ()

let make (kind : int) (raw : value) (aux : value) : value =
  let cell = {
    h_kind = kind; h_raw = raw; h_aux = aux;
    h_closed = false; h_released = false;
    h_release = (fun () ->
        match Hashtbl.find_opt releasers kind with
        | Some f -> f raw aux
        | None -> ());
  } in
  Gc.finalise finalise cell;
  VHandle cell

let kind_ok ~(want : int) (have : int) : bool =
  have = want || (have = kind_tcp_borrowed && want = kind_tcp)

let builtins : env =
  [ ("handle_new", VBuiltin ("handle_new", function
         | [VInt kind; raw; aux] -> make kind raw aux
         | _ -> eval_error "handle_new(kind, raw, aux)"));
    ("handle_enter", VBuiltin ("handle_enter", function
         | [VHandle c; VInt want] ->
           if not (kind_ok ~want c.h_kind) then
             eval_error "march: handle enter: a %s box used as a %s"
               (kind_name c.h_kind) (kind_name want)
           else if c.h_closed then VInt (-1)
           else c.h_raw
         | [_; VInt _] -> eval_error "march: handle enter: not a handle box"
         | _ -> eval_error "handle_enter(h, kind)"));
    ("handle_leave", VBuiltin ("handle_leave", function
         | [VHandle _] -> VUnit
         | [_] -> eval_error "march: handle leave: not a handle box"
         | _ -> eval_error "handle_leave(h)"));
    ("handle_close", VBuiltin ("handle_close", function
         | [VHandle c] ->
           if c.h_closed then VBool false
           else begin
             c.h_closed <- true;
             release_once c;
             VBool true
           end
         | [_] -> eval_error "march: handle close: not a handle box"
         | _ -> eval_error "handle_close(h)"));
    ("handle_detach", VBuiltin ("handle_detach", function
         | [VHandle c] ->
           if c.h_closed then VInt (-1)
           else begin
             c.h_closed <- true;
             c.h_released <- true;
             c.h_raw
           end
         | [_] -> eval_error "march: handle detach: not a handle box"
         | _ -> eval_error "handle_detach(h)"));
    ("handle_is_closed", VBuiltin ("handle_is_closed", function
         | [VHandle c] -> VBool c.h_closed
         | [_] -> eval_error "march: handle is_closed: not a handle box"
         | _ -> eval_error "handle_is_closed(h)"));
    ("handle_aux", VBuiltin ("handle_aux", function
         | [VHandle c] -> c.h_aux
         | [_] -> eval_error "march: handle aux: not a handle box"
         | _ -> eval_error "handle_aux(h)"));
  ]
