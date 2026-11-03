# Hot-reload compiles: three driver costs removed, and the two-node builds run at once

**Landed** 2026-11-03.

## Why

After early DCE (specs/progress/2026-11-02-early-dce-after-defun.md) the
slowest CI jobs were the two-node shards (26-35 min) and the Ubuntu `rest`
shard (46-50 min). Both are dominated by `--hot-reload` builds: the
`control_*`, `hcr_*` and `protocol_*` scenarios build a baseline and one or
more patches each, serially (a `control_*` scenario spent 2-4 of its 3-6
minutes compiling), and `rest`'s long pole is `upgrade-from`, `deploy-e2e`
and `hcr-manifest-diff`, which build the same way. A hot-reload build keeps
every slot function, so it misses most of what early DCE saved.

`--timings` on `test/two_node/control_plane/app.march` (the control-plane
app, `--hot-reload CtlApp --signing-pubkey ... --topology ...`) showed three
costs in the driver, none of them in a compiler pass:

- **`Llvm_rc_inline.rewrite`, ~10 s.** It scans every line of the finished
  module and allocated a substring at every character, six times per line
  (once per refcount entry point), plus 18 concatenated strings per line for
  the `declare` check. Now it allocates nothing on a line with no match. This
  pass runs on every native compile; a hot-reload module is just large
  enough to make it show.
- **The HCR manifest, built twice, ~4 s.** The post-TIR CAS key folds in
  `hcr_manifest ""` and emission embeds `hcr_manifest ch`; all the work but
  the header line ran both times. Now `make_hcr_manifest a b c` builds the
  per-function and ROLE lines once and returns a function of `ch`.
- **The role solve, repeated, ~3.6 s.** `role_capability_closures` (the
  manifest's ROLE lines) re-ran the solve `check_role_grants` had already
  run in typecheck. What it reads (keyed roots, own/refs/rows) does not
  depend on `decls`; the solve is memoized, keyed on the env tables it
  reads (the driver holds a copy of `final_env`, so not on the record).
- **The C runtime, recompiled on every hot-reload server build, ~8 s.** The
  precompiled runtime-object cache (Stage A, `lib/cas/runtime_archive.ml`)
  excluded any `--hot-reload` build because `--signing-pubkey` and the HCR
  identity bake `-D`s into the runtime. Only four files read them
  (`march_sig.c`, `march_reload.c`, `march_shell.c`,
  `march_hcr_identity.c`); those stay sources on the final command line,
  in their old position, and the rest come from the cache.

On the script side, `scripts/two-node.sh` gains `bg_build` / `wait_builds`
(independent builds in the background, at most `TWO_NODE_JOBS` at once:
one takes ~1.5 GB) and `compile a b [c]` (a scenario's nodes at once). Each
concurrent compile has its own working directory, since a compiler's cwd
holds its CAS, whose writes are not atomic. Used by `ctl_prepare` (six
`control_*` scenarios), `hcr_role_policy`, `hcr_rollback`,
`hcr_new_code_session`, `hcr_remote_msg_epoch`, `protocol_evolve` and
`protocol_expand_contract`.

## Measured

`--timings` on the control-plane app, server binary, on an M-series Mac,
measured one run at a time (the session's later A/B rerun was lost to a load
average of 280 from another session; CI's job times are the real check):

| stage | main | this change |
|---|---|---|
| `cas-hash` to `llvm-emit` (HCR hashes, ABI, manifest, emission, IR rewrites) | 21.0 s | 3.7 s |
| `clang`, warm `HOME` (runtime objects cached) | 21.2 s | 13.7 s |
| whole build, warm `HOME` | ~51 s (derived*) | 26.4 s |

\* Not one measured run: 34.1 s measured with every change but the runtime
cache, plus the 17.3 s the emit-side changes saved. A cold-`HOME` build of
main measured 63.2 s.

A patch `.so` (`--compile-so`, which never linked the runtime) measured
26.6 s after the change. The typecheck stage varied 4.5-12.6 s from run to run
with machine load and is not counted.

## Equivalence

- `--emit-llvm` of four hot-reload programs (the control-plane app and its
  v2 patch, `hcr_rollback`'s and `hcr_new_code_session`'s node-a) is
  byte-identical to main's: 18,420 rewritten refcount calls, the embedded
  manifest and its ROLE lines.
- `scripts/oracle-base.sh ir`: IR IDENTICAL across 515 programs against
  main (5cdfd2b0f7).
