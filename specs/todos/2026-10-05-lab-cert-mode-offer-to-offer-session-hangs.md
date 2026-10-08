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

## Not reproduced on one machine (2026-10-05)

`test/two_node/cert_order` runs the lab's `Order` protocol, its certificate layout
(`forge host init`'s: roles only, no raw_send; both work roles on each work node) and
its hosting (Stock offered on node-b and node-c, Ledger hosted in an actor on node-c
only), three rounds of four concurrent sessions. It fails unless some session put Stock
on node-b, away from the Ledger: 6 of 12 did, and all 12 finished. Simpler variants
(three-role ring, offered or hosted third role, sequential or concurrent) passed too.
So certificate mode plus the cross-node offer-to-offer edge is not enough by itself.
Still unexercised: separate hosts under load (the lab's load average was 5-13), the
`[control]` wiring, and long runs (the shared-secret stall came after ~90 sessions).
That points at a timing race on the delivery path rather than a certificate check.
The lab runs before the colliding-type drop fix leaked ~1 object per message byte;
re-run the lab soak with this branch before digging further.

## Reproduced on one machine: `cert_order` hangs under load (2026-10-08)

`two-node[cert_order]` "flaked" in the ASan sanitize gate (merge train D, run 37573786349;
merge train N, run 37717699263, `sanitize-gate (3/3)`): `panic: node-a: round 1 stalled,
3 sessions done in all`, no sanitizer report. That is this hang, not a slow run, so its
60 s round deadline must NOT be scaled under ASan:

- A clean ASan run of the whole scenario (three nodes, twelve sessions) takes ~3.5 s in
  CI; the failing one sat on its last round-1 session for the full 60 s.
- Linux container (`march-ci-ubuntu-step6b`, `--cpus 2`), ASan, 4 busy loops: 4 of 20
  runs stalled. With node-a logging each `initiate_Shop` and the round deadline raised to
  400 s, healthy sessions took 0.3-5.5 s, and 2 of 4 runs stalled for the full 400 s:
  `initiate_Shop` never returned `Ok` or `Err`, though under ASan two-node.sh scales the
  session heartbeat to 50 s and setup to 100 s. Neither bound fired.
- Same container, NO ASan, 8 busy loops: 2 of 30 runs stalled for the full 120 s round
  (the plain bounds are 10 s heartbeat, 20 s setup). ASan only widens the window.

Shape of the 8 local stalls (Stock starts printed by node-b / node-c vs sessions done;
nothing failed, cancelled or was dropped on any node, the Ledger actor included):

| run | round | Stock on b / c | done | stuck after `want` | never reached Stock |
|---|---|---|---|---|---|
| ASan 1 | 1 | 2 / 2 | 3 of 4 | 1 | 0 |
| ASan 2 | 1 | 4 / 0 | 0 of 4 | 4, all on b | 0 |
| ASan 3 | 1 | 4 / 0 | 2 of 4 | 2, both on b | 0 |
| ASan 4 | 3 | 6 / 6 | 11 of 12 | 1 | 0 |
| ASan 400 s, 1 | 1 | 3 / 0 | 2 of 4 | 1, on b | 1 |
| ASan 400 s, 2 | 1 | 1 / 2 | 2 of 4 | 1 | 1 |
| plain 1 | 1 | 3 / 0 | 3 of 4 | 0 | 1 |
| plain 2 | 1 | 4 / 0 | 0 of 4 | 4, all on b | 0 |

Two ways to hang, then: Stock (on node-b, wherever the table can tell) got its first
`want` and nothing followed; or the session never reached any Stock, past the setup
bound. 7 of 8 were in round 1, right after the offers opened, and 3 runs put every
round-1 Stock on node-b. So the race is around the cross-node Stock -> hosted-Ledger
path while it first forms, and the session's own failure detection does not cover it.

Repro:

```
docker run -d --name cert-repro --cpus 2 march-ci-ubuntu-step6b sleep infinity
# copy the tree (COPYFILE_DISABLE=1 tar --no-xattrs), opam switch 5.5,
# opam install --deps-only ./march.opam ./forge.opam,
# dune build bin/main.exe forge/bin/main.exe
MARCH_SANITIZE=1 scripts/two-node.sh --precompile ~/pre cert_order
# then ~20 runs with 4 `while :; do :; done` loops alongside:
MARCH_SANITIZE=1 ASAN_OPTIONS=detect_leaks=0:halt_on_error=1 TWO_NODE_TIMEOUT=240 \
  TWO_NODE_PREBUILT=~/pre scripts/two-node.sh cert_order
```

`cert_order` stays in the sanitize gate as it is: it is this todo's regression test, and
it fails only when a session hangs. Fixing this item fixes the "flake".
