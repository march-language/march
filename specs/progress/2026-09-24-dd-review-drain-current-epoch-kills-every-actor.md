# `DRAIN epoch:<E>` with E at or above the current epoch kills every live actor

**DONE 2026-09-24.** The reload server's verb is now `DRAIN <sig64> epoch:<E> …`, signed
like `ACTIVATE` over `DRAIN epoch:<E> soft_ms:<n> hard_ms:<n>`, and refuses `E >=
current` with `ERR bad_epoch` (an unsigned request: `ERR bad_signature`).
`test/test_reload_activate4.c` pins the three refusals and the accepted form. The C
API `march_hcr_drain` is NOT clamped: `SessionNode.drain_epochs(io, soft, hard)` (a
program draining itself, holding `Cap(IO)`) needs a hard deadline on the current
epoch, which `test/two_node/drain_hard` relies on, and `Topology.drain` passes no hard
deadline. Filed 2026-09-24; the text below is the finding as filed.

Filed 2026-09-24 by the distributed-deploys review (step 6, PR #612, commit
1157997f5). Plan: II.4.7; progress deviation 5.

## Defect

The reload server's `DRAIN` verb (`runtime/march_reload.c:1465-1477`) rejects
only `epoch <= 0`, and it takes no signature, unlike every `ACTIVATE*` verb.
`march_hcr_drain(E, soft, hard)` arms a hard deadline whose
`hcr_hard_kill(E)` (`runtime/march_runtime.c:6069-6102`) kills every actor
with `code_epoch <= E` and requests a stop on every other proc at or below E.
Every live unit is pinned at or below the current epoch, so `DRAIN
epoch:<current> hard_ms:<n>` kills every actor in the process: stdlib actors,
ClusterNode's actor, unsupervised actors, which stay dead. No deploy is
needed. A typo, or a script that drains "the epoch `PINS` shows", is enough.

## Confirmed

C harness against the real runtime. One actor at the base epoch, no deploy,
then `march_hcr_drain(march_epoch_current(), 0, 50)`, which is what the
verb does:

```
[hcr] drain: hard deadline for epoch <= 1: killing actor on dispatch slot 1 (epoch 1)
current epoch 1, actor alive before DRAIN: 1
actor alive 1s after DRAIN of the current epoch: 0
```

The source is in the review session's scratchpad (`m3/repro_drain_current.c`).

## Fix I would make

Refuse `DRAIN` for any `E >= march_epoch_current()` with `ERR bad_epoch`, and
clamp inside `march_hcr_drain` as well, since `Topology.drain` will call it
too. Decide whether `DRAIN` needs the same signature as `ACTIVATE*`: it is
destructive, and the socket is reachable by any process with the node's uid.
