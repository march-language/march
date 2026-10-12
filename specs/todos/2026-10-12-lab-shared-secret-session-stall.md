# `[P1]` Shared-secret sessions can still hang when a node pair is replaced (lab, session_churn under ASan), and session frames whose DELIVERY_FAILED nobody reads

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
