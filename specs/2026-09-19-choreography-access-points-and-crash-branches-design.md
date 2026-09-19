# Choreography: access points and crash branches

Design, 2026-09-19. Two parts, built in this order:

- **Part A, access points.** A node offers a role of a protocol for many sessions. A
  session forms when an *initiator* invites one registered instance of each other role;
  each session gets a fresh id. This finishes [[2026-09-18-choreography-access-points]]
  (phase 4 of [[2026-09-18-choreography-failure-handling]]).
- **Part B, crash branches.** A protocol names the roles that may crash, and every
  receive from such a role says what the survivors do instead. The survivors keep
  talking after a failure, where today the session can only be cancelled.

Decisions taken with the user on 2026-09-19: **the initiator invites** (not a central
matchmaker, not server-only accept), and **crash branches** in the protocol (not a
cancel handler that may send). Everything marked *(choice)* below is a further decision
made in this design, open to change before its phase is built.

Background reading: Maty (Fowler and Hu, *Speak Now*, OOPSLA 2026) for access points
and cancellation; Barwell, Hou, Yoshida and Zhou, *Designing Asynchronous Multiparty
Protocols with Crash-Stop Failures* (ECOOP 2023) for crash branches, including the
global type syntax (`p→q:{mᵢ.Gᵢ, crash.G′}`), projection with a set of reliable roles
(their Def. 3) and detection at reception (their rule Γ-⊙). The CONCUR 2022 paper by
Barwell, Scalas, Yoshida and Zhou has the local-type version and no global types.

---

## Part A: access points

### What exists

`SessionNode.run_cluster(io, node, my_role, peers, session, on_close, body)` forms one
session over a cluster node: it registers the role's endpoint as
`"session:<sid>/<role>"`, finds the peers' endpoints by name (polling `lookup`, 30 s),
takes each peer node's data queue, and serves. Frames carry the sid in their type tag
(`"SessionNode.Deliver#<sid>"`) and a frame for another sid is refused. A node's death
(SWIM) ends its data connection, and the reader's close cancels every session using
it. The session id is supplied by whoever runs the nodes; one call is one blocking
session; the `ap` argument of `Session.register` is always 0 and ignored.

### What an access point is

An **offer**: a node declares that it plays role R of protocol P for any number of
sessions, up to a limit. An **initiator**: a node that starts one session in its own
role, choosing the other members from the offers.

```march
-- a server node: offers role Server of Echo, up to 64 sessions at once
let ap = Echo_Run.offer_Server(c, node, 64, fn (s, st) -> serve_one(s, st))

-- a client node: starts a session as Client, with some offering Server
match Echo_Run.initiate_Client(c, node, fn (s, st) -> ask(s, st)) do
  Ok(_) -> ...
  Err(SessionNode.NoOffer(role, why)) -> ...     -- nobody offering, or all refused
  Err(e) -> ...                                  -- as run_cluster's errors
end
```

Every role gets both functions *(choice)*: any role may initiate, and a protocol needs
no annotation saying which. In a session exactly one role initiates and every other
role is filled from an offer. A server/client protocol has servers offer and clients
initiate; a pipeline might have its first stage initiate.

### Names

- An offer registers its actor under **`"ap:<P>/<R>/<node_id>"`** *(choice)*: one offer
  per role per node. A second `offer_<R>` for the same role on the same node gets
  `Err(Taken)`. (Several offers of one role on one node would buy nothing: a node
  already runs many sessions.)
- The initiator lists candidates with `ClusterNode.names(node)`, keeping the names with
  prefix `"ap:<P>/<R>/"`. Visibility is the registry's: a binding held by a node SWIM
  declared dead is hidden, so a dead node's offer is not a candidate.

### Forming a session

1. **Mint the id.** `sid = <node_id>.<creation>.<counter>`, where `creation` is the
   node's incarnation number (ClusterNode already has one, part of every global pid)
   and `counter` is per node. Unique across the cluster and across restarts of this
   node, so a restarted or partitioned node can never be addressed by an old session's
   frames (they carry the old sid and are refused).
