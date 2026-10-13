# `[P1]` Without a control-plane leader, every node grows by ~13k heap objects a second

**FIXED 2026-10-12.** Not the control plane: the node itself. Two compiler bugs on every
cluster node's hot path, plus one allocation per Agent retry.

## Repro without the lab

Three nodes of the control-plane test app on one machine (the `control_plane` scenario's
lib.sh), sampled every 10 s on the observe socket (`MEM`'s `live_objects`):

| build | leader, after a release | no leader |
|---|---|---|
| 53d66f068 (the lab's) | ~4,600/s (standby), ~15,000/s (leader) | ~3,200/s per node |
| main 0c50b9a4c | ~140/s, ~260/s (leader) | ~65/s per node |
| this fix | 0 | ~0.2/s (1 per Agent retry; 0 after the third fix) |

The leaderless state was made by re-reading the topology with #808's pin check disabled (a
scratch stdlib), and, more simply, by giving no node the candidate label: every Agent then
retries for ever. Most of the lab's 13k/s was already gone on main (the record, closure
and crypto-builtin leak fixes of 2026-10-06..12); the rest is below. Growth was the same
with and without a leader, and on a node with no roles, because it is per cluster frame.

## What the 13k/s was made of

`test/two_node/control_leaderless_flat` (below), node a's growth over 30 s, built at a
series of main commits; the lab's commit grew 2,285 objects/s here (the lab's four nodes,
roles and traffic made it ~13k/s; the shares are what carries over):

