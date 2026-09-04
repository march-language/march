(** End-to-end tests for the COMPILED March HTTP server.

    Why this file exists
    ────────────────────
    Three stacked bugs (fixed in "fix(runtime): compiled HTTP server serves
    requests again") took the compiled HTTP server from "works" to "panics on
    request 1", then "answers a well-formed 200 with an empty body", then
    "segfaults on request 2" — and none of it was noticed, because the only
    end-to-end test of the compiled server, [test/test_http_native.sh], was
    referenced by no dune rule and no CI workflow.  It was also too weak to
    have caught two of the three bugs even if it HAD been running.

    This file is the wired-up, strengthened replacement.  It is deliberately
    shaped around the exact ways the previous coverage failed.  Every property
    below corresponds to a bug that actually shipped — do not weaken one
    without understanding which outage it re-opens:

    1. COMPILED, at [--opt 2].  All three bugs were compiled-only: the
       interpreter served the very same program correctly the whole time, and
       every interpreted `http_server` test in test_stdlib_suite.ml stayed
       green throughout the outage.  An interpreted HTTP test has zero value
       as a guard here.

    2. MANY requests against ONE server process.  Bug 3 (a closure refcount
       dropped at the C→March boundary) freed the pipeline closure after
       exactly two calls: request 1 succeeded, request 2 segfaulted.  A
       one-request-per-server test passes cleanly against a fatally broken
       server.  This makes ~65 requests per server.

    3. Assertions on the RESPONSE BODY, not just the status.  Bug 2 (a boxed
       vs. raw Bool) made every fresh conn read as already-halted, so the plug
       pipeline never ran and the server answered a perfectly well-formed
       `HTTP/1.1 200 OK` with `Content-Length: 0`.  A status-only assertion is
       green against that.  Two of the routes here echo request-derived data,
       so the body cannot be satisfied by any constant response.

    4. An explicit LIVENESS assertion on the server process, reporting its
       exit status / fatal signal when it died.  Bug 3's segfault was silent:
       exit 139, nothing on stderr, connection simply refused.

    5. BOTH server implementations.  [MARCH_HTTP_EVLOOP=1] selects a
       completely separate code path (runtime/march_http_evloop.c,
       SO_REUSEPORT + kqueue/epoll, one thread per core) which carried its own
       copy of the bug-3 call site and was broken identically.  Keep-alive and
       pipelined requests on a single connection are exercised on both, since
       the evloop path batches pipelined requests through the pipeline
       closure in a tight loop — the most refcount-sensitive shape there is.

    Skip policy
    ───────────
    The ONLY legitimate skip is a genuinely absent toolchain — no clang on
    PATH — and that decision is made by [compile_march_or_skip], which is the
    same tool-absence ledger the rest of the compiled-regression suite uses.
    Anything else (compile failure, server that never binds, wrong body, dead
    process, timeout) is a loud FAILURE.  "Vacuous green" is precisely the
    failure mode that let this outage ship; there is no code path in this file
    that turns a broken server into a pass or a skip.

    Every wait is bounded.  A hung server must fail this test in bounded time,
    never wedge the suite. *)

open Test_helpers

(* ── Small HTTP/1.1 client (no curl dependency, full timeout control) ──── *)

(** Index of [needle] in [hay] at or after [from], if present. *)
let find_from hay needle from =
  let nl = String.length needle and hl = String.length hay in
  if nl = 0 then Some from
  else begin
    let res = ref None in
    let i = ref (max 0 from) in
    while !res = None && !i <= hl - nl do
      if String.sub hay !i nl = needle then res := Some !i else incr i
    done;
    !res
  end

(** The March source served by both variants.  Three of the four routes
    produce distinct non-empty bodies and one of them ECHOES the request
    body, so no constant/empty response can satisfy the assertions.  The
    listen port comes from the environment so a port collision can be retried
    without recompiling (and so two variants share one CAS entry). *)
let server_src = {|mod HttpNativeE2e do

  needs IO.Process
  needs IO.NetListen

  fn router(conn) do
    match (HttpServer.method(conn), HttpServer.path_info(conn)) do
    (:get, Nil) -> conn |> HttpServer.text(200, "Hello from compiled March!")
    (:get, Cons("ping", Nil)) -> conn |> HttpServer.text(200, "pong")
    (:post, Cons("echo", Nil)) -> conn |> HttpServer.text(200, HttpServer.req_body(conn))
    _ -> conn |> HttpServer.text(404, "Not Found")
    end
  end

  fn port_from_env() do
    match process_env("MARCH_TEST_HTTP_PORT") do
    Some(s) ->
      match string_to_int(s) do
      Some(n) -> n
      None -> 0
      end
    None -> 0
    end
  end

  fn main(_cap_netlisten : Cap(IO.NetListen), _cap_process : Cap(IO.Process)) do
    let port = port_from_env()
    if port == 0 do
      process_exit(2)
    else
      HttpServer.new(port)
      |> HttpServer.plug(router)
      |> HttpServer.listen()
    end
  end

end
|}

(** Ask the kernel for a currently-unused loopback port (bind to :0, read it
    back, release it).  Beats a fixed or pid-derived port: concurrent March
    sessions habitually hold 8080 and the 21000/25000 ranges the interpreted
    HTTP tests derive from their pid.  There is an unavoidable
    release-to-rebind window, so the caller retries on a bind failure. *)
let pick_free_port () =
  let s = Unix.socket Unix.PF_INET Unix.SOCK_STREAM 0 in
  Fun.protect ~finally:(fun () -> try Unix.close s with _ -> ()) (fun () ->
    Unix.bind s (Unix.ADDR_INET (Unix.inet_addr_loopback, 0));
    match Unix.getsockname s with
    | Unix.ADDR_INET (_, p) -> p
    | _ -> Alcotest.fail "pick_free_port: getsockname returned a non-inet address")

(* ── The shared exercise, run once per server implementation ───────────── *)

let run_http_e2e ~variant ~slug ~evloop () =
  (* Without this, writing to a socket whose peer has just crashed kills THIS
     process with SIGPIPE — the test would die instead of reporting the dead
     server, which is the whole point of the exercise.  Ignoring it turns the
     same event into an EPIPE we can describe. *)
  ignore (Sys.signal Sys.sigpipe Sys.Signal_ignore);
  let main_exe = find_main_exe () in
  let root = march_project_root () in
  (* [slug], not [variant]: the build directory ends up spliced unquoted into
     the compiler's own clang command line, so a space or paren in the path
     is a shell syntax error at link time.  (Found the hard way — the pretty
     variant name worked only for as long as the CAS was serving a cached
     binary and clang was never actually invoked.) *)
  let tmp = Filename.temp_file ("march_http_e2e_" ^ slug) "" in
  Sys.remove tmp;
  Unix.mkdir tmp 0o755;
  let src = Filename.concat tmp "srv.march" in
  let oc = open_out src in
  output_string oc server_src;
  close_out oc;
  let bin = Filename.concat tmp "srv" in
  let log_path = Filename.concat tmp "srv.log" in

  (* --opt 2 is not decoration: the bugs this guards are codegen/runtime
     interactions, and an unoptimized build is not the build users ship.  The
     env prefix is what selects the event-loop implementation; it is already
     part of the CAS cache key (bin/main.ml's cas_flags), so the two variants
     cannot collide on one cached binary. *)
  let cmd_prefix =
    Printf.sprintf "cd %s && %s" (Filename.quote root)
      (if evloop then "MARCH_HTTP_EVLOOP=1 " else "")
  in
  match compile_march_or_skip ~cmd_prefix ~extra_args:"--opt 2"
          ~main_exe ~bin ~src () with
  | None -> ()  (* legitimate, counted skip: no clang on PATH.  The ONLY skip. *)
  | Some bin ->

  (* ── Server process lifecycle ───────────────────────────────────────── *)
  let child = ref None in                 (* Some pid while unreaped *)
  let final_status = ref None in          (* Some status once reaped *)
  let read_log () =
    try
      let ic = open_in_bin log_path in
      let n = in_channel_length ic in
      let s = really_input_string ic n in
      close_in ic; s
    with _ -> "(server log unavailable)"
  in
  let describe_status = function
    | `Alive -> "still running"
    | `Exited rc ->
      Printf.sprintf "exited with status %d%s" rc
        (* A crashing March binary is usually reaped as a plain exit with the
           shell's 128+signal encoding rather than WSIGNALED, so spell it out:
           139 = 128+11 is the request-2 closure-refcount SIGSEGV's signature. *)
        (if rc > 128 && rc < 128 + 32 then
           Printf.sprintf " (= 128 + signal %d — the process CRASHED)" (rc - 128)
         else if rc = 0 then " (clean exit — but a listening server must not \
                              exit at all while requests are in flight)"
         else "")
    | `Signaled s ->
      Printf.sprintf "was KILLED BY SIGNAL %d%s" s
        (if s = Sys.sigsegv then " (SIGSEGV — this is the shape of the \
                                  request-2 closure-refcount crash)"
         else if s = Sys.sigbus then " (SIGBUS)"
         else if s = Sys.sigabrt then " (SIGABRT)" else "")
    | `Stopped s -> Printf.sprintf "was stopped by signal %d" s
  in
  (* Poll the child without blocking.  Once reaped the status is remembered,
     because a second waitpid would raise ECHILD. *)
  let child_status () =
    match !final_status with
    | Some st -> st
    | None ->
      (match !child with
       | None -> `Exited (-1)
       | Some pid ->
         (match Unix.waitpid [ Unix.WNOHANG ] pid with
          | 0, _ -> `Alive
          | _, Unix.WEXITED rc -> child := None; final_status := Some (`Exited rc); `Exited rc
          | _, Unix.WSIGNALED s -> child := None; final_status := Some (`Signaled s); `Signaled s
          | _, Unix.WSTOPPED s -> `Stopped s
          | exception Unix.Unix_error (Unix.ECHILD, _, _) ->
            child := None; final_status := Some (`Exited (-1)); `Exited (-1)))
  in
  let cleanup () =
    (match !child with
     | None -> ()
     | Some pid ->
       (try Unix.kill pid Sys.sigkill with _ -> ());
       (try ignore (Unix.waitpid [] pid) with _ -> ());
       child := None)
  in
  Fun.protect ~finally:cleanup (fun () ->

  (* Every failure carries the variant, the server's own stderr, and the
     process's current state — the three things that were missing when this
     broke silently. *)
  let bail (msg : string) =
    Alcotest.failf
      "[compiled HTTP server: %s] %s\n\
       server process: %s\n\
       --- server stdout/stderr (%s) ---\n%s"
      variant msg (describe_status (child_status ())) log_path (read_log ())
  in

  (* ── Start, with bounded readiness wait and port-collision retry ─────── *)
  let port = ref 0 in
  let start_once () =
    port := pick_free_port ();
    let log_fd =
      Unix.openfile log_path [ Unix.O_WRONLY; Unix.O_CREAT; Unix.O_TRUNC ] 0o644 in
    (* Select the implementation AT RUN TIME, explicitly, for BOTH variants.
       The event loop is now the default, so the thread-pool case must force
       MARCH_HTTP_EVLOOP=0 -- otherwise both cases would silently exercise the
       same server and this suite's whole point (covering both code paths)
       would evaporate into vacuous green.  Do not "simplify" this by relying
       on the default for either arm. *)
    let env =
      Array.append (Unix.environment ())
        [| Printf.sprintf "MARCH_TEST_HTTP_PORT=%d" !port
         ; (if evloop then "MARCH_HTTP_EVLOOP=1" else "MARCH_HTTP_EVLOOP=0") |] in
    let pid =
      Unix.create_process_env bin [| bin |] env Unix.stdin log_fd log_fd in
    Unix.close log_fd;
    child := Some pid;
    final_status := None
  in
  (* Generous but ALWAYS bounded: this machine can be heavily loaded, but a
     hung server must fail in finite time rather than wedge the suite. *)
  let ready_timeout = 90.0 in
  let addr () = Unix.ADDR_INET (Unix.inet_addr_loopback, !port) in
  let try_connect () =
    let s = Unix.socket Unix.PF_INET Unix.SOCK_STREAM 0 in
    match Unix.connect s (addr ()) with
    | () -> (try Unix.close s with _ -> ()); true
    | exception Unix.Unix_error _ -> (try Unix.close s with _ -> ()); false
  in
  (* A child that dies during startup is a port collision ONLY if it said so.
     Anything else is a real startup crash and must fail loudly. *)
  let died_of_port_collision () =
    let l = String.lowercase_ascii (read_log ()) in
    find_from l "tcp_listen" 0 <> None
    || find_from l "address already in use" 0 <> None
    || find_from l "no event-loop threads started" 0 <> None
    || find_from l "listener[0] failed" 0 <> None
  in
  let rec start_with_retry attempts_left =
    start_once ();
    let deadline = Unix.gettimeofday () +. ready_timeout in
    let rec poll () =
      if try_connect () then ()
      else
        match child_status () with
        | `Alive ->
          if Unix.gettimeofday () >= deadline then
            bail (Printf.sprintf
              "server never accepted a connection on 127.0.0.1:%d within %.0fs \
               (process is still running — it hung before or during listen)"
              !port ready_timeout)
          else (Unix.sleepf 0.05; poll ())
        | st ->
          (* Exited before serving.  Retry only for a diagnosed port clash. *)
          if attempts_left > 0 && died_of_port_collision () then
            start_with_retry (attempts_left - 1)
          else
            bail (Printf.sprintf
              "server process died during startup on port %d without ever \
               accepting a connection (%s). This is NOT a tool-absence skip: \
               the binary compiled, it simply does not run."
              !port (describe_status st))
    in
    poll ()
  in
  start_with_retry 4;

  (* PROVE the requested implementation is the one that actually started.
     Forcing MARCH_HTTP_EVLOOP above is necessary but not sufficient: if the
     runtime selector regressed, both variants would quietly run the same
     server and every assertion below would still pass.  The server announces
     itself on stderr, so check it.  ("(event-loop)" appears only in the
     event-loop banner; the pool prints "HTTP thread pool started".)

     WAIT for the banner rather than sampling the log once.  A successful
     connect does not imply the banner has been written: the thread-pool path
     binds and listen()s first, and only then calls march_http_pool_start,
     which is what prints "HTTP thread pool started"
     (runtime/march_http.c:2188, reached from the serve path at :2314).  A
     client can therefore complete a TCP handshake out of the listen backlog
     strictly before the banner exists, so the poll above can return with an
     EMPTY log.  That is not load-dependent -- the window is unconditional --
     and it reddened main's Linux leg on 2026-09-04 (run 33916841033) with
     "asked for the THREAD POOL but the server did not announce it" over a
     log containing nothing at all.

     Reading it as a missing banner rather than an unwritten one is the trap
     this comment exists to stop: the diagnostic accuses the runtime selector,
     and the selector was fine. An EMPTY log means "not yet"; a log carrying
     the OTHER variant's banner is the real regression, and still fails
     below. *)
  let banner_deadline = Unix.gettimeofday () +. 30.0 in
  let want = if evloop then "(event-loop)" else "thread pool" in
  let rec await_banner () =
    let b = read_log () in
    if find_from b want 0 <> None then b
    else if Unix.gettimeofday () >= banner_deadline then b
    else (Unix.sleepf 0.05; await_banner ())
  in
  let banner = await_banner () in
  let saw_evloop = find_from banner "(event-loop)" 0 <> None in
  let saw_pool   = find_from banner "thread pool"  0 <> None in
  if evloop && not saw_evloop then
    bail "asked for the EVENT LOOP but the server did not announce it — the \
          runtime implementation selector (march_http_evloop_enabled) is \
          broken, and both variants of this suite are testing one server";
  if (not evloop) && not saw_pool then
    bail "asked for the THREAD POOL but the server did not announce it — the \
          runtime implementation selector (march_http_evloop_enabled) is \
          broken, and both variants of this suite are testing one server";

  (* ── Request/response plumbing ──────────────────────────────────────── *)
  let recv_more fd pending ~deadline =
    let remaining = deadline -. Unix.gettimeofday () in
    if remaining <= 0.0 then
      bail "timed out waiting for response bytes (server hung mid-response)";
    match Unix.select [ fd ] [] [] remaining with
    | [], _, _ ->
      bail (Printf.sprintf
        "no response bytes within the %.0fs deadline — server is not \
         answering (hung, or died between accept and respond)" remaining)
    | _ ->
      let b = Bytes.create 65536 in
      let n = try Unix.read fd b 0 65536 with Unix.Unix_error _ -> 0 in
      if n = 0 then
        bail "server closed the connection mid-response (no bytes left to \
              read but the response is incomplete) — a crashed or \
              prematurely-closing server, not a valid HTTP exchange"
      else pending := !pending ^ Bytes.sub_string b 0 n
  in
  (* Parses exactly ONE response out of [pending], leaving any surplus bytes
     behind so pipelined responses can be read one after another. *)
  let read_response fd pending ~deadline =
    let rec header_end () =
      match find_from !pending "\r\n\r\n" 0 with
      | Some i -> i
      | None -> recv_more fd pending ~deadline; header_end ()
    in
    let hend = header_end () in
    let head = String.sub !pending 0 hend in
    let status =
      if String.length head < 12 then bail (Printf.sprintf "malformed status line: %S" head)
      else match int_of_string_opt (String.trim (String.sub head 9 3)) with
        | Some s -> s
        | None -> bail (Printf.sprintf "malformed status line: %S" head)
    in
    let lower = String.lowercase_ascii head in
    let clen =
      match find_from lower "\r\ncontent-length:" 0 with
      | None ->
        bail (Printf.sprintf
          "response has no Content-Length header; this client cannot frame \
           the body:\n%S" head)
      | Some i ->
        let j = i + String.length "\r\ncontent-length:" in
        let k = match find_from head "\r\n" j with Some k -> k | None -> String.length head in
        (match int_of_string_opt (String.trim (String.sub head j (k - j))) with
         | Some n -> n
         | None -> bail (Printf.sprintf "unparsable Content-Length:\n%S" head))
    in
    let body_start = hend + 4 in
    let rec fill () =
      if String.length !pending >= body_start + clen then ()
      else (recv_more fd pending ~deadline; fill ())
    in
    fill ();
    let body = String.sub !pending body_start clen in
    pending :=
      String.sub !pending (body_start + clen)
        (String.length !pending - body_start - clen);
    (status, body, lower)
  in
  let request_bytes ~meth ~path ~body ~keep_alive =
    Printf.sprintf
      "%s %s HTTP/1.1\r\nHost: 127.0.0.1\r\nConnection: %s\r\n\
       Content-Length: %d\r\n\r\n%s"
      meth path (if keep_alive then "keep-alive" else "close")
      (String.length body) body
  in
  let send fd s =
    let n = String.length s in
    let rec go off =
      if off < n then
        match Unix.write_substring fd s off (n - off) with
        | 0 -> bail "socket write returned 0 (server went away mid-request)"
        | w -> go (off + w)
        | exception Unix.Unix_error (e, _, _) ->
          bail (Printf.sprintf "socket write failed: %s (server went away \
                                mid-request)" (Unix.error_message e))
    in
    go 0
  in
  let connect_or_bail label =
    let s = Unix.socket Unix.PF_INET Unix.SOCK_STREAM 0 in
    match Unix.connect s (addr ()) with
    | () -> s
    | exception Unix.Unix_error (e, _, _) ->
      (try Unix.close s with _ -> ());
      bail (Printf.sprintf
        "could not connect to 127.0.0.1:%d for %s: %s — the server was \
         serving a moment ago, so it has since died or stopped accepting"
        !port label (Unix.error_message e))
  in
  let req_timeout = 30.0 in
  let check_response label ~exp_status ~exp_body (status, body, _) =
    if status <> exp_status then
      bail (Printf.sprintf "%s: expected status %d, got %d (body was %S)"
              label exp_status status body);
    if body <> exp_body then
      bail (Printf.sprintf
        "%s: status %d was correct but the BODY was wrong — expected %S \
         (%d bytes), got %S (%d bytes).%s"
        label status exp_body (String.length exp_body) body (String.length body)
        (if body = "" then
           "  An empty body with a well-formed status is the exact signature \
            of the plug pipeline never running."
         else ""))
  in

  (* ── Phase A: ~45 requests, each on its own connection ───────────────── *)
  (* One request per server process is what let a crash-on-request-2 ship.
     Cycling three routes means a constant responder cannot pass either. *)
  for i = 1 to 45 do
    let fd = connect_or_bail (Printf.sprintf "sequential request %d" i) in
    Fun.protect ~finally:(fun () -> try Unix.close fd with _ -> ()) (fun () ->
      let pending = ref "" in
      let deadline = Unix.gettimeofday () +. req_timeout in
      let label = Printf.sprintf "sequential request %d/45" i in
      (* Request 1 is deliberately the 200-with-a-body route: a server whose
         plug pipeline never runs answers it `200 OK` with an empty body, so
         the FIRST thing this test reports is the body mismatch rather than a
         status mismatch on some other route. *)
      match i mod 3 with
      | 1 ->
        send fd (request_bytes ~meth:"GET" ~path:"/" ~body:"" ~keep_alive:false);
        check_response (label ^ " GET /") ~exp_status:200
          ~exp_body:"Hello from compiled March!"
          (read_response fd pending ~deadline)
      | 2 ->
        send fd (request_bytes ~meth:"GET" ~path:"/no/such/route" ~body:""
                   ~keep_alive:false);
        check_response (label ^ " GET /no/such/route") ~exp_status:404
          ~exp_body:"Not Found" (read_response fd pending ~deadline)
      | _ ->
        let payload = Printf.sprintf "echo-payload-%d" i in
        send fd (request_bytes ~meth:"POST" ~path:"/echo" ~body:payload
                   ~keep_alive:false);
        check_response (label ^ " POST /echo") ~exp_status:200
          ~exp_body:payload (read_response fd pending ~deadline))
  done;

  (* ── Phase B: keep-alive — 15 requests on ONE connection ─────────────── *)
  let ka_fd = connect_or_bail "keep-alive connection" in
  Fun.protect ~finally:(fun () -> try Unix.close ka_fd with _ -> ()) (fun () ->
    let pending = ref "" in
    for i = 1 to 15 do
      let deadline = Unix.gettimeofday () +. req_timeout in
      let payload = Printf.sprintf "keepalive-%d" i in
      send ka_fd (request_bytes ~meth:"POST" ~path:"/echo" ~body:payload
                    ~keep_alive:true);
      let (status, body, head) = read_response ka_fd pending ~deadline in
      check_response (Printf.sprintf "keep-alive request %d/15" i)
        ~exp_status:200 ~exp_body:payload (status, body, head);
      if find_from head "connection: close" 0 <> None then
        bail (Printf.sprintf
          "keep-alive request %d/15: server answered `Connection: close` \
           despite a keep-alive request — the connection is being torn down \
           per request" i)
    done);

  (* ── Phase C: HTTP pipelining — 5 requests written in one go ─────────── *)
  (* The most refcount-sensitive shape on the event-loop path: it batches a
     whole pipelined burst through the same pipeline closure in one loop. *)
  let pl_fd = connect_or_bail "pipelining connection" in
  Fun.protect ~finally:(fun () -> try Unix.close pl_fd with _ -> ()) (fun () ->
    let burst = Buffer.create 1024 in
    for i = 1 to 5 do
      Buffer.add_string burst
        (request_bytes ~meth:"POST" ~path:"/echo"
           ~body:(Printf.sprintf "pipelined-%d" i) ~keep_alive:true)
    done;
    send pl_fd (Buffer.contents burst);
    let pending = ref "" in
    let deadline = Unix.gettimeofday () +. req_timeout in
    for i = 1 to 5 do
      check_response (Printf.sprintf "pipelined response %d/5" i)
        ~exp_status:200 ~exp_body:(Printf.sprintf "pipelined-%d" i)
        (read_response pl_fd pending ~deadline)
    done);

  (* ── Phase C2: bodies larger than one read buffer ────────────────────── *)
  (* Regression guard. The event-loop server read into a FIXED 64 KB inline
     buffer. A body larger than that filled it, failed to parse, and returned
     IO_PARTIAL — and because the loop is edge-triggered, no further readable
     event was ever delivered for the bytes still sitting in the socket. The
     request was never dispatched: no response, no log line, connection hung
     until the peer gave up. Every upload over 64 KB was affected, which in
     practice meant every package publish to a registry.

     64 KB is the exact boundary, so probe either side of it and well past it.
     /echo returns the body verbatim, so a truncated or mis-assembled read
     shows up as a mismatch rather than merely a non-200. *)
  List.iter (fun size ->
    let fd = connect_or_bail (Printf.sprintf "large-body %d" size) in
    Fun.protect ~finally:(fun () -> try Unix.close fd with _ -> ()) (fun () ->
      let pending = ref "" in
      let deadline = Unix.gettimeofday () +. req_timeout in
      (* Non-repeating payload: a run of one byte would hide an offset error. *)
      let payload = String.init size (fun i -> Char.chr (33 + (i mod 90))) in
      send fd (request_bytes ~meth:"POST" ~path:"/echo" ~body:payload
                 ~keep_alive:false);
      check_response
        (Printf.sprintf "%s POST /echo (%d-byte body)" variant size)
        ~exp_status:200 ~exp_body:payload (read_response fd pending ~deadline)))
    [ 32 * 1024; 64 * 1024; 65536 + 1; 256 * 1024; 1024 * 1024 ];

  (* ── Phase D: still serving, and still ALIVE ─────────────────────────── *)
  let fd = connect_or_bail "final request" in
  Fun.protect ~finally:(fun () -> try Unix.close fd with _ -> ()) (fun () ->
    let pending = ref "" in
    let deadline = Unix.gettimeofday () +. req_timeout in
    send fd (request_bytes ~meth:"GET" ~path:"/ping" ~body:"" ~keep_alive:false);
    check_response "final GET /ping" ~exp_status:200 ~exp_body:"pong"
      (read_response fd pending ~deadline));

  (* The segfault that shipped was completely silent — nothing on stderr, the
     process just vanished.  Assert the process explicitly, and report how it
     died rather than merely "requests stopped working". *)
  (match child_status () with
   | `Alive -> ()
   | st ->
     bail (Printf.sprintf
       "server process is NOT alive after serving the request sequence: it %s. \
        A server that dies after serving requests is a crash, never a skip."
       (describe_status st))))

let suites =
  [ ("http server (compiled, end-to-end)",
     [ Alcotest.test_case
         "thread-pool server: 65 requests, bodies, keep-alive, pipelining, \
          process alive (compiled --opt 2)" `Quick
         (run_http_e2e ~variant:"thread pool (default)" ~slug:"threadpool"
            ~evloop:false);
       Alcotest.test_case
         "event-loop server (MARCH_HTTP_EVLOOP=1): 65 requests, bodies, \
          keep-alive, pipelining, process alive (compiled --opt 2)" `Quick
         (run_http_e2e ~variant:"event loop (MARCH_HTTP_EVLOOP=1)"
            ~slug:"evloop" ~evloop:true);
     ]);
  ]
