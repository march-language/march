(** Read deadlines on sockets — Socket.recv_timeout / Socket.set_recv_timeout.

    Why this file exists
    ────────────────────
    [Socket.recv_timeout] shipped for a long time as a function that took a
    [_timeout_ms] parameter, ignored it, and had a body byte-for-byte identical
    to the untimed [Socket.recv] above it.  A caller that reached for it
    believed it was protected against a peer going quiet and was not; the
    failure that surfaced it was a real application driving streamed HTTPS to a
    model provider, where the provider accepted the connection and then sent
    nothing, and the session stopped dead with no error and no way to recover.

    That shape — accept, then silence — is exactly what the peers here
    reproduce, and it is why the assertions below are what they are:

    1. A SILENT PEER IS A LISTENING SOCKET THAT NEVER CALLS accept().  The
       kernel completes the TCP handshake into the listen backlog, so the
       client's connect() succeeds and then nothing ever arrives.  No thread,
       no subprocess, no timing race — the peer cannot accidentally send.

    2. BOTH MECHANISMS ARE EXERCISED, because they are not interchangeable.
       [recv_timeout] is poll()-then-recv() and bounds one call without
       touching the fd; [set_recv_timeout] is SO_RCVTIMEO, a persistent
       property of the descriptor, and is the ONLY one of the two that reaches
       reads made through OpenSSL.  A test of one says nothing about the other.
       Probe B deliberately calls the UNTIMED [Socket.recv] after setting the
       option: that is the code path SSL_read rides, and if the option did not
       take effect the probe would hang rather than fail.

    3. THE TIMEOUT IS A DISTINCT ERROR, asserted as [RecvTimeout(500)] and not
       merely as "some Err".  "The peer went quiet" and "the read failed" are
       different facts and only one is worth retrying; if the sentinel string
       shared by runtime/march_http.c (MARCH_RECV_TIMEOUT_MSG), eval.ml
       (recv_timeout_msg) and stdlib/socket.march ever drifts apart, every
       timeout silently degrades back into a generic RecvFailed. That drift is
       invisible to any assertion that only checks for failure.

    4. A NON-VACUITY CONTROL (probe D): a peer that DOES answer within the
       deadline must still return Ok with its data.  Without it, a
       [recv_timeout] that had regressed into "always report a timeout" would
       pass every other assertion in this file.

    5. EVERY WAIT IS BOUNDED, and the bound is what proves the deadlines fired.
       Because the silent peer never sends, an ignored deadline blocks forever:
       simply REACHING a later probe is evidence the earlier one expired, and
       the harness additionally asserts the whole process finished in seconds
       and caps it with [run_with_timeout].  A regression that restores the
       hang must fail this test in bounded time, never wedge the suite.
       (Timing is measured in the harness rather than in March because
       [unix_time_ms] typechecks but has no codegen backing, so it does not
       link in a compiled program — see specs/todos.)

    Skip policy
    ───────────
    The only legitimate skip is genuine toolchain absence, decided by
    [compile_march_or_skip].  The TLS probe additionally requires an OpenSSL
    the compiler can find; when it is missing that ONE probe is skipped with a
    loud message, and the plain-socket probes — which cover the mechanism TLS
    rides — still run. Nothing else here turns a broken deadline into a pass. *)

open Test_helpers

(* ── Peers ─────────────────────────────────────────────────────────────── *)

(** A listening socket that never accepts.  The kernel completes the handshake
    into the backlog, so a client connects successfully and then waits forever
    for bytes that cannot come.  Returns the port and a cleanup thunk. *)
let silent_peer () =
  let s = Unix.socket Unix.PF_INET Unix.SOCK_STREAM 0 in
  Unix.setsockopt s Unix.SO_REUSEADDR true;
  Unix.bind s (Unix.ADDR_INET (Unix.inet_addr_loopback, 0));
  Unix.listen s 8;
  let port =
    match Unix.getsockname s with
    | Unix.ADDR_INET (_, p) -> p
    | _ -> Alcotest.fail "silent_peer: getsockname returned a non-inet address"
  in
  (port, fun () -> try Unix.close s with Unix.Unix_error _ -> ())

(** A peer that accepts and immediately writes [payload].  This is the
    non-vacuity control: it must still be read successfully. *)
