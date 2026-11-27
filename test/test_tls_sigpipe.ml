(** A TLS write or read on a connection the peer has reset fails with an
    error; it does not kill the process with SIGPIPE.

    OpenSSL's socket BIO writes with write(), so on Linux (no per-socket
    SO_NOSIGPIPE) a [Tls.write] to a peer that had gone raised SIGPIPE, whose
    default action ends the process with status 141. [Tls.read] can write
    too (session tickets, alerts, key updates). macOS never had the problem:
    the fd gets SO_NOSIGPIPE at the handshake. So this test can only fail on
    Linux; it runs everywhere.

    One compiled program plays both roles, as in test_tls_groups.ml. The
    server completes one handshake and exits at once, without a close_notify.
    The client then writes until a write fails: the first write after the
    peer is gone draws a reset, and the next one is the EPIPE write that
    used to signal.

    Skip policy: only a missing toolchain (compile_march_or_skip) or a missing
    [openssl] CLI to mint the throwaway certificate. *)

open Test_helpers

let probe_src =
  {|
mod TlsSigpipeProbe do
  needs IO.NetConnect
  needs IO.NetListen
  needs IO.NetConnect.TLS
  needs IO.Console
  needs IO.Process

  fn env_or(name, dflt) do
    match Authority.must(Process.env(name)) do
    Some(s) -> s
    None -> dflt
    end
  end

  fn env_int(name) do
    match string_to_int(env_or(name, "0")) do
    Some(n) -> n
    None -> 0
    end
  end

  -- Accept until one handshake completes (the harness's readiness probe
  -- fails its handshake), then leave without closing anything.
  fn serve(l, ctx) do
    match Socket.accept(l) do
    Err(e) -> Authority.ignore(println("S FAIL accept " ++ Socket.error_message(e)))
    Ok(s) ->
      match Tls.accept(s, ctx) do
      Ok(_conn) ->
        println("S handshake done, leaving")
        Authority.ignore(Process.exit(0))
      Err(_) ->
        let _ = Socket.close(s)
        serve(l, ctx)
      end
    end
  end

  fn write_until_error(conn, i) do
    if i > 100 do Authority.ignore(println("C FAIL 100 writes to a dead peer all succeeded"))
    else
      match Tls.write(conn, "ping") do
      Ok(_) ->
        sleep_ms(20)
        write_until_error(conn, i + 1)
      Err(_) -> Authority.ignore(println("C write error"))
      end
    end
  end

  fn client(port) do
    match Authority.must(Tls.client_ctx(Tls.TlsConfig("", "", "", [], Tls.Tls12, false))) do
    Err(_) -> Authority.ignore(println("C FAIL ctx"))
    Ok(ctx) ->
      match Authority.must(Socket.connect("127.0.0.1", port)) do
      Err(e) -> Authority.ignore(println("C FAIL connect " ++ Socket.error_message(e)))
      Ok(s) ->
        match Socket.set_recv_timeout(s, 5000) do
        _ -> ()
        end
        match Tls.connect(s, ctx, "127.0.0.1") do
        Err(e) -> Authority.ignore(println("C FAIL handshake " ++ Tls.error_to_string(e)))
        Ok(conn) ->
          sleep_ms(500)
          write_until_error(conn, 1)
          -- A read can write too (alerts, key updates); it only has to
          -- return, with end of stream or an error.
          match Tls.read(conn, 16) do
          _ -> println("C read returned")
          end
          Tls.close(conn)
          Authority.ignore(println("C done"))
        end
      end
    end
  end

  fn main() needs IO.NetConnect, IO.NetListen, IO.Process, IO.Console do
    let port = env_int("MARCH_TLS_PORT")
    if env_or("MARCH_TLS_ROLE", "client") == "server" do
      match Authority.must(Tls.server_ctx(Tls.server_config(env_or("MARCH_TLS_CERT", ""), env_or("MARCH_TLS_KEY", "")))) do
      Err(e) -> Authority.ignore(println("S FAIL ctx " ++ Tls.error_to_string(e)))
      Ok(ctx) ->
        match Authority.must(Socket.listen(port)) do
        Err(e) -> Authority.ignore(println("S FAIL listen " ++ Socket.error_message(e)))
        Ok(l) -> serve(l, ctx)
        end
      end
    else client(port)
    end
  end

end
|}

