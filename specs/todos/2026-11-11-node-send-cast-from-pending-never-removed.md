`[P2]` `NodeSend.cast_from` records every sender and only a failure removes the record (2026-11-11)

`cast_from` stores the sender under the seq in the process-wide `node_send_pending` Vault before writing. `on_failure` removes the entry when a DELIVERY_FAILED comes back; nothing removes it when the message is delivered, so the table grows by one entry per successful send for the life of the node. The doc string says so. There is no acknowledgement to hang a removal on, so this needs a bound (a seq window or a TTL).

Repro (`node_send_cast_from_pending.march`):

```march
mod A do
  needs IO.Console
  needs IO.Mut
  needs IO.NetListen
  needs IO.NetConnect

  pfn show(r) do
    match r do
      Ok(_) -> "Ok"
      Err(_) -> "Err"
    end
  end
  pfn send_n(fd : Int, seq : Int, n : Int, ok : Int) : Int do
    if seq > n do ok
    else
      let r = NodeSend.cast_from(fd, seq, "sender-" ++ int_to_string(seq), GlobalPid.make("node-b", 7, 1), "A.Msg", Nil)
      send_n(fd, seq + 1, n, if Result.is_ok(r) do ok + 1 else ok end)
    end
  end
  pfn pending_size() : Int do
    match Vault.whereis("node_send_pending") do
      Ok(Some(t)) -> Vault.size(t)
      _ -> 0 - 1
    end
  end

  fn main(_c : Cap(IO.Console), _n : Cap(IO.NetConnect), _l : Cap(IO.NetListen), _m : Cap(IO.Mut)) do
    let lfd = match tcp_listen(0) do
      Ok(fd) -> fd
      Err(e) -> panic("listen: " ++ e)
    end
    let port = match tcp_local_port(lfd) do
      Ok(p) -> p
      Err(e) -> panic("local_port: " ++ e)
    end
    let fd = match tcp_connect("127.0.0.1", port) do
      Ok(fd) -> fd
      Err(e) -> panic("connect: " ++ e)
    end
    -- 50 messages written successfully; no DELIVERY_FAILED ever comes back
    let ok1 = send_n(fd, 1, 50, 0)
    println("casts that returned Ok: " ++ int_to_string(ok1) ++ "; senders still recorded: " ++ int_to_string(pending_size()))
    let ok2 = send_n(fd, 51, 100, 0)
    println("casts that returned Ok: " ++ int_to_string(ok1 + ok2) ++ "; senders still recorded: " ++ int_to_string(pending_size()))
    tcp_close(fd)
    tcp_close(lfd)
  end
end
```

Expected: the table stays bounded.

Actual (interpreted / compiled): 50 entries after 50 successful casts, 100 after 100 / the same.

Source: `cast_from`, `on_failure`, stdlib/node_send.march.

Found by the 2026-10-18 doc sweep; re-verified 2026-11-11 on a7110f95f.
