# DONE 2026-09-24: `--check` CAS short-circuit keyed on `--no-cap-strict`

**Fixed.** The `--check` early CAS short-circuit in `bin/main.ml` (the
`~target:"check"` lookup right after the source digest) cached a clean verdict
keyed on the source digest only. `--no-cap-strict` (`cap_strict := false`) also
changes the verdict: `Typecheck.cap_strict_ceiling` is set from it on the
`--check`/`--check-json`/`--emit-core-ast` path, and that is what rejects a
stdlib-mediated capability use (`File.write` in a module with no
`needs IO.FileWrite`). So `march --check --no-cap-strict f.march` exiting 0
seeded an artifact that the next plain `march --check f.march` of the same
source found, exited 0 and printed nothing.

The key now carries `"capstrict"` when the ceiling is on, the same spelling
the `--compile` path's `build_cas_key` already used, so the strict and relaxed
verdicts have different keys. Measured before the fix in a scratch directory:
cold plain `--check` rc=1 with the ceiling error, `--check --no-cap-strict`
rc=0, warm plain `--check` rc=0 and silent. After: warm plain `--check` rc=1
with the same error.

**Regression test:** `test/test_check_cas_cap_strict.ml`, registered in the
`march-compiler` suite (`scripts/run-tests.sh compiler`). Driver-level on
purpose, in `test_tcenv_cli_cache.ml`'s style: it runs `_build/default/bin/main.exe`
as a subprocess on a temp file from a private scratch cwd (so the `.march/cas`
it writes is its own) with a private `HOME`. It first asserts the cold plain
run rejects for the ceiling reason (the control that keeps the case
non-vacuous), then runs `--check --no-cap-strict` and asserts it accepts, then
runs plain `--check` again and asserts exit 1 plus the
`does not declare \`needs IO.FileWrite\`` diagnostic. Verified RED against the
unfixed driver ("exited 0 (expected 1)") and GREEN after the fix.

**Not changed:** the compile-path key, which already carried `"capstrict"`
(`specs/progress/2026-08-04-cap-ceiling-strict.md`). The early short-circuit
is gated on `do_check` alone, so `--check-json` / `--emit-core-ast` runs without
`--check` never took it and were not affected; with `--check` they now get the
corrected key too.
