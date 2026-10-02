# two-node `protocol_expand_contract`: node-a SIGSEGVs (addr=0x62) after the expand deploy — on main

Logged 2026-10-02 from PR #753's CI (`two-node (2/2)`), reproduced locally on
an untouched `origin/main` (9dfd7171c) with `scripts/two-node.sh
protocol_expand_contract`:

```
hcr_deploy: connect: Connection refused
two-node[protocol_expand_contract]: the contract deploy to node-a failed
march: fatal SIGSEGV si_code=2 addr=0x62 pc=... sched=12 pid=5 status=1 fault outside its stack
```

Both nodes die identically (CI showed node-b too). `addr=0x62` is an even
small word dereferenced as a pointer, after the expand hot-deploy and before
the contract deploy; the deploy then finds node-a's reload socket gone. The
scenario was last touched by 9b8ec3ef9 ("fit CI's Linux runner"). Not caused
by #753 (same failure, same address, on main without it). CI's `two-node`
jobs on main pushes are sparse, which is how it went unnoticed.
