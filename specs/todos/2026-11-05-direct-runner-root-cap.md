# `run_<Role>` and `host_<Role>` still take `Cap(IO)`

The entry points over a cluster node take the node and the role's grant
(`specs/progress/2026-11-05-cluster-entry-points-without-root-cap.md`). The three that
open their own connections do not: `run_R(io, node_id, secret, addrs, body)`,
`host_R(io, ...)` and `host_R_or(io, ...)` take the root capability and narrow the grant
from it.

What `SessionNode.run` does with it: reads the node certificate from the environment
(`ClusterNode.auth_from_env`), listens and dials (`IO.NetListen`, `IO.NetConnect`), and
mints the session capability with `Session.attach(io, ops)`. The last is the obstacle:
`mint_cap` is typed `Cap(IO) -> Cap(a)`, and there is no node here to hold a delegated
closure over `Session.attach`.

Options, none chosen:

- a second public factory in `Session` that takes the two network capabilities; this needs
  `mint_cap` to accept a narrower argument, which is a change to the typechecker's mint
  rule (`check_mint_cap_sites`);
- make `run_R` start a private one-node `ClusterNode` and go through `with_session`;
- leave it: the direct runner is the two-process demo path, and a deployed program uses a
  cluster node.

Then the grant: with no `Cap(IO)` to narrow from, the direct fronts take the grant as
parameters, as the cluster fronts do. About 120 call sites.
