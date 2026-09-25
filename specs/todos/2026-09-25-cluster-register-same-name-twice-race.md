# [P2] `ClusterNode.register` accepts the same name twice; `topology_place` golden encodes the race

**Logged:** 2026-09-25

## Symptom

`test/native/topology_place` fails its golden about one run in fifty on Linux
(CI runs 36100461806 and 36110008640 of PR #648, `test (ubuntu-24.04, rest)`):

```
-offered: [Echo.Counted, Echo.Server]
+offered: [Echo.Server]
 marker registered
 topology: Echo.Server: its offer or hosting actor died; offering it again
-re-offered after its offer died
+never re-offered
```

Reproduced in the `march-amdr-repro` container (arm64 glibc) with the compiled
fixture run in a loop: origin/main 1 failure in 90 runs, the PR's tree 2 in 75;
macOS 0 in 23 (including 12 under eight CPU hogs). Not a regression of #648.

## Mechanism (confirmed with prints at every step)

`h_register` (`stdlib/cluster_node.march`) decides `Taken` against the node's
*view* (`h.names`), which the node actor fills only when it processes the
`Register` message. Two back-to-back local registrations of one name both
return `Ok` unless the node actor gets a turn in between; when both succeed the
second `Register` silently overwrites the first binding, and the first pid's
death then unregisters a name the second pid holds.

The fixture's roles `Echo.Server` and `Echo.Counted` both open
`Echo_Run.offer_Server`, so they register the same offer name
(`ap_prefix(proto, role) ++ node_id`). The passing golden is the interleaving
where both registrations slip in before either is visible. The failing one:

1. The node actor runs between the two: `Echo.Counted`'s register gets
   `Taken(holder = Echo.Server's worker)`, `offer_with` turns it into
   `AlreadyOffered`, `open_role` drops it silently; every later tick retries
   and is refused the same way.
2. After `kill(before)` the name is released (`RegWatch` → `LocalDown` →
   `Unregister`). On the next tick `reconcile` visits `Echo.Server` first
   (retire), then `Echo.Counted`, whose retry now succeeds and takes the name.
   From then on `Echo.Server`'s re-open is `Taken` by `Echo.Counted`'s worker
   on every tick, so `wait_reoffered` times out: `never re-offered`.

## What to do

1. Make `h_register` refuse a name with a *pending* local registration (record
   the binding in the view synchronously, or keep a pending set), so two
   concurrent local `register`s of one name cannot both succeed, and stop a
   pid's death from unregistering a name another pid holds. Pin both with a
   stdlib test.
2. Give the fixture's `Echo.Counted` role an offer of its own (a second
   protocol, or a distinct role) so the golden no longer depends on two roles
   sharing one name; regenerate `topology_place.expected`.
