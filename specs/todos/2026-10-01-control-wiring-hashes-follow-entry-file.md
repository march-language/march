# `[P4]` The control-plane wiring's functions change hash with the entry file's length

**Found by:** the `forge test --upgrade-from` control-plane fixture (2026-10-01,
[../progress/2026-10-01-dd-step12a-forge-cluster-backend.md](../progress/2026-10-01-dd-step12a-forge-cluster-backend.md)).

**What.** `lib/desugar/control_wiring.march` is spliced into the entry module of an app with
a `[control]` section (`bin/topology_gen.ml`), after the user's code. Its ~80 functions
(`ctl_*`, `Ctl_Control.*`, `Ctl_Agent.*`, ...) get spans in the entry file, so their impl
hashes change whenever the user's part of the file gains or loses a line, though their code
did not change. Compare the manifests of fixtures/upgrade v1+control_v1 and live: 80 impl
hashes differ, 2 signature hashes (the user's own).

**Why it matters.** Those functions have no hot slot in the base (they are outside the
`--hot-reload` prefix), so a patch cannot reach them anyway: forge lists them as
"new and require a server restart" on every deploy of such an app, and the release path had
to be taught to ask the nodes for their slots (`Cluster_deploy.restrict_manifest`), because a
release recorded against the whole manifest ordered them and every node refused the batch
(`commit_partial_failure`). Any check that compares a deploy's manifest to the last one
(drift, `forge deploy --plan`'s function diff) should see ~80 phantom changes, and the ssh
path's "changed function with no dispatch slot" check may then plan a restart for an app
whose entry file merely changed length (not verified yet: the cluster backend's plan has
no slot list, so it does not run that check).

**Fix direction.** Give spliced code spans of its own file (the wiring's embedded text, as a
virtual file name), not the entry file's, so its hashes depend on its own text only. This is
in the compiler's splice (`bin/topology_gen.ml`) or the hashing in `lib/tir/`; both belong
to other work at the time of filing.
