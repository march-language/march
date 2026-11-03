# `[P1]` A session whose two offered roles are on different nodes can hang for ever (nearly always in certificate mode)

## Fixed 2026-10-12: two hangs and a use-after-free, all in `stdlib/session_node.march`

`two-node/cert_order` reproduced the hang on one machine (Linux container
`march-ci-ubuntu-step6b`, `--cpus 2`, compiled nodes prebuilt, busy loops
alongside). Per-node trace logs of each party's formation, frames and peer
events found two separate hangs, and verifying the fix turned up a
use-after-free. None was a frame lost on the wire.

**1. A certificate check ran before the link it needed (most of the hangs, all
in round 1).** `run_cluster_party` checked who holds each peer role's registry
name (`check_holders` with `ap_holder_check`, step 11b) BEFORE it waited for a
link to that peer's node (`cluster_links`). In certificate mode a peer's
certificate is known only from its link's handshake. Node-b and node-c learn of
each other through node-a and link up only as round 1 starts. So the Ledger
party on node-c could see Stock's name on node-b before it had a link to node-b,
fail the check with "role Order.Stock is held by node-b: presented no
certificate", unregister and return. Nobody was told. Shop (node-a) and Stock
(node-b) had already found the Ledger's endpoint and formed. Stock's `book` and
later its `Cancel` reached node-c with no route for that endpoint. They were
refused as "not authorized: raw send", which is what an unrouted frame gets in
certificate mode. Node-b's session ignores DELIVERY_FAILED, so Shop waited on
`booked` for ever. This gives both stall shapes in the todo. When the Ledger
gave up, Stock had its `want` and nothing followed. When Stock on node-b gave up
the same way, the session never reached Stock. Shared-secret mode was unaffected
because `authorize_peer` is always `Ok` there.

Fix: link first, then check the holders. Also, a party that gives up after
registering now sends a `SessionNode.Cancel` for its role to every peer it found
and can reach (`abandon_found`), whichever setup step it gave up in: a peer
never registered (`find_peers`, which now returns the peers it did find), a
holder failed its check, or a peer's node never linked. A peer that formed then
fails, and does not hang, if the check fails for real or a peer's node never
links. A peer on a node this one has no link to yet is not told directly. It
learns when its own setup gives up, because it can no longer find this role's
unregistered name, and it then tells its own found peers. The negative control
below exercises that chain.

**2. A hosted endpoint's Bye was sent after its party was torn down (rarer,
round 2/3).** The Ledger is hosted in an actor. Its last `skip` is forwarded to
the host actor. The Byes from Stock and Shop then end both links, the outcome
settles, and `serve_cluster_outcome` tears the party down, closing its Vaults.
Meanwhile the host's `close` set "done" and THEN queued its Byes. If the
runner saw "done" first, the Byes were built after `Vault.close(p.why)`. They
had no session id ("untagged frame SessionNode.Bye for cluster session ...")
and both peers refused them, so Shop waited for the Ledger's Bye for ever.

Fix: `close` queues its Byes before setting "done". Before the runner cancels an
endpoint that is still running, it gives a hosted endpoint's host up to the
setup time to finish (`await_hosted_end`, in both the cluster and the standalone
runner). A callback-API party needs no wait: its continuations run in the
endpoint actor, ahead of the `LinkEnded` that settles the outcome.

**3. A late SessionAP.Answer wrote into a freed table (ASan, about 1 run in 40,
seen while verifying the above).** `initiate` kept each initiation's answers in
its own Vault. It dropped the inbox's route and then `Vault.close`d the table. A
data reader that had already picked up the route for a late Answer (one that
arrived after `NoAnswer`, under load) then ran `Vault.set` on the freed table.
ASan reported a heap-use-after-free in `march_vault_reap` from `inbox_frame`.
Fix: one process-wide answers table (`answers_table`, never closed), keyed
"<sid>/<node id>". Its keys are deleted when the initiation ends
(`forget_answers`). A key a late Answer writes after that is never read.

**Rates** (the same container, `scripts/two-node.sh cert_order` with prebuilt
nodes):

| | before | after |
|---|---|---|
| plain, 8 busy loops | 8 of 30 runs stalled | 0 of 30 failed; after rebasing on main, 1 of 30 (see below) |
| ASan (`MARCH_SANITIZE=1`, `ASAN_OPTIONS=detect_leaks=0:halt_on_error=1`), 4 busy loops | 11 of 20 stalled | 0 of 30 failed, 0 of 40 more with tracing on, and 0 of 30 after rebasing |

The one plain failure after the rebase was not this bug. Node-a's SWIM declared a
live node-c dead under the 8 busy loops ("suspect timeout"), and a round-3
session hung after its node pair was redialled. That is the open item below.

With fix 1 alone, hang 2 remained: 1 of 30 plain runs and 2 of 19 traced ASan
runs stalled in round 2, and one traced ASan run hit the use-after-free (3).

macOS (plain, no extra load, load average ~55 from other sessions) never
stalled in 20 runs, before or after.

**Regression test.** `cert_order` itself, now stricter. Node-a still retries
refusals while the offers open, and logs and retries a session that failed
for a transport reason. It now panics on a session that failed because a
party gave up on a peer's certificate (" is held by "). That is the fixed
check-before-link race: with `abandon_found` it would fail and not hang, and a
blind retry would hide it.

Negative control: the old check order with `abandon_found` (plain, 8 busy loops,
traced) failed 12 of 30 runs. Every failure was a clean "is held by" session
failure, and none stalled. Two earlier controls without the `find_peers` part
of `abandon_found` each stalled once, in 20 and in 30 runs. In the traced one,
node-c's Ledger cancelled toward node-a but could not reach node-b, which had
no link yet. Node-b's Stock then sat in `find_peers` and gave up without telling
node-a.

What is left, filed as specs/todos/2026-10-12-lab-shared-secret-session-stall.md
(since fixed: specs/progress/2026-10-12-session-redial-hang.md):
the lab's one shared-secret stall, which none of these fixes explains. Its likely
cause, a session whose node pair ends and is redialled while it runs, hangs
`session_churn` under ASan about 3 runs in 8, on main and on this branch alike.
Also left: session frames whose DELIVERY_FAILED nobody reads.

## The original report

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
