(** End-to-end tests for HTTPS in the COMPILED March HTTP server.

    Same rules as test_http_native.ml (whose harness this reuses): compiled
    at --opt 2, many requests per server, assertions on bodies, an explicit
    liveness check, every wait bounded, and the only skip a missing
    toolchain (compile_march_or_skip). The TLS client is the [openssl] CLI;
    without it the HTTPS cases fail loudly rather than skip, since every CI
    image and dev machine that builds the runtime has it.

    Design: specs/2026-11-05-https-server-design.md.
    Plan:   specs/plans/2026-11-06-https-server-plan.md. *)

open Test_helpers

(* ── Compiling and running one-shot programs ───────────────────────────── *)

let fresh_dir slug =
  let tmp = Filename.temp_file ("march_https_e2e_" ^ slug) "" in
  Sys.remove tmp;
  Unix.mkdir tmp 0o755;
  tmp

(** Compile [src] at --opt 2; [None] only when the toolchain is absent. *)
let compile_src ~slug src =
  let dir = fresh_dir slug in
  let path = Filename.concat dir "prog.march" in
  let oc = open_out path in
  output_string oc src;
  close_out oc;
  let bin = Filename.concat dir "prog" in
  let cmd_prefix = Printf.sprintf "cd %s &&" (Filename.quote (march_project_root ())) in
  match compile_march_or_skip ~cmd_prefix ~extra_args:"--opt 2"
          ~main_exe:(find_main_exe ()) ~bin ~src:path () with
  | None -> None
  | Some bin -> Some (dir, bin)

(** Run [argv] with [env] added, stdout and stderr together into one file;
    kill it after [timeout] seconds. *)
let run_capture ?(env = [||]) ~timeout argv =
  let out = Filename.temp_file "march_https_run" ".out" in
  let fd = Unix.openfile out [ Unix.O_WRONLY; Unix.O_CREAT; Unix.O_TRUNC ] 0o644 in
  let pid =
    Unix.create_process_env argv.(0) argv (Array.append (Unix.environment ()) env)
      Unix.stdin fd fd in
  Unix.close fd;
  let deadline = Unix.gettimeofday () +. timeout in
  let rec wait () =
    match Unix.waitpid [ Unix.WNOHANG ] pid with
    | 0, _ ->
      if Unix.gettimeofday () >= deadline then begin
        (try Unix.kill pid Sys.sigkill with Unix.Unix_error _ -> ());
        ignore (Unix.waitpid [] pid);
        `Timeout
      end else (Unix.sleepf 0.05; wait ())
    | _, Unix.WEXITED rc -> `Exited rc
    | _, Unix.WSIGNALED s -> `Signaled s
    | _, Unix.WSTOPPED s -> `Signaled s
  in
  let st = wait () in
  let text = read_file_contents out in
  (try Sys.remove out with Sys_error _ -> ());
  (st, text)

let contains hay needle = Test_http_native.find_from hay needle 0 <> None

let show_status = function
  | `Exited rc -> Printf.sprintf "exited %d" rc
  | `Signaled s -> Printf.sprintf "killed by signal %d" s
  | `Timeout -> "timed out"

let port_refuses port =
  let s = Unix.socket Unix.PF_INET Unix.SOCK_STREAM 0 in
  Fun.protect ~finally:(fun () -> try Unix.close s with _ -> ()) (fun () ->
    match Unix.connect s (Unix.ADDR_INET (Unix.inet_addr_loopback, port)) with
    | () -> false
    | exception Unix.Unix_error _ -> true)

(* ── config_errors ─────────────────────────────────────────────────────── *)

let config_src = {|mod HttpsConfigProbe do
  needs IO.Console
  needs IO.NetListen
  needs IO.NetConnect.TLS

  fn show(r) do
    match r do
    Ok(_) -> "Ok"
    Err(e) -> "Err(" ++ e ++ ")"
    end
  end

  fn main(_c : Cap(IO.Console), _l : Cap(IO.NetListen), _t : Cap(IO.NetConnect.TLS)) do
    println("reload: " ++ show(http_server_reload_tls(0, "a", "b")))
    println("configure: " ++ show(http_server_tls_configure(0, "/nonexistent.pem", "/nonexistent.key", 0, 0)))
    let conn = HttpServer.test_conn(:get, "/", Nil, "")
    println("scheme: " ++ HttpServer.scheme(conn))
  end
end
|}

let test_config_errors () =
  match compile_src ~slug:"config" config_src with
  | None -> ()
  | Some (_, bin) ->
    let st, out = run_capture ~timeout:20. [| bin |] in
    if st <> `Exited 0 then
      Alcotest.failf "config probe %s:\n%s" (show_status st) out;
    let expect s =
      if not (contains out s) then Alcotest.failf "expected %S in:\n%s" s out in
    expect "reload: Err(reload_tls: no TLS server is configured)";
    expect "configure: Err(";
    expect "/nonexistent.pem";
    expect "scheme: http"

(* ── importers keep their needs ────────────────────────────────────────── *)

(* A module that imports HttpServer must declare every module-level `needs`
   HttpServer declares wherever the checker cannot narrow the import's demand
   to the names used (import_cap_missing; reproduced with Bastion 0.3.1's
   modules on MARCH_LIB_PATH, which is how forge builds forgepm). Bastion and
   forgepm declare only IO.NetListen for it, and the design's anti-goal is
   that they compile unchanged, so HTTPS adds no module-level `needs` to
   HttpServer: reload_tls is classified IO.NetListen, and acme_webroot (the
   one file reader) lives in HttpAcme. *)
let test_importer_needs_unchanged () =
  let src = read_file_contents (Filename.concat (march_project_root ()) "stdlib/http_server.march") in
  let needs =
    String.split_on_char '\n' src
    |> List.filter_map (fun l ->
        let l = String.trim l in
        if String.length l > 6 && String.sub l 0 6 = "needs " then Some l else None) in
  Alcotest.(check (list string)) "HttpServer's module-level needs" [ "needs IO.NetListen" ] needs

(* ── listen_bad_cert_exits ─────────────────────────────────────────────── *)

let bad_cert_src = {|mod HttpsBadCert do
  needs IO.Process
  needs IO.NetListen
  needs IO.NetConnect.TLS

  fn env_int(name) do
    match process_env(name) do
    Some(s) ->
      match string_to_int(s) do
      Some(n) -> n
      None -> 0
      end
    None -> 0
    end
  end

  fn main(_l : Cap(IO.NetListen), _t : Cap(IO.NetConnect.TLS), _p : Cap(IO.Process)) do
    HttpServer.new(env_int("MARCH_TEST_HTTP_PORT"))
    |> HttpServer.tls(HttpServer.TlsFiles("/nonexistent/march-cert.pem", "/nonexistent/march-key.pem"))
    |> HttpServer.plug(fn c -> HttpServer.text(c, 200, "should never serve"))
    |> HttpServer.listen()
  end
end
|}

