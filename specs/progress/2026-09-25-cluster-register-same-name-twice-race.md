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
2. ~~Give the fixture's `Echo.Counted` role an offer of its own~~ Done in #646
   (commit 4a450eadc): `Echo.Counted` now offers its own `Tally` protocol, and
   the golden is unchanged. An independent run with a per-role-protocol fixture
   in the `march-amdr-repro` container (60 runs, 12-way parallel) went from 4/60
   failures to 0/60. With a trace in `Topology.open_role`, `AlreadyOffered`
   never happened after the change, and every passing run before it had
   BOTH roles' `offer_Server` return `Ok` for the one name, confirming item 1.
   Item 1 is what remains; no test exercises it any more, so its fix needs its
   own stdlib test.

## Resolution (2026-09-25)

Item 1 fixed in `stdlib/cluster_node.march`:

- `CnHandle` gains `claims : Vault(Int)`: local registrations sent to the node
  actor but not yet processed there (name -> pid). `h_register` now calls the
  public `ClusterNode.reserve(names, claims, node_id, creation, name, pid)`,
  which takes the claim with `Vault.put_new` (atomic) and only then checks the
  view. A name claimed by a different local pid is `Err(Taken(claimant))`. A
  refused register drops the claim it took. The same pid registering again is
  still allowed.
- The node actor's `Register` handler releases the claim (`release_claim`, a
  compare-and-delete on the pid) only after `step_io` has mirrored the outcome
  into `h.names`, on every path (bound, refused as `Lost`, pid already dead).
  So a racing register always sees either the claim or the binding.
- The death half: `core_local_down` already unregistered only the names whose
  `regs` entry is the dead pid. The "first pid's death unregisters a name the
  second pid holds" was the second pid's phantom `Ok`: its `Register` had been
  refused in the actor (`core_register` saw the first binding in `vis`), so it
  never held the name. With the synchronous `Taken`, the second caller now
  knows that.

Tests (`test/stdlib/test_cluster_node.march`, "local registration races"): a
back-to-back second register of a pending name is `Taken` by the first pid,
the same pid may re-register, a refused register leaves no claim,
`release_claim` leaves another pid's claim alone, and (core level) a pid's
death releases only its own names while a second pid's refused `Register`
never becomes the binding. A live node cannot run in the interpreter (the
accept loop's `task_spawn` runs eagerly and blocks the runner), so the tests
drive `reserve` over the two Vaults directly.

RED check: with `reserve` reduced to the old view-only check, the three claim
tests fail (41 tests, 3 failures). The core death test passes on both trees
because that rule was already correct. End to end, a scratch compiled program
on a live node (two back-to-back `register`s of one name, then the first pid
killed) printed `r1=Ok r2=Ok` on every pre-fix run and `r1=Ok r2=Taken(2)`
with the fix.
