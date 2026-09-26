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