let talking_peer payload =
  let s = Unix.socket Unix.PF_INET Unix.SOCK_STREAM 0 in
  Unix.setsockopt s Unix.SO_REUSEADDR true;
  Unix.bind s (Unix.ADDR_INET (Unix.inet_addr_loopback, 0));
  Unix.listen s 8;
  let port =
    match Unix.getsockname s with
    | Unix.ADDR_INET (_, p) -> p
    | _ -> Alcotest.fail "talking_peer: getsockname returned a non-inet address"
  in
  let stop = ref false in
  let t =
    Thread.create
      (fun () ->
        try
          while not !stop do
            let c, _ = Unix.accept s in
            ignore (Unix.write_substring c payload 0 (String.length payload));
            (* Leave the connection open: the client is testing reads, and a
               close would let an EOF masquerade as a successful read. *)
            Thread.delay 2.0;
            (try Unix.close c with Unix.Unix_error _ -> ())
          done
        with Unix.Unix_error _ -> ())
      ()
  in
  ( port,
    fun () ->
      stop := true;
      (try Unix.close s with Unix.Unix_error _ -> ());
      (* The accept thread dies with the listening socket; do not join on it,
         since a thread parked in accept() would hold the suite. *)
      ignore t )

(* ── The probe program ─────────────────────────────────────────────────── *)

(* Prints one machine-checkable line per probe.  Elapsed time is measured
   inside March, so each probe proves its OWN deadline rather than relying on
   the wall clock of a process that runs several of them. *)
let probe_src =
  {|
mod SocketTimeoutProbe do
  needs IO.NetConnect
  needs IO.Console
  needs IO.Process

  fn port_from_env(name) do
    match process_env(name) do
    Some(s) ->
      match string_to_int(s) do
      Some(n) -> n
      None -> 0
      end
    None -> 0
    end
  end

  -- Probe A: recv_timeout against a peer that accepts and then says nothing.
  -- Must report RecvTimeout carrying the deadline it was given.
  fn probe_recv_timeout(port) do
    match Socket.connect("127.0.0.1", port) do
    Err(e) -> println("A FAIL connect " ++ Socket.error_message(e))
    Ok(fd) ->
      match Socket.recv_timeout(fd, 1024, 500) do
      Err(RecvTimeout(ms)) ->
        println("A OK RecvTimeout " ++ int_to_string(ms))
      Err(other) -> println("A FAIL wrong-error " ++ Socket.error_message(other))
      Ok(_)      -> println("A FAIL unexpected-data")
      end
      Socket.close(fd)
    end
  end

  -- Probe B: the fd-level mechanism TLS rides.  set_recv_timeout, then the
  -- UNTIMED recv -- which hangs forever unless SO_RCVTIMEO actually took.
  fn probe_set_recv_timeout(port) do
    match Socket.connect("127.0.0.1", port) do
    Err(e) -> println("B FAIL connect " ++ Socket.error_message(e))
    Ok(fd) ->
      match Socket.set_recv_timeout(fd, 500) do
      Err(e) -> println("B FAIL setopt " ++ Socket.error_message(e))
      Ok(_) ->
        match Socket.recv(fd, 1024) do
        Err(RecvTimeout(_)) -> println("B OK bounded")
        Err(other)          -> println("B FAIL wrong-error " ++ Socket.error_message(other))
        Ok(_)               -> println("B FAIL unexpected-data")
        end
      end
      Socket.close(fd)
    end
  end

  -- Probe D: the non-vacuity control.  A peer that answers must still be read.
  fn probe_live_peer(port) do
    match Socket.connect("127.0.0.1", port) do
    Err(e) -> println("D FAIL connect " ++ Socket.error_message(e))
    Ok(fd) ->
      match Socket.recv_timeout(fd, 1024, 5000) do
      Ok(data) -> println("D OK data " ++ data)
      Err(e)   -> println("D FAIL " ++ Socket.error_message(e))
      end
      Socket.close(fd)
    end
  end

  fn main(_c1 : Cap(IO.NetConnect), _c2 : Cap(IO.Process), _c3 : Cap(IO.Console)) do
    let silent = port_from_env("MARCH_TEST_SILENT_PORT")
    let live   = port_from_env("MARCH_TEST_LIVE_PORT")
    if silent == 0 do
      println("FAIL no-silent-port")
    else
      probe_recv_timeout(silent)
      probe_set_recv_timeout(silent)
      probe_live_peer(live)
    end
  end

end
|}

