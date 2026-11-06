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
    let conn = HttpServer.Conn(0, :get, "/", Nil, "", Nil, "", 0, Nil, "", false, Nil, HttpServer.NoUpgrade)
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

(** One compiled server per mode; every case runs against it in turn and
    checks it is still alive. *)
let run_deadlines ~mode ~evloop () =
  Test_http_native.with_compiled_server ~variant:("deadlines, " ^ mode)
    ~slug:("deadlines" ^ mode) ~evloop ~server_src:deadline_server_src (fun ctx ->
      List.iter (fun (name, f) -> f ctx; assert_alive ctx name) deadline_cases)

let suites =
  [ ( "https server (compiled, end-to-end)",
      [ Alcotest.test_case "config_errors" `Quick test_config_errors;
        Alcotest.test_case "listen_bad_cert_exits" `Quick test_listen_bad_cert_exits;
        Alcotest.test_case "deadlines: event loop" `Quick (run_deadlines ~mode:"evloop" ~evloop:true) ] ) ]
