# `[P1]` A session whose two offered roles are on different nodes can hang for ever (nearly always in certificate mode)

Found 2026-10-05 by the multi-host lab (`LAB_AUTH=certs scripts/lab/run.sh deploy`,
docs/lab.md), load average 5-13, four containers, main at 53d66f068.

`examples/lab_app`'s `Order` has three roles: Shop (initiated on lab-1), Stock (offered on
lab-2, lab-3, lab-4) and Ledger (offered on one of lab-3/lab-4, an actor-hosted role). In
each round Stock sends `have` to Shop and `book` to Ledger, and Ledger sends `booked` to
Shop.

With `forge cluster keygen` before `forge host init` (every node gets a certificate naming
the roles its pool offers and initiates: `Order.Stock:offer`, `Order.Ledger:offer` for the
work pool, `Order.Shop:initiate` for ingress), the ingress counters after a few minutes,
Ledger on lab-4:

```
booked@work-lab-4 6
finished 3
have:stock-v1@work-lab-2 3
have:stock-v1@work-lab-3 3
have:stock-v1@work-lab-4 6
started 13
```

Every session whose Stock ran on lab-4 (the Ledger's node) finished. Every session whose
Stock ran on lab-2 or lab-3 got its first `have` to Shop and then nothing: no `booked`,
no failure, no cancellation. The status files show them running for good
(`offer Order.Stock ... sessions 2` on lab-2 and lab-3, `offer Order.Ledger ... sessions 4`
on lab-4), minutes later, and the nodes log nothing about them. The same deploy with a
shared secret instead (`LAB_AUTH=secret`) finished 65 of 68 sessions, with Stock on all
three hosts (2 refused while the offers opened).

With the shared secret it happened once too, later: after ~90 sessions, 4 sessions
stayed `running` on the Ledger's offer (lab-4) and Stock offers for good (started 91,
finished 85, refused 2), with nothing in any log; the Ledger actor logged no dropped
message and no cancellation (the lab app prints both).

So the edge that stalls is offer-to-offer across nodes (Stock on lab-2 to Ledger on
lab-4) under certificate checks. The initiator-to-offer edges work. A session that
cannot proceed should at least fail (a `Connect` error, a cancel) rather than wait for
ever: these sessions hold an offer slot each and never free it.

## Where to look

The per-frame and per-session certificate checks for a frame between two parties
neither of which initiated (stdlib/session_node.march, the "each party checks the
others once the session forms" step, and the cluster node's frame authorization). A
two-node scenario with three roles on three nodes, two of them offered on different
nodes, in certificate mode, should reproduce it; the existing `cert_*` scenarios have
two parties.

## Repro

`LAB_AUTH=certs scripts/lab/run.sh deploy`: the scenario's "every started session ends"
check fails.