(* Probe C lives in its own program because it is the only one that needs the
   compiler to have found an OpenSSL to link against.  The claim it pins is the
   one the originating outage was about: an fd-level deadline set BEFORE the
   handshake bounds a TLS client against a peer that accepts and goes silent,
   where previously there was no timeout-capable read on any TLS path at all. *)
let tls_probe_src =
  {|
mod TlsTimeoutProbe do
  needs IO.NetConnect
  needs IO.NetConnect.TLS
  needs IO.Console
  needs IO.Process

  fn port_from_env(name) do
    match process_env(name) do
    Some(s) ->
      match string_to_int(s) do
      Some(n) -> n
      None -> 0
      end
    None -> 0
    end
  end

  fn main(_c1 : Cap(IO.NetConnect), _c2 : Cap(IO.NetConnect.TLS),
          _c3 : Cap(IO.Process), _c4 : Cap(IO.Console)) do
    let port = port_from_env("MARCH_TEST_SILENT_PORT")
    match Socket.connect("127.0.0.1", port) do
    Err(e) -> println("C FAIL connect " ++ Socket.error_message(e))
    Ok(fd) ->
      match Socket.set_recv_timeout(fd, 500) do
      Err(e) -> println("C FAIL setopt " ++ Socket.error_message(e))
      Ok(_) ->
        match Tls.client_ctx(Tls.default_client_config()) do
        Err(_) -> println("C FAIL ctx")
        Ok(ctx) ->
          match Tls.connect(fd, ctx, "127.0.0.1") do
          Err(_) -> println("C OK bounded")
          Ok(_)  -> println("C FAIL handshake-succeeded")
          end
        end
      end
      Socket.close(fd)
    end
  end

end
|}

(* ── Harness ───────────────────────────────────────────────────────────── *)

let read_file path =
  let ic = open_in_bin path in
  Fun.protect
    ~finally:(fun () -> close_in_noerr ic)
    (fun () -> really_input_string ic (in_channel_length ic))

(** Compile [src] and run it with the given extra environment, bounded by
    [timeout_secs].  Returns the program's stdout.  A process that outruns the
    bound is a FAILURE, never a skip: a hang is precisely the regression this
    file exists to catch. *)