2. **Choose members.** For each other role, pick one candidate *(choice: the first
   candidate in a rotation seeded per initiator, so load spreads without coordination)*.
   Candidates on the initiator's own node, or on a node already chosen for another role,
   are skipped: cluster sessions still need every role on a different node (a node has
   no connection to itself). This limit stays documented, as today.
3. **Invite.** Send each chosen offer `SessionAP.Invite{sid, protocol, fingerprint,
   roster}` where `roster` maps every role to its node, and `fingerprint` is a hash of
   the protocol's steps generated with the protocol (`<P>_Msg.fingerprint()`), so two
   nodes built from different versions of a protocol refuse each other instead of
   exchanging messages the other cannot decode.
4. **Accept or refuse.** An offer answers `Accept{sid}` if it has room and the
   fingerprint matches, and starts that session's role at once (step 6); otherwise
   `Refuse{sid, reason}` (`"full"`, `"protocol differs"`, `"closing"`).
5. **Wait, bounded.** The initiator waits for every answer up to
   `MARCH_SESSION_CONNECT_MS` (20 s, the setup bound the standalone runner uses).
   - All accepted: the session forms (step 6).
   - Any refusal, or no answer by the deadline: send `Withdraw{sid}` to those that
     accepted, and retry that role with its next candidate. A role runs out of
     candidates: `Err(NoOffer(role, why))`, after withdrawing from the rest.
