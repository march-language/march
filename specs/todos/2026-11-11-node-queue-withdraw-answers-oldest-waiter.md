`[P2]` `NodeQueue`: a `BlockSender` timeout fails the oldest blocked caller, not the one that timed out (2026-11-11)

`withdraw` removes the timed-out caller's frame by key, but then pops the FRONT of the caller line and answers it `false`. When a younger caller times out first, the oldest caller, which is still inside its own timeout and whose frame is still waiting, returns `Err(NoConnection)` at once. Its frame is later admitted and sent anyway, so the caller is told the connection is gone about a message that is delivered.

Repro (`node_queue_withdraw.march`):

```march
-- Compiled only: under the interpreter a BlockSender call never parks.
mod A do
  needs IO.Console
  needs IO.Mut
  needs IO.NetListen
  needs IO.NetConnect
  needs IO.Spawn
  needs IO.Process
  needs IO.Clock

  pfn frame() : Bytes do
    Bytes.from_list(NetFrame.encode(List.map(Range.to_list(Range.new(0, 40)), fn _ -> 120)))
  end
  pfn show(r) do
    match r do
      Ok(_) -> "Ok"
      Err(NodeQueue.Backpressure) -> "Err(Backpressure)"
      Err(NodeQueue.NoConnection) -> "Err(NoConnection)"
      Err(_) -> "Err(other)"
    end
  end
  pfn wait_depth(q, want : Int, attempts : Int) : Bool do
    if NodeQueue.depth(q) == want do true
    else if attempts <= 0 do false
    else
      let _ = Process.run("sleep", Cons("0.01", Nil))
      wait_depth(q, want, attempts - 1)
    end end
  end

  fn main(_c : Cap(IO.Console), _n : Cap(IO.NetConnect), _l : Cap(IO.NetListen), _s : Cap(IO.Spawn), _m : Cap(IO.Mut), _p : Cap(IO.Process), _k : Cap(IO.Clock)) do
    let listen_fd = match tcp_listen(0) do
      Ok(fd) -> fd
      Err(e) -> panic("listen: " ++ e)
    end
    let port = match tcp_local_port(listen_fd) do
      Ok(p) -> p
      Err(e) -> panic("local_port: " ++ e)
    end
    -- a live connection nobody reads: the 44-byte frames sit in the kernel buffer
    let fd = match tcp_connect("127.0.0.1", port) do
      Ok(fd) -> fd
      Err(e) -> panic("connect: " ++ e)
    end
    let q = NodeQueue.start(fd, 100)
    let _ = NodeQueue.enqueue(q, 1, frame(), NodeQueue.DropNew)
    let _ = NodeQueue.enqueue(q, 2, frame(), NodeQueue.DropNew)
    let _ = wait_depth(q, 0, 500)
    -- frames 3 and 4 wait for credit and fill the budget (88 of 100)
    let r3 = NodeQueue.enqueue(q, 3, frame(), NodeQueue.DropNew)
    let r4 = NodeQueue.enqueue(q, 4, frame(), NodeQueue.DropNew)
    println("queued behind credit: " ++ show(r3) ++ " " ++ show(r4) ++ ", depth " ++ int_to_string(NodeQueue.depth(q)))
    let t0 = unix_time_ms()
    -- caller A: patient (4 s). Credit arrives at 1.5 s, so A should get Ok at about 1.5 s.
    let a = task_spawn(fn _ -> do
      let r = NodeQueue.enqueue(q, 5, frame(), NodeQueue.BlockSender(4000))
      (show(r), unix_time_ms() - t0)
    end)
    -- caller B: starts 0.3 s later and gives up after 0.3 s.
    let b = task_spawn(fn _ -> do
      let _ = Process.run("sleep", Cons("0.3", Nil))
      let r = NodeQueue.enqueue(q, 6, frame(), NodeQueue.BlockSender(300))
      (show(r), unix_time_ms() - t0)
    end)
    let _ = Process.run("sleep", Cons("1.5", Nil))
    NodeQueue.credit(q, 88)
    match task_await(a) do
      Ok((r, ms)) -> println("A (BlockSender 4000 ms): " ++ r ++ ", answered before the credit at 1500 ms: " ++ bool_to_string(ms < 1300))
      Err(_) -> println("A: task failed")
    end
    match task_await(b) do
      Ok((r, ms)) -> println("B (BlockSender 300 ms, started at 300 ms): " ++ r ++ ", answered before 1300 ms: " ++ bool_to_string(ms < 1300))
      Err(_) -> println("B: task failed")
    end
    let _ = wait_depth(q, 0, 100)
    println("depth after credit: " ++ int_to_string(NodeQueue.depth(q)) ++ " (44 = frame 5 was admitted to the queue although A was told NoConnection)")
    tcp_close(fd)
    tcp_close(listen_fd)
  end
end
```

Expected: A returns `Ok` at about 1500 ms (when credit arrives); B returns `Err(Backpressure)` at about 600 ms.

Actual (interpreted / compiled): not applicable (the interpreter never parks a `BlockSender` call) / `A: Err(NoConnection)`, answered at about 600 ms; frame 5 is then admitted (depth 44).

Source: `withdraw` (and the `Wait` handler), stdlib/node_queue.march. The fix is to key the caller line the same way the frame line is keyed.

Found by the 2026-10-18 doc sweep; re-verified 2026-11-11 on a7110f95f.
