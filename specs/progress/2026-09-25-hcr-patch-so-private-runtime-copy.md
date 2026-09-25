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

## Resolution (2026-09-25)

Filed on step 9's branch (`claude/silly-gagarin-1e8898`, not yet merged); copied
here and closed by the same change.

**The link step.** `march --compile --compile-so` (bin/main.ml, the
`patch_inputs`/`runtime_inputs` bindings of the native link) now hands clang
only the patch's generated IR plus `runtime/march_hcr_identity.c`, the three
constant strings the reload server reads with `dlsym(handle, ...)` to preflight
the patch's target identity (#606); `dlsym` on a handle does not search the host
executable, so the patch must carry those itself. Every other `march_*`
reference is left undefined (`-undefined dynamic_lookup` on macOS; a `-shared`
GNU/lld link leaves undefined symbols undefined by default) and binds at
`dlopen` time to the host process, whose `--hot-reload` baseline has always been
linked with `-Wl,-export_dynamic` / `-Wl,--export-dynamic` for that purpose.
The user's FFI shim sources (`--ffi-c`) are dropped from the patch for the same
reason: the baseline links and exports them, and a second copy would duplicate
their file-static state too; a patch that needs a NEW shim now fails to `dlopen`
with an undefined symbol instead of silently carrying one. The cross-compiled
patch used to drop a hand-picked subset (blake3, the reload server, TLS, zlib);
it is now the same rule with no exceptions left to make. Before:

```
nm -m v2.so | grep -c ' undefined '           # 0
nm -m v2.so | grep -c march_sched_current     # 2 (defined in the patch)
```

After, macOS and Linux alike: 25 undefined `march_*` references, none defined;
the patch's own symbols are its hidden March functions, the exported boundary
functions (`Hot.probe`, `Worker_dispatch`, ...), `__march_init`, the cap
tables and the three identity strings.

**Where it showed.** A single-process repro (an actor whose handler spawns a
task per message; the task reads a Vault `main` created) ran on the unfixed
compiler without crashing only because of the second defect below: the task's
call into the patched function was compiled direct and never reached the patch.
With that fixed and the runtime still duplicated, new code ran green threads on
a second scheduler table and looked names up in a second vault registry.

**The stdlib.** Checked for module-level state held in March code rather than
the runtime, which the patch (a whole-program `.so` with everything but the
boundary hidden) would duplicate the same way: the stdlib has module-level
`let`s only for constants (`Bytes.b64_alphabet`, `Crypto.pw_iterations`,
`Crypto.pw_dklen`); every registry (vaults, actor names, remote/monitor
registries, the dispatch table, offers) lives in runtime C statics, which a
patch now shares with the host. Nothing to list.

**The JIT** (lib/jit/repl_jit.ml) was already in the right shape: fragments are
linked with `-undefined dynamic_lookup` (macOS) against an explicit runtime
`.so` and never carry the runtime; `test_jit` still passes.

**#606's identity preflight** still works with an undefined-runtime patch: the
identity object is the one runtime file a patch keeps (see above), and
`test/cross_hcr_compile.sh` / `test_hcr_identity` cover it.

**Proof.** `forge test --upgrade-from`'s new `live` fixture
(forge/test/fixtures/upgrade/live) and the two-node scenario
`test/two_node/hcr_new_code_session` (both described in
`2026-09-25-hcr-dispatch-callee-only-rule.md`) fail on the old link step and
pass on macOS and in the Linux container. Step 9's `protocol_evolve` stays on
its branch: it needs step 9's protocol-compatibility table and has not merged.
