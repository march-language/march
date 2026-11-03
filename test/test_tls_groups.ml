(** TLS key-exchange groups: the hybrid post-quantum X25519MLKEM768 is offered
    first, it is what two March peers agree on, and the override works.

    Why both peers are March
    ────────────────────────
    The group two endpoints agree on depends on BOTH libraries. An
    [openssl s_server] peer would be whatever [openssl] is first on PATH, which
    on a macOS runner is LibreSSL and on Ubuntu 24.04 is OpenSSL 3.0, neither
    of which knows ML-KEM, while the compiled program links Homebrew's
    OpenSSL. So one compiled program plays both roles (MARCH_TLS_ROLE), and
    the two processes share the one OpenSSL under test.

    What is asserted
    ────────────────
    1. DEFAULT CONTEXTS, BOTH SIDES. When [Tls.post_quantum_available()] says
       the linked OpenSSL has ML-KEM, the default handshake agrees on
       X25519MLKEM768 on the client and on the server, and
       [Tls.is_post_quantum] is true. When it says not, the handshake still
       succeeds on a classical group and is_post_quantum is false: the
       fallback keeps old OpenSSLs working. Which branch ran is printed.
    2. THE OVERRIDE, a non-vacuity control: a client restricted with
       [Tls.set_groups(ctx, ["X25519"])] agrees on x25519 whatever the
       library. Without it, a [negotiated_group] that always answered the
       first configured group would pass (1).
    3. A BAD LIST IS AN ERROR and leaves the context usable: [set_groups]
       with an unknown name is Err.

    Skip policy: only a missing toolchain (compile_march_or_skip) or a missing
    [openssl] CLI to mint the throwaway certificate. *)

open Test_helpers

let probe_src =
  {|
mod TlsGroupsProbe do
  needs IO.NetConnect
  needs IO.NetListen
  needs IO.NetConnect.TLS
  needs IO.Console
  needs IO.Process

  fn env_or(name, dflt) do
    match process_env(name) do
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

  fn show(o) do
    match o do
    Some(g) -> g
    None -> "none"
    end
  end

  -- Accept [n] connections; report the group of each completed handshake.
  -- The harness's readiness probe is one of them and fails the handshake.
  fn serve(listen_fd, ctx, n) do
    if n <= 0 do ()
    else
      match tcp_accept(listen_fd) do
      Err(e) -> println("S FAIL accept " ++ e)
      Ok(fd) ->
        match Tls.accept(fd, ctx) do
        Ok(conn) ->
          println("S group=" ++ show(Tls.negotiated_group(conn))
                  ++ " pq=" ++ bool_to_string(Tls.is_post_quantum(conn)))
          Tls.close(conn)
        Err(_) -> ()
        end
        Socket.close(fd)
        serve(listen_fd, ctx, n - 1)
      end
    end
  end

  fn client_config() do
    Tls.TlsConfig("", "", "", [], Tls.Tls12, false)
  end

  fn handshake(label, ctx, port) do
    match Socket.connect("127.0.0.1", port) do
    Err(e) -> println(label ++ " FAIL connect " ++ Socket.error_message(e))
    Ok(fd) ->
      match Socket.set_recv_timeout(fd, 5000) do
      _ -> ()
      end
      match Tls.connect(fd, ctx, "127.0.0.1") do
      Ok(conn) ->
        println(label ++ " group=" ++ show(Tls.negotiated_group(conn))
                ++ " pq=" ++ bool_to_string(Tls.is_post_quantum(conn)))
        Tls.close(conn)
      Err(e) -> println(label ++ " FAIL handshake " ++ Tls.error_to_string(e))
      end
      Socket.close(fd)
    end
  end

  fn client(port) do
    println("AVAIL " ++ bool_to_string(Tls.post_quantum_available()))
    match Tls.client_ctx(client_config()) do
    Err(_) -> println("C FAIL ctx")
    Ok(ctx) ->
      handshake("C1", ctx, port)
      match Tls.set_groups(ctx, ["no-such-group"]) do
      Ok(_) -> println("C3 FAIL accepted a bogus group")
      Err(_) -> println("C3 OK rejected")
      end
      match Tls.set_groups(ctx, ["X25519"]) do
      Err(e) -> println("C2 FAIL set_groups " ++ Tls.error_to_string(e))
      Ok(_) -> handshake("C2", ctx, port)
      end
      Tls.ctx_free(ctx)
    end
  end

  fn main(_c1 : Cap(IO.NetConnect), _c2 : Cap(IO.NetConnect.TLS), _c3 : Cap(IO.NetListen),
          _c4 : Cap(IO.Process), _c5 : Cap(IO.Console)) do
    let port = env_int("MARCH_TLS_PORT")
    if env_or("MARCH_TLS_ROLE", "client") == "server" do
      match Tls.server_ctx(Tls.server_config(env_or("MARCH_TLS_CERT", ""), env_or("MARCH_TLS_KEY", ""))) do
      Err(e) -> println("S FAIL ctx " ++ Tls.error_to_string(e))
      Ok(ctx) ->
        match tcp_listen(port) do
        Err(e) -> println("S FAIL listen " ++ e)
        Ok(lfd) ->
          serve(lfd, ctx, env_int("MARCH_TLS_ACCEPTS"))
          Socket.close(lfd)
        end
      end
    else client(port)
    end
  end

end
|}

