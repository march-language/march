`[P2]` **Observe: the signed `MESSAGES` verb (an actor's queued messages).**

The last piece of R4 in [`specs/plans/2026-09-28-observe-recon-shell-plan.md`](../plans/2026-09-28-observe-recon-shell-plan.md)
(`MESSAGES … pid:<p> n:<n>`, n ≤ 100). R4b ([progress](../progress/2026-10-05-observe-r4b-signed-debug-verbs.md))
shipped `STATE` and `CRASHES_FULL` with all the signing, nonce, policy and
audit machinery; `MESSAGES` would reuse it unchanged (`admit()` in
`runtime/march_observe_debug.c`).

**Why it did not ship with them: where the rendering runs.**

- **On the socket thread** (the plan's wording: walk the mailbox under
  `mbox_lock`, copy out rendered strings). Rendering calls compiled March code
  (`to_string` at the message type, through a generated per-actor
  `Name_show_msg`). A user `Show` that panics then runs `march_panic` on a
  thread with no proc and no crash trap, which kills the node. An observe
  request must never be able to do that.
- **On the actor itself** (the way `STATE` works): safe, but an actor answers
  only between messages, so exactly the actor you want to look at (stuck in a
  handler with a growing queue) cannot answer.
- **On a helper green thread** (a renderer proc started with the observe
  socket): runs March code under a crash trap like any proc, and can read
  another actor's mailbox while that actor is stuck. Needs: a C-spawned
  green thread with a request loop; the queue walked under `mbox_lock`, each
  message `incrc`'d and the lock released before rendering; a per-type
  message renderer registered beside `Name_inspect`; and a rule for messages
  whose layout is not the user's `Msg` (call envelopes carry the reply-ref as
  an extra field, plus system tags and epoch markers). Likely the right
  answer, and a week of work.

**Done when:** `forge observe --messages PID` shows the first n queued
messages of an actor that is stuck in a handler, a panicking `Show` answers an
error without hurting the node, and the A/B gate holds if the actor loop
changes.