let test_write_to_reset_peer () =
  (* Named one by one: opening Test_tls_groups would shadow [probe_src]. *)
  let contains = Test_tls_groups.contains and read_file = Test_tls_groups.read_file
  and free_port = Test_tls_groups.free_port and wait_bound = Test_tls_groups.wait_bound in
  let dir = Filename.concat (Filename.get_temp_dir_name ())
      (Printf.sprintf "march-tlssigpipe-%d" (Unix.getpid ())) in
  (try Unix.mkdir dir 0o700 with Unix.Unix_error (Unix.EEXIST, _, _) -> ());
  let cert = Filename.concat dir "cert.pem" and key = Filename.concat dir "key.pem" in
  let src = Filename.concat dir "probe.march" and bin = Filename.concat dir "probe.bin" in
  let s_out = Filename.concat dir "server.out" and c_out = Filename.concat dir "client.out" in
  let cleanup () =
    List.iter (fun f -> try Sys.remove f with Sys_error _ -> ())
      [cert; key; src; bin; s_out; c_out];
    (try Unix.rmdir dir with Unix.Unix_error _ -> ())
  in
  Fun.protect ~finally:cleanup @@ fun () ->
  let gen = Printf.sprintf
      "openssl req -x509 -newkey rsa:2048 -nodes -keyout %s -out %s -days 1 \
       -subj /CN=127.0.0.1 >/dev/null 2>&1" (Filename.quote key) (Filename.quote cert) in
  if Sys.command gen <> 0 then
    Printf.printf "  [skip] TLS SIGPIPE probe: no openssl CLI to mint a certificate\n"
  else begin
    let oc = open_out src in
    output_string oc probe_src;
    close_out oc;
    match compile_march_or_skip ~main_exe:(find_main_exe ()) ~bin ~src () with
    | None -> ()
    | Some bin ->
      let port = free_port () in
      (* Drop any MARCH_TLS_* already set: test_tls_groups, which runs in
         this process first, leaves MARCH_TLS_ROLE=client behind (putenv),
         and getenv answers the first entry of a duplicated name. *)
      let inherited =
        List.filter (fun kv -> not (String.length kv >= 10 && String.sub kv 0 10 = "MARCH_TLS_"))
          (Array.to_list (Unix.environment ())) in
      let env extra =
        Array.of_list (inherited @ (Printf.sprintf "MARCH_TLS_PORT=%d" port :: extra)) in
      let s_fd = Unix.openfile s_out [Unix.O_WRONLY; Unix.O_CREAT; Unix.O_TRUNC] 0o600 in
      let server = Unix.create_process_env bin [| bin |]
          (env [ "MARCH_TLS_ROLE=server"; "MARCH_TLS_CERT=" ^ cert; "MARCH_TLS_KEY=" ^ key ])
          Unix.stdin s_fd Unix.stderr in
      Unix.close s_fd;
      let stop_server () =
        (try Unix.kill server Sys.sigkill with Unix.Unix_error _ -> ());
        (try ignore (Unix.waitpid [] server) with Unix.Unix_error _ -> ())
      in
      Fun.protect ~finally:stop_server @@ fun () ->
      if not (wait_bound port) then begin
        let state = match Unix.waitpid [Unix.WNOHANG] server with
          | (0, _) -> "still running"
          | (_, Unix.WEXITED n) -> Printf.sprintf "exited %d" n
          | (_, Unix.WSIGNALED n) -> Printf.sprintf "killed by signal %d" n
          | (_, Unix.WSTOPPED n) -> Printf.sprintf "stopped by signal %d" n
          | exception Unix.Unix_error _ -> "gone" in
        Alcotest.failf "TLS SIGPIPE probe: the March server never listened on %d (%s). Output:\n%s"
          port state (read_file s_out)
      end;
      Unix.putenv "MARCH_TLS_ROLE" "client";
      Unix.putenv "MARCH_TLS_PORT" (string_of_int port);
      let rc =
        match run_with_timeout ~timeout_secs:30. ~stdout_file:c_out [| bin |] with
        | `Timeout -> Alcotest.failf "TLS SIGPIPE client hung. Output:\n%s" (read_file c_out)
        | `Exited rc -> rc
      in
      let c = read_file c_out and s = read_file s_out in
      let ctx = Printf.sprintf "client (exit %d):\n%s\nserver:\n%s" rc c s in
      let check what cond = Alcotest.(check bool) (what ^ "\n" ^ ctx) true cond in
      if contains c "C FAIL ctx" then
        Printf.printf "  [skip] TLS SIGPIPE probe: no usable OpenSSL TLS context\n"
      else begin
        check "the server completed the handshake and left" (contains s "S handshake done");
        check "a write to the dead peer is an error" (contains c "C write error\n");
        check "a read on the dead connection returns" (contains c "C read returned\n");
        check "the client survived to its last line (no SIGPIPE)" (contains c "C done\n");
        check "the client exited 0, not 141" (rc = 0)
      end
  end

let suites =
  [ ( "tls_sigpipe",
      [ Alcotest.test_case "a write to a reset TLS peer is an error, not SIGPIPE (compiled)" `Slow
          test_write_to_reset_peer ] ) ]