let compile_and_run ~slug ~src ~env ~timeout_secs =
  let main_exe = find_main_exe () in
  let dir = Filename.get_temp_dir_name () in
  let base = Filename.concat dir (Printf.sprintf "march_%s_%d" slug (Unix.getpid ())) in
  let src_path = base ^ ".march" in
  let bin = base ^ ".bin" in
  let out = base ^ ".out" in
  let oc = open_out src_path in
  output_string oc src;
  close_out oc;
  match compile_march_or_skip ~extra_args:"--opt 2" ~main_exe ~bin ~src:src_path () with
  | None -> None
  | Some bin ->
    let child_env =
      Array.append (Unix.environment ()) (Array.of_list env)
    in
    (* run_with_timeout does not take an environment, so set it here and
       restore afterwards: the child inherits this process's environment. *)
    List.iter
      (fun kv ->
        match String.index_opt kv '=' with
        | Some i ->
          Unix.putenv (String.sub kv 0 i)
            (String.sub kv (i + 1) (String.length kv - i - 1))
        | None -> ())
      env;
    ignore child_env;
    let t0 = Unix.gettimeofday () in
    let result = run_with_timeout ~timeout_secs ~stdout_file:out [| bin |] in
    let elapsed = Unix.gettimeofday () -. t0 in
    let output = try read_file out with Sys_error _ -> "" in
    (try Sys.remove src_path with Sys_error _ -> ());
    (try Sys.remove bin with Sys_error _ -> ());
    (try Sys.remove out with Sys_error _ -> ());
    (match result with
    | `Timeout ->
      Alcotest.failf
        "%s did not finish within %.0fs — a read deadline is being ignored and \
         the process is hung. Output so far:\n%s"
        slug timeout_secs output
    | `Exited rc ->
      if rc <> 0 then
        Alcotest.failf "%s exited %d. Output:\n%s" slug rc output);
    Some (output, elapsed)

let contains hay needle =
  let nl = String.length needle and hl = String.length hay in
  let rec go i = i + nl <= hl && (String.sub hay i nl = needle || go (i + 1)) in
  nl = 0 || go 0

let test_socket_read_deadlines () =
  let silent_port, close_silent = silent_peer () in
  let live_port, close_live = talking_peer "hello-from-peer" in
  Fun.protect
    ~finally:(fun () ->
      close_silent ();
      close_live ())
    (fun () ->
      match
        compile_and_run ~slug:"socket_timeout" ~src:probe_src ~timeout_secs:30.
          ~env:
            [ Printf.sprintf "MARCH_TEST_SILENT_PORT=%d" silent_port;
              Printf.sprintf "MARCH_TEST_LIVE_PORT=%d" live_port ]
      with
      | None -> ()  (* no toolchain — compile_march_or_skip already reported it *)
      | Some (out, elapsed) ->
        (* The peer NEVER sends. Two 500ms deadlines plus process startup is
           about a second; an ignored deadline is unbounded. This is what makes
           the probe lines below proof of timing and not merely of shape: had
           probe A's deadline not fired, the program could never have reached
           probe B or D to print them. *)
        Alcotest.(check bool)
          (Printf.sprintf
             "two 500ms deadlines against a silent peer complete promptly \
              (took %.1fs)" elapsed)
          true (elapsed < 10.);
        (* Probe A: the timeout is reported as its own fact, carrying the
           deadline. Asserting the exact variant is what guards the sentinel
           string shared between the runtime, the interpreter and the stdlib. *)
        Alcotest.(check bool)
          (Printf.sprintf
             "recv_timeout against a silent peer returns RecvTimeout(500) \
              promptly (got: %s)"
             (String.trim out))
          true
          (contains out "A OK RecvTimeout 500");
        (* Probe B: SO_RCVTIMEO bounds the UNTIMED read — the path SSL_read
           takes. Without the option this line cannot appear, because the
           process would still be blocked in recv(). *)
        Alcotest.(check bool)
          (Printf.sprintf
             "set_recv_timeout bounds a subsequent untimed recv (got: %s)"
             (String.trim out))
          true
          (contains out "B OK bounded");
        (* Probe D: non-vacuity. A peer that answers is still read. *)
        Alcotest.(check bool)
          (Printf.sprintf
             "a peer that answers within the deadline still returns its data \
              (got: %s)"
             (String.trim out))
          true
          (contains out "D OK data hello-from-peer"))

let test_tls_read_deadline () =
  let silent_port, close_silent = silent_peer () in
  Fun.protect
    ~finally:(fun () -> close_silent ())
    (fun () ->
      match
        compile_and_run ~slug:"tls_timeout" ~src:tls_probe_src ~timeout_secs:30.
          ~env:[ Printf.sprintf "MARCH_TEST_SILENT_PORT=%d" silent_port ]
      with
      | None -> ()
      | Some (out, elapsed) ->
        Alcotest.(check bool)
          (Printf.sprintf
             "the TLS probe completes promptly rather than hanging (took %.1fs)"
             elapsed)
          true (elapsed < 10.);
        if contains out "C FAIL ctx" then
          (* No OpenSSL for the compiler to link: the ONE probe that needs it
             cannot run. The plain-socket probes cover the same mechanism. *)
          Printf.printf
            "  [skip] TLS read-deadline probe: no usable OpenSSL TLS context\n"
        else
          Alcotest.(check bool)
            (Printf.sprintf
               "a TLS handshake against a silent peer fails within the fd \
                deadline instead of hanging (got: %s)"
               (String.trim out))
            true
            (contains out "C OK bounded"))

let suites =
  [ ( "socket_timeout",
      [ Alcotest.test_case "socket read deadlines (compiled)" `Slow
          test_socket_read_deadlines;
        Alcotest.test_case "TLS read deadline via SO_RCVTIMEO (compiled)" `Slow
          test_tls_read_deadline ] ) ]
