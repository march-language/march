`[P2]` `ClusterConn.accept_split_auth` leaks accepted sockets on its role and node mismatch errors (2026-11-11)

Three error paths return `Err` without closing what they accepted: the first connection announcing a role other than control (its fd is leaked), and the second connection being not the data role or from a different node (both fds are leaked). The accept-timeout path does close the first socket, and `connect_split_auth` closes on every path. Each leaked socket has completed the authenticated handshake, so only a peer holding the cluster secret or a certificate can trigger it, but each failed attempt costs the acceptor one or two descriptors for the life of the process.

Repro (`cluster_conn_accept_leak.march`):

```march
-- Compiled only (the accept runs in a task). After accept_split_auth returns Err,
-- is the accepted socket closed? The dialling side probes its end: a closed peer
-- reads as end-of-stream at once, a leaked one reads as a timeout.
mod A do
  needs IO.Console
  needs IO.Mut
  needs IO.NetListen
  needs IO.NetConnect
  needs IO.Random
  needs IO.Spawn
  needs IO.Clock

  pfn secret() do "test-cluster-secret" end
  pfn id_a() do NodeIdentity.make("node-a", "pk-a", 1) end
  pfn id_b() do NodeIdentity.make("node-b", "pk-b", 1) end

  pfn dial(port : Int, role : String) : Int do
    match tcp_connect("127.0.0.1", port) do
      Err(e) -> panic("connect: " ++ e)
      Ok(fd) ->
        match NetKernel.handshake_auth(fd, id_a(), ClusterAuth.Secret(secret()), NetKernel.fresh_nonce(), role, "", 0) do
          Ok(_) -> fd
          Err(e) -> panic("client handshake: " ++ e)
        end
    end
  end

  pfn probe(fd : Int) : String do
    let _ = tcp_set_recv_timeout(fd, 700)
    match tcp_recv_exact(fd, 1) do
      Ok(_) -> "got data"
      Err(e) -> e
    end
  end

  pfn accept_result(t) : String do
    match task_await(t) do
      Ok(Ok(_)) -> "Ok"
      Ok(Err(e)) -> "Err(" ++ e ++ ")"
      Err(_) -> "task failed"
    end
  end

  fn main(_c : Cap(IO.Console), _n : Cap(IO.NetConnect), _l : Cap(IO.NetListen), _r : Cap(IO.Random), _s : Cap(IO.Spawn), _m : Cap(IO.Mut), _k : Cap(IO.Clock)) do
    let lfd = match tcp_listen(0) do
      Ok(fd) -> fd
      Err(e) -> panic("listen: " ++ e)
    end
    let port = match tcp_local_port(lfd) do
      Ok(p) -> p
      Err(e) -> panic("local_port: " ++ e)
    end
    -- control case: only the control connection arrives; the second accept times
    -- out, and that path does close the first socket
    let t0 = task_spawn(fn _ -> ClusterConn.accept_split_auth(PeerRegistry.empty(), lfd, id_b(), ClusterAuth.Secret(secret()), 500))
    let c0 = dial(port, Handshake.role_control())
    println("0. second accept times out:   accept -> " ++ accept_result(t0))
    println("   client's control socket reads: " ++ probe(c0))
    -- case 1: the first connection announces the data role
    let t1 = task_spawn(fn _ -> ClusterConn.accept_split_auth(PeerRegistry.empty(), lfd, id_b(), ClusterAuth.Secret(secret()), 2000))
    let c1 = dial(port, Handshake.role_data())
    println("1. data role arrives first:   accept -> " ++ accept_result(t1))
    println("   client's socket reads: " ++ probe(c1))
    -- case 2: control, then a second control connection instead of data
    let t2 = task_spawn(fn _ -> ClusterConn.accept_split_auth(PeerRegistry.empty(), lfd, id_b(), ClusterAuth.Secret(secret()), 2000))
    let c2 = dial(port, Handshake.role_control())
    let d2 = dial(port, Handshake.role_control())
    println("2. second connection is not data: accept -> " ++ accept_result(t2))
    println("   client's first socket reads: " ++ probe(c2))
    println("   client's second socket reads: " ++ probe(d2))
  end
end
```

Expected: after an `Err` the dialling side sees its sockets closed (as in case 0).

Actual (interpreted / compiled): not run (the accept runs in a task) / case 0 reads `connection closed`; cases 1 and 2 read `timed out` on every socket: the acceptor still holds them.

Source: `accept_split_auth`, stdlib/cluster_conn.march. The fix is a `tcp_close` of `cfd` (and `dfd`) on the two mismatch branches.

Found by the 2026-10-18 doc sweep; re-verified 2026-11-11 on a7110f95f.
