# A crash branch over the cluster node service is pinned by a scenario

Closes the second out-of-scope item of [[2026-09-20-crash-branches-b1]]: "Cluster mode is
untested with crash branches; the same `check_waiting` runs there, so a SWIM-declared death
should take the branch, but no scenario pins it."

It does take the branch. `test/two_node/cluster_crash_branch` is the witness.

## The scenario

Three nodes on one cluster, running the Logging protocol of the design's Part B
(`specs/2026-09-19-choreography-access-points-and-crash-branches-design.md`), entered
through `cluster_<Role>` rather than `run_<Role>`:

- node-a is the seed and hosts L, which offers over Read (normal) and Fatal (crash branch);
- node-b hosts I, the detector, whose `recv_Msg_C_I_1` carries a crash callback;
- node-c hosts C, the role declared `may crash`. It reaches its send state, prints, and is
  SIGKILLed there.

I is waiting on C with nothing queued and a crash continuation installed, so
`SessionNode.check_waiting` runs the continuation instead of `cancel_endpoint`: I sends L
the Fatal and closes. All three entry points return, nothing is cancelled, and no Cancel
frame goes out.

What makes this different from `crash_before_send`, which pins the same protocol on the
direct transport, is where the death comes from. Over a cluster node there is no
per-session connection to drop: node-c going is reported by the node itself, through SWIM
or a refused redial, and reaches the session as a peer-gone event. That is a different
route into the same `check_waiting`, and it was the untested one.

## Proving the scenario is not vacuous

Both crash-path lines (`I: role 3 crashed`, `L: got Fatal(...)`) are printed only from the
crash callbacks, so a session that failed to take the branch cannot produce them. That was
checked rather than assumed, by perturbing the mechanism the scenario exists to test:
appending a suffix to the key in `check_waiting`'s `Vault.get(p.crash_hs, crash_key(ep,
role))` lookup, so no continuation is ever found. With the stdlib restaged (a full
`dune build --root .`, since `dune build bin/main.exe` does not restage `stdlib/`) the
scenario fails, and fails in the shape the pre-B1 behaviour would have:

```
node-b:  I: cancelled waiting on role 3: connection lost
node-a:  L: cancelled waiting on role 2: role 3: connection lost
```

The perturbation was then reverted and the scenario re-run green. Five consecutive runs
pass.

## Why the cause string is not pinned

I prints the crashed role but not `crashed.cause`. Which detector observes node-c first
decides the wording, so asserting it would assert the outcome of a race. The direct-transport
scenario pins `connection lost` because there the dropped session connection is the only
detector; here it is one of several.

## Out of scope

The remaining B2 items are untouched: the event API has no `Crashed_<Ctor>` and a hosted
role still does not take crash branches; a crash branch inside a `loop` ends the loop; the
`Chan` projection refuses crash protocols rather than learning them.
