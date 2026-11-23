`[P3]` Compile CAS serves a `--compile --test` binary built from another path

A `--compile --test` binary embeds the source file's path in every failure report
(`-- TEST FAILURE -- /abs/path/file.march`), but the compile CAS key does not include that
path: the same source content compiled from a different directory is a cache hit and reports
the old path. Seen in `test/test_codegen.ml` `test_js_test_runner` (#1176,
`iface_impl_mono_codegen` case 14): it writes the program to a fresh temp dir each run, so the
native half passes on a cold cache and fails on the second run (its report names the first
run's temp dir), while the JS half names the current one. Reproduce: move
`.march/cas/artifacts-v2` aside, run the case twice with a private `HOME`; the first passes, the
second fails. Fix in the cache key (include the display path of anything embedded in the
binary), not in the test.

## Closed 2026-11-22: already fixed

Fixed by `195fddc1b` (2026-11-09, "cas: key the source-level cache on the entry path as
written"; `specs/progress/2026-11-07-cas-key-omits-entry-path.md`), which left this file open.
Re-checked on `40f901bab`: the same failing test file at two absolute paths, compiled with
`--compile --test` from one cwd under one private `HOME`, reports its own path in each binary,
cold and `(cached)`.
