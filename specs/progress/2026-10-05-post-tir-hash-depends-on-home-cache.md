# Post-TIR CAS hash of an unchanged source depends on `$HOME` cache warmth

Found 2026-10-05 while verifying `specs/progress/2026-10-05-post-opt-name-scans-quadratic.md`.
Compiling `examples/topology_app` (`--opt 2 --topology .forge/topology.json`) with a cold
`$HOME` (no `~/.cache/march` stdlib AST/tcenv cache) prints post-TIR
`MARCH_CASFLAGS ... src=e69c3b16…`; the same TIR compiled with a warm `$HOME` prints
`src=36a9b933…` (a comment-only edit, which must not change the TIR, also gives `36a9b933…`).
The same happens with compilers built before and after that change.

Effects: the first compile after a cold one misses the post-TIR cache. More importantly, the
whole-program TIR differs with cache state (fn/type order, fresh-name counters, or Hashtbl
iteration order when stdlib decls come from the cache rather than a fresh parse), which may
be more than a cache-key problem.

Next step: dump the TIR (or per-SCC hashes from `March_cas.Pipeline.hash_module`) in both
states, find the first difference, make it independent of cache state, and add a regression
test that compiles twice (cold then warm private `HOME`) and asserts the same post-TIR `src=`.

## Resolution (2026-10-06)

Fixed by PR #805 (one shared decoder for the cold and warm stdlib env), verified on
`main` at `eea23d6dc` two ways:

- The repro above, run three times in one fresh `$HOME` (cold, warm, warm) with
  `--compile --opt 2 --topology .forge/topology.json`: both `MARCH_CASFLAGS` lines print the
  same `src=` every time (`5864f1cf…` source-level, `d187d508…` post-TIR).
- `scripts/determinism-oracle.sh` (A5, [`2026-10-06-determinism-oracle.md`](2026-10-06-determinism-oracle.md))
  compiles `examples/topology_app` with `--emit-llvm --dump-impl-hashes` cold and warm under
  two private `HOME`s from two cwds: IR and all 2136 per-definition hashes identical. The same
  oracle on a compiler built from `d441bec17` (just before #805) fails on exactly this program,
  1808 of 2136 hashes and 69062 IR lines differing between cold and warm, while cold matches
  cold and warm matches warm. CI's `determinism` job keeps it that way.
