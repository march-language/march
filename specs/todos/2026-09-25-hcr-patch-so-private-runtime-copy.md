`[P1]` A hot-reload patch `.so` carries its own copy of the C runtime

Filed 2026-09-25 while building distributed-deploys step 9's network
acceptance test (`test/two_node_pending/protocol_evolve`), which it blocks.

## What was seen

A patch built with `march --compile --compile-so --hot-reload <Mod>` DEFINES the
runtime's functions itself and imports none from the process it is loaded
into:

```
nm -m v2.so | grep _march_sched_        # _march_sched_current, _march_sched_find, ... (__TEXT,__text) external
nm -m v2.so | grep ' undefined ' | grep -c march_    # 0
```

So code the patch runs calls the patch's own runtime, whose file-statics are
separate from the running process's: a second scheduler table, a second vault
registry (`runtime/march_extras.c`, `vault_registry`), and so on. Two symptoms,
on macOS (arm64), in the two-node scenario:

1. **A new-code session kills the process.** node-b's Driver actor spawns a
   task per session; after a deploy reloads the actor's handler, the first
   task it spawns (patch code: `SessionNode.initiate`, `run_cluster`, a party
   Endpoint actor) crashes the process: `fatal SIGSEGV si_code=2 addr=0x11
   ... fault outside its stack` on this branch, `fatal SIGBUS ... sched=-1
   pid=-1 (no green thread running on this scheduler)` on origin/main
   504c54c23 (the pre-change control: same scenario, no protocol change in the
   patch, only the handler's state update differs). With the driving stopped
   before the deploy, the node survives the deploy.
2. **Named state is invisible to the new code.** node-a's hosting actor, on
   the new code, looks up `Vault.whereis("evolve_offers")` and gets `None`,
   although the old code created it: it opened a second offer instead of
   replacing the first.

A patch whose new code only does arithmetic in an actor handler works, which
is all `forge test --upgrade-from`'s fixtures (forge/test/fixtures/upgrade) do,
so nothing caught this.

## Reproduce

Move `test/two_node_pending/protocol_evolve` to `test/two_node/`, build
`test/hcr_deploy.exe` and `bin/main.exe`, and run
`scripts/two-node.sh protocol_evolve`. The deploy logs are in the harness's
work directory (`deploy_a.log`, `deploy_b.log`).

## Direction

The patch should resolve runtime symbols against the host process, not carry
them: leave them undefined in the `.so` (macOS: `-undefined dynamic_lookup`;
Linux: do not link the runtime objects into a `--compile-so` output), keeping
only the patch's own March functions hidden as `llvm_toplevel.ml` intends
(the compile-so path's "hide all non-exported symbols" note). Check the stdlib
too: module-level state held in March code (not the runtime) would be
duplicated the same way.
