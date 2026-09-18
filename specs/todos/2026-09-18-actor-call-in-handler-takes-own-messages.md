# `Actor.call` inside an actor's handler takes the actor's own messages as its reply

Filed 2026-09-18, found while fixing
[[2026-09-18-session-frames-never-dropped]].

## The bug

`march_actor_call` (runtime/march_runtime.c) waits for its reply by reading the
CALLER's mailbox (`march_sched_recv_user` / `march_sched_recv_user_until`). A reply
comes back as an envelope tagged `MARCH_CALL_REPLY_TAG`, and `march_actor_call_unwrap`
discards envelopes whose correlation id does not match. Anything that is NOT an
envelope is passed through as the reply ("legacy/raw send"). When the caller is a
plain green thread (main, a task), nothing else arrives in that mailbox, so this is
harmless. When the caller is an ACTOR running a handler, its mailbox is also where its
ordinary messages arrive: one sent while the handler waits is returned as the call's
answer and never reaches its handler.

Minimal repro (compiled): actor `Caller`'s `Work` handler does
`Actor.call(slow, Ask, 2000)` against an actor that replies after 300 ms; main sends
`Caller` a `Note(1)` 100 ms in. Output:

```
call answered: 4395975664     -- the Note message's pointer, read as the reply
                              -- ("note 1 handled" is never printed)
```

The real reply (42) then arrives as a stale envelope and is dropped on the next call.

## Where it bit

`NodeQueue.BlockSender` rides `Actor.call` on the writer. SessionNode briefly used it
for session frames; a send blocked inside the endpoint actor's turn swallowed the
reader's `LinkEnded` and the heartbeat's `PeerGone`, and `serve` then waited forever.
SessionNode now uses `NodeQueue.Unbounded` and never blocks (see the progress entry);
docs/clustering.md warns against `BlockSender` in a handler until this is fixed.

## Fix direction

Selective receive for the call's wait: a non-envelope message received while an actor
is waiting in `Actor.call` must be kept (re-queued at the front of the mailbox, in
order, once the call returns) rather than returned. Then decide whether the
non-envelope passthrough is still needed at all (it exists for replies sent through a
raw proc, the interpreter-parity path in `march_actor_reply`). The interpreter's
`Actor.call` should be checked for the same behaviour.
