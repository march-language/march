# [P2] `ClusterNode.register` accepts the same name twice; `topology_place` golden encodes the race

**Logged:** 2026-09-25

## Symptom

CI run 36100461806 (`test (ubuntu-24.04, rest)`, PR #648) failed the
`test/native/topology_place` golden:

```
-offered: [Echo.Counted, Echo.Server]
+offered: [Echo.Server]
 marker registered
 topology: Echo.Server: its offer or hosting actor died; offering it again
-re-offered after its offer died
+never re-offered
```

The same commit passed the fixture locally 3/3 through dune, 8/8 and 12/12 under
eight CPU hogs; the branch's previous CI run and every neighbouring run of main
passed it. One occurrence, on a heavily loaded runner.

## Mechanism (read from the code, not reproduced)

`h_register` (`stdlib/cluster_node.march`) decides `Taken` against the node's
*view* (`h.names`), which the node actor fills only when it processes the
`Register` message. Two back-to-back local registrations of one name therefore
both return `Ok` unless the node actor gets a turn in between.

The fixture's three roles (`Echo.Server`, `Echo.Gpu`, `Echo.Counted`) all open the
same `Echo_Run.offer_Server`, so `Echo.Server` and `Echo.Counted` register the
same offer name (`ap_prefix(proto, role) ++ node_id`). The expected
`offered: [Echo.Counted, Echo.Server]` line is the outcome where the second
registration slips in before the first is visible; when the node actor runs
between them (a preemption tick, a slow runner) the second gets
`Err(Taken)`, which `offer_with` turns into `AlreadyOffered` and `open_role`
drops silently. The `never re-offered` line is the same race on the re-open
after the kill (5 s budget, 200 ms ticks, the dead worker's name released
asynchronously by its `RegWatch`).

## What to do

1. Make `h_register` refuse a name with a *pending* local registration (record
   the binding in the view synchronously, or keep a pending set), so two
   concurrent local `register`s of one name cannot both succeed. Pin it with a
   stdlib test.
2. Give the fixture's `Echo.Counted` role an offer of its own (a second
   protocol, or a distinct role) so the golden no longer depends on two roles
   sharing one name; regenerate `topology_place.expected`.
