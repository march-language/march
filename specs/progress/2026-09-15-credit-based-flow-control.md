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


---

## Shipped so far (2026-09-14): steps 1–2, and `drop_old`

`stdlib/node_queue.march` (`NodeQueue`): `start(fd, budget)` spawns the
writer actor — a library-owned actor, which works on both backends (the
constructor question is moot: the library sends to its own actor) — and
returns the queue handle; `enqueue(q, seq, frame : Bytes, policy)` checks
the budget synchronously with one atomic `Vault.incr` and hands the frame
to the writer; `credit(q, total)` applies a CREDIT; `depth(q)`;
`take_evicted(q)`; receiver side `consumed(control_fd, budget, len)` sends
`CREDIT(total)` every budget/4 bytes. Wire: tag 11, the consumed TOTAL
(decision 2: totals, so a replayed CREDIT never over-credits). The writer
holds `granted = consumed_total + budget`, so at most one budget of bytes
is ever written-but-unconsumed. `block_sender` is not offered: there is no
primitive to park a green thread on the queue; callers retry on
`Backpressure` (its step is still open, as is `NodeSend.enqueue` and the
`stream` scenario switch).

Two things measured while building it:
- Inside the writer's helpers a `{ st with … }` update was typed as only its
  updated fields (a smaller stand-alone program did not reproduce it); the
  helpers rebuild the record whole. Unisolated; not filed until it is.
- Queue depth read from `main` differs between backends by design: the
  compiled writer runs concurrently and may have written already; the
  interpreter's runs at `run_until_idle`. Tests assert admission/refusal,
  never depth after an admitted frame.

Step 4 shipped too: `NodeQueue.cast(q, seq, to, type_tag, payload, policy)`
is the remote-send path through the queue, and the `stream` two-node
scenario runs on it — split connections, `emit` through the queue, the
data reader accounting each delivery as consumed (in the mailbox) and the
control reader feeding CREDIT back. Two things it taught:
- `run_until_idle()` inside a reader never returns while another task is
  parked in a socket read (the control reader), so the data reader no
  longer drains the actor per frame; the endpoint actor runs on the
  scheduler in mailbox order, which keeps one node's prints in protocol
  order — and "consumed" is "in the mailbox", the spec's definition.
- Ending two readers per node without a symmetric deadlock: an endpoint's
  `close` sends a `Bye` on the data connection (through the queue) and each
  node sends a `Bye` on control after its data reader ends; a peer close
  after the local endpoint has closed is a clean end (the peer's Bye may
  still be in its writer when it closes).

Witness `test/native/credit_backpressure_loopback`: budget 100, 44-byte
frames; frames 1-2 are written under the initial credit (the test waits for
`depth == 0`), 3-4 sit queued behind the credit line (`depth == 88`), the
fifth is `Backpressure`; the receiver consumes after a "go" on control, its
CREDIT re-admits the fifth; receiver consumed 5. (Reworked 2026-09-22 from a
three-frame version that raced the writer actor; see
`2026-09-22-flake-credit-backpressure-loopback-timing.md`.)
Unit tests in `test/stdlib/test_node_queue.march`.

---

## Shipped 2026-09-15: `BlockSender(timeout_ms)` — the last policy; item closed

`NodeQueue.Policy` gains `BlockSender(timeout_ms)`. It needs no new
scheduler primitive: it rides `Actor.call` on the writer. A frame that does
not fit is sent as `Waiting(key, seq, frame)` (uncharged; the writer charges
it on admission), and the caller blocks in `Actor.call(w, WaitReq, timeout_ms)`.
The writer keeps two FIFO lines, waiting frames and blocked callers, one
entry each per call; every admission from the frame line (on credit, or
whenever something else frees budget) answers the oldest caller `true`. A
dead connection answers everyone `false` (`Err(NoConnection)`); a timed-out
caller sends `Withdraw(key)`, which drops its frame if still waiting and
answers one caller entry `false` so the lines stay the same length. Under
the interpreter `Actor.call` cannot park the caller across later credit, so
a send that cannot be admitted at once is `Err(Backpressure)` there.

Holding a reply across handler turns needed one runtime helper,
`actor_reply_retain(ref)` (`march_actor_reply_retain`): a reply ref's only
reference is retired with the call envelope when the handler returns, so a
reply from a LATER turn was a use-after-free. `retain` takes a second
reference; `march_actor_reply` retires one per reply, so a held ref must be
answered exactly once.

Measured while building it:
- **A reply ref must never sit in an Int-typed slot.** The first cut held
  refs in `Deque(Int)`; the ref was Int-tagged on the way in, so the later
  `Actor.reply` saw a non-ref, took the legacy raw-proc path, and sent to a
  garbage proc (SIGBUS in `march_sched_send`, 5/5 runs). The writer now holds
  each blocked caller as the closure that answers it (`Bool -> Unit`), so the
  ref stays a counted heap value. The crash pc was first misattributed to
  `Bytes.length` by guessing the symbol from the page offset; `dladdr` in the
  fault report named the real function at once.
- `Actor.call` routes a sentinel to the handler at the sentinel's
  constructor index, so `TakeEvicted` and `Wait` are the writer's first two
  handlers (`WriterReq = EvictedReq | WaitReq`). `take_evicted` had used a
  one-constructor sentinel against handler 0 = `Configure` and nothing
  exercised it; an interpreter unit test now does.
- Interpreter: an actor declared in a module captured the env as of its own
  declaration, so a handler calling a fn declared after it died with "stub X
  called before initialisation". `eval_decl` now re-points every actor of a
  module at the module's final env.

Witness `test/native/block_sender_loopback`: budget 100, 44-byte frames; two
written at once, two queued behind the credit line, the fifth enqueued under
`BlockSender(5000)` returns `Ok` only after the receiver's delayed consumption
(wall clock >= 150 ms), and the receiver consumes all five. Unit tests in
`test/stdlib/test_node_queue.march` (admits at once when it fits; a dead
connection is `NoConnection` at once with nothing queued; `take_evicted`).
