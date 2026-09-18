# `Actor.call` inside an actor's handler takes the actor's own messages as its reply

Filed and fixed 2026-09-18, found while fixing
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

## The fix

**Compiled: selective receive for the call's wait** (`march_actor_call`,
`runtime/march_runtime.c`). A message that is not a reply envelope is no longer the
call's answer. The wait holds it (`call_held`: message plus its mailbox sequence number)
and keeps waiting; on every exit (reply, timeout, stop request) `call_held_restore` puts
the held messages back at the FRONT of the user mailbox, in arrival order, ahead of
anything that arrived after them. So the handler's actor sees its messages exactly as if
it had not been interrupted, after the handler returns.

Scheduler support (`runtime/march_scheduler.c`):
- `march_sched_recv_user_seq` / `march_sched_recv_user_until_seq`: the user-only
  receives, also reporting the popped node's `enqueue_seq`.
- `march_sched_requeue_user_front(msgs, seqs, n)`: splices n messages back at the head
  of the current proc's user mailbox with their ORIGINAL sequence numbers, so the
  user/control interleaving `mbox_pop_any` sees (an explicit `receive()`) is also
  unchanged. No wake (the owner is the caller, running); the mailbox limit is not
  re-checked (the messages were admitted once). While held, they are not counted in the
  mailbox size.

Holding rather than scanning in place was deliberate: a receive that skips unmatched
messages would park with a non-empty mailbox, which the idle detection and wake paths
(`mbox_waiting_has_deliverable`, `march_sched_wait_idle`) read as "has work".

**The non-envelope passthrough is gone.** It existed for replies sent through a bare
proc, the legacy path in `march_actor_reply`. Compiled code never takes that path: every
handler's reply ref is the envelope-tagged one `march_actor_call` built. `Actor.reply`'s
legacy branch is kept (the builtin is polymorphic in the ref) but a bare value it sends
is now held as an ordinary message, not accepted as a reply.

**Interpreter: the same bug in another shape.** Its call correlates by a private ref id
in a table, so no message could be taken as the reply. But `actor_call` pumps
`run_scheduler` from inside the calling handler, and that nested pass ran the SAME
actor's next messages re-entrantly, mid-handler: the repro printed both notes before
"call answered", and the waiting handler's returned state then overwrote the state the
notes had produced (lost updates). `run_scheduler` now keeps `busy_actors` (pids with a
handler on the stack) and a nested pass skips them; their messages wait in the mailbox.

## Tests

- `test/native/actor_call_in_handler_keeps_messages` (compiled and interpreted, one
  golden): Caller's `Work` handler calls Slow (replies after 300 ms); main sends
  `Note(1)`, `Note(2)` 100 ms in, then calls Caller's `Count`. Expected:
  `call answered: 42`, `note 1 handled`, `note 2 handled`, `notes seen: 3`.
  Pre-fix runtime: `call answered: 4390208208`, only `note 2 handled`, `notes seen: 2`.
  Pre-fix interpreter: the notes print before the call's answer.

## Docs

`docs/clustering.md` and `specs/lang/clustering.md` no longer warn against
`NodeQueue.BlockSender` in a handler; they say what it does there (the actor handles
nothing else while it waits). `docs/actors.md` and `specs/lang/actors.md` gain a
"Calling from inside a handler" paragraph. SessionNode still sends with `Unbounded`: a
node's one endpoint actor serves every peer, and waiting on one slow peer would hold up
the rest.
