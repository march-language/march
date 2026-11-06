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

let suites =
  [ ( "https server (compiled, end-to-end)",
      [ Alcotest.test_case "config_errors" `Quick test_config_errors;
        Alcotest.test_case "listen_bad_cert_exits" `Quick test_listen_bad_cert_exits ] ) ]
