# Two quadratic name scans after `opt` (CAS SCC build, alloc contracts)

Found by `scripts/compile-time-bench.sh` (B0 of `specs/plans/incremental-codegen-cas-plan.md`):
on `examples/topology_app` at `--opt 2`, ~5.7 s of an 18.8 s leaf-edit compile, and most of an
8.0 s comment-edit (post-TIR cache **hit**) compile, ran between the `opt` stamp and `llvm-emit`
with no stamp of its own. The baseline attributed it to `lib/cas/scc.ml`. Stamping the window
showed it was two costs of similar size, both a per-reference linear scan over every definition
in the whole program (stdlib included):

1. **`lib/cas/scc.ml` `refs_in_expr`/`refs_in_atom`** tested each variable/def reference with
   `List.mem v.v_name known`, `known` being the list of all `tm_fns` names: O(references x
   definitions). It runs twice per compile (Tarjan's `compute_sccs`, then the Merkle fold in
   `Pipeline.hash_module`) and again in `bin/main.ml`'s `hr_slot_hashes` under `--hot-reload`.
   `known` is now a `(string, unit) Hashtbl.t` built once per caller (`Scc.known_of_names`), and
   the walk threads an accumulator instead of `@`-concatenating lists. `deps_of` still
   `sort_uniq`s, so the dependency lists, and therefore every hash, are unchanged.
2. **`lib/tir/alloc_contract.ml` `decl_of`** was
   `List.find_opt (fun d -> d.d_name = base name) decls`: `base` is
   `Tir_names.strip_specialization_suffix`, recomputed inside the closure once per decl on every
   lookup (`is_assume` calls it for every function and call site). These were the
   `String.rindex` / `find_dollar` / `strip_specialization_suffix` frames in the profile, which
   had been misread as part of `scc.ml`. `base name` is now computed once per lookup.

`--timings` now stamps both phases: `alloc-contract` (in `Contract_pipeline`, after
`Alloc_contract.check`) and `cas-hash` (in `bin/main.ml`, after `Pipeline.hash_module`).
`compile-time-bench.sh`'s three buckets are unchanged (they read `typecheck`, `opt`, `clang`).
`MARCH_DEBUG_CASFLAGS=1` now also prints `src=`, a digest of the key's source/TIR input alone.
`ch=` folds in the compiler executable's own digest, so it differs between any two compiler
builds and cannot show that a hashing refactor kept the key; `src=` can.

## Measured (2026-10-05, Apple M3 Max, load average 15-50 from other sessions)

Same-tree A/B of the stamped phases on topology_app, 3 interleaved runs each:

| phase | before | after |
|---|---|---|
| `cas-hash` (SCC build + Merkle hashing) | 4.35-4.44 s | 0.20 s |
| `alloc-contract` | 3.06-3.69 s | 0.27-0.36 s |

`scripts/compile-time-bench.sh --corpus topology` (`--opt 2`, 3 runs, medians; cpu = user+sys,
the number to trust under load):

| scenario | before wall / cpu | after wall / cpu |
|---|---|---|
| cold | 38.8 s / 33.1 s | 27.3 s / 25.3 s |
| comment (tir-hit) | 11.2 s / 10.9 s | 4.3 s / 4.1 s |
| leaf (miss) | 26.0 s / 25.3 s | 18.4 s / 18.2 s |

## Verified

- Post-TIR `src=` digests byte-identical between the old and new compiler for topology_app
  (cold, warm and comment-edit) and `bench/tree_transform.march`.
- `scripts/ir-oracle.sh` baseline (old compiler) / check (new compiler).

Found while measuring, filed separately: the post-TIR hash of an unchanged source differs
between a cold and a warm `$HOME` stdlib cache (`e69c3b…` vs `36a9b9…` on topology_app), with
the old and new compiler alike, so the whole-program TIR depends on cache state.