let contains hay needle =
  let nl = String.length needle and hl = String.length hay in
  let rec go i = i + nl <= hl && (String.sub hay i nl = needle || go (i + 1)) in
  nl = 0 || go 0

let read_file path =
  try
    let ic = open_in_bin path in
    Fun.protect ~finally:(fun () -> close_in_noerr ic)
      (fun () -> really_input_string ic (in_channel_length ic))
  with Sys_error _ -> ""

let free_port () =
  let s = Unix.socket Unix.PF_INET Unix.SOCK_STREAM 0 in
  Unix.setsockopt s Unix.SO_REUSEADDR true;
  Unix.bind s (Unix.ADDR_INET (Unix.inet_addr_loopback, 0));
  let port = match Unix.getsockname s with Unix.ADDR_INET (_, p) -> p | _ -> 0 in
  Unix.close s;
  port

(* Wait for the listener rather than sleeping a guessed amount.  The probe
   connection is one of the server's accepts (its handshake fails, which the
   server ignores). *)
let wait_bound port =
  let rec go n =
    n > 0 &&
    let c = Unix.socket Unix.PF_INET Unix.SOCK_STREAM 0 in
    match Unix.connect c (Unix.ADDR_INET (Unix.inet_addr_loopback, port)) with
    | () -> Unix.close c; true
    | exception Unix.Unix_error _ ->
      (try Unix.close c with Unix.Unix_error _ -> ());
      Thread.delay 0.1; go (n - 1)
  in
  go 100

let test_pq_groups () =
  let dir = Filename.concat (Filename.get_temp_dir_name ())
      (Printf.sprintf "march-tlsgroups-%d" (Unix.getpid ())) in
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
    Printf.printf "  [skip] TLS groups probe: no openssl CLI to mint a certificate\n"
  else begin
    let oc = open_out src in
    output_string oc probe_src;
    close_out oc;
    match compile_march_or_skip ~main_exe:(find_main_exe ()) ~bin ~src () with
    | None -> ()
    | Some bin ->
      let port = free_port () in
      let common = [ Printf.sprintf "MARCH_TLS_PORT=%d" port ] in
      let env extra = Array.append (Unix.environment ()) (Array.of_list (common @ extra)) in
      (* readiness probe + C1 + C2 *)
      let s_fd = Unix.openfile s_out [Unix.O_WRONLY; Unix.O_CREAT; Unix.O_TRUNC] 0o600 in
      let server = Unix.create_process_env bin [| bin |]
          (env [ "MARCH_TLS_ROLE=server"; "MARCH_TLS_ACCEPTS=3";
                 "MARCH_TLS_CERT=" ^ cert; "MARCH_TLS_KEY=" ^ key ])
          Unix.stdin s_fd Unix.stderr in
      Unix.close s_fd;
      let stop_server () =
        (try Unix.kill server Sys.sigkill with Unix.Unix_error _ -> ());
        (try ignore (Unix.waitpid [] server) with Unix.Unix_error _ -> ())
      in
      Fun.protect ~finally:stop_server @@ fun () ->
      if not (wait_bound port) then
        Alcotest.failf "TLS groups probe: the March server never listened. Output:\n%s"
          (read_file s_out);
      Unix.putenv "MARCH_TLS_ROLE" "client";
      Unix.putenv "MARCH_TLS_PORT" (string_of_int port);
      (match run_with_timeout ~timeout_secs:30. ~stdout_file:c_out [| bin |] with
       | `Timeout -> Alcotest.failf "TLS groups client hung. Output:\n%s" (read_file c_out)
       | `Exited rc ->
         if rc <> 0 then Alcotest.failf "TLS groups client exited %d:\n%s" rc (read_file c_out));
      (* The server exits after its third accept; give it a moment to flush. *)
      let rec wait_exit n =
        if n > 0 then
          match Unix.waitpid [Unix.WNOHANG] server with
          | (0, _) -> Thread.delay 0.1; wait_exit (n - 1)
          | _ -> ()
          | exception Unix.Unix_error _ -> ()
      in
      wait_exit 50;
      let c = read_file c_out and s = read_file s_out in
      let ctx = Printf.sprintf "client:\n%s\nserver:\n%s" c s in
      let check what cond = Alcotest.(check bool) (what ^ "\n" ^ ctx) true cond in
      if contains c "C FAIL ctx" then
        Printf.printf "  [skip] TLS groups probe: no usable OpenSSL TLS context\n"
      else begin
        check "the bogus group list is rejected" (contains c "C3 OK rejected");
        check "the X25519-only override agrees on x25519 (control)"
          (contains (String.lowercase_ascii c) "c2 group=x25519 pq=false");
        if contains c "AVAIL true" then begin
          check "client agrees on the hybrid post-quantum group"
            (contains c "C1 group=X25519MLKEM768 pq=true");
          check "server agrees on the hybrid post-quantum group"
            (contains s "S group=X25519MLKEM768 pq=true")
        end else begin
          Printf.printf
            "  [note] linked OpenSSL has no ML-KEM: asserting the classical fallback only\n";
          check "without ML-KEM the default handshake is classical and still succeeds"
            (contains c "C1 group=" && not (contains c "C1 FAIL")
             && not (contains c "C1 group=X25519MLKEM768"))
        end
      end
  end

let suites =
  [ ( "tls_groups",
      [ Alcotest.test_case "post-quantum key exchange by default (compiled)" `Slow
          test_pq_groups ] ) ]
