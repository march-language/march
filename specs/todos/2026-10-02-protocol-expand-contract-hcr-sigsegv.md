# protocol_expand_contract: both nodes SIGSEGV after the expand patch activates (Linux)

**Logged:** 2026-10-02

## Symptom

`two-node[protocol_expand_contract]: the contract deploy to node-a failed`
fails intermittently on CI (ubuntu x86_64). One example is job 110709588938,
run 36965942049, branch `claude/nostalgic-lumiere-7fd591`. It is not a timing
or harness problem: the scenario already precompiles both nodes, and both
nodes die with:

```
march: fatal SIGSEGV si_code=1 addr=0x62 pc=... fault outside its stack
```

In an ubuntu-24.04 **arm64** container (the `march-two-node:local` image),
on main c59ace9af, it fails **4/4**. The same scenario passes on macOS.

## What is known

- `deploy_expand_a.log` and `deploy_expand_b.log` both end with
  `Deploy complete: 8 function(s) activated`. Each node crashes right after
  its own expand deploy, so the contract deploy then gets
  `hcr_deploy: connect: Connection refused`.
- Every deploy logs "13102 function(s) are new". The base build
  (`--compile --hot-reload`, without `--compile-so`) writes no
  `node_<x>.schemas.json` or `.hcr_manifest`, so `step`'s `$was` is empty.
  The scenario expects this.
- node-a under gdb (break `march_report_fatal_fault`):

  ```
  #3  ClusterNode.names ()          main exe
  #4  offered ()                    main exe
  #5  ShopHost_dispatch ()          the expand patch .so (~/.march/cas/artifacts/...)
  #6  actor_green_thread ()
  ```

  The frame names are the nearest exported symbols, so `offered` may be a
  mis-symbolized static. In either case, the v2 `ShopHost` handler, called on
  an actor whose state was built by v1, ends up dereferencing a small tagged
  value (`0x62`) as a pointer.
- The patch is linked `-Wl,-Bsymbolic` and dlopen'd `RTLD_NOW | RTLD_GLOBAL`
  (no DEEPBIND since 2026-09-25, `runtime/march_reload.c:689`). So "ELF
  interposition sends the patch's calls to v1's own functions" should already
  be ruled out. Confirm this with `readelf --dyn-syms` / `objdump -R` on the
  patch.

## Repro

In the container recipe from the memory notes (`march-two-node:local`, copy the
tree to `/tmp/work`, then
`dune build --root . bin/main.exe forge/bin/main.exe @test/stage-source-trees`):

```
scripts/two-node.sh protocol_expand_contract
```

For a backtrace, start node-a under
`gdb -batch -ex 'handle SIGSEGV nostop noprint pass' -ex 'handle SIGUSR1 nostop noprint pass' -ex 'break march_report_fatal_fault' -ex run -ex bt --args`.
The runtime takes legitimate SIGSEGVs for lazy stack growth, so gdb must
pass them through and stop only at the fatal reporter.

## Next

1. Build the expand patch with debug info and symbolize frames #3-#5 exactly.
2. Compare the record layout of the `Tick(c, h)` message and of `ShopHost`'s
   state between v1 and the expand build.
3. Check whether `protocol_evolve` (similar deploy flow) shares the cause.
   It failed on runs 36911866986 and 36935259865 with a node-b output diff.
