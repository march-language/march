# Check/report switches answered by the build cache

**Filed and fixed:** 2026-10-12. Same family as
`project_refine_report_cas_shortcircuit` (--refine-report printed nothing on a
warm cache) and `2026-09-22` (sanitizer mode missing from the key).

## Symptom

`MARCH_VERIFY_TIR_LEAKS` was not part of the CAS key. A `--verify-tir` compile
with leak reporting on, after one with it off, hit the source-level cache and
checked nothing. The TIR verifier sweep's first leaks-on pass reported 11
programs instead of 485: a plain `--verify-tir` sweep had already cached the
rest under the same key (`verify-tir` was keyed; the leaks switch was not).

The same hole hid the output of every other check/report switch that leaves
the binary unchanged:

- `--emit-llvm --compile` wrote no `.ll` on a warm cache (both layers hid it:
  the source-level hit exits before parsing, and the post-TIR hit skips
  emission).
- `--dump-provenance`, `--dump-tir`, `--dump-phases`, `--dump-impl-hashes`
  with `--compile`.
- The env-var dumps and audits read inside the compiler: `MARCH_DUMP_TXT`,
  `MARCH_DUMP_CAP_PASSING(_FN)`, `MARCH_DUMP_CAP_ROWS`,
  `MARCH_DUMP_TOPOLOGY_MAIN`, `MARCH_TRMC_REPORT`, `MARCH_MONO_REPR_REPORT`,
  `MARCH_ALIAS_AUDIT`, `MARCH_REPR_AUDIT`, `MARCH_DEBUG_PERCEUS`,
  `MARCH_DEBUG_BORROW`, `MARCH_DEBUG_HANDLER_OWNER`, `MARCH_DEBUG_TC`,
  `MARCH_DEBUG_ORDER`, `MARCH_REFINE_Z3_LOG`, `MARCH_REFINE_Z3_ERRORS`.

One verdict input was missing from the key outright: whether z3 can be found
(`MARCH_Z3`, else `z3` on `PATH`). Without z3 an obligation z3 refutes comes
back unverified (a hint, rc 0); that verdict was cached and served to the
next build that had z3, which should have failed with `refinement_violated`.

## Fix (bin/main.ml)

- `source_cache_bypass ()`: any verifier (`Tir_verify.enabled ()`, i.e.
  `--verify-tir`, `--verify-tir-rc`, `MARCH_VERIFY_TIR(_RC)`; the leaks switch
  only acts under it), dump flag or listed env var skips the source-level
  lookup (and so the source-level store, like the existing `--refine-report`
  bypass). Bypass, not a key tag: the binary is identical, and the run that
  asked for a check must run it.
- `post_tir_cache_bypass ()`: `--emit-llvm` and `MARCH_REPR_AUDIT`, the only
  outputs produced after the post-TIR lookup, skip that lookup too.
  Everything else (the verifier included) has already run by the time it is
  reached, so a post-TIR hit is still allowed for them.
- `z3_cas_tag ()`: `noz3` in both the `--check` key and `build_cas_key` when
  z3 cannot be found. Keyed, not bypassed: it changes the verdict, and a
  z3-less build is still cacheable against other z3-less builds. Only the
  absence is tagged, so ordinary keys are unchanged.
- `MARCH_DEBUG_CASFLAGS=1` prints which switch forced a bypass.

### Audited and already right

Keyed in `codegen_cas_tags`/`build_cas_key`: `--rc-trace`/`MARCH_RC_TRACE`,
`--debug-info`, `--debug`/`--debug-tui`, `--disable-pass`/`MARCH_DISABLE_PASS`
(so `--bisect-pass` probes, which use it, are keyed), `--fast-math`,
`--pin-main`, `--test`, `MARCH_SANITIZE` (mode), `MARCH_SANITIZE_CC`,
`MARCH_MALLOC`, `MARCH_HTTP_EVLOOP`, `MARCH_CAP_PASSING`, `MARCH_CAP_DISPATCH`,
`MARCH_NO_INLINE_RC`, `MARCH_NO_HOF_SPEC`, `MARCH_NO_NATIVEARR_FUSION`,
`MARCH_NO_OWNED_CALLS`, `MARCH_NO_UNBOX`, `--verify-tir` (tag kept so a
verified build never stores over the plain entry). Covered by other key
inputs: `MARCH_STDLIB` (stdlib digest), `MARCH_RUNTIME_DIR` (runtime
identity), `MARCH_LIB_PATH` (source walk), `MARCH_CROSS_SYSROOT*` (sysroot
digest). Already bypassed: `--refine-*`, `--report-contracts`,
`--dump-role-authority`, `--emit-protocols`.

Deliberately left alone: `--timings` (timing a hit is a real measurement and
how the hit's layer is told apart), `MARCH_ECHO_CC` (a hit runs no clang),
`MARCH_DEBUG_CASFLAGS` (reports the key itself), `MARCH_DEBUG_RUNTIME` and
`MARCH_FFI_SHIM_LDFLAGS` (interpreter/JIT `.so` only, not the CAS),
`MARCH_NO_RUNTIME_CACHE` (the runtime object cache, not the CAS).

## Tests

`test/test_cas_report_bypass.ml` (run_compiler, `Slow`): each compiles once
without the switch and once with it in the same HOME/store and asserts the
second run did the work: leaks run reaches the TIR pipeline and matches a
cold leaks run's rc and verifier header; `--emit-llvm` writes `m.ll`;
`--dump-provenance` prints the table; `MARCH_TRMC_REPORT` prints its lines;
a z3 build after a z3-less one fails with `refinement_violated`. Against the
pre-fix compiler all five fail.
