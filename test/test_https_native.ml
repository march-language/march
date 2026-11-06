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
  let validity =
    if days >= 0 then Printf.sprintf "-days %d" days
    else begin
      let t = Unix.gmtime (Unix.time () -. 86400.) in
      Printf.sprintf "-not_after %04d%02d%02d%02d%02d%02dZ" (t.tm_year + 1900) (t.tm_mon + 1)
        t.tm_mday t.tm_hour t.tm_min t.tm_sec
    end in
  sh (Printf.sprintf "openssl x509 -req -in %s -CA %s -CAkey %s -set_serial %d %s -extfile %s -out %s 2>/dev/null"
        (q csr) (q ca) (q ca_key) (1000 + Random.int 1_000_000) validity (q ext) (q cert));
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

  fn router(conn) do
    match (HttpServer.method(conn), HttpServer.path_info(conn)) do
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
    Cons("scheme", Nil) -> conn |> HttpServer.text(200, "plain:" ++ HttpServer.scheme(conn))
    _ -> conn |> HttpServer.text(200, "plain-pipeline")
    end
  end

  fn main(_l : Cap(IO.NetListen), _p : Cap(IO.Process)) do
    HttpServer.new(env_int("MARCH_TEST_HTTP_PORT"))
    |> HttpServer.tls(HttpServer.TlsFiles(env_str("MARCH_TEST_CERT"), env_str("MARCH_TEST_KEY")))
    |> HttpServer.tls_handshake_timeout(2)
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
    ("plain_listener_own_pipeline", h_plain_own_pipeline) ]

let run_https ~mode ~evloop ~extra_env () =
  let dir = fresh_dir ("pki" ^ mode) in
  let pki = make_pki ~dir ~name:"a" () in
  let plain_port = Test_http_native.pick_free_port () in
  let extra_env = Array.append extra_env
      [| "MARCH_TEST_CERT=" ^ pki.cert; "MARCH_TEST_KEY=" ^ pki.key;
         Printf.sprintf "MARCH_TEST_PLAIN_PORT=%d" plain_port |] in
  Fun.protect ~finally:reap_s_clients (fun () ->
    Test_http_native.with_compiled_server ~extra_env ~variant:("https, " ^ mode)
      ~slug:("https" ^ mode) ~evloop ~server_src:https_server_src (fun ctx ->
        let h = { ctx; pki; plain_port } in
        List.iter (fun (name, f) -> f h; assert_alive ctx name) https_cases))

let suites =
  [ ( "https server (compiled, end-to-end)",
      [ Alcotest.test_case "config_errors" `Quick test_config_errors;
        Alcotest.test_case "listen_bad_cert_exits" `Quick test_listen_bad_cert_exits;
      ]
      @ List.map (fun (mode, evloop, extra_env) ->
          Alcotest.test_case ("deadlines: " ^ mode) `Quick
            (run_deadlines ~mode ~evloop ~extra_env)) modes
      @ [ Alcotest.test_case "https: evloop" `Quick (run_https ~mode:"evloop" ~evloop:true ~extra_env:[||]) ] ) ]
