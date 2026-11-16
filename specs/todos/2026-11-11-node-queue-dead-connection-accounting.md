`[P2]` `NodeQueue`: a dead or closed queue never gives bytes back, and `DropOld` keeps queueing on it (2026-11-11)

Once the writer marks the connection dead (a failed write, `close`, `close_fd`):
1. The shared byte counter is never reduced. `enqueue` charges the counter, `admit` drops the frame without refunding it, and the `Close` handler empties `pending` without refunding either. `depth` then reports bytes that are not queued, `DropNew` answers `Err(Backpressure)` for ever instead of `Err(NoConnection)`, and `Unbounded` grows the counter without bound.
2. `admit_evicting` has no `dead` check (`admit` has one), so under `DropOld` frames are still pushed on `pending`, older ones are evicted and reported through `take_evicted`, and up to one budget of frames is held for a connection that will never write.

Repro (`node_queue_dead_counter.march`):

```march
mod A do
needs IO.Console
needs IO.Mut
needs IO.NetConnect
fn show(r) do
  match r do
    Ok(_) -> "Ok"
    Err(NodeQueue.Backpressure) -> "Err(Backpressure)"
    Err(NodeQueue.NoConnection) -> "Err(NoConnection)"
    Err(_) -> "Err(other)"
  end
end
fn frame() do Bytes.from_list([1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31, 32, 33, 34, 35, 36, 37, 38, 39, 40]) end
fn step(q, seq, policy, label) do
  let r = NodeQueue.enqueue(q, seq, frame(), policy)
  -- take_evicted is an Actor.call: it also lets the writer run its mailbox
  let ev = NodeQueue.take_evicted(q)
  println(label ++ " seq " ++ int_to_string(seq) ++ ": " ++ show(r) ++ ", depth=" ++ int_to_string(NodeQueue.depth(q)) ++ ", evicted=" ++ to_string(ev))
end
fn main(_c : Cap(IO.Console), _m : Cap(IO.Mut), _n : Cap(IO.NetConnect)) do
  -- fd 9999 is not open: the first write fails and the writer marks the queue dead.
  let q = NodeQueue.start(9999, 100)
  step(q, 1, NodeQueue.DropNew, "DropNew")
  step(q, 2, NodeQueue.DropNew, "DropNew")
  step(q, 3, NodeQueue.DropNew, "DropNew")
  step(q, 4, NodeQueue.DropOld, "DropOld")
  step(q, 5, NodeQueue.DropOld, "DropOld")
  step(q, 6, NodeQueue.DropOld, "DropOld")
  step(q, 7, NodeQueue.DropOld, "DropOld")
  NodeQueue.close(q)
  step(q, 8, NodeQueue.DropNew, "after close, DropNew")
  step(q, 9, NodeQueue.Unbounded, "after close, Unbounded")
  step(q, 10, NodeQueue.Unbounded, "after close, Unbounded")
end
end
```

Expected: after the connection dies `depth` is 0, nothing is queued or evicted, and a refused frame reports `NoConnection`.

Actual (interpreted / compiled): depth 40, 80, 80 (`Backpressure`), 120, 120, 120, 120, then 160 and 200 after `close`; `DropOld` reports evictions `[1]`, `[4]`, `[5]` / the same.

Source: `admit`, `admit_evicting`, `drain`, the `Close` and `CloseFd` handlers, stdlib/node_queue.march.

Found by the 2026-10-18 doc sweep; re-verified 2026-11-11 on a7110f95f.
