# `[P1]` Choreography failure handling, after Maty

Filed 2026-09-18. The design for what happens to a session when one of its roles fails,
taken from Fowler and Hu, *Speak Now: Safe Actor Programming with Multiparty Session
Types* (PACMPL 10, OOPSLA 2026; the language is Maty, and its failure extension is called
Maty↯ in §5). The design record for the generated event API
([[2026-09-13-endpoints-event-api-actor-state]]) already follows Maty's core model, so this
extends a design March has partly adopted rather than importing a new one.

This replaces two earlier framings, recorded here so they are not revived by accident:

- **"Restart the whole session"** as the recovery story. Maty does not restart sessions. A
  failed session is cancelled and discarded, supervisors restart crashed actors, and a
  restarted actor joins the *next* session through an access point.
- **Crash branches in the global type** (`on crash B do C -> A : Partial`). That is the
  crash-stop MPST line of work (Barwell, Scalas, Yoshida, Zhou, CONCUR 2022; the paper's
  reference [6]). Maty deliberately keeps global types unchanged, and its failure handlers
  cannot communicate in the failed session. Crash branches stay available as a later
  extension (see Out of scope).

## The model, as the paper defines it

Maty's failure handling (§5, Fig. 14) is small. Everything below is from the paper.

1. **Sessions are affine.** An actor that crashes, or calls `raise`, has its role in every
   session marked cancelled (E-RaiseS: the zapper threads `↯a` and `↯s[p]`).
2. **Messages sent to a cancelled role are discarded** (E-CancelMsg), not reported.
3. **A role fails only when it waits on a cancelled role and nothing from that role is
   still queued** (E-CancelH, side condition `messages(q, p, δ) = ∅`). Its failure
   callback then runs with the actor's state, and its own endpoint is cancelled in turn.
   That is how failure cascades through a session, one waiting role at a time.
4. **The failure callback cannot communicate in the failed session.** `suspend` takes an
   extra callback `W` typed `C --end,end--> C`: it maps actor state to actor state and
   starts and ends with no session. The default is `λst. raise`, which crashes the actor
   and propagates further.
5. **Supervision is separate from sessions.** `monitor b V` runs callback `V` when actor
   `b` crashes (E-InvokeM). The paper's shop supervisor respawns the shop, and the new shop
   registers again at the access point and takes part in *subsequent* sessions. The failed
   session is garbage.
6. **`leave`** (§5.2) exits a session without terminating the actor.
7. **The guarantee** (Theorem 5.5, global progress for Maty↯): if every handler
   terminates, then every ongoing session eventually either performs a communication
   action or is cancelled. No session gets stuck.

Their Scala implementation runs fully distributed sessions over TCP (§6.1), and it treats
a dynamically detected linearity error as a failure, using the same machinery.

## Where March is today

The runner ([[2026-09-16-role-runner]], [[2026-09-17-actor-hosted-runner]],
[[2026-09-17-protocol-errors-and-parked-socket-waits]]) already ends sessions rather than
hanging, but at a much coarser grain than Maty:

