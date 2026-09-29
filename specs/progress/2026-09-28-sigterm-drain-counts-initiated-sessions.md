# `[P2]` The SIGTERM drain counts only offer sessions

**Filed** 2026-09-25 from the distributed-deploys review's unconfirmed item 3.
Confirmed from the code, which is deterministic here: `Topology.running`
(stdlib/topology.march) sums `active` over the node's open and draining offers and
has no other input. Sessions a hook's task started with `initiate_R`, or a
hand-written `cluster_R`, are not counted, so a pool that serves no role exits 0 at
once on SIGTERM and cuts its in-flight initiated sessions. The step-3 progress entry
says it "exits 0 once no session runs", with no listed deviation.

**Fix.** Count initiated sessions too, e.g. a per-node counter that
`SessionNode.initiate` maintains (session_node.march: coordinate with its owner),
and add a test: a pool that serves no role, initiates a long session from its hook,
gets SIGTERM, and must wait for it.

## Fixed 2026-09-28

**Cause.** As filed: `Topology.running` summed only `OfferCount.active` over the
node's open and draining offers, so `drain_wait` saw 0 on a node whose sessions
were all ones it initiated and exited at once.

**Fix.** `SessionNode` keeps a per-node counter (`Vault.open("session_node_initiated_"
<> node id)`, key `n`, atomic `Vault.incr`) that `initiate` (from its invitations on,
so a session still forming counts), `run_cluster` and `run_cluster_hosted` raise on
entry and lower on return; `SessionNode.initiated(node)` reads it. An offer's sessions
go through the private `*_with` runners and stay counted by the offer alone, so
nothing is counted twice. `Topology.running` adds `initiated`, which feeds both the
SIGTERM drain wait (soft report, hard exit 1, unchanged) and the status file's
`running` line. A body that panics skips the decrement; the drain then waits out its
hard deadline, which bounds it.

**Test.** `test/two_node/drain_initiated`: node-b serves no role, installs
`drain_on_signal`, initiates one Echo session whose server answers after 2 s, and gets
SIGTERM mid-session. Red before the fix (node-b printed "drained" without
"Client: got 70"); green after. A throwaway variant with a 6 s answer and a 1.5 s hard
deadline showed the soft report and the hard exit 1 naming "1 session(s)".