6. **Run.** Every member, the initiator included, runs the existing cluster session
   with that sid (`run_cluster`'s register / find peers / serve). The offer runs each of
   its sessions in its own task.

`Withdraw` must stop a member that accepted and is waiting in `find_peers` for the
initiator's registration: `run_cluster` gains a way to abandon a session still forming
(a flag in the party that the find loop checks), so a withdrawn member releases its
slot at once instead of timing out.

### What happens when a node dies

- **Before the invite:** its offer is hidden; not a candidate.
- **During the invite:** no answer, the deadline passes, the initiator tries the next
  candidate. (The initiator also watches the chosen offers' names: an `Unbound` on one
  counts as a refusal at once rather than at the deadline.)
- **After accept, before every member is serving:** the existing setup machinery:
  `find_peers` / `cluster_links` fail, the others see the dead node's connection end,
  the session is cancelled for everyone.
- **During the session:** the existing failure handling (and, with Part B, crash
  branches).
- **The initiator dies:** its invitees are waiting for it to register the session's
  name; they give up at the setup deadline, or at once if they watch its node's
  connection end (they do: `recheck_links`).

### Local restart

An offer's name is bound to its actor's pid, and ClusterNode unregisters a name when its
holder dies. A supervisor that restarts the offer's actor calls `offer_<R>` again, which
registers again, and the next invitation finds it. Sessions the old actor was in are
cancelled for their peers by the existing machinery. No cross-node restart coordination
is needed, which is Maty's point.

### Hosted offers (an actor hosting many sessions)

For a role hosted in an actor, the actor keeps one parked session per sid:

```march
actor ServerActor do
  state { sessions : LinearMap(String, Echo_Server.Parked_Server), ... }
  ...
end
let ap = Echo_Run.offer_hosted_Server(c, node, 64, pid_to_int(srv), start, deliver, cancel)
```

The callbacks gain the sid: `start(sid, s)`, `deliver(sid, s, from, msg, ep)`,
`cancel(sid, s, role, cause, ep)`. The actor's handler does `LinearMap.take_slot` on the
sid, `resume`, then `fill` with the next `await_*` or `vacate` after `finish`, the shape
[[2026-09-18-linear-map]] was designed for (its worked example, lines 183-201). This
needs a hosted variant of `run_cluster`, which does not exist yet (only the standalone
runner has `run_hosted`).

### Phases

- **A1: callback-mode access points.** `<P>_Msg.fingerprint()`; `SessionNode.offer` and
  `SessionNode.initiate` in the stdlib; generated `offer_<R>` / `initiate_<R>`;
  abandoning a forming session; `RunError.NoOffer`. Tests: a two-node scenario with one
  offer and two initiators in sequence (two sessions, distinct sids); a three-node one
  with two offers of the server role, one full (capacity 1), so the initiator's
  retry picks the other; a refusal for a fingerprint mismatch; an offer node killed
  between two sessions, restarted, found again (local restart); the initiator killed
  after invites went out (the invitees release their slots).
- **A2: hosted access points.** A hosted `run_cluster`; `offer_hosted_<R>`; the sid in
  the callbacks. Test: one actor hosting several concurrent sessions in a `LinearMap`,
  one of them cancelled, the others finishing.

### Open questions for Part A

- **Offer limits across restarts.** An offer's capacity is counted in its own process;
  a restarted offer starts at zero while its old sessions are being cancelled. Fine for
  now; noted.
- **Choosing by load.** The rotation ignores how busy an offer is. An offer could
  publish its free capacity (in its registry value, or answered on invite) later.

---

## Part B: crash branches

### The model

Following the ECOOP 2023 paper, adapted to what March already has:

- A protocol names the roles that **may crash**. Every other role is **reliable**:
  assumed not to crash, as every role is today.
- A receive from a role that may crash must say what happens if that role crashes
  instead of sending: a **crash branch**. The receiver *detects* the crash and takes the
  branch; this is the only place a crash is observed.
- Detection is the rule the runtime already enforces for cancellation (Maty's E-CancelH,
  the paper's Γ-⊙): a receiver takes the crash branch only when the sender is gone *and*
  nothing it sent is still queued. Messages sent before the crash are still delivered.
- Other roles learn of the crash only from messages in the crash branch, exactly as
  they learn which branch of a `choose` was taken.
- A reliable role that does fail anyway gets today's behaviour: the session is
  cancelled (Maty). The guarantees of crash branches assume only the declared roles
  crash, as the paper's do.

### Syntax *(choice)*

```march
@[endpoints]
protocol Logging do
  may crash C
  L -> I : Trigger
  C -> I : Read
    or crash do
      I -> L : Fatal
    end
  I -> L : Read
  L -> I : Report
  I -> C : Report
end
```

- `may crash C, D` is a declaration step, first in the protocol. Without it every role
  is reliable and no crash branch is allowed: every existing protocol means exactly
  what it means today *(choice: name the crashing roles rather than the paper's
  reliable ones, so that the default is today's semantics)*.
- `A -> B : T or crash do ... end` attaches a crash branch to a message step. The
  message's normal continuation is the rest of the enclosing sequence; the crash
  branch's steps are the continuation if A crashes, and that continuation *ends* the
  protocol (or, inside a `loop`, ends the loop, which is the protocol's last step). It
  does not rejoin the rest, which will usually involve the crashed role.
- In a `choose by A:` where A may crash, a branch labelled `crash` is the crash branch:
  `choose by C: read -> ... | done -> ... | crash -> ... end`.

### Well-formedness (new errors)

1. Every receive from a role that may crash has a crash branch. Error names the step:
   "C may crash, so `C -> I : Read` needs `or crash do ... end`: what does I do if C
   crashes before sending?"
2. A crash branch on a step whose sender is reliable is an error ("C is not declared
   `may crash`").
3. The crashed role does not appear in its own crash branch (it has crashed).
4. **Third parties must be told.** A role other than the detector that takes part in
   both continuations must be able to tell them apart from the detector's messages: in
   both, its first interaction is a receive from the detector, with different labels
   (the rule `choose` already has for a role that is not the chooser). Otherwise: "L
   cannot tell whether C crashed: the crash branch must begin with a message from I to
   L". This is the paper's full merge, restricted the way the generator's merge
   already is.
5. For `choose by C` with a crash branch: every other branch head goes to the same
   receiver (the detector). A choice whose branches go to different receivers has no
   single detector and is rejected (a later extension could lift this).
6. The existing checks apply inside crash branches (no self-sends, `stop` only in a
   loop, and so on).

### Projection

For `A -> B : T or crash do G′ end ; G`, with A declared `may crash`:

- **A (the sender):** sends `T`, continues as `G|A`. The crash branch does not exist
  for it (a crashed role does nothing).
- **B (the detector):** a receive from A with two outcomes: the message `T` (continue
  as `G|B`) or `crash` (continue as `G′|B`). This is an `LOffer` whose extra label is
  the crash.
- **Any other role:** the merge of `G|p` and `G′|p`: the same if they project the
  same, else an `LOffer` from B over the two first labels (rule 4).

This is the shape of a `choose` in which the detector is the chooser and the runtime
makes the choice, so the generator's choice machinery (state types, offers, the merge)
carries it; the new work is at the detector.

### Generated API

For the detector, a receive with a crash branch takes a second callback in place of the
`_or` cancel handler:

```march
Logging_I.recv_Read(s, st,
  fn (msg, st1) -> ...,                    -- the message arrived
  fn (crashed, st2) -> ...)                -- C crashed: st2 is the crash branch's state
```

`crashed` carries the role and the cause (the same information a cancel handler gets
today). Unlike a cancel handler, the second callback gets a *live* state and the
conversation goes on. The event API (`Parked_<R>`, `resume`) gains a
`Crashed_<ctor>(role, cause, next)` alternative in `Received_<R>`.

### Runtime

- `Session.Ops` gains `on_crash : Int -> Int -> (Int -> String -> Int -> Int) -> Int`
  (endpoint, the role that may crash, the crash continuation). The generated receive
  installs it alongside the message handler.
- `SessionNode.check_waiting`: when the endpoint waits on a role that is gone with
  nothing queued, and a crash continuation is installed for that role, run it (in the
  endpoint actor's turn, like a delivery) instead of cancelling. The endpoint stays
  live; no Cancel frame goes out.
- Messages to the crashed role are discarded (already the case for a gone role).
- A crash branch is not for a *reliable* role, so the cancellation path is unchanged for
  those, and for a protocol with no `may crash`.

### Phases

- **B1: syntax, checks, projection, callback API, runtime.** Parser (`may crash`,
  `or crash do ... end`, a `crash` branch in `choose`); AST; the well-formedness errors
  above (desugar or typecheck, beside the existing protocol checks); projection in
  `desugar_endpoints.ml`; the generated receive with a crash callback; `on_crash` in
  `Session.Ops` for every transport (the in-process ones included); `check_waiting`.
  Tests: generator unit tests; types corpus fixtures (accept: the logging protocol;
  reject: each well-formedness error); in-process goldens; two-node scenarios with C
  killed before and after sending `Read` (before: I takes the crash branch and L gets
  `Fatal`; after: the `Read` is still delivered, the protocol continues until it next
  waits on C).
- **B2: the event API and cluster mode.** `Crashed_*` in `Received_<R>`; hosted and
  cluster runners (cluster mode detects through SWIM and the data connection's end,
  which already reaches `check_waiting`).

### Open questions for Part B

- **Crash branches inside loops.** Ending the loop on a crash (and so the protocol) is
  the simplest reading; continuing the loop without the crashed role would need the
  loop body to be re-projected without it. Start with "ends"; revisit if a real
  protocol needs the other.
- **Several roles crashing.** Each crash branch is a protocol among survivors, and may
  itself contain crash branches for other `may crash` roles, so nested failures are
  expressible. Whether the generated state names stay readable at depth two is a
  question for B1's tests.
- **Typecheck's own projection.** `typecheck_session.ml` projects protocols for the older
  `Chan(Role, Proto)` channel types. B1 decides whether that path learns crash branches
  or refuses a protocol that has them (refusing is the smaller step).

---

## Order of work

A1, A2, B1, B2, each its own PR with its records (`specs/progress/`, CHANGELOG, the
guide). Part B does not depend on Part A; it is after it only because the user asked
for access points first.
