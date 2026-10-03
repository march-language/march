# `[P2]` Topology firewall rules open the cluster port only between protocol peers

`forge topology gen ufw` / `do-firewall` (step 7) allow the cluster port into a pool
only from the hosts of the pools it exchanges protocol messages with (the connectivity
graph). SWIM membership probes and gossips with every member, and every node is given
every other node as a seed, so two pools that share no protocol would see each other as
unreachable once the rules are applied, and `count = n` placement (D19) would rank on a
wrong membership. `forge host init` applies the ufw rules when ufw is installed
(distributed-deploys step 10b).

Decide: open the cluster port between all members (the segregation of section 3 is then
by certificate, not by firewall), or make membership segregation-aware. Test with a
two-pool topology whose pools share no protocol, with the rules applied.

## Resolution (2026-10-03)

**Decision: open the cluster port between all cluster members.** The segregation of
section 3 of the distributed-deploys plan is by certificate, not by firewall. Made by the
coordinating session (the owner may override), for three reasons, from the plan's
section 3 and D4:

- the threat model is a misbehaving member on a trusted network, not an outside
  attacker that a firewall between pools would stop;
- steps 11a/11b (merged) already enforce roles, raw sends and cross-node references by
  certificate, with a MAC on every frame, so a pool that can reach another's cluster
  port still cannot act outside its roles;
- making SWIM membership segregation-aware (partial views per pool, placement ranking on
  a filtered membership) would be a much bigger change with its own failure modes.

**What changed.** `Topology.Gen.cluster_hosts` lists every host in the topology once.
`Gen.ufw` allows the cluster port into each host from every other host in that list,
not from the hosts of the connectivity-graph peers; `Gen.do_firewall` gives every pool's
firewall one cluster-port rule whose sources are every pool's tag (its own included, so a
droplet tagged later is covered). `forge host init` writes and applies `Gen.ufw`'s
script, so it follows; only its doc comment and the no-rules note changed. Public ports
and the control-port rule (#731) are unchanged, and no other port is opened between
pools. In the shop golden, the `imaging` pool talks to nobody, so before this its two
hosts could not even reach each other's cluster port.

**Tests.** `test_topology`: "cluster port open between pools sharing no protocol" builds a
two-pool topology (pool `a` on two hosts, pool `b` on one, no connectivity edges) and
asserts every host's ufw script admits the cluster port from every other host, that `b`'s
public port is not opened on `a`, and that both DigitalOcean firewalls take the cluster
port from both pool tags. It fails on the old generator (checked by swapping the old
`topology.ml` back in: it and both goldens go red). The ufw and do-firewall goldens are
regenerated.

**Not run: a live check with the rules applied.** Applying ufw needs root, and the
two-node harness runs both nodes on one machine, where a rule keyed on the source host
cannot tell them apart; the partition scenarios cut traffic with iptables on ports
instead. So the rules are asserted as generated, and the check that membership sees both
pools with the rules applied is root-only and multi-host, not part of the suite.
