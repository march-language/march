# Cluster entry points take the node, not `Cap(IO)`

Every generated `<P>_Run` entry point used to take the root capability as its first
parameter. A program that played any role over a cluster therefore had to hold `Cap(IO)`,
its pool derived `caps: ["IO"]` whatever its code did, and the hot-deploy widening gate
had nothing narrower to compare a patch against. Measured on `examples/lab_app` before the
change: `ingress` derived `IO`, `work` derived `IO, IO.Console, IO.Mut`.

## What the root capability was used for

Two things, both in `lib/desugar/desugar_endpoints.ml` and `stdlib/session_node.march`:

1. Threaded through twelve `SessionNode` functions to reach one line,
   `Session.attach(io, ops)`, which mints the `Cap(Session.Live)` (`mint_cap` is typed
   `Cap(IO) -> Cap(a)`).
2. `cap_narrow(io)`, once per path of a `role R needs ...` line, to make the capabilities
   the role's body receives.

## What changed

- **A node can attach a session.** `ClusterNode.ClusterOps` gains `attach_session :
  Session.Ops -> Cap(Session.Live)`. `ClusterNode.attach(io, ops)` (which `start` goes
  through) fills it with `fn sops -> Session.attach(io, sops)`, over whatever the caller's
  dictionary holds, so a test dictionary cannot supply its own. The public operation is
  `ClusterNode.with_session(node, sops, body)`, which calls `body` with the capability.
  `ClusterNode` declares `needs Session.Live` for naming it. No typechecker rule changed:
  the mint is still in `Session`, still from a `Cap(IO)`; the node holds that one delegated
  use of it.

  The first version returned the capability (`attach_session(node, sops) :
  Cap(Session.Live)`) and was wrong: Check 6 of `check_module_needs` (`proof_cap_return`)
  forbids a function outside the declaring module from returning a proof capability it was
  not given, and `cluster_node.march` checked as the entry file reported it. Nothing local
  showed it, because a diagnostic inside a stdlib file is dropped when a program merely
  loads the file; CI's `cluster_node_check.out` rule is what caught it. Handing the
  capability to a callback is what the rule asks for (capabilities flow down as
  parameters), and the mint is a call to `Session`'s own factory. A `Session.Attacher`
  type declared in `Session` was tried first and dropped: a module cannot name its own
  proof capability in one of its type declarations when it is the entry file (the entry
  module's types are pre-bound before its `proof cap` line is registered).
- **`SessionNode`'s cluster runners lost their `io` parameter**: `run_cluster`,
  `run_cluster_hosted`, `offer_role`, `start_offered_role`, `offer_hosted`,
  `start_offered_hosted`, `initiate` and the private helpers under them.
- **The generated cluster fronts** (`cluster_R`, `offer_R`, `offer_work_R`, `initiate_R`,
  `offer_hosted_R`, `offer_work_hosted_R`, `cluster_hosted_R` and the two `__offer_work*`
  adapters) take `(node, <one Cap(P) per granted path>, ...)`. The grant parameters are
  named after the path (`IO.FileWrite` is `io_filewrite`) and passed to the body or to
  `start` unchanged. With no grant line the front is `(node, ...)`.
- **The role-grant walk** (`role_front_of` in `lib/typecheck/typecheck.ml`) finds a hosted
  cluster front's callbacks after the grant parameters (`Hosted_after_grant`).
- **The topology-generated `main`** (`lib/desugar/desugar_topology.ml`) and the control
  wiring's agent (`lib/desugar/control_wiring.march`) pass `cap_narrow(io)` per granted
  path; `main` is where the root capability is held, so that is where it is narrowed.
  Its `__topology_entry_*_open` adapters now annotate `topology_io : Cap(IO)`. Nothing else
  pins that parameter any more (`cap_narrow` takes any capability, and a role with no grant
  does not use it), so the adapter became generic, monomorphisation named it after its
  argument types, and its symbol changed with the pool's `Env` type, which is what the
  hot-deploy ABI guard compares by name. `test_topology_flag`'s "captured environment
  changes generated work-entry ABI" caught it.
- 140 call sites in 94 test, fixture and example files dropped their first argument.

## Left alone

`run_R`, `host_R` and `host_R_or`, the fronts that open their own connections, still take
`Cap(IO)` and narrow the grant themselves. They have no node to attach the session, so
narrowing them needs a second route to `Cap(Session.Live)`:
`specs/todos/2026-11-05-direct-runner-root-cap.md`.

## Result

`forge topology export --json --env lab` on `examples/lab_app`, whose hooks no longer take
`Cap(IO)`:

- `ingress`: `IO.Clock, IO.FileRead, IO.FileWrite, IO.Mut, IO.Process, IO.Spawn`
- `work`: `IO.Clock, IO.Console, IO.FileWrite, IO.Mut, IO.Process, IO.Spawn`

`examples/topology_app`: `front` derives `IO.Console, IO.Mut, IO.Process, IO.Spawn`, `back`
derives `IO.Console`.

## What this weakens

Before, only a holder of `Cap(IO)` could make a `Cap(Session.Live)`. Now a holder of a
`Cap(ClusterNode.Live)` can. A session capability carries only the dictionary its maker
built, so it grants nothing its holder could not already do; what is lost is the
property "a session capability exists only where the root capability was".

## Tests

`test/test_endpoints.ml`: `cluster_fronts_take_no_root` pins every front's parameter list
with and without a grant; `cli_role_grant_cluster_fronts` runs the grant walk from
`cluster_`, `offer_`, `initiate_`, `offer_hosted_` and `cluster_hosted_`.

## Found on the way, not fixed here

A role served through a topology file is not checked against its grant:
`specs/todos/2026-11-05-topology-role-grant-unenforced.md`.