| Situation | March today | Maty↯ |
|---|---|---|
| A peer's connection drops | The whole session ends at once for this role: `Err(PeerGone)` | Only a role *waiting* on that peer fails, and only once nothing from it is still queued |
| Deliveries from the failed peer already received and parked | Discarded | Handled first |
| Messages sent to the failed role | Written to a dead link | Discarded |
| A role that no longer needs the failed peer | Also ends with `PeerGone` | Carries on and can complete |
| What runs on failure | Nothing; `run` returns | A failure handler per receive, default: propagate |
| Hosted actor crashes | Links shut down, no Bye; peers see `PeerGone` | The crashed actor's roles are cancelled; waiting peers run their handlers |
| A peer violates the protocol (#509) | Session ends, `Err(Protocol(role, why))` | Treated as a failure of that peer |
| A peer is silent behind a partition | The reader waits forever | Out of scope for the paper, which assumes crashes are known |
| Recovering | Run the role again on every node | Supervisor restarts the actor; it re-registers; the next session forms |
| Sessions per node | One per `run` | Many per actor (the paper's KP3) |

The first four rows are a correctness gap, not just a difference of style. Here is the
example that shows it.

**`Fan`, with B crashing after it sends.** A and B each send C a number and C answers A.
If B sends its 9 and then crashes, B has nothing left to do in the protocol. C's receive
from B is satisfied by the message already sent, so C can answer A and the session can
complete. Maty completes it. March today aborts it: C's reader sees B's connection drop
before C has closed, and `run_C` returns `PeerGone(3)` even though the protocol never
needed B again. A is then aborted too, although A never talks to B.

## Design

### 1. Cancellation on the wire

- A new data frame, **`SessionNode.Cancel [role, cause]`**. A node sends it to every peer
  when one of its local endpoints is cancelled: its host actor died, the role called
  `leave`, a failure handler ran, or a protocol violation was decided against a peer.
- It goes on the **data** connection, behind everything that role already sent. Each
  connection is FIFO, so a peer handles every message from `q` before it learns `q` is
  cancelled. **That gives Maty's side condition, `messages(q, p, δ) = ∅`, for free**: no
  separate bookkeeping is needed to "drain first".
- **End of file on a data connection** from a role that has not closed normally counts as
  `Cancel(role, "connection lost")` at that point in the stream, in the same order. A
  crashed process cannot send a Cancel, and its unsent writes are lost, which is correct:
  a crashed actor sends nothing more.
- **A cancellation is final** within its session. Frames for that role that arrive later
  are dropped.
- **Only direct peers need to hear it.** A role waits only on roles it receives from, and
  `peers_of` connects a role to every role it sends to or receives from. A role that does
  not share a message with `q` never waits on `q`, and if the failure matters to it, it
  arrives by cascade: the role that *was* waiting on `q` is cancelled and sends its own
  Cancel onwards.

### 2. In the endpoint actor

The per-party endpoint actor (`SessionNode.Endpoint`) already runs every resumption in
mailbox order. Cancellation goes through the same mailbox:

- A reader that decodes `Cancel(q, cause)`, or reaches end of file from `q`, sends the
  endpoint actor `PeerCancelled(q, cause)`. It is queued behind every `Deliver` from `q`, so
  those are handled first.
- The party records cancelled roles with their causes.
- On `PeerCancelled(q, cause)`, for each local endpoint whose installed continuation waits
  on `q`, and that has nothing from `q` in `pending`: run that continuation's cancel
  handler, mark the local endpoint cancelled, and send `Cancel(my_role, cause')` to every
  peer. Here `cause'` records the chain, for example `role 2: role 3: connection lost`.
- **On `suspend`**, the same check runs at once. A role can install a wait on `q` after
  `q`'s cancellation has already arrived, and must fail then rather than wait forever.
- **`emit` to a cancelled role** discards the message and counts it (E-CancelMsg).
- A local endpoint that **closes normally** sends Bye as it does today. A peer's
  connection dropping afterwards is not a failure; the existing `closed` flag already
  handles this.

`want = 0` ("receive from anyone") is what the two-party transport passes. There the only
peer is the role being waited on, and the rule applies to it.

### 3. Failure handlers in the generated API

Maty types the failure callback `end → end`: it cannot communicate in the failed session.
March gets the same guarantee from the linearity it already has, **provided the handler
receives no session state**. Without a state value, there is no step function it can call.

**Callback API.** Each receive and offer gets a variant that takes a cancel handler:

```march
Fan_C.recv_Msg_B_C_1_or(s, st1,
  fn (b, st2) -> ...,                          -- the message arrived
  fn (c) -> do                                 -- role 3, or a role it depended on, failed
    log("fan: " ++ Fan_C.cause(c))
    Fan_C.cancelled(s, c)
  end)
```

- `c : Fan_C.Cancelled` is linear and unforgeable, built from the module's private
  `Secret` like `Yield` and the event API's `Parked`. It carries the failed role and the
  cause chain.
- The only way to turn it into the `Yield` the handler must return is
  `Fan_C.cancelled(s, c)`. So the handler can log, record a partial result, or release a
  resource, but it cannot send or receive in the session, because it holds no state
  value. Dropping `c` is a linearity error. This is Maty's typing of `W`, expressed with
  the machinery March already has.
- **The existing names are unchanged, and their behaviour is the default: propagate.** The
  transport cancels the endpoint without running any user code, which is Maty's
  `suspend V W ≜ suspend V W (λst. raise)` without crashing the host. Existing programs
  keep compiling. The `_or` suffix is a placeholder name, to be settled in review.

**Event API.** The actor-hosted runner gets a third function beside `start` and
`deliver`:

```march
Stream_Run.host_Cons(c, node, secret, addrs, pc, start, deliver,
  fn (s, role, cause, ep) -> send(pc, CancelC(role, cause)))
```

The generator adds `Stream_Cons.cancel(p : Parked_Cons) : Parked_Cons`, which consumes
the parked value and returns `Closed_Cons`. The actor handles the event with its own state
in scope, which is Maty's `W : C → C`. The linear-field rules that already govern `parked`
(R3/R4, [[2026-09-13-endpoints-event-api-actor-state]]) force it to store the result, so
an actor cannot ignore a cancellation and keep a dead `Parked` value.

**`leave`.** `Fan_C.leave(s, st) : Fan_C.Yield` consumes any state, cancels the endpoint
with cause `left`, and sends Cancel to its peers (Maty §5.2). Maty's `raise` is already
March's `panic` inside a supervised actor.

### 4. `Session.Ops`

- `suspend : Int -> Int -> (Int -> Bytes -> Int -> Int) -> (Int -> String -> Int -> Int) -> Int`
  gains a cancel handler, `(role, cause, ep)`. The generated code passes the user's
  handler, or a default that ends the endpoint.
- A new op, `leave : Int -> String -> ()`.
- `fail` (#509) is reinterpreted: the peer that sent this message has violated the
  protocol. The transport cancels that peer locally with cause `protocol: …`, and the
  cascade proceeds as for a crash. `run` still reports it as `Protocol`, so the cause is
  not lost.
- The same-thread transports in `test/session/` need the new fields. Nothing crashes
  inside one thread, so their cancel path is only reached through `leave`, which they
  should implement so the in-process tests can cover it. **Open:** whether to give them a
  small cancellation implementation or just a `leave`.

### 5. What `run` returns

- `Ok(())` when every local endpoint completed. **This includes the case where a peer was
  cancelled after this role no longer needed it**: `Fan` with B crashing after its send
  returns `Ok` on A and on C.
- `Err(Cancelled(role, cause))` when this role's endpoint was cancelled. `role` is the
  peer it was waiting on, and `cause` is the chain back to the origin.
- `Cancelled` **replaces `PeerGone`**. March is pre-1.0; the docs, the choreography guide
  and the CHANGELOG say so in the same change. `Protocol` and `HostGone` keep their names
  and are now reported as causes of a cancellation.

### 6. Failure detection

Maty assumes a crash is known (the zapper threads are part of the semantics). Our runner
learns about one when a connection ends, which leaves one real gap:

- **A peer that is silent behind a network partition sends no FIN and no RST.** The reader
  waits indefinitely. TCP keepalive defaults to hours, and Theorem 5.5's "eventually
  communicates or is cancelled" fails in the meantime.
- **The fix is a heartbeat on the control connection**, which already carries CREDIT. After
  an interval with nothing received, the node sends a ping; if nothing arrives by the
  deadline, it treats the peer as `Cancel(role, "no heartbeat")` and shuts the link down.
- **The partitioned node reaches the same conclusion independently**, because it misses our
  heartbeats. Neither side resumes the old session, and session ids (section 7) stop a
  healed node from rejoining it.
- **A false suspicion is safe.** A slow peer mistaken for a dead one cancels a session that
  could have completed. Affine sessions permit that, so it costs a retry and never
  corrupts state. Say this plainly in the docs.

With the heartbeat in place, the property we can state is Maty's: **every session on a
node eventually completes or is cancelled**, provided handlers terminate and failures are
crash-stop. The heartbeat's timeout is the bound on "eventually".

### 7. Access points and supervised restart

This is Maty's recovery story, and it needs its own design note before it is built. The
outline:

- **A network access point.** A node offers a role for repeated sessions of a protocol,
  where today it runs one session per `run` call. Each established session gets a fresh
  **session id**, Maty's fresh session name `s`. It goes in the hello, and every frame
  carries it. A node or a hosting actor can then take part in several sessions at once
  (the paper's KP3).
- **Restart is local.** A supervisor restarts a crashed actor, the actor registers at the
  access point again, and the next session forms. No cross-node restart coordination is
  needed: the surviving roles were cancelled out of the failed session, and they register
  again as their handlers (or the default) direct.
- **Open: forming sessions when a role has many instances** (one server, many clients).
  Maty's access point establishes a session once one registration per role is present.
  Across nodes, the lowest-numbered role's node is the natural matchmaker, since it is
  already the listener under the connect rule. How it pairs registrations, and what a
  client waits for, is the design note's main question.

## Order of work, and the witness for each phase

1. **Cancellation semantics, default handling only** (sections 1, 2, 5). No generator
   change. Witnesses:
   - **`two_node/fan_late_crash`** (new): B is SIGKILLed after its send. A and C both
     return `Ok`. This scenario must go red on today's runner (`PeerGone`); that is the
     drain rule's witness.
   - **`two_node/fan_early_crash`** (new): B is SIGKILLed before it sends. C returns
     `Cancelled(3, …)`, and **A returns `Cancelled(2, "role 3: …")` although A has no
     connection to B**. That is the cascade's witness.
   - `two_node/gone`: A returns `Cancelled(2, "connection lost")`.
   - `two_node/hosted_restart`: the host's death sends Cancel frames; the peer reports
     `Cancelled`.
   - Unit tests of the endpoint actor's rule: a pending delivery from `q` stops the cancel
     handler from firing; a `suspend` on an already-cancelled role fires at once; `emit`
     to a cancelled role is discarded and counted.
2. **Failure handlers** (sections 3, 4): the generator, `Session.Ops`, and the in-process
   transports. Witnesses in `test/test_endpoints.ml`:
   - accept: a cancel handler that logs and calls `cancelled`;
   - reject: a cancel handler that tries to send, with no state in scope;
   - reject: a cancel handler that drops its `Cancelled`;
   - an event-API actor that handles `CancelC` and stores `cancel(state.parked)`, plus the
     reject for one that doesn't.
3. **Heartbeat** (section 6). Witness: a scenario that `stop_node`s (SIGSTOP) a peer, which
   is silent without any end of file; the survivors return `Cancelled(…, "no heartbeat")`
   within the timeout. The harness already has the hook, which the `stall` scenario uses.
4. **Access points and repeated sessions** (section 7): the design note first, then the
   implementation.

Phases 1 and 3 change behaviour that programs can observe, so each needs a CHANGELOG entry
and an update to `docs/choreography.md`'s "How a session ends" and "Limits" sections. Its
statement that "sessions do not survive a failure of any role" becomes the precise rule
above.

## Out of scope

- **Crash branches in the global type** (Barwell et al., CONCUR 2022, the paper's [6]):
  protocols that must keep talking after a failure, which Maty's `end → end` handlers
  cannot express. A later extension; nothing here prevents it.
- **Protocol-directed recovery**, as in Neykova and Yoshida, *Let It Recover* (CC 2017, the
  paper's [48]), which the paper lists as future work.
- **Timeouts on a receive** (Maty §5.2, `suspend U V t W`, after Hou, Lagaillardie and
  Yoshida, ECOOP 2024). Cheap once phase 3 exists, since the runtime already has timers;
  file it separately then.
- **Byzantine peers.** A peer that sends valid but malicious messages is outside crash-stop.

## What would make this fail

The drain rule depends on one ordering: a peer's Cancel, or its end of file, must reach the
endpoint actor *behind* every delivery that peer sent before it. The readers already send
`Deliver` in stream order through one mailbox, and `PeerCancelled` must use the same
mailbox. It must never be a side channel such as a vault flag the endpoint actor polls.
If it becomes one, a fast cancellation overtakes a slow delivery, and `fan_late_crash`
fails intermittently rather than every time. That makes it a flake instead of a bug, and
that is the reason it is named here.
