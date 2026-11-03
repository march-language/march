# `[P1]` A cluster session could hang when its node pair was redialled while it formed, and nobody read a session frame's DELIVERY_FAILED

## Fixed 2026-10-12 (`stdlib/session_node.march`, `stdlib/cluster_node.march`)

**Found with per-node traces** (each party's register/link/emit/receive/peer-gone/
cancel/result, and each node's link install/drop/discard, `data_closed`, refusal and
DELIVERY_FAILED; the cert_order investigation's approach). `session_churn` under ASan
in the `march-ci-ubuntu-step6b` container (`--cpus 2`) hung this way:

1. Session `churn62`: node-b's role B registered, found A, formed on pair gen 2 and
   waited for A's message. Node-a's role A had registered at the same moment but had
   not found B yet (registry gossip under ASan took seconds).
2. Node-a's SWIM declared node-b dead ("suspect timeout") and dropped gen 2. Node-b's
   reader saw the close, and B's session failed ("connection lost") at once. B's
   Cancel went into gen 2's queue, which was dead: lost. B unregistered and moved on.
3. The nodes redialled (gen 3) within 200 ms. Node-a's A then found B's endpoint (the
   name was stale: the registration had reached node-a, the unregistration had not),
   linked over gen 3, formed and sent its message.
4. Node-b refused it: "no route to pid 130 for SessionNode.Deliver#churn62" (the
   endpoint was gone), answered DELIVERY_FAILED. Nothing on node-a read it (a session
   frame's refusal went to `on_delivery_failed`'s one node-wide handler, unset here,
   and a session's seqs are per party anyway). A waited for B's reply for ever, and
   node-a never reached the next session. Node-b failed its next sessions for want
   of A ("no endpoint registered for role 1"), finished, and node-a hung: the
   harness's "timed out waiting for node-a to exit".

So the frame was not lost on the wire, and no route pointed at the old link: the party
that ended told its peer only over a pair that no longer existed, and the peer's node
refused the one frame that would have revealed it, with nobody listening. The
todo's crossed-dial candidate is the same class: a party on a pair that its node drops
as "replaced" while the peer's node never installed that pair, so the peer's party,
on the surviving pair, hears nothing.

**Fix, three parts.**

- **A session frame's DELIVERY_FAILED fails the session that sent it.** Each cluster
  party gets a key from a process-wide counter and sends every frame under
  `ClusterNode.session_seq(key, n)`, a negative seq. A DELIVERY_FAILED with a negative
  seq goes to the handler that party installed with `ClusterNode.on_session_failed`
  (removed by `off_session_failed` when the party ends), with the refusing node's id.
  `slot_refused` reports every role on that node gone ("frame refused by node <id>:
  <reason>") and ends its link, as a closed connection does, so a party waiting on
  that role is cancelled. Other seqs still go to `on_delivery_failed`; session
  refusals no longer reach it (they used to, with seqs that meant nothing to it).
- **A party whose node's pair to a peer ends tells that peer over the next pair.**
  `peer_node_closed` (from `on_peer_closed` and `recheck_links`) now also spawns
  `notify_redialled` for each peer that had not ended: a task that waits (up to the
  setup time, `connect_ms`) for the node to have a pair to that peer's node other
  than the old one, then sends the peer's endpoint a `SessionNode.Cancel` for this
  role. It touches none of the party's tables, which may be closed by then. A peer
  still forming holds it until it is ready (`Early`), then fails.
- **A dropped pair leaves the link mirror at once.** `perform`'s `Drop` removes the
  pair from `h.links` itself, before shutting it, instead of at the `mirror` after
  the step: a session forming on another scheduler could take the dying pair's queue
  from `session_queue_for`, have its close told before it installed its handler, and
  then pass `recheck_links` against the stale mirror.

Docs: docs/choreography.md (when a cluster peer is gone, and the redial limitation),
docs/clustering.md (`on_delivery_failed` no longer hears session frames).

**Rates** (`march-ci-ubuntu-step6b` container, `--cpus 2`, prebuilt nodes,
`ASAN_OPTIONS=detect_leaks=0:halt_on_error=1`, SIGTERM timeouts):

| scenario | before (origin/p1/cert-mode-session-hang) | after |
|---|---|---|
| `session_churn`, ASan | 1 of 8 hung; traced, with 2 busy loops, 1 of 25 (plus one OOM kill, below) | 0 of 12; 0 of 10 with 2 busy loops |
| `session_churn`, plain | - | 0 of 10; macOS 0 of 5 |
| `session_refused` (new), plain | 5 of 5 hung | 0 of 15 failed; macOS 0 of 5 |
| `session_refused`, ASan | - | 0 of 15 failed |
| `session_redial` (new), plain | 2 of 6 hung (and 1 of 1 traced) | 0 of 20 failed; macOS 0 of 5 |
| `session_redial`, ASan | - | 0 of 20 failed |

Every other session scenario (`cert_order`, `cluster_sessions`, `protocol_evolve`,
`hosted_protocol_change`, `cluster_ap*`, `control_*`) passed once each, ASan and plain
(`protocol_evolve` skips itself under ASan), except `control_certs` plain: "b died",
3 of 8 after and 2 of 8 on the base, the same race in the scenario's own check (node-c,
revoked and cut off by then, declares node-b dead by suspect timeout before the grep of
c.out runs). Not this change.

**Regression tests.** Two new two-node scenarios, both in shared-secret mode:

- `session_refused` (deterministic): node-b binds role B's registry name to an
  actor that is no session endpoint, the state step 3 above left; node-a's A finds
  it, forms and is refused. It must fail, naming the refusal, while node-b stays
  up (node-b stopping would end the session as "connection lost" and hide a hang),
  and a normal session must then finish. Before the fix: hung in 5 of 5 runs.
- `session_redial` (forced redial mid-session, steps 1-4 above on cue): A registers,
  node-a is SIGSTOPped before A finds B, B forms against it, node-b declares node-a
  dead and drops the pair (B fails), SIGCONT, the nodes redial. A must fail
  (B's Cancel over the new pair, the refusal, or its setup giving up), never hang,
  and a fresh session over the new pair must finish. Before the fix it hung
  whenever A found B's stale name (2 of 6 plain runs); when A never finds it, its
  setup gives up after 30 s.

One more `session_churn` failure seen while tracing was not this bug: node-b went
silent for 14 s and its port then refused connections (the process was gone, no
sanitizer report), with a second ASan loop sharing the Docker VM's 7.6 GB; node-a
then failed every remaining session after its 30 s setup bound and overran the
harness timeout. Memory pressure (the VM's OOM killer), not a session hang.

Not yet re-run in the multi-host lab (`LAB_AUTH=secret scripts/lab/run.sh deploy`),
whose one shared-secret stall this most likely was: its `deploy` scenario still
reports any session that never ends.

## The original report

Filed as specs/todos/2026-10-12-lab-shared-secret-session-stall.md: "Shared-secret
sessions can still hang when a node pair is replaced (lab, session_churn under ASan),
and session frames whose DELIVERY_FAILED nobody reads".

Split out on 2026-10-12 from the certificate-mode offer-to-offer hang (now fixed:
specs/progress/2026-10-12-cert-mode-offer-to-offer-session-hang.md). That fix explains
the certificate-mode stalls: a party's certificate check of a peer whose node it was not
linked to yet. It does NOT explain the one shared-secret stall the lab saw, because no
certificate check runs in shared-secret mode (`ClusterNode.authorize_peer` is always
`Ok` there).

## The stall

`LAB_AUTH=secret scripts/lab/run.sh deploy` (docs/lab.md), 2026-10-05, main at
53d66f068: after ~90 sessions, 4 stayed `running` on the Ledger's offer (lab-4) and on
Stock offers for good (started 91, finished 85, refused 2), with nothing in any log;
the Ledger actor logged no dropped message and no cancellation. Seen once. Not
reproduced on one machine: `cert_order` is certificate-mode only, and its shared-secret
variants passed.

Not yet re-run on a main that has the 2026-10-12 fix. Do that first: the fix also
covers a party that gives up after registering for want of a LINK to a peer's node
(`cluster_links`, 30 s): it now cancels toward the peers that found it, where before
they waited for ever. That path exists in shared-secret mode too.

## Candidates

- **A duplicate link replaced under a live session.** When two nodes dial each other at
  once, each keeps the pair dialled by the lower node id (`ClusterNode.keeps_new`). The
  side that installed the losing pair closes it as "replaced" and its sessions see
  `PeerGone` for the other node's roles. The other side, if it never installed that pair
  (`Discard`), tells its sessions nothing. A frame queued on the losing pair is lost,
  and a receiver waiting on it waits for ever. The sender's role does not fail either
  if it is not waiting on that peer. The 2026-10-12 cert_order traces (eight busy
  loops, two CPUs) never showed a crossed dial between the work nodes. But
  `two-node/session_churn` under ASan (shared secret, no busy loops, the same
  container) hangs this way: 3 of 8 runs on main and 3 of 8 with the 2026-10-12 fix,
  every failure the harness's "timed out waiting for node-a to exit". Under ASan,
  SWIM suspects node-b, and the pair to it ends and is redialled. Node-a's cluster
  session fails ("cancelled while waiting on role B: connection lost", "... node
  node-b dead: suspect timeout", once "... replaced"). Node-b never finishes its
  cluster loop and never prints again, and node-a then waits for it in the direct
  phase. So node-b's party never learned that its session ended. Every session
  captures a pair's queue once, when it forms (`cluster_links`), so a Cancel sent
  after that pair ended is lost, and node-b's side of the old pair may not have
  told its sessions anything. The same class showed once in cert_order after the fix
  (1 of 30 plain runs with 8 busy loops on 2 CPUs). Node-a's SWIM declared node-c
  dead ("suspect timeout") while it was alive. Three sessions failed and were
  retried, and one session in round 3 then hung. Not yet traced: instrument it as the cert_order
  investigation did (per-node `link install/drop/discard`, `data_closed`,
  `peer_gone` and `emit` lines) before changing anything.
- **DELIVERY_FAILED is dropped for session frames.** The data reader answers a frame
  it cannot route (no route for the pid, a stale creation) with DELIVERY_FAILED, but a
  cluster session never reads it. `ClusterNode.on_delivery_failed` has one node-wide
  handler, and SessionNode's seqs are per party, not per node. So a frame to an
  endpoint that is gone is lost without a word, and the sender only learns of it if
  that peer's node closes. The certificate-mode hang showed exactly this: node-c
  refused every Deliver and Cancel for the dead Ledger party ("not authorized: raw
  send", since no session route remained), and node-b's session never noticed. Routing
  that failure back to the sending party would turn any remaining "lost frame" hang into
  a failure. That is the property the lab's "every started session ends" check wants.

## Repro

- One machine: in the `march-ci-ubuntu-step6b` container (`--cpus 2`),
  `MARCH_SANITIZE=1 ASAN_OPTIONS=detect_leaks=0:halt_on_error=1 scripts/two-node.sh session_churn`,
  about 3 runs in 8.
- Lab: `LAB_AUTH=secret scripts/lab/run.sh deploy`, long run; the scenario's "every
  started session ends" check reports `FINDING: n of m sessions never ended`.
