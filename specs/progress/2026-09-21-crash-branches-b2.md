# Crash branches, phase B2: an actor-hosted role takes its crash branch

Shipped 2026-09-21. Closes the first item of
[[2026-09-20-crash-branches-b1]]'s out-of-scope list, the hosted path sketched in
[[2026-09-20-crash-branches-implementation]]'s Runtime section and deferred there.

## The gap

`SessionNode.check_waiting` already took the crash branch for ANY endpoint whose crash
continuation was installed: it looks `crash_hs` up under the endpoint and the gone role and
runs it instead of `cancel_endpoint`. An actor-hosted role installed none. The generated
`await_*` only called `Session.suspend`, so `crash_hs` was empty, `check_waiting` fell to
its `None ->` arm, and the session was cancelled exactly as before crash branches existed.
A protocol with `may crash C` therefore meant one thing in a callback role and another in a
hosted one, which matters because a hosted offer is the recommended shape for serving many
sessions (#537).

## The route: a crash as a delivery

A crash has to reach the actor's own handler, because the actor owns the session state. The
route that already reaches it is the delivery one (`p.forward`, key `"f"`, the user's
`deliver` callback). The implementation spec's preferred design was a third forward,
`forward_crash` (key `"x"`), rather than overloading `forward_cancel`; that is what
shipped, with one refinement: **`forward_crash` is built from the same `deliver` callback**
rather than from a new one. `host_party` sets

```march
Vault.set(p.forward_crash, "x", fn (role, cause, ep) -> deliver(s, role, Session.crash_payload(cause), ep))
```

so `host_<Role>`, `host_<Role>_or`, `offer_hosted_<Role>` and `cluster_hosted_<Role>` keep
the callbacks they had: no user-facing signature changed. `host_party` is shared by the
standalone runner (`run_hosted_or`) and the cluster one (`run_cluster_hosted_with`), so both
modes got it from one line.

`Session.crash_payload(cause)` / `Session.crash_cause(msg)` (`stdlib/session.march`) are the
marker: `"!session-crash!" ++ cause` in the delivery's `Bytes`. Every real payload is
`Json.to_string` of a variant, which never begins with `!`, so the two cannot collide. They
are plain functions, not `Ops` fields: `resume` takes no capability, and a role module must
stay transport-agnostic.

`check_waiting` now branches where it runs the continuation: hosted, it calls the forward and
returns (the actor's next `suspend` drains what is queued, as a delivery does); otherwise it
runs the installed continuation and drains, as in B1.

## What is generated

`lib/desugar/desugar_endpoints.ml`:

- `Received_<Role>` gains `Crashed_<name>(Crashed_<Role>, S_<crash branch's first state>)`,
  one per state with a crash branch, beside the `Got_<Ctor>` constructors. `<name>` is the
  message's constructor for a single receive and the joined labels plus `_crash` for the
  `choose` form, the same name the state's `await_`/`offer_` carries; the payload is the
  same `Crashed_<Role>` record the callback API's crash callback gets.
- `await_<name>` of an `LRecvCrash` state installs a crash continuation
  (`Session.on_crash`) before it suspends, so the transport knows there is a branch to take
  rather than a session to cancel. The continuation itself panics, like the delivery handler
  beside it: a hosted transport routes the crash to the actor and never runs it.
- `resume` asks `Session.crash_cause(msg)` before decoding, in the states that have a crash
  branch only, and builds the `Crashed_` event with `from` as the crashed role.

## Tests

- `test/test_endpoints.ml`: `crash_hosted_shape` (the detector's `await_Msg_C_I_1`, and
  `Received_I`'s constructors pinned exactly, including `Crashed_Msg_C_I_1`; `Received_L`,
  the third party, has none — it hears about the crash as one of I's messages),
  `crash_choose_hosted_shape` (the `choose` form's `await_read_done_crash` and
  `Crashed_read_done_crash`), `crash_hosted_ok` (an actor taking every step, the crash
  branch included, from its resume handler) and `crash_hosted_state_is_the_branch` (the
  crash event's state is the branch's: the normal continuation's step is a type error).
  The test stdlib gained `string.march`, which `Session.crash_cause` reads the marker with.
- `test/two_node/crash_hosted`: `crash_before_send` with I hosted in an actor instead of run
  from callbacks. Three OS processes, C SIGKILLed after connecting and before its `Read`; the
  actor gets `Crashed_Msg_C_I_1`, sends L the `Fatal` and finishes, and I and L both return
  `Ok`. All three nodes are compiled before the first `start_node`. Proven non-vacuous:
  with the `forward_crash` line removed the scenario fails, L reporting
  `cancelled waiting on role 2` and I panicking in the inert continuation.

## Out of scope

The other three B1 items stand: cluster mode has no crash scenario of its own (the same
`check_waiting` and the same `host_party` run there, and `cluster_hosted_<Role>` gets the
forward from it, but nothing pins it); a crash branch inside a `loop` ends the loop; the
`Chan` projection refuses crash protocols rather than learning them.
