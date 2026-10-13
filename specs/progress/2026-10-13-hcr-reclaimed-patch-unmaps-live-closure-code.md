`[P1]` Hot reload: reclaiming a version dlcloses code that live closures still point into

Found by the HCR Phase 0 spike (`specs/progress/2026-10-13-hcr-phase0-spike.md`,
experiment E4; prototype in `specs/spikes/2026-10-13-hcr-phase0/`).

## Symptom

A closure built by patched code keeps its apply function's address at +16. A
version's `refs` (`march_dispatch_enter`/`leave`) counts only calls in
progress. So once the ring (`MARCH_MAX_LIVE_VERSIONS`, 3) reuses that version's
slot, `march_dispatch_stage` dlcloses its `.so` (`slot_dlclose`,
runtime/march_dispatch.c), even though closures from it are still reachable.
Calling one of them later jumps into unmapped memory:
`march: fatal SIGSEGV ... pc=<addr> addr=<addr>`, with pc equal to the fault
address. Seen on macOS and on Linux, plain and ASan. Reproducer: four deploys
of the same slots, then call a closure each version built:

```
HCR0_N=50000 specs/spikes/2026-10-13-hcr-phase0/run.sh /tmp/o v1 v2b_mk_only v1 v2_newshape v1
```

With dlclose suppressed (`HCR0_NO_UNLOAD=1`), the same run is correct and
ASan-clean. In production: any callback, plug, or closure kept in actor state
or a Vault, followed by three later deploys of the slot whose code built it.

## Direction

`specs/hot-code-reload.md` § Part 3 says captured closures "carry their version and keep
it pinned". Implement that, for example with a per-version count of live
closures whose apply lives in that version's image, bumped at closure
allocation in a hot-reload build and dropped when the cell is freed, and
checked in `pick_ring_slot`. The simpler option: never dlclose a patch
(bounded by deploy count; a restart reclaims it). The capture-release table
(`march_clo_register_drops`) has the same key-lifetime problem once patches
register into it; see `2026-10-13-hcr-patch-closures-not-in-drop-table.md`.

## Fixed 2026-10-13

**Cause.** Reclaiming a ring slot (`march_dispatch_stage`, and
`march_dispatch_shutdown`) called `slot_dlclose`, which dlclosed the version's
patch handle as soon as no call was in progress (`refs == 0`). Nothing counted
the other references into the image: closures it built (apply pointer at +16),
immortal statics it handed out, and, with the companion fix
(`2026-10-13-hcr-patch-closures-not-in-drop-table.md`), the capture-release
entries its `__march_init` put in the closure-drop table.

**Fix: a patch image is never unmapped (option (a)).** A reclaim recycles only
the slot's bookkeeping. `slot_release_handle` (runtime/march_dispatch.c, renamed
from `slot_dlclose`) hands the handle to `march_dispatch_retain_image`, which
counts it (`march_dispatch_retained_images`) and does not dlclose it. The same
applies at shutdown, and in `activate_items` (runtime/march_reload.c) once
`__march_init` has run on a deploy that then fails or WAITs. Before that point
nothing of the image has escaped, so it is still dlclosed. The test seam
`march_dispatch_set_close_hook` keeps its meaning ("the moment the ring lets
go"), so the reclaim-ordering unit tests are unchanged. The retire-then-recheck
(Dekker) ordering in `march_dispatch_stage` stays: it now protects the slot
rewrite rather than an unmap.

Why not pin per closure (option (b)): a per-version count of live closures only
covers closures. A patch's statics and drop-table entries also point into its
image. It would also put work on every closure allocation and release, and a
cell released through the generic `march_decrc` path does not know which image
built it. Filed as a follow-up:
`specs/todos/2026-10-13-hcr-unload-unreachable-patch-images.md`.

**Known limit: one mapped `.so` per deploy, accumulating until restart.** Each
(deploy, slot) handle reference is kept. Identical files share one mapping:
dlopen refcounts by file, and the reload server loads each artifact from one
digest-named path. So the cost is the patch images' mapped size, mostly
file-backed clean text that the kernel can evict. A restart reclaims it. Measure it with
`march_dispatch_retained_images()`. Hot path cost: none. No closure allocation
or release path changed, and the emitted IR of every non-hot-reload build is
byte-identical (below).

**Tests.**
- `test/hcr_closure_pin/` (dune rule `hcr_closure_pin.out`, every platform):
  a `--hot-reload` base and four `--compile-so` patches (v2, v1, v2, v1, as four
  distinct files), deployed in process by `shim.c` (ACTIVATE minus the
  socket, with no close hook). The base keeps one closure in 97 that each
  version built and calls them all after the fourth deploy, when the ring has
  reclaimed patch 1. Its ASan leg runs in `specs/lang/golden/sanitize.sh`
  (`hcr_closure_pin_leg`, CI `sanitize-gate` shard 1).
- `test/test_dispatch.c` `test_reclaim_retains_image`: with no close hook, a
  reclaim and a shutdown retain fake handles (a real dlclose of them would
  crash) and count them. The dune rule now also lists `march_trace.h`, which
  `march_dispatch.c` includes: on a fresh `_build` the runner did not compile.

**RED/GREEN** (the fixture, compiler × runtime from origin/main `3d2925fce` or
this branch, copies in a scratch worktree):

| compiler / runtime | macOS plain | Linux plain | Linux ASan+LSan |
|---|---|---|---|
| main / main | SIGSEGV, pc == addr | SIGSEGV, pc == addr | SEGV |
| fix / main (P1 alone unfixed) | SIGSEGV | SIGSEGV | SEGV |
| main / fix (P2 alone unfixed) | runs; `delta=9903` | same | runs; LSan 9 895 allocations |
| fix / fix | expected output | expected output | clean |

`sanitize.sh`'s leg on its own: CLEAN with this branch's runtime, SANITIZER FAIL
(SEGV) with main's. ir-oracle (origin/main compiler as baseline, this branch's
as check, private HOME, corpus split in six chunks): 493 programs emitted,
IR identical. Red check: a one-line perturbation of main's prologue made all of
them differ.