let test_listen_bad_cert_exits () =
  match compile_src ~slug:"badcert" bad_cert_src with
  | None -> ()
  | Some (_, bin) ->
    let port = Test_http_native.pick_free_port () in
    let st, out =
      run_capture ~env:[| Printf.sprintf "MARCH_TEST_HTTP_PORT=%d" port |] ~timeout:5. [| bin |] in
    (match st with
     | `Exited rc when rc <> 0 -> ()
     | st -> Alcotest.failf "server with a missing certificate %s (want a nonzero exit within 5 s):\n%s"
               (show_status st) out);
    if not (contains out "/nonexistent/march-cert.pem") then
      Alcotest.failf "the startup error does not name the missing file:\n%s" out;
    if not (port_refuses port) then
      Alcotest.failf "port %d accepts connections after a failed startup" port

(* ── Deadlines (plain HTTP) ──────────────────────────────────────────── *)

(* Every timeout is 2 s, so a connection the server should cut is cut well
   inside the test's windows, and one it must keep (a slow transfer that
   keeps moving) outlives several timeouts. *)
let deadline_server_src = {|mod HttpsDeadlines do
  needs IO.Process
  needs IO.NetListen

  fn env_int(name) do
    match process_env(name) do
    Some(s) ->
      match string_to_int(s) do
      Some(n) -> n
      None -> 0
      end
    None -> 0
    end
  end

  fn router(conn) do
    match (HttpServer.method(conn), HttpServer.path_info(conn)) do
    (:get, Nil) -> conn |> HttpServer.text(200, "ok")
    (:get, Cons("big", Cons(n, Nil))) ->
      match string_to_int(n) do
      Some(k) -> conn |> HttpServer.text(200, string_repeat("x", k))
      None -> conn |> HttpServer.text(400, "bad size")
      end
    (:post, Cons("upload", Nil)) ->
      conn |> HttpServer.text(200, int_to_string(string_byte_length(HttpServer.req_body(conn))))
    _ -> conn |> HttpServer.text(404, "Not Found")
    end
  end

  fn main(_l : Cap(IO.NetListen), _p : Cap(IO.Process)) do
    HttpServer.new(env_int("MARCH_TEST_HTTP_PORT"))
    |> HttpServer.idle_timeout(2)
    |> HttpServer.header_timeout(2)
    |> HttpServer.progress_timeout(2)
    |> HttpServer.plug(router)
    |> HttpServer.listen()
  end
end
|}

(** Seconds until the peer closes [fd] (read returns 0 or the connection is
    reset), draining whatever it sends; [None] if still open at [timeout]. *)
let wait_closed fd ~timeout =
  let t0 = Unix.gettimeofday () in
  let buf = Bytes.create 65536 in
  let rec go () =
    let left = t0 +. timeout -. Unix.gettimeofday () in
    if left <= 0. then None
    else match Unix.select [ fd ] [] [] left with
      | [], _, _ -> None
      | _ ->
        (match Unix.read fd buf 0 65536 with
         | 0 -> Some (Unix.gettimeofday () -. t0)
         | _ -> go ()
         | exception Unix.Unix_error ((Unix.ECONNRESET | Unix.EPIPE), _, _) ->
           Some (Unix.gettimeofday () -. t0))
  in
  go ()

(** Write without bailing: [false] once the peer is gone. *)
let try_send fd s =
  match Unix.write_substring fd s 0 (String.length s) with
  | _ -> true
  | exception Unix.Unix_error _ -> false

let assert_alive (ctx : Test_http_native.server_ctx) label =
  match ctx.child_status () with
  | `Alive -> ()
  | st -> ctx.bail (Printf.sprintf "%s: server not alive afterwards (%s)" label
                      (ctx.describe_status st))

let close_quietly fd = try Unix.close fd with Unix.Unix_error _ -> ()

let expect_closed_within ctx label fd ~lo ~hi =
  match wait_closed fd ~timeout:(hi +. 2.) with
  | None -> ctx.Test_http_native.bail (Printf.sprintf "%s: connection still open after %.1fs" label (hi +. 2.))
  | Some t when t < lo || t > hi ->
    ctx.bail (Printf.sprintf "%s: closed after %.2fs, want %.1f-%.1fs" label t lo hi)
  | Some _ -> ()

let d_idle_closes (ctx : Test_http_native.server_ctx) =
  let fd = ctx.connect_or_bail "idle_closes" in
  expect_closed_within ctx "idle_closes" fd ~lo:1.5 ~hi:4.5;
  close_quietly fd

let d_idle_after_response (ctx : Test_http_native.server_ctx) =
  let fd = ctx.connect_or_bail "idle_after_response" in
  ctx.send fd (ctx.request_bytes ~meth:"GET" ~path:"/" ~body:"" ~keep_alive:true);
  let pending = ref "" in
  ctx.check_response "idle_after_response" ~exp_status:200 ~exp_body:"ok"
    (ctx.read_response fd pending ~deadline:(Unix.gettimeofday () +. 10.));
  expect_closed_within ctx "idle_after_response" fd ~lo:1.0 ~hi:4.5;
  close_quietly fd

let d_slowloris_closes (ctx : Test_http_native.server_ctx) =
  let fd = ctx.connect_or_bail "slowloris" in
  let t0 = Unix.gettimeofday () in
  ignore (try_send fd "GET / HTTP/1.1\r\nX-Slow: ");
  let rec drip () =
    let el = Unix.gettimeofday () -. t0 in
    if el > 6.5 then ctx.bail "slowloris: still open 6.5s after the first byte although headers never completed"
    else match Unix.select [ fd ] [] [] 0.5 with
      | [], _, _ -> if try_send fd "a" then drip () else el
      | _ ->
        (match Unix.read fd (Bytes.create 4096) 0 4096 with
         | 0 -> Unix.gettimeofday () -. t0
         | _ -> drip ()
         | exception Unix.Unix_error _ -> Unix.gettimeofday () -. t0)
  in
  let t = drip () in
  if t > 4.5 then ctx.bail (Printf.sprintf "slowloris: closed only after %.2fs (want < 4.5s)" t);
  close_quietly fd

let upload_head n =
  Printf.sprintf "POST /upload HTTP/1.1\r\nHost: 127.0.0.1\r\nConnection: close\r\n\
                  Content-Length: %d\r\n\r\n" n

let d_slow_upload_survives (ctx : Test_http_native.server_ctx) =
  let fd = ctx.connect_or_bail "slow_upload" in
  ctx.send fd (upload_head 40000);
  for _ = 1 to 10 do
    Unix.sleepf 1.0;
    if not (try_send fd (String.make 4000 'u')) then
      ctx.bail "slow_upload: the server cut an upload that kept making progress"
  done;
  let pending = ref "" in
  ctx.check_response "slow_upload" ~exp_status:200 ~exp_body:"40000"
    (ctx.read_response fd pending ~deadline:(Unix.gettimeofday () +. 10.));
  close_quietly fd

let d_stalled_upload_cut (ctx : Test_http_native.server_ctx) =
  let fd = ctx.connect_or_bail "stalled_upload" in
  ctx.send fd (upload_head 40000 ^ String.make 4000 'u');
  expect_closed_within ctx "stalled_upload" fd ~lo:1.0 ~hi:4.5;
  close_quietly fd

let big = 4 * 1024 * 1024

(* A small receive buffer keeps what the kernel can absorb on the client's
   side far below the response, so "the server stopped sending" shows. *)
let connect_small_rcvbuf (ctx : Test_http_native.server_ctx) =
  let s = Unix.socket Unix.PF_INET Unix.SOCK_STREAM 0 in
  Unix.setsockopt_int s Unix.SO_RCVBUF 16384;
  (try Unix.connect s (Unix.ADDR_INET (Unix.inet_addr_loopback, ctx.port))
   with Unix.Unix_error (e, _, _) ->
     ctx.bail ("connect: " ^ Unix.error_message e));
  s

let d_slow_reader_survives (ctx : Test_http_native.server_ctx) =
  let fd = connect_small_rcvbuf ctx in
  ctx.send fd (Printf.sprintf "GET /big/%d HTTP/1.1\r\nHost: x\r\nConnection: close\r\n\r\n" big);
  (* 256 KB every 0.3 s: about 5 s for 4 MiB, never 2 s without progress. *)
  let got = Buffer.create (big + 1024) in
  let chunk = Bytes.create 262144 in
  let t0 = Unix.gettimeofday () in
  let rec go () =
    if Unix.gettimeofday () -. t0 > 60. then ctx.bail "slow_reader: response not complete after 60s";
    Unix.sleepf 0.3;
    let rec fill want =
      if want > 0 then
        match Unix.select [ fd ] [] [] 0.0 with
        | [], _, _ -> ()
        | _ ->
          (match Unix.read fd chunk 0 want with
           | 0 -> raise Exit
           | n -> Buffer.add_subbytes got chunk 0 n; fill (want - n)
           | exception Unix.Unix_error _ -> raise Exit)
    in
    match fill 262144 with
    | () -> go ()
    | exception Exit -> ()
  in
  go ();
  let resp = Buffer.contents got in
  match Test_http_native.find_from resp "\r\n\r\n" 0 with
  | None -> ctx.bail "slow_reader: no response headers"
  | Some h ->
    let body_len = String.length resp - h - 4 in
    if body_len <> big then
      ctx.bail (Printf.sprintf "slow_reader: body %d bytes, want %d (cut mid-transfer?)" body_len big);
    String.iteri (fun i ch -> if i > h + 3 && ch <> 'x' then
                     ctx.bail (Printf.sprintf "slow_reader: corrupt byte at %d" i)) resp;
    close_quietly fd

let d_stalled_reader_cut (ctx : Test_http_native.server_ctx) =
  let fd = connect_small_rcvbuf ctx in
  ctx.send fd (Printf.sprintf "GET /big/%d HTTP/1.1\r\nHost: x\r\nConnection: close\r\n\r\n" big);
  Unix.sleepf 6.0;
  (* Now drain fast: a server that cut the stalled transfer delivers EOF
     well before the 4 MiB body is complete. *)
  let total = ref 0 in
  let buf = Bytes.create 65536 in
  let t0 = Unix.gettimeofday () in
  let rec go () =
    if Unix.gettimeofday () -. t0 > 8. then
      ctx.bail (Printf.sprintf "stalled_reader: still open after 6s stall + 8s (%d bytes read)" !total)
    else match Unix.select [ fd ] [] [] 1.0 with
      | [], _, _ -> go ()
      | _ ->
        (match Unix.read fd buf 0 65536 with
         | 0 -> ()
         | n -> total := !total + n; go ()
         | exception Unix.Unix_error _ -> ())
  in
  go ();
  if !total >= big then
    ctx.bail (Printf.sprintf "stalled_reader: the whole body (%d bytes) arrived; the stalled transfer was not cut" !total);
  close_quietly fd

let deadline_cases =
  [ ("idle_closes", d_idle_closes);
    ("idle_after_response", d_idle_after_response);
    ("slowloris_closes", d_slowloris_closes);
    ("slow_upload_survives", d_slow_upload_survives);
    ("stalled_upload_cut", d_stalled_upload_cut);
    ("slow_reader_survives", d_slow_reader_survives);
    ("stalled_reader_cut", d_stalled_reader_cut) ]

(** The three server modes: the event loop (default), the thread pool, and
    the pool's sequential variant, which serves on the accept loop's green
    thread. Every runtime-behaviour group below runs over all three. *)
let modes =
  [ ("evloop", true, [||]);
    ("pool", false, [||]);
    ("sequential", false, [| "MARCH_HTTP_SEQUENTIAL=1" |]) ]

(* One compiled server per mode; every case runs against it in turn and
   checks it is still alive. *)
let run_deadlines ~mode ~evloop ~extra_env () =
  Test_http_native.with_compiled_server ~extra_env ~variant:("deadlines, " ^ mode)
    ~slug:("deadlines" ^ mode) ~evloop ~server_src:deadline_server_src (fun ctx ->
      List.iter (fun (name, f) -> f ctx; assert_alive ctx name) deadline_cases)

(* ── TLS client and certificates (openssl CLI) ────────────────────────── *)

type pki = { dir : string; ca : string; cert : string; key : string }

let sh cmd =
  if Sys.command cmd <> 0 then Alcotest.failf "command failed: %s" cmd

let write_text path text =
  let oc = open_out_bin path in
  output_string oc text;
  close_out oc

let () = Random.self_init ()

(** A throwaway P-256 CA and a leaf for localhost / 127.0.0.1 signed by it,
    as PEM files in [dir] prefixed by [name]. [days] < 0 makes a leaf that
    expired yesterday. *)
let make_pki ~dir ~name ?(days = 2) () =
  let p f = Filename.concat dir (name ^ "-" ^ f) in
  let q = Filename.quote in
  let ca_key = p "ca.key" and ca = p "ca.pem" and key = p "key.pem"
  and csr = p "leaf.csr" and cert = p "cert.pem" and ext = p "ext.cnf" in
  write_text ext "subjectAltName=DNS:localhost,IP:127.0.0.1\nbasicConstraints=CA:FALSE\n";
  sh (Printf.sprintf "openssl ecparam -name prime256v1 -genkey -noout -out %s 2>/dev/null" (q ca_key));
  sh (Printf.sprintf "openssl req -x509 -new -key %s -subj /CN=march-test-ca-%s -days 3 -out %s 2>/dev/null"
        (q ca_key) name (q ca));
  sh (Printf.sprintf "openssl ecparam -name prime256v1 -genkey -noout -out %s 2>/dev/null" (q key));
  sh (Printf.sprintf "openssl req -new -key %s -subj /CN=localhost -out %s 2>/dev/null" (q key) (q csr));
  let sign validity =
    Sys.command (Printf.sprintf
      "openssl x509 -req -in %s -CA %s -CAkey %s -set_serial %d %s -extfile %s -out %s 2>/dev/null"
      (q csr) (q ca) (q ca_key) (1000 + Random.int 1_000_000) validity (q ext) (q cert)) = 0
    && (try (Unix.stat cert).Unix.st_size > 0 with Unix.Unix_error _ -> false) in
  if days >= 0 then begin
    if not (sign (Printf.sprintf "-days %d" days)) then Alcotest.fail "openssl x509 -req failed"
  end else begin
    (* An already-expired leaf: -not_after where the CLI has it (OpenSSL >=
       3.4), else a negative -days (older releases accept it). *)
    let stamp ago =
      let t = Unix.gmtime (Unix.time () -. ago) in
      Printf.sprintf "%04d%02d%02d%02d%02d%02dZ" (t.tm_year + 1900) (t.tm_mon + 1)
        t.tm_mday t.tm_hour t.tm_min t.tm_sec in
    if not (sign (Printf.sprintf "-not_before %s -not_after %s" (stamp 172800.) (stamp 86400.)))
       && not (sign "-days -1") then
      Alcotest.fail "cannot make an expired certificate with this openssl CLI"
  end;
  { dir; ca; cert; key }

(* s_client children, by the socket end handed to the test, so a close (or
   the end of a run) can reap them. *)
let s_clients : (Unix.file_descr, int) Hashtbl.t = Hashtbl.create 16

let tls_close fd =
  (try Unix.close fd with Unix.Unix_error _ -> ());
  match Hashtbl.find_opt s_clients fd with
  | None -> ()
  | Some pid ->
    Hashtbl.remove s_clients fd;
    (try Unix.kill pid Sys.sigkill with Unix.Unix_error _ -> ());
    (try ignore (Unix.waitpid [] pid) with Unix.Unix_error _ -> ())

let reap_s_clients () =
  Hashtbl.fold (fun fd _ acc -> fd :: acc) s_clients [] |> List.iter tls_close

(** A TLS connection to the server through [openssl s_client -quiet]: the
    returned socket carries plaintext both ways, so the plain-HTTP helpers
    ([send], [read_response]) work on it unchanged. The certificate is
    verified against [ca]; [sni] = None sends no server name. *)
let tls_connect_or_bail (ctx : Test_http_native.server_ctx) ?port ~ca ?(sni = Some "localhost") () =
  let port = match port with Some p -> p | None -> ctx.port in
  let parent, child = Unix.socketpair Unix.PF_UNIX Unix.SOCK_STREAM 0 in
  let argv = Array.of_list
      ([ "openssl"; "s_client"; "-quiet"; "-connect"; Printf.sprintf "127.0.0.1:%d" port;
         "-CAfile"; ca; "-verify_return_error" ]
       @ (match sni with Some n -> [ "-servername"; n ] | None -> [ "-noservername" ])) in
  let devnull = Unix.openfile "/dev/null" [ Unix.O_WRONLY ] 0 in
  let pid =
    try Unix.create_process "openssl" argv child child devnull
    with Unix.Unix_error (e, _, _) ->
      ctx.bail ("cannot run openssl s_client: " ^ Unix.error_message e) in
  Unix.close child;
  Unix.close devnull;
  Hashtbl.replace s_clients parent pid;
  parent

let connect_port (ctx : Test_http_native.server_ctx) port =
  let s = Unix.socket Unix.PF_INET Unix.SOCK_STREAM 0 in
  (try Unix.connect s (Unix.ADDR_INET (Unix.inet_addr_loopback, port))
   with Unix.Unix_error (e, _, _) ->
     ctx.bail (Printf.sprintf "connect 127.0.0.1:%d: %s" port (Unix.error_message e)));
  s

(* ── HTTPS (event loop, then the other modes) ───────────────────────────── *)

let https_server_src = {|mod HttpsE2e do
  needs IO.Process
  needs IO.NetListen
  needs IO.WebSocket
  needs IO.Spawn

  fn env_str(name) do
    match process_env(name) do
    Some(s) -> s
    None -> ""
    end
  end

  fn env_int(name) do
    match string_to_int(env_str(name)) do
    Some(n) -> n
    None -> 0
    end
  end

  fn sum_bytes(s, i, n, acc) do
    if i >= n do acc
    else sum_bytes(s, i + 1, n, (acc + string_byte_at(s, i)) % 1000003)
    end
  end

  fn ws_echo_loop(socket) do
    match WebSocket.recv(socket) do
    TextFrame(msg) ->
      WebSocket.send_frame(socket, TextFrame(msg))
      ws_echo_loop(socket)
    Close(_, _) -> ()
    _ -> ws_echo_loop(socket)
    end
  end

  fn push_loop(socket, i) do
    if i > 200 do ()
    else
      WebSocket.send_frame(socket, TextFrame("push " ++ int_to_string(i)))
      push_loop(socket, i + 1)
    end
  end

  -- Another task pushes 200 frames while this handler sits in recv: two
  -- threads on one connection at once.
  fn ws_push(socket) do
    let _t = Task.async(fn () -> push_loop(socket, 1))
    ws_echo_loop(socket)
  end

  -- A task that keeps sending after its handler returned (the connection
  -- is closed and its fd may be reused by then).
  fn late_loop(socket, i) do
    if i > 100 do ()
    else
      sleep_ms(20)
      WebSocket.send_frame(socket, TextFrame("late " ++ int_to_string(i)))
      late_loop(socket, i + 1)
    end
  end

  fn ws_late(socket) do
    let _t = Task.async(fn () -> late_loop(socket, 1))
    match WebSocket.recv(socket) do
    _ -> ()
    end
  end

  fn big_push(socket, tag, i) do
    if i > 200 do ()
    else
      WebSocket.send_frame(socket, TextFrame(tag ++ " " ++ int_to_string(i) ++ " " ++ string_repeat("p", 4000)))
      big_push(socket, tag, i + 1)
    end
  end

  -- Two tasks push 200 large frames each to a client that is not reading.
  fn ws_push2(socket) do
    let _a = Task.async(fn () -> big_push(socket, "A", 1))
    let _b = Task.async(fn () -> big_push(socket, "B", 1))
    ws_echo_loop(socket)
  end

  fn router(conn) do
    match (HttpServer.method(conn), HttpServer.path_info(conn)) do
    (:get, Cons("ws", Nil)) -> WebSocket.upgrade(conn, fn s -> ws_echo_loop(s))
    (:get, Cons("wspush", Nil)) -> WebSocket.upgrade(conn, fn s -> ws_push(s))
    (:get, Cons("wslate", Nil)) -> WebSocket.upgrade(conn, fn s -> ws_late(s))
    (:get, Cons("wspush2", Nil)) -> WebSocket.upgrade(conn, fn s -> ws_push2(s))
    (:get, Cons("echo", Nil)) -> conn |> HttpServer.text(200, "echo:" ++ HttpServer.query_string(conn))
    (:get, Cons("scheme", Nil)) -> conn |> HttpServer.text(200, HttpServer.scheme(conn))
    (:get, Cons("big", Cons(n, Nil))) ->
      match string_to_int(n) do
      Some(k) -> conn |> HttpServer.text(200, string_repeat("x", k))
      None -> conn |> HttpServer.text(400, "bad size")
      end
    (:post, Cons("upload", Nil)) ->
      let b = HttpServer.req_body(conn)
      let n = string_byte_length(b)
      conn |> HttpServer.text(200, int_to_string(n) ++ ":" ++ int_to_string(sum_bytes(b, 0, n, 0)))
    _ -> conn |> HttpServer.text(404, "Not Found")
    end
  end

  fn plain(conn) do
    match HttpServer.path_info(conn) do
    Cons("ws", Nil) -> WebSocket.upgrade(conn, fn s -> ws_echo_loop(s))
    Cons("scheme", Nil) -> conn |> HttpServer.text(200, "plain:" ++ HttpServer.scheme(conn))
    _ -> conn |> HttpServer.text(200, "plain-pipeline")
    end
  end

  fn main(_l : Cap(IO.NetListen), _p : Cap(IO.Process), _w : Cap(IO.WebSocket), _s : Cap(IO.Spawn)) do
    HttpServer.new(env_int("MARCH_TEST_HTTP_PORT"))
    |> HttpServer.tls(HttpServer.TlsFiles(env_str("MARCH_TEST_CERT"), env_str("MARCH_TEST_KEY")))
    |> HttpServer.tls_handshake_timeout(2)
    |> HttpServer.idle_timeout(2)
    |> HttpServer.plain_listener(env_int("MARCH_TEST_PLAIN_PORT"), [plain])
    |> HttpServer.plug(router)
    |> HttpServer.listen()
  end
end
|}

type https_env = { ctx : Test_http_native.server_ctx; pki : pki; plain_port : int }

let get_req path = Printf.sprintf "GET %s HTTP/1.1\r\nHost: localhost\r\nConnection: keep-alive\r\n\r\n" path

let one_shot (h : https_env) fd label path ~status ~body =
  h.ctx.send fd (h.ctx.request_bytes ~meth:"GET" ~path ~body:"" ~keep_alive:false);
  let pending = ref "" in
  h.ctx.check_response label ~exp_status:status ~exp_body:body
    (h.ctx.read_response fd pending ~deadline:(Unix.gettimeofday () +. 20.))

let h_basic (h : https_env) =
  let fd = tls_connect_or_bail h.ctx ~ca:h.pki.ca () in
  one_shot h fd "https_basic" "/echo?x=1" ~status:200 ~body:"echo:x=1";
  tls_close fd

let h_keepalive_65 (h : https_env) =
  let fd = tls_connect_or_bail h.ctx ~ca:h.pki.ca () in
  let pending = ref "" in
  for i = 1 to 65 do
    h.ctx.send fd (get_req (Printf.sprintf "/echo?i=%d" i));
    h.ctx.check_response (Printf.sprintf "https_keepalive %d/65" i) ~exp_status:200
      ~exp_body:(Printf.sprintf "echo:i=%d" i)
      (h.ctx.read_response fd pending ~deadline:(Unix.gettimeofday () +. 20.))
  done;
  tls_close fd

let h_pipelined (h : https_env) =
  let fd = tls_connect_or_bail h.ctx ~ca:h.pki.ca () in
  h.ctx.send fd (String.concat "" (List.init 16 (fun i -> get_req (Printf.sprintf "/echo?p=%d" i))));
  let pending = ref "" in
  for i = 0 to 15 do
    h.ctx.check_response (Printf.sprintf "https_pipelined %d/16" i) ~exp_status:200
      ~exp_body:(Printf.sprintf "echo:p=%d" i)
      (h.ctx.read_response fd pending ~deadline:(Unix.gettimeofday () +. 20.))
  done;
  tls_close fd

let h_post_large (h : https_env) =
  let n = 200_000 in
  let payload = String.init n (fun i -> Char.chr (33 + (i * 7 mod 90))) in
  let sum = ref 0 in
  String.iter (fun c -> sum := (!sum + Char.code c) mod 1000003) payload;
  let fd = tls_connect_or_bail h.ctx ~ca:h.pki.ca () in
  h.ctx.send fd (h.ctx.request_bytes ~meth:"POST" ~path:"/upload" ~body:payload ~keep_alive:false);
  let pending = ref "" in
  h.ctx.check_response "https_post_large" ~exp_status:200
    ~exp_body:(Printf.sprintf "%d:%d" n !sum)
    (h.ctx.read_response fd pending ~deadline:(Unix.gettimeofday () +. 30.));
  tls_close fd

let h_scheme (h : https_env) =
  let fd = tls_connect_or_bail h.ctx ~ca:h.pki.ca () in
  one_shot h fd "https_scheme over TLS" "/scheme" ~status:200 ~body:"https";
  tls_close fd;
  let pfd = connect_port h.ctx h.plain_port in
  one_shot h pfd "https_scheme on the plain port" "/scheme" ~status:200 ~body:"plain:http";
  close_quietly pfd

let h_no_sni (h : https_env) =
  let fd = tls_connect_or_bail h.ctx ~ca:h.pki.ca ~sni:None () in
  one_shot h fd "https_no_sni" "/echo?x=nosni" ~status:200 ~body:"echo:x=nosni";
  tls_close fd

let h_plaintext_to_tls_port (h : https_env) =
  let fd = h.ctx.connect_or_bail "plaintext to the TLS port" in
  ignore (try_send fd "GET / HTTP/1.1\r\nHost: localhost\r\n\r\n");
  (match wait_closed fd ~timeout:2.0 with
   | Some _ -> ()
   | None -> h.ctx.bail "https_plaintext_to_tls_port: plain HTTP on the TLS port was not closed within 2s");
  close_quietly fd;
  assert_alive h.ctx "https_plaintext_to_tls_port";
  h_basic h

let h_slow_reader_big (h : https_env) =
  let size = 1048576 in
  let fd = tls_connect_or_bail h.ctx ~ca:h.pki.ca () in
  h.ctx.send fd (String.concat "" (List.init 4 (fun _ -> get_req (Printf.sprintf "/big/%d" size))));
  (* Read 32 KB every 50 ms into one buffer, then frame the 4 responses. *)
  let got = Buffer.create (4 * size + 4096) in
  let chunk = Bytes.create 32768 in
  let t0 = Unix.gettimeofday () in
  let have_all () =
    let s = Buffer.contents got in
    let rec count from k =
      if k = 4 then true
      else match Test_http_native.find_from s "\r\n\r\n" from with
        | None -> false
        | Some h -> h + 4 + size <= String.length s && count (h + 4 + size) (k + 1) in
    count 0 0 in
  while not (have_all ()) do
    if Unix.gettimeofday () -. t0 > 90. then
      h.ctx.bail (Printf.sprintf "https_slow_reader_big: only %d bytes after 90s" (Buffer.length got));
    Unix.sleepf 0.05;
    match Unix.select [ fd ] [] [] 1.0 with
    | [], _, _ -> ()
    | _ ->
      (match Unix.read fd chunk 0 32768 with
       | 0 -> h.ctx.bail (Printf.sprintf "https_slow_reader_big: closed after %d bytes" (Buffer.length got))
       | n -> Buffer.add_subbytes got chunk 0 n)
  done;
  let pending = ref (Buffer.contents got) in
  for i = 1 to 4 do
    let (st, body, _) = h.ctx.read_response fd pending ~deadline:(Unix.gettimeofday () +. 5.) in
    if st <> 200 || String.length body <> size || String.exists (fun c -> c <> 'x') body then
      h.ctx.bail (Printf.sprintf "https_slow_reader_big: response %d/4 wrong (status %d, %d bytes)"
                    i st (String.length body))
  done;
  tls_close fd

let h_fd_reuse (h : https_env) =
  for i = 1 to 50 do
    let fd = tls_connect_or_bail h.ctx ~ca:h.pki.ca () in
    one_shot h fd (Printf.sprintf "fd_reuse TLS %d/50" i) "/echo?r=1" ~status:200 ~body:"echo:r=1";
    tls_close fd
  done;
  for i = 1 to 50 do
    let fd = connect_port h.ctx h.plain_port in
    one_shot h fd (Printf.sprintf "fd_reuse plain %d/50" i) "/scheme" ~status:200 ~body:"plain:http";
    close_quietly fd
  done

let h_handshake_timeout (h : https_env) =
  let fd = h.ctx.connect_or_bail "handshake timeout" in
  expect_closed_within h.ctx "handshake_timeout" fd ~lo:1.5 ~hi:4.5;
  close_quietly fd

let h_plain_own_pipeline (h : https_env) =
  let fd = connect_port h.ctx h.plain_port in
  one_shot h fd "plain_listener_own_pipeline" "/echo?x=1" ~status:200 ~body:"plain-pipeline";
  close_quietly fd

(* ── A minimal WebSocket client (RFC 6455) over any byte stream ─────────── *)

let ws_key = "dGhlIHNhbXBsZSBub25jZQ=="
let ws_accept = "s3pPLMBiTxaQ9kYGzzhZRbK+xOo="     (* RFC 6455 section 1.3 example *)

(* Read until [pending] holds at least [n] bytes. *)
let rec ws_fill (ctx : Test_http_native.server_ctx) fd pending n ~deadline =
  if String.length !pending < n then begin
    let left = deadline -. Unix.gettimeofday () in
    if left <= 0. then ctx.bail (Printf.sprintf "websocket: timed out waiting for %d bytes" n);
    (match Unix.select [ fd ] [] [] left with
     | [], _, _ -> ()
     | _ ->
       let b = Bytes.create 65536 in
       (match Unix.read fd b 0 65536 with
        | 0 -> ctx.bail "websocket: connection closed"
        | k -> pending := !pending ^ Bytes.sub_string b 0 k
        | exception Unix.Unix_error (e, _, _) -> ctx.bail ("websocket read: " ^ Unix.error_message e)));
    ws_fill ctx fd pending n ~deadline
  end

let ws_upgrade (ctx : Test_http_native.server_ctx) fd path =
  ctx.send fd (Printf.sprintf
    "GET %s HTTP/1.1\r\nHost: localhost\r\nUpgrade: websocket\r\nConnection: Upgrade\r\n\
     Sec-WebSocket-Key: %s\r\nSec-WebSocket-Version: 13\r\n\r\n" path ws_key);
  let pending = ref "" in
  let deadline = Unix.gettimeofday () +. 20. in
  let rec head () =
    match Test_http_native.find_from !pending "\r\n\r\n" 0 with
    | Some i -> i
    | None -> ws_fill ctx fd pending (String.length !pending + 1) ~deadline; head () in
  let h = head () in
  let hdr = String.sub !pending 0 h in
  if not (contains hdr "101") || not (contains hdr ws_accept) then
    ctx.bail (Printf.sprintf "websocket upgrade of %s: bad response %S" path hdr);
  pending := String.sub !pending (h + 4) (String.length !pending - h - 4);
  pending

let ws_send_text (ctx : Test_http_native.server_ctx) fd msg =
  let n = String.length msg in
  let b = Buffer.create (n + 14) in
  Buffer.add_char b '\x81';
  if n < 126 then Buffer.add_char b (Char.chr (0x80 lor n))
  else if n < 65536 then begin
    Buffer.add_char b (Char.chr (0x80 lor 126));
    Buffer.add_char b (Char.chr (n lsr 8)); Buffer.add_char b (Char.chr (n land 0xff))
  end else begin
    Buffer.add_char b (Char.chr (0x80 lor 127));
    for i = 7 downto 0 do Buffer.add_char b (Char.chr ((n lsr (8 * i)) land 0xff)) done
  end;
  let mask = "\x12\x34\x56\x78" in
  Buffer.add_string b mask;
  String.iteri (fun i c -> Buffer.add_char b (Char.chr (Char.code c lxor Char.code mask.[i land 3]))) msg;
  ctx.send fd (Buffer.contents b)

(* One unmasked server frame: (opcode, payload). *)
let ws_read_frame (ctx : Test_http_native.server_ctx) fd pending ~deadline =
  ws_fill ctx fd pending 2 ~deadline;
  let b0 = Char.code !pending.[0] and b1 = Char.code !pending.[1] in
  let len7 = b1 land 0x7f in
  let hl, len =
    if len7 < 126 then 2, len7
    else if len7 = 126 then begin
      ws_fill ctx fd pending 4 ~deadline;
      4, (Char.code !pending.[2] lsl 8) lor Char.code !pending.[3]
    end else begin
      ws_fill ctx fd pending 10 ~deadline;
      let v = ref 0 in
      for i = 2 to 9 do v := (!v lsl 8) lor Char.code !pending.[i] done;
      10, !v
    end in
  ws_fill ctx fd pending (hl + len) ~deadline;
  let payload = String.sub !pending hl len in
  pending := String.sub !pending (hl + len) (String.length !pending - hl - len);
  (b0 land 0x0f, payload)

let ws_expect_text ctx fd pending label want =
  match ws_read_frame ctx fd pending ~deadline:(Unix.gettimeofday () +. 20.) with
  | (1, got) when got = want -> ()
  | (op, got) ->
    ctx.Test_http_native.bail (Printf.sprintf "%s: want text %S, got opcode %d (%d bytes) %S" label
                                 (if String.length want > 60 then String.sub want 0 60 ^ "..." else want)
                                 op (String.length got)
                                 (if String.length got > 60 then String.sub got 0 60 ^ "..." else got))

let w_echo (h : https_env) =
  let fd = tls_connect_or_bail h.ctx ~ca:h.pki.ca () in
  let pending = ws_upgrade h.ctx fd "/ws" in
  for i = 1 to 20 do
    let m = Printf.sprintf "msg %d" i in
    ws_send_text h.ctx fd m;
    ws_expect_text h.ctx fd pending (Printf.sprintf "wss_echo %d/20" i) m
  done;
  tls_close fd

let w_large_frame (h : https_env) =
  let fd = tls_connect_or_bail h.ctx ~ca:h.pki.ca () in
  let pending = ws_upgrade h.ctx fd "/ws" in
  let m = String.init 100_000 (fun i -> Char.chr (97 + (i mod 26))) in
  ws_send_text h.ctx fd m;
  ws_expect_text h.ctx fd pending "wss_large_frame" m;
  tls_close fd

let w_idle (h : https_env) =
  let fd = tls_connect_or_bail h.ctx ~ca:h.pki.ca () in
  let pending = ws_upgrade h.ctx fd "/ws" in
  Unix.sleepf 6.0;                         (* idle_timeout is 2 s *)
  ws_send_text h.ctx fd "still here";
  ws_expect_text h.ctx fd pending "wss_idle_outlives_idle_timeout" "still here";
  tls_close fd

let w_concurrent_push (h : https_env) =
  let fd = tls_connect_or_bail h.ctx ~ca:h.pki.ca () in
  let pending = ws_upgrade h.ctx fd "/wspush" in
  let deadline = Unix.gettimeofday () +. 5. in
  for i = 1 to 200 do
    match ws_read_frame h.ctx fd pending ~deadline with
    | (1, got) when got = Printf.sprintf "push %d" i -> ()
    | (op, got) -> h.ctx.bail (Printf.sprintf "wss_concurrent_push: frame %d: opcode %d %S" i op got)
  done;
  tls_close fd

let w_plain_unchanged (h : https_env) =
  let fd = connect_port h.ctx h.plain_port in
  let pending = ws_upgrade h.ctx fd "/ws" in
  for i = 1 to 5 do
    let m = Printf.sprintf "plain %d" i in
    ws_send_text h.ctx fd m;
    ws_expect_text h.ctx fd pending (Printf.sprintf "ws_plain_unchanged %d/5" i) m
  done;
  close_quietly fd

(* C1: a task sends after its handler returned while new TLS connections
   take the freed fd numbers; every new connection must be served intact. *)
let w_send_after_close (h : https_env) =
  let fd = tls_connect_or_bail h.ctx ~ca:h.pki.ca () in
  let _pending = ws_upgrade h.ctx fd "/wslate" in
  ws_send_text h.ctx fd "go";               (* the handler returns on it *)
  Unix.sleepf 0.1;
  tls_close fd;
  for i = 1 to 40 do
    let c = tls_connect_or_bail h.ctx ~ca:h.pki.ca () in
    one_shot h c (Printf.sprintf "send_after_close churn %d/40" i) "/echo?c=1" ~status:200 ~body:"echo:c=1";
    tls_close c
  done;
  Unix.sleepf 2.5                           (* the late sender runs out *)

(* I1: two pushers, a client that reads nothing for 2 s. All 400 frames
   arrive, each pusher's in order. With one scheduler thread a sender that
   parks holding a lock deadlocks the other. *)
let w_two_pushers (h : https_env) =
  let fd = tls_connect_or_bail h.ctx ~ca:h.pki.ca () in
  let pending = ws_upgrade h.ctx fd "/wspush2" in
  Unix.sleepf 2.0;
  let next = Hashtbl.create 2 in
  Hashtbl.replace next "A" 1; Hashtbl.replace next "B" 1;
  let deadline = Unix.gettimeofday () +. 30. in
  for _ = 1 to 400 do
    match ws_read_frame h.ctx fd pending ~deadline with
    | (1, got) ->
      (match String.split_on_char ' ' got with
       | tag :: n :: _ when Hashtbl.mem next tag ->
         let want = Hashtbl.find next tag in
         if int_of_string_opt n <> Some want then
           h.ctx.bail (Printf.sprintf "two_pushers: %s frame %s, want %d" tag n want);
         Hashtbl.replace next tag (want + 1)
       | _ -> h.ctx.bail (Printf.sprintf "two_pushers: unexpected frame %S"
                            (String.sub got 0 (min 40 (String.length got)))))
    | (op, _) -> h.ctx.bail (Printf.sprintf "two_pushers: opcode %d" op)
  done;
  tls_close fd

(* I2: a client stalled behind a 16 MiB response (more than every buffer between that ends in an upgrade
   must not stall others on its loop thread (the event loop runs one thread
   here); once it reads, its WebSocket works. *)
let w_upgrade_behind_slow_reader (h : https_env) =
  let x = tls_connect_or_bail h.ctx ~ca:h.pki.ca () in
  h.ctx.send x (get_req "/big/16777216"
                ^ Printf.sprintf "GET /ws HTTP/1.1\r\nHost: localhost\r\nUpgrade: websocket\r\n\
                                  Connection: Upgrade\r\nSec-WebSocket-Key: %s\r\n\
                                  Sec-WebSocket-Version: 13\r\n\r\n" ws_key);
  Unix.sleepf 0.5;
  let t0 = Unix.gettimeofday () in
  let y = tls_connect_or_bail h.ctx ~ca:h.pki.ca () in
  one_shot h y "upgrade_behind_slow_reader: another client" "/echo?y=1" ~status:200 ~body:"echo:y=1";
  tls_close y;
  let took = Unix.gettimeofday () -. t0 in
  if took > 5. then
    h.ctx.bail (Printf.sprintf "upgrade_behind_slow_reader: another client waited %.1fs" took);
  let pending = ref "" in
  let (st, body, _) = h.ctx.read_response x pending ~deadline:(Unix.gettimeofday () +. 20.) in
  if st <> 200 || String.length body <> 16777216 then
    h.ctx.bail (Printf.sprintf "upgrade_behind_slow_reader: /big gave %d, %d bytes" st (String.length body));
  let deadline = Unix.gettimeofday () +. 20. in
  let rec head () =
    match Test_http_native.find_from !pending "\r\n\r\n" 0 with
    | Some i -> i
    | None -> ws_fill h.ctx x pending (String.length !pending + 1) ~deadline; head () in
  let i = head () in
  if not (contains (String.sub !pending 0 i) ws_accept) then
    h.ctx.bail "upgrade_behind_slow_reader: no 101 after the response";
  pending := String.sub !pending (i + 4) (String.length !pending - i - 4);
  ws_send_text h.ctx x "after";
  ws_expect_text h.ctx x pending "upgrade_behind_slow_reader echo" "after";
  tls_close x

let ws_lifetime_cases =
  [ ("wss_send_after_close", w_send_after_close);
    ("wss_two_pushers", w_two_pushers);
    ("wss_upgrade_behind_slow_reader", w_upgrade_behind_slow_reader) ]

let https_cases =
  [ ("https_basic", h_basic);
    ("https_keepalive_65", h_keepalive_65);
    ("https_pipelined", h_pipelined);
    ("https_post_large", h_post_large);
    ("https_scheme", h_scheme);
    ("https_no_sni", h_no_sni);
    ("https_plaintext_to_tls_port", h_plaintext_to_tls_port);
    ("https_slow_reader_big", h_slow_reader_big);
    ("fd_reuse_plain_after_tls", h_fd_reuse);
    ("handshake_timeout", h_handshake_timeout);
    ("plain_listener_own_pipeline", h_plain_own_pipeline);
    ("wss_echo", w_echo);
    ("wss_large_frame", w_large_frame);
    ("wss_idle_outlives_idle_timeout", w_idle);
    ("wss_concurrent_push", w_concurrent_push);
    ("ws_plain_unchanged", w_plain_unchanged) ]

let run_https_cases ~cases ~tag ~mode ~evloop ~extra_env () =
  let dir = fresh_dir ("pki" ^ mode) in
  let pki = make_pki ~dir ~name:"a" () in
  let plain_port = Test_http_native.pick_free_port () in
  let extra_env = Array.append extra_env
      [| "MARCH_TEST_CERT=" ^ pki.cert; "MARCH_TEST_KEY=" ^ pki.key;
         Printf.sprintf "MARCH_TEST_PLAIN_PORT=%d" plain_port |] in
  Fun.protect ~finally:reap_s_clients (fun () ->
    Test_http_native.with_compiled_server ~extra_env ~variant:(tag ^ ", " ^ mode)
      ~slug:(tag ^ mode) ~evloop ~server_src:https_server_src (fun ctx ->
        let h = { ctx; pki; plain_port } in
        List.iter (fun (name, f) -> f h; assert_alive ctx name) cases))

let run_https = run_https_cases ~cases:https_cases ~tag:"https"

(* Two scheduler threads (main's green thread holds one: pthread_join on the
   event loop, select in the pool, so tasks get exactly one) and one loop
   thread: what a lock held across a park, or a loop thread waiting on one
   client, turns into a hang. *)
let run_ws_lifetime ~mode ~evloop ~extra_env () =
  run_https_cases ~cases:ws_lifetime_cases ~tag:"wsl" ~mode ~evloop
    ~extra_env:(Array.append extra_env [| "MARCH_NUM_SCHEDULERS=2"; "MARCH_HTTP_EVLOOP_THREADS=1" |]) ()

(* ── Rotation, reload_tls, bootstrap, expired startup ─────────────────── *)

let cert_serial path =
  let ic = Unix.open_process_in (Printf.sprintf "openssl x509 -in %s -noout -serial 2>/dev/null"
                                   (Filename.quote path)) in
  let l = try input_line ic with End_of_file -> "" in
  ignore (Unix.close_process_in ic);
  String.trim l

(** The serial of the leaf a NEW connection to [port] is served (no
    verification, so an expired leaf still reports). *)
let served_leaf_serial ~port ~ca =
  let ic = Unix.open_process_in (Printf.sprintf
      "openssl s_client -connect 127.0.0.1:%d -servername localhost -CAfile %s </dev/null 2>/dev/null \
       | openssl x509 -noout -serial 2>/dev/null" port (Filename.quote ca)) in
  let l = try input_line ic with End_of_file -> "" in
  ignore (Unix.close_process_in ic);
  String.trim l

(* Replace a file in one step, as certbot's symlink swap does. *)
let atomic_copy ~src ~dst =
  let tmp = dst ^ ".tmp" in
  write_text tmp (read_file_contents src);
  Unix.rename tmp dst

let count_sub hay needle =
  let n = String.length needle in
  let rec go i acc =
    match Test_http_native.find_from hay needle i with
    | None -> acc
    | Some j -> go (j + n) (acc + 1) in
  if n = 0 then 0 else go 0 0

let rotate_server_src = {|mod HttpsRotate do
  needs IO.Process
  needs IO.NetListen
  needs IO.NetConnect.TLS
  needs IO.FileRead
  needs IO.Spawn

  fn env_str(name) do
    match process_env(name) do
    Some(s) -> s
    None -> ""
    end
  end

  fn env_int(name) do
    match string_to_int(env_str(name)) do
    Some(n) -> n
    None -> 0
    end
  end

  fn read_or_empty(path) do
    match Authority.must(File.read(path)) do
    Ok(s) -> s
    Err(_) -> ""
    end
  end

  fn reload_from(cert_env, key_env) do
    let src = HttpServer.TlsPem(read_or_empty(env_str(cert_env)), read_or_empty(env_str(key_env)))
    match HttpServer.reload_tls(src) do
    Ok(_) -> "ok"
    Err(e) -> "err:" ++ e
    end
  end

  fn race(i) do
    if i >= 100 do ()
    else
      let _r = if i % 2 == 0 do reload_from("MARCH_TEST_A_CERT", "MARCH_TEST_A_KEY")
               else reload_from("MARCH_TEST_B_CERT", "MARCH_TEST_B_KEY") end
      sleep_ms(10)
      race(i + 1)
    end
  end

  fn router(conn) do
    match HttpServer.path_info(conn) do
    Cons("echo", Nil) -> conn |> HttpServer.text(200, "echo")
    Cons("reload", Cons(which, Nil)) ->
      let r = if which == "a" do reload_from("MARCH_TEST_A_CERT", "MARCH_TEST_A_KEY")
              else if which == "b" do reload_from("MARCH_TEST_B_CERT", "MARCH_TEST_B_KEY")
              else reload_from("MARCH_TEST_A_CERT", "MARCH_TEST_B_KEY") end end
      conn |> HttpServer.text(200, r)
    Cons("race", Nil) ->
      let _t = Task.async(fn () -> race(0))
      conn |> HttpServer.text(200, "started")
    _ -> conn |> HttpServer.text(404, "Not Found")
    end
  end

  fn configure(server) do
    if env_str("MARCH_TEST_WAIT") == "1" do HttpServer.tls_wait_for_cert(server) else server end
  end

  fn main(_l : Cap(IO.NetListen), _p : Cap(IO.Process), _t : Cap(IO.NetConnect.TLS),
          _f : Cap(IO.FileRead), _s : Cap(IO.Spawn)) do
    HttpServer.new(env_int("MARCH_TEST_HTTP_PORT"))
    |> HttpServer.tls(HttpServer.TlsFiles(env_str("MARCH_TEST_CERT"), env_str("MARCH_TEST_KEY")))
    |> HttpServer.tls_poll_interval(1)
    |> configure()
    |> HttpServer.plain_listener(env_int("MARCH_TEST_PLAIN_PORT"), [fn c -> HttpServer.text(c, 200, "plain")])
    |> HttpServer.plug(router)
    |> HttpServer.listen()
  end
end
|}

type rot = { rctx : Test_http_native.server_ctx; bundle : string; live_cert : string; live_key : string;
             a : pki; b : pki; c : pki; rplain : int }

let wait_serial (r : rot) label want ~within =
  let t0 = Unix.gettimeofday () in
  let rec go () =
    let got = served_leaf_serial ~port:r.rctx.port ~ca:r.bundle in
    if got = want then ()
    else if Unix.gettimeofday () -. t0 > within then
      r.rctx.bail (Printf.sprintf "%s: served %S, want %S after %.0fs" label got want within)
    else (Unix.sleepf 0.25; go ()) in
  go ()

let rot_get (r : rot) label path ~body =
  let fd = tls_connect_or_bail r.rctx ~ca:r.bundle () in
  r.rctx.send fd (r.rctx.request_bytes ~meth:"GET" ~path ~body:"" ~keep_alive:false);
  let pending = ref "" in
  let (st, b, _) = r.rctx.read_response fd pending ~deadline:(Unix.gettimeofday () +. 20.) in
  tls_close fd;
  if st <> 200 || not (body b) then r.rctx.bail (Printf.sprintf "%s: got %d %S" label st b);
  b

let r_poll_rotation (r : rot) =
  wait_serial r "poll_rotation (start)" (cert_serial r.a.cert) ~within:2.;
  let k = tls_connect_or_bail r.rctx ~ca:r.bundle () in
  let pending = ref "" in
  let ka () =
    r.rctx.send k (get_req "/echo");
    r.rctx.check_response "poll_rotation keep-alive" ~exp_status:200 ~exp_body:"echo"
      (r.rctx.read_response k pending ~deadline:(Unix.gettimeofday () +. 20.)) in
  ka ();
  atomic_copy ~src:r.b.key ~dst:r.live_key;
  atomic_copy ~src:r.b.cert ~dst:r.live_cert;
  wait_serial r "poll_rotation" (cert_serial r.b.cert) ~within:4.;
  ka ();                                    (* the old connection keeps working *)
  tls_close k;
  if not (contains (r.rctx.read_log ()) "installed certificate") then
    r.rctx.bail "poll_rotation: no `installed certificate` line on stderr"

let r_poll_refusal (r : rot) =
  let refused0 = count_sub (r.rctx.read_log ()) "refused certificate" in
  atomic_copy ~src:r.c.cert ~dst:r.live_cert;   (* C's cert with B's key *)
  Unix.sleepf 3.0;
  let got = served_leaf_serial ~port:r.rctx.port ~ca:r.bundle in
  if got <> cert_serial r.b.cert then
    r.rctx.bail (Printf.sprintf "poll_refusal: a mismatched pair replaced the certificate (served %S)" got);
  let refused = count_sub (r.rctx.read_log ()) "refused certificate" - refused0 in
  if refused <> 1 then
    r.rctx.bail (Printf.sprintf "poll_refusal: `refused certificate` logged %d times over 3 polls, want once" refused);
  atomic_copy ~src:r.c.key ~dst:r.live_key;
  wait_serial r "poll_refusal (fixed pair)" (cert_serial r.c.cert) ~within:4.

let r_reload_pem (r : rot) =
  ignore (rot_get r "reload_tls mismatched" "/reload/bad"
            ~body:(fun b -> contains b "err:" && contains b "do not match"));
  let got = served_leaf_serial ~port:r.rctx.port ~ca:r.bundle in
  if got <> cert_serial r.c.cert then
    r.rctx.bail (Printf.sprintf "reload_tls_pem: a refused reload changed the certificate (%S)" got);
  ignore (rot_get r "reload_tls b" "/reload/b" ~body:(fun b -> b = "ok"));
  wait_serial r "reload_tls_pem" (cert_serial r.b.cert) ~within:1.

let r_race (r : rot) =
  ignore (rot_get r "reload_race start" "/race" ~body:(fun b -> b = "started"));
  for i = 1 to 200 do
    ignore (rot_get r (Printf.sprintf "reload_race connection %d/200" i) "/echo" ~body:(fun b -> b = "echo"))
  done

let rotate_env ~dir ~live_cert ~live_key ~a ~b ~plain ~wait =
  [| "MARCH_TEST_CERT=" ^ live_cert; "MARCH_TEST_KEY=" ^ live_key;
     "MARCH_TEST_A_CERT=" ^ a.cert; "MARCH_TEST_A_KEY=" ^ a.key;
     "MARCH_TEST_B_CERT=" ^ b.cert; "MARCH_TEST_B_KEY=" ^ b.key;
     Printf.sprintf "MARCH_TEST_PLAIN_PORT=%d" plain;
     "MARCH_TEST_WAIT=" ^ (if wait then "1" else "0"); "MARCH_TEST_DIR=" ^ dir |]

let run_rotation ~mode ~evloop () =
  let dir = fresh_dir ("rot" ^ mode) in
  let a = make_pki ~dir ~name:"a" () and b = make_pki ~dir ~name:"b" ()
  and c = make_pki ~dir ~name:"c" () in
  let bundle = Filename.concat dir "bundle.pem" in
  write_text bundle (String.concat "" (List.map (fun p -> read_file_contents p.ca) [ a; b; c ]));
  let live_cert = Filename.concat dir "live-cert.pem" and live_key = Filename.concat dir "live-key.pem" in
  atomic_copy ~src:a.cert ~dst:live_cert;
  atomic_copy ~src:a.key ~dst:live_key;
  let plain = Test_http_native.pick_free_port () in
  let extra_env = Array.append (if evloop then [||] else [||])
      (rotate_env ~dir ~live_cert ~live_key ~a ~b ~plain ~wait:false) in
  Fun.protect ~finally:reap_s_clients (fun () ->
    Test_http_native.with_compiled_server ~extra_env ~variant:("rotation, " ^ mode)
      ~slug:("rot" ^ mode) ~evloop ~server_src:rotate_server_src (fun ctx ->
        let r = { rctx = ctx; bundle; live_cert; live_key; a; b; c; rplain = plain } in
        List.iter (fun (name, f) -> f r; assert_alive ctx name)
          [ ("poll_rotation", r_poll_rotation); ("poll_refusal_keeps_old", r_poll_refusal);
            ("reload_tls_pem", r_reload_pem); ("reload_race", r_race) ]))

let run_bootstrap ~mode ~evloop () =
  let dir = fresh_dir ("boot" ^ mode) in
  let a = make_pki ~dir ~name:"a" () in
  let live_cert = Filename.concat dir "live-cert.pem" and live_key = Filename.concat dir "live-key.pem" in
  let plain = Test_http_native.pick_free_port () in
  let extra_env = rotate_env ~dir ~live_cert ~live_key ~a ~b:a ~plain ~wait:true in
  Fun.protect ~finally:reap_s_clients (fun () ->
    Test_http_native.with_compiled_server ~extra_env ~ready_port:plain ~variant:("bootstrap, " ^ mode)
      ~slug:("boot" ^ mode) ~evloop ~server_src:rotate_server_src (fun ctx ->
        let pfd = connect_port ctx plain in
        ctx.send pfd (ctx.request_bytes ~meth:"GET" ~path:"/" ~body:"" ~keep_alive:false);
        let pending = ref "" in
        ctx.check_response "bootstrap plain listener" ~exp_status:200 ~exp_body:"plain"
          (ctx.read_response pfd pending ~deadline:(Unix.gettimeofday () +. 20.));
        close_quietly pfd;
        if not (port_refuses ctx.port) then
          ctx.bail "bootstrap_mode: the HTTPS port accepts connections before any certificate exists";
        atomic_copy ~src:a.key ~dst:live_key;
        atomic_copy ~src:a.cert ~dst:live_cert;
        let t0 = Unix.gettimeofday () in
        while port_refuses ctx.port do
          if Unix.gettimeofday () -. t0 > 4. then
            ctx.bail "bootstrap_mode: HTTPS port still closed 4s after the certificate appeared";
          Unix.sleepf 0.2
        done;
        let r = { rctx = ctx; bundle = a.ca; live_cert; live_key; a; b = a; c = a; rplain = plain } in
        ignore (rot_get r "bootstrap_mode first HTTPS request" "/echo" ~body:(fun b -> b = "echo"));
        assert_alive ctx "bootstrap_mode"))

let run_expired_startup ~mode ~evloop () =
  let dir = fresh_dir ("exp" ^ mode) in
  let old = make_pki ~dir ~name:"old" ~days:(-1) () in
  let plain = Test_http_native.pick_free_port () in
  let extra_env = rotate_env ~dir ~live_cert:old.cert ~live_key:old.key ~a:old ~b:old ~plain ~wait:false in
  Test_http_native.with_compiled_server ~extra_env ~variant:("expired startup, " ^ mode)
    ~slug:("exp" ^ mode) ~evloop ~server_src:rotate_server_src (fun ctx ->
      let t0 = Unix.gettimeofday () in
      while not (contains (ctx.read_log ()) "expired") && Unix.gettimeofday () -. t0 < 5. do
        Unix.sleepf 0.1 done;
      if not (contains (ctx.read_log ()) "expired") then
        ctx.bail "expired_at_startup: no warning naming the expired certificate";
      let got = served_leaf_serial ~port:ctx.port ~ca:old.ca in
      if got <> cert_serial old.cert then
        ctx.bail (Printf.sprintf "expired_at_startup: handshake did not serve the expired leaf (%S)" got);
      assert_alive ctx "expired_at_startup_serves")

let rotation_modes = [ ("evloop", true); ("pool", false) ]

let suites =
  [ ( "https server (compiled, end-to-end)",
      [ Alcotest.test_case "config_errors" `Quick test_config_errors;
        Alcotest.test_case "listen_bad_cert_exits" `Quick test_listen_bad_cert_exits;
        Alcotest.test_case "importer_needs_unchanged" `Quick test_importer_needs_unchanged;
      ]
      @ List.map (fun (mode, evloop, extra_env) ->
          Alcotest.test_case ("deadlines: " ^ mode) `Quick
            (run_deadlines ~mode ~evloop ~extra_env)) modes
      @ List.map (fun (mode, evloop, extra_env) ->
          Alcotest.test_case ("https: " ^ mode) `Quick
            (run_https ~mode ~evloop ~extra_env)) modes
      (* Not sequential mode: it serves one connection at a time by design,
         so a client behind a stalled one waits there. *)
      @ List.map (fun (mode, evloop) ->
          Alcotest.test_case ("wss lifetime: " ^ mode) `Quick
            (run_ws_lifetime ~mode ~evloop ~extra_env:[||])) rotation_modes
      @ List.concat_map (fun (mode, evloop) ->
          [ Alcotest.test_case ("rotation: " ^ mode) `Quick (run_rotation ~mode ~evloop);
            Alcotest.test_case ("bootstrap: " ^ mode) `Quick (run_bootstrap ~mode ~evloop);
            Alcotest.test_case ("expired startup: " ^ mode) `Quick (run_expired_startup ~mode ~evloop) ])
        rotation_modes ) ]
