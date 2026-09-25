# March `simd-map2` timing is bimodal on Linux x86_64 (about 22 ms or about 160 ms)

Filed 2026-09-25 from the cross-language benchmark refresh
(`bench/results/2026-09-25-x86_64-xeon-cloud.txt`, `bench/RESULTS.md` "Latest run").

## Symptom

`bench/simd_map2.march`, compiled `--compile --opt 2` with the `nightly-20260924`
compiler (commit `59ecf17`), on a 4-vCPU Xeon @ 2.10GHz cloud VM. The self-timed
region (`native_float_arr_alloc_raw` plus the inlined map2 loop) alternates
between two modes across process runs:

```
March: 160 36 164 23 163 30 172 27 177 45 162 22   (ms, consecutive runs)
Rust:   22 22 21 21 21 21 20 22 22 23 25 21
```

The 10-run benchmark median came out at 97.4 ms (min 20.7, max 196.8). The
2026-08-04 dedicated-x86 run measured 19.8 ms with a tight spread, and
`simd-map` (the one-array shape) is steady at about 20 ms on the same box.

## Ruled out so far

- **Hypervisor steal:** under 1% during the runs; Rust is flat on the same box.
- **Threads:** persists with `taskset -c 0`, `MARCH_NUM_SCHEDULERS=1` and
  `MARCH_PIN_MAIN=1`.
- **Address layout:** persists with ASLR off (`setarch -R`).
- **Page faults:** minor-fault counts and max RSS are identical in fast and slow
  runs (about 225k faults, about 900 MB RSS). Slow runs do show a few thousand
  more voluntary context switches.
- **Missed inlining:** `--emit-llvm` shows the `nmap2_*` inlined loop with
  `native_arr_map2_check_len` and no `native_float_arr_map2` call, so the
  unboxed path from the map2 fix history is what runs.

## Next steps

1. Reproduce on a build of current `main` (this was a nightly binary; the box
   had no opam switch), and on macOS/arm64.
2. `perf stat`/`perf record` a fast and a slow run of the same binary and diff.
   The about 900 MB RSS for three 5M-float arrays suggests the two 5M-element
   source `List(Float)`s are still being freed, or reclaimed, around the timed
   region; check whether that work can overlap the loop.
3. If it is teardown of the input lists, consider moving list construction and
   freeing fully out of the timed region in the benchmark, and separately decide
   whether the runtime behaviour is a bug.
