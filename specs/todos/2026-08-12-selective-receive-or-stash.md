`[P3]` # No selective receive, stash, or `become`

## The gap

`receive()` pops the **oldest** message with no pattern selection, and
`specs/lang/actors.md` documents a further restriction: only the *first*
`receive()` in a handler is safe to block on — a second blocking `receive()`
loses the message the first one already popped, because the scheduler's re-queue
only restores the outer triggering message.

So an actor that needs "wait for *this particular* message next" has no
mechanism. There is no stash/unstash, and no `become`-style handler swap.

## Why it matters

Selective receive is how BEAM expresses a protocol step inline (`receive {ok,
Ref, Reply} -> …`), which is what makes multi-step conversations readable
without hand-rolling a state machine. Akka doesn't have selective receive
either — it has `stash`/`unstash` plus `become`/`context.become`, which covers
the same ground differently: park the messages you can't handle yet, swap the
handler when the state changes.

March today has neither, so the only tool is the actor's state record plus
handler dispatch — i.e. every protocol becomes an explicit state machine the
author writes by hand. That is workable but verbose, and it interacts badly
with session types (`specs/lang/session-types.md`), whose whole selling point
is expressing a conversation in order.

## The realistic option

Full selective receive is expensive: it implies scanning the mailbox and
preserving skipped messages in order, which the current single-linked-list
mailbox with an O(1) FIFO pop is not shaped for, and it has a well-known
quadratic blow-up when a long queue is scanned repeatedly.

`stash` / `unstash_all` + a handler swap is the cheaper and more March-shaped
answer: the stash is an ordinary list in actor state, the swap is a field. It
may not even need runtime support — it could be a stdlib pattern plus a
documented idiom, in which case the deliverable is a cookbook recipe rather
than a compiler change. Establish that first before building anything.

## Acceptance

Either a stash/become idiom is documented (with a worked multi-step protocol),
or `receive` grows pattern selection with its complexity cost measured against
a long mailbox.
