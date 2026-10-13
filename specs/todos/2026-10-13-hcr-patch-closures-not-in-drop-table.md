`[P2]` Hot reload: a patch's closures leak their captures when released outside their apply

Found by the HCR Phase 0 spike (`specs/progress/2026-10-13-hcr-phase0-spike.md`,
experiment E1; prototype in `specs/spikes/2026-10-13-hcr-phase0/`).

## Symptom

`march_clo_release` (runtime/march_runtime.c) finds a dying closure's
capture-release function in a table keyed by apply code pointer, which
`march_clo_register_drops` fills from the MAIN binary's prologue only. A patch
`.so` never registers its own, so a closure type the patch introduces leaks
every capture when the base drops it without calling it, or after calling it
(5 objects per request in the reproducer, about 1.3 MB of LSan reports per
10 000 requests). The runtime comment already lists "one built by a hot patch"
as a known leak.

```
specs/spikes/2026-10-13-hcr-phase0/run.sh /tmp/o v1 v2_newshape   # live_allocs delta=49962
```

## Direction

Have `__march_init` call the patch's `march_clo_drops_register` (closure pairs
and record shape drops), as the spike's
`specs/spikes/2026-10-13-hcr-phase0/patch-registers-closure-drops.diff` does
(env-gated there). With that diff the leak is gone and the run is LSan-clean on
Linux. Land it together with
`2026-10-13-hcr-reclaimed-patch-unmaps-live-closure-code.md`: the table never
removes keys, so once a patch is unloaded its entries point at unmapped drop
functions, and a later image mapped at the same address could match a stale key.
