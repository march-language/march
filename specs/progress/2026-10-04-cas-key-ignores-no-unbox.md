# DONE `MARCH_NO_UNBOX=1` was missing from the CAS key

Found and fixed 2026-10-04 while reviewing the codegen CAS tags.

## The bug

`MARCH_NO_UNBOX=1` (`Contract_pipeline.unboxing_env_disabled`, read once per
process) classifies every type Boxed, restoring the pre-Milestone-3
representation for bisection. That changes the emitted code without changing
the compiler binary, but `codegen_cas_tags` in `bin/main.ml` did not include
it, so the same source compiled with and without the variable hashed to the
same `.march/cas/artifacts-v2/` entry and an A/B run reused whichever variant
was cached first.

## The fix

`codegen_cas_tags` appends a `"nounbox"` tag when the lazy is set, in the same
style and for the same reason as the `"noinlinerc"` (`MARCH_NO_INLINE_RC`,
f49c43b6, 2026-10-01) and `"nohofspec"` (`MARCH_NO_HOF_SPEC`, 900ccb80,
2026-10-01) tags next to it. `MARCH_DEBUG_CASFLAGS=1` prints the full tag list,
so it shows the new tag with no further change. The lazy already lives in
`lib/tir/contract_pipeline.ml`, which has no `.mli`, so nothing needed exposing.

## Verification

Written in a container without `dune`/`opam`: the change is unbuilt and
untested here. It is a one-line addition mirroring the two tags above it.
