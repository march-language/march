`[P2]` Host-scoped network capabilities: `needs IO.NetConnect("example.com")`.

Design: `specs/2026-11-09-host-scoped-network-capabilities-design.md` (not yet approved).

Today a network capability cannot be narrowed to a host: `needs IO.NetConnect("…")` is
`[invalid_cap_scope]`, so a module that talks to one API holds the same authority as one
that talks to any host. The only separation available is handing each module a closure
built by a module that holds the unscoped capability.

## Done when

Phase 1 of the design is in: module `A` scoped to `example.com` and module `B` scoped to
`foo.com` each build when they reach only their own host, fail to build when they reach
the other's (directly, through another user module, or with a destination the compiler
cannot see), and a cross-host redirect from a scoped call is refused at run time.
