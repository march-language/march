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
