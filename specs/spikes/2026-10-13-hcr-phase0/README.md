# HCR Phase 0 spike (2026-10-13) — THROWAWAY

Not wired into the product, the test suites or CI. Kept for the record of
`specs/progress/2026-10-13-hcr-phase0-spike.md`, which has the results and the
go/no-go.

## What it is

One March program (`app.march.in`) that serves N fake "requests". Each one
builds a `SpikeConn` record, calls four boundary functions in `mod Handler`
(`handle(conn)`, `mk(conn)` returning a closure, `tag()` returning a string
literal, `count(headers)` taking a borrowable `List(String)`), keeps using the
values after the call, and keeps every 997th closure and tag string alive to
the end. Mid-run it swaps `Handler.*` to the k-th patch `.so`, in-process.

- `handlers/*.march` are the `Handler` bodies; `run.sh` splices one into the
  template for the base binary (`--hot-reload App`) and one per patch
  (`--compile-so --hot-reload App`).
- `swap_shim.c` (linked into the base with `--ffi-c`) is the swap: dlopen,
  `__march_init`, dlsym, then `march_hcr_activate` as ONE deploy — what the
  reload server's ACTIVATE does, minus socket, signing, CAS and audit log.
  `HCR0_NO_UNLOAD=1` installs a close hook that keeps reclaimed versions mapped.
- `patch-registers-closure-drops.diff` is the spike-only compiler change
  (env-gated, reverted before commit) that makes a patch's `__march_init`
  register its closure capture-release functions.
- `linux-asan.sh` is the Linux ASan/LSan leg (run inside a
  `march-ci-ubuntu-step6b` container with the worktree at `/mnt`).
- `mc.sh` runs the worktree compiler under a private `HOME`.

## Reproduce

```
dune build --root . bin/main.exe @warm-cache
S=specs/spikes/2026-10-13-hcr-phase0
$S/run.sh /tmp/hcr0-out/c  v1 v1                  # control
$S/run.sh /tmp/hcr0-out/e1 v1 v2_newshape         # new closure shape
$S/run.sh /tmp/hcr0-out/e2 v1 v3_owned            # borrow flip (UAF)
$S/run.sh /tmp/hcr0-out/e2r v3_owned v1           # reverse flip (leak)
HCR0_N=50000 $S/run.sh /tmp/hcr0-out/e4 v1 v2b_mk_only v1 v2_newshape v1   # code unload
MARCH_SANITIZE=1 HCR0_HOME=/tmp/hcr0-home-asan $S/run.sh ...                # ASan build
```

Each run prints the totals, `live_allocs delta=` (net heap objects at exit; 7
with no swap, 12 after a clean swap) and the exit status. Use a fresh output
directory and HOME whenever the compiler or `HCR0_PATCH_REGISTERS_DROPS`
changes: the CAS does not key on that variable.
