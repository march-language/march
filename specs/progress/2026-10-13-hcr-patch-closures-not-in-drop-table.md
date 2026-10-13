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

## Fixed 2026-10-13

**Cause.** `march_clo_register_drops` was called only from the main binary's
prologue (`@march_clo_drops_register`, `Llvm_toplevel.clo_drop_registration`).
A `--compile-so` patch's `__march_init` registered nothing, so
`march_clo_release` found no capture-release function for a closure type the
patch introduced, and freed the cell without its captures.

**Fix.** The spike diff, without its env gate:
`__march_init` (lib/tir/llvm_toplevel.ml, emitted only for
`--compile-so --hot-reload`) calls the patch's own internal
`@march_clo_drops_register`, which registers its (apply, release) pairs and its
record shape drops. Registration is idempotent per key (a re-tried deploy runs
`__march_init` again: same mapping, same keys, an in-place overwrite).

**Why the table's entries stay valid.** Keys are never removed, and they don't
have to be: it landed together with
`2026-10-13-hcr-reclaimed-patch-unmaps-live-closure-code.md`, under which no
patch image is ever unmapped (`march_dispatch_retain_image`; the reload
server's failure path keeps an image once its `__march_init` has run). Every
registered apply and drop pointer stays mapped for the life of the process,
and no later image can be mapped at a registered address.

**Non-hot-reload builds are unchanged**: only the `--compile-so --hot-reload`
branch of `emit_module` changed. ir-oracle identical over 493 programs (see the
companion record).

**Tests and RED/GREEN.** `test/hcr_closure_pin/` checks the net heap objects
at exit (`live_allocs bounded=true`). With this branch's runtime but
origin/main's compiler, it reports `delta=9903` (macOS and Linux), and LSan on
Linux reports 9 895 leaked allocations. With both fixes it is bounded and
LSan-clean. Details are in the companion record's table.
