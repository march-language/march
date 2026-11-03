# Clustering chapter restructured for first readers (2026-10-13)

`specs/lang/clustering.md` (rendered as `docs/clustering.md`) got the frame treatment used
for the refinement-types and hot-code-reload chapters the same day: section bodies kept,
the frame and order changed.

- a three-paragraph opener (what a cluster is, in actor terms; `ClusterNode` as the
  assembled node most programs start with; the layer cake underneath), which absorbs the two
  old blockquotes ("This page is an API reference, not a runnable quickstart" and "New to
  March concurrency? Don't start here") as plain prose; then an **On this page** index
  grouping every section into Start here, The layers, Sending across nodes, Assembling it
  by hand, and Status;
- **When to use it**: a goal-to-API table (join and watch, typed messages, remote monitors,
  RPC, choreography over the node, certificate mode, no-socket testing) and the two things
  the cluster is not (a global name is not a lock; links are not encrypted);
- **How it fits with the rest of March**: actors and supervision (`GlobalPid` creation,
  `GlobalRegistry` as distributed `Actor.register`), capabilities (`Cap(ClusterNode.Live)`;
  certificates as the cross-node counterpart), choreography, hot code reload (schema hashes,
  reader tasks moving epochs), topology and certificates, observe (no cluster section yet);
- sections regrouped so the two actor-message sections (`NodeSend`, `Node.send`/`@[remote]`)
  come before the RPC pair, since they are the common path; `See also` gains choreography,
  certificates and topology;
- a pre-existing dead in-page link (`#starting-the-listener`, no such heading) now points at
  `#the-handshake-in-code`; two phrase edits ("Here's the whole arc", the layer-cake
  sentence).

All five inbound anchors (`#authorization`, `#typed-remote-messages-nodesend-and-remote`,
`#remote-calls`, `#a-running-node-clusternode`, `#authentication--handshake`) are unchanged.
Every anchor checked; no inline-code token dropped; `scripts/check-docs.sh` passes.