| step | objects/s | share of 2,285 |
|---|---|---|
| 53d66f068 (lab) .. 33527ba9e | 2,285 → 2,283 | 0 (#785 and the rest: no change here) |
| #808 (3926df302): char builtins borrowed (`char_to_int` per byte of every Msgpack string), dropped closures' captures, colliding-type shallow drop | → 629 | 72% |
| #812 (7b1db5973): crypto builtins borrowed, record ownership drops | → 533 | 4% |
| trains a-d, #838 (0cdea7c35): session ops, wildcard binder, killed-actor state | → 395 | 6% |
| trains i, k, #873 (5002b4950): mixed-tail aggregate drop | → 216 | 8% |
| train m, #886 (6044af7e1): reused closures' captures | → 63 | 7% |
| this branch, fix 1 (group-bb's partial-release drop): `CtlFrame` old state | → 8.5 (node a: 298/30 s) | 2.4% |
| this branch, fix 2: `hmac_sha256_bytes` | → 0.2 | 0.4% |
| this branch, fix 3: Agent retry | → 0 | 0.01% |

So ~97% of the lab's growth was already fixed on main by 2026-10-12 (the shares inside
#808 were not split further); this branch removes the last ~3%, which on main was still
~65 objects/s per node, ~250/s on a leader.

## 1. A handler with a nested match leaked its old state (Perceus)

Allocation-site tracing (`--rc-trace`, `MARCH_TRACE_GC=1`, `scripts/gc-trace-report.py`,
live objects grouped by site) showed ~1 `CnState` (192 bytes) per frame still live, with
everything only it held: the registry's visible-names map, the dial map, the SWIM
driver's lists. Each was held by a 40-byte actor-state record allocated at the top of
`ClusterNodeActor`'s `CtlFrame` handler, `let state = { h = $sf_h, st = $sf_st, .. }`,
and never released.

`CtlFrame`'s body has a nested pattern (`Ok((st1, c)) -> ..`), and the match compiler gives
it a non-exhaustive arm, `_ -> dec_rc state; panic(..)`. Perceus's aggregate scope-end
drop (`Perceus_core.drop_agg_at_tails`) walks `let $result = <body> in <write-back>` and
stopped at the first scope that released `state` on ANY path (`releases_var`), on the
reasoning that "this path already let go of it": the panic arm made the whole body count
as released, and the arms that end in `step_io(..)` kept their reference. Every message
to such a handler leaked the old state record, and every frame a node reads goes through
`CtlFrame`.

Fix: the same bug as group-bb's `ClusterNode.CtlWriter` finding
([2026-10-12-perceus-agg-drop-partial-release.md](2026-10-12-perceus-agg-drop-partial-release.md),
commit "fix(perceus): drop an aggregate on the paths a statement or let value does not
release it"), cherry-picked onto this branch with the rest of that sweep rather than fixed
twice: a let whose value releases the aggregate on some paths, with the aggregate dead
after it, now gets the drop on each of its other paths. A first fix written here for
`CtlFrame` (requiring a release on every path before stopping) did the same; the
cherry-picked one alone makes every leg of this branch's tests flat, so it was dropped.

## 2. `hmac_sha256_bytes` was an indirect call

The remaining ~5 objects a second were sealed frames: a `Bytes` and its `String` from
`Bytes.concat` in `NetFrame.mac_tag`, allocated and never touched again. `mac_tag` compiled
to `call_ptr hmac_sha256_bytes(key, msg)`: the builtin was missing from
`Defun.builtin_names`, so defun treated it as a function value, and an indirect call
consumes its arguments while the C entry only reads them (its borrow-table entry from
specs/progress/2026-10-06-crypto-builtins-borrow.md never applied). Every frame sent or
received leaked its MAC input. Fix: listed with its neighbours, and so are `md5` and
`stdlib_hmac_sha256`, missing the same way (both in the borrow table and the typechecker).

## 3. One object per Agent retry

With no leader the Agent's `initiate_Agent` fails every 5 s with "no access point is
registered", and each attempt spawned an `ApInbox` actor, two tables and a route before
finding no offer. A killed actor's state record is not released in a `--hot-reload` build
(specs/progress/2026-10-06-killed-actor-state-leak.md keeps that deliberately), so each
attempt left one. `SessionNode.initiate_counted` now answers `NoOffer` before minting a
session when the first role to fill has no offer name registered at all, which is exactly
when `fill_roles` would have failed on it at once with the same error.

## Tests

- `test/native/actor_nested_match_state_leak_probe.march` (`--opt 2`): an actor handler of
  `CtlFrame`'s shape, both paths, 5,000 messages each; the same with the state's record
  shared with a second field before each replacement, read back at the end (a release
  must be a decrement there, not a free); 5,000 `hmac_sha256_bytes` and `md5` calls. Red
  with either fix reverted, on the legs it covers (3, 2 and 2 objects a message; 2 a MAC,
  1 an md5).
- `test/two_node/control_leaderless_flat`: three nodes of a `[control]` topology app, no
  candidate label anywhere, so there is never a leader; each node counts its live objects
  over 30 s after a 10 s warm-up and must stay under 100. Main: 1,981 on node a (~66/s);
  with fix 1 only: 210-298; with fixes 1 and 2: 6 (one per retry); all three: 0 (also 0
  under ASAN on Linux).

## The verifier's view

`march --verify-tir` with `MARCH_VERIFY_TIR_LEAKS=1` over the scenario's app (private
`HOME` and CAS, so nothing came from a cache) reports exactly the seven findings of
[2026-10-12-distributed-stdlib-leaks-from-verifier-sweep.md](../todos/2026-10-12-distributed-stdlib-leaks-from-verifier-sweep.md)
and nothing else. None is on the leaderless path: CtlWriter's `Err` arm (a failed write),
`start_writers` and `on_accepted` (once per link), `agent_apply_certs_recording` (a cert
order), `SessionNode.candidates` (an initiate that finds offers), `Session.ip_step`
(in-process sessions). The scenario measures 0 with all of them still there.

## Not covered here

The lab itself was not re-run (its containers were in use by another session). The
simultaneous-restart burst
([2026-10-05-lab-simultaneous-restart-memory-burst.md](../todos/2026-10-05-lab-simultaneous-restart-memory-burst.md))
is a separate finding; its "then went on at the usual ~11k objects/s" part is this leak.

---

Found 2026-10-05 by the multi-host lab (docs/lab.md), main at 53d66f068, four containers,
shared-secret mode, after the first `forge deploy --via ssh`.

After the deploy no candidate leads (the topology push closes `Ctl.Control`,
[2026-10-05-lab-topology-reread-closes-ctl-control.md](2026-10-05-lab-topology-reread-closes-ctl-control.md)).
With the app's own traffic paused (`lab-traffic` = 0: no session started, none running),
every node kept growing, live heap objects (`live_allocs()`, from the lab's probe) and
RSS sampled every 30 s:

```
t=1791218965 lab-1=12810123/832784KB lab-2=9530406/621044KB lab-3=10775419/695152KB lab-4=14195622/910500KB
t=1791218995 lab-1=13196642/858612KB lab-2=9918904/654880KB lab-3=11164757/725736KB lab-4=14584845/940468KB
t=1791219026 lab-1=13582781/895452KB lab-2=10306890/695812KB lab-3=11555396/765472KB lab-4=14974333/978324KB
t=1791219056 lab-1=13970868/938476KB lab-2=10695670/739216KB lab-3=11945340/808548KB lab-4=15364514/1021436KB
```

About 386k objects and 35-45 MB per node per 30 s, the same on the ingress node (no
roles) as on the work nodes. A node reaches 1.5 GB about 20 minutes after it starts.

## Likely cause

With no leader, each node's Agent loop (`ctl_agent_loop`, lib/desugar/control_wiring.march)
tries `Ctl_Run.initiate_Agent` every 5 s (backoff capped at 5000 ms) and gets
`NoOffer`. A failed initiate leaves its session tables behind
([2026-10-01-session-node-vault-tables-leak.md](2026-10-01-session-node-vault-tables-leak.md);
#785 closes them, not merged when this was measured), but one attempt per 5 s would mean
~65k objects per attempt, more than the ~40k #785 reports for a whole session. Measure
with the attempts disabled before concluding; the placement loop and the Agent's report
(`NODE_STATE` and `PINS` read every poll) run every tick too.

## Repro

`scripts/lab/run.sh deploy`, then `echo 0 > /var/lib/march/lab_app/lab-traffic` on lab-1
and sample `/var/lib/march/lab_app/lab-probe` on each host. `scripts/lab/run.sh soak`
reports the same growth with traffic.
