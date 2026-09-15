# `[P1]` Credit-based flow control on the data connection

Filed 2026-09-14 as the remaining step 3 of
[[2026-09-14-distributed-plane-flow-control-and-control-channel]] (now a
progress record). Steps 1 and 2 shipped the pieces this needs: one reader
per connection (`PeerReader`, #459) and two connections per peer with the
role in the hello (`ClusterConn.connect_split` / `accept_split`, #465).
Until this lands, `NodeSend.cast` writes straight to the socket: a peer
that stops reading makes `Socket.write` block the sending green thread once
the kernel buffer is full, and nothing on our side can see it coming.

## Measured while building steps 1–2 (constraints on the design)

- Frames are `List(Int)` end to end (`NetFrame.encode`, `NetKernel.send_frame`
  → `bytes_to_str` → `Socket.write`). `recv_frame` is linear now (#465) but
  a 16 MiB frame is still 16 M cons cells; a queue that buffers frames must
  hold `Bytes` (`Bytes.from_list` once at enqueue, `Bytes.to_string` once at
  write), or the budget accounting is meaningless.
- `Socket.write` (`march_tcp_send_all`) loops until every byte is written
  and never returns a short count; it parks the green thread while the
  kernel buffer is full. There is no non-blocking write and no writability
  wait. A queue therefore needs a **writer task** per peer that owns the
  data fd; `emit` never touches the socket.
- The control connection has its own reader (`PeerReader`) and its writes
  are small; `CREDIT` travels on it. `DELIVERY_FAILED` already does
  (`NodeSend.serve_one_reply(fd, reply_fd, …)`).
- A library cannot name an actor's constructors: the queue's "tell the
  sender it was refused" is an injected callback, as `NodeSend.on_failure`.

## Design

### Wire

One new tag on the control connection, `0x0B CREDIT`:

```
[tag=11, bytes:Int]     -- "I have consumed `bytes` more of your data frames"
```

*Consumed* means handed to a local mailbox or answered with
`DELIVERY_FAILED` — the point after which the receiver holds no copy. The
receiver's `PeerReader` dispatch adds each data frame's byte length to a
per-peer counter and sends `CREDIT` when it exceeds `budget / 4` (batching;
a credit per frame doubles the frame count). Initial credit is the budget,
announced by nothing: both sides know the default (4 MiB) and a
non-default budget is a handshake extension for later.

### Sender: a per-peer outbound queue

```march
mod NodeQueue do
  type Policy = DropNew | DropOld | BlockSender
  type Queue                                   -- opaque; one per peer
  fn start(data_fd : Int, budget : Int, policy : Policy) : Queue      -- spawns the writer task
  fn enqueue(q : Queue, seq : Int, frame : Bytes, from) : Result((), SendError)
  fn credit(q : Queue, bytes : Int) : ()       -- called by the control reader on CREDIT
  fn depth(q : Queue) : Int                    -- bytes queued, for monitoring
end
```

- `enqueue` appends when `queued + len(frame) <= budget`, else applies the
  policy: `DropNew` → `Err(Backpressure)` immediately; `DropOld` → evict
  from the head until it fits, each evicted seq reported to the injected
  refusal callback as `Backpressure`; `BlockSender` → park the calling green
  thread on a Chan until `credit` frees room (native only — the interpreter
  refuses it at `start`, exactly as `Actor.set_queue_limit` policy 3 is
  refused).
- The writer task loops: wait until `credit_available >= len(head)` and
  the queue is non-empty; pop; `Socket.write`; `credit_available -= len`.
  It is the only thing that touches the data fd for writing.
- `NodeSend.cast` gains a sibling `NodeSend.enqueue(q, seq, to, type_tag,
  payload)`; `cast` stays for the loopback fixtures and for control-plane
  frames.

Why the state lives in an actor-shaped task rather than a Vault: the queue
mutates from three green threads (senders, the writer, the control reader
applying credit); a Vault gives atomic single ops but not "check budget then
append" as one step. A task with a mailbox (`Enqueue`, `Credit`, `Pop`)
serialises them. The `depth` query is the mailbox-size-style probe the
overload-shedding docs need for remote sends.

### Receiver

`PeerReader` dispatch for tag 9 on the data connection: after
`NodeSend.serve_one_reply` (or its frame-taking variant) returns, add the
frame length to `consumed_since_credit`; when it passes `budget / 4`, send
`CREDIT(consumed)` on the control fd and reset. A frame the dispatch
refuses still counts as consumed (the `DELIVERY_FAILED` is the receipt).

### What `Node.send` returns

Written-to-queue returns `Ok(seq)`; `Err(Backpressure)` under `DropNew` at
the budget; `Err(NoConnection)` once the writer has seen the socket close.
`DELIVERY_FAILED` still arrives later through `NodeSend.on_failure`. This
is decision 1 of [[2026-09-14-remote-send-to-a-global-pid]], unchanged.

## Order of work

1. `NodeQueue` with `DropNew` only, `Bytes` frames, the writer task, unit
   tests for the budget arithmetic (interpreter: no sockets needed for
   `enqueue`/`credit` if the writer is injected as a function).
2. `CREDIT` on the wire: encode/decode + the receiver's batching counter;
   `PeerReader` dispatch example in a fixture.
3. `DropOld`, then `BlockSender` (native only; the interpreter refusal).
4. `NodeSend.enqueue` and the `stream` two-node scenario switched to it
   (its traffic is tiny; the point is that the path is the production one).

## Tests

- `test/native/credit_backpressure_loopback.march`: a receiver that
  handshakes (split) and then never reads the data connection; the sender
  with budget 64 KiB and `DropNew` sees `Err(Backpressure)` on the first
  frame that does not fit, and `depth()` stops at the budget; the receiver
  then reads and sends `CREDIT`; the sender's next `enqueue` is `Ok`.
- Two-node scenario `stall_data` (harness): SIGSTOP the receiver; the
  sender's queue fills to the budget and reports `Backpressure` while its
  control reader still gets SWIM acks (the split's promise); SIGCONT; the
  queue drains and the last frame is delivered.
- Interpreter: `BlockSender` refused at `start` with the message naming
  `drop_new`/`drop_old`; `DropOld` evicts oldest-first with each evicted seq
  reported once.

## Decisions to make before building

1. Budget default (proposed 4 MiB) and whether a peer can raise it — a
   handshake field is the natural place; not needed for the first cut.
2. Whether `CREDIT` should carry the receiver's *total* consumed count
   (idempotent under duplication, needs a 64-bit counter both sides) or a
   delta (simpler; a duplicated CREDIT over-credits). Recommend total: the
   control connection is reliable TCP, but a reconnect (step 4's retry
   table) replays state, and totals survive replay.
