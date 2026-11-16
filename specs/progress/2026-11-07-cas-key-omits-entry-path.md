`[P2]` A compiled artifact is reused for the same source at a different path, with the old path baked in.

Found 2026-11-07 reviewing `fix/js-test-runner-gaps`. The source-level CAS key (`early_cas`
in `bin/main.ml`) hashes the entry's CONTENTS, the stdlib and its sibling/`MARCH_LIB_PATH`
files, but not the entry's own path. A `--compile --test` binary bakes the entry's path into
every failure report (`-- TEST FAILURE -- /path/to/file.march`), so compiling the same source
from a second directory is served the first directory's binary (through the global
`~/.march/cas/artifacts-v2/` write-through, even after clearing the project store) and its
reports name a file that is not the one compiled.

Repro: `test_js_test_runner` ("--target js --test runs the tests like the native runner
(#1176)", `test/test_codegen.ml`) writes its source to a fresh temp dir each run. Its first run
on a given compiler binary passes; every later run fails, the native output naming the first
run's temp dir and the JS output the current one:

```
./_build/default/test/run_codegen.exe test iface_impl_mono_codegen 13   # OK on a cold HOME
./_build/default/test/run_codegen.exe test iface_impl_mono_codegen 13   # FAIL: stale path
```

CI passes only because it starts cold. Any other path the binary embeds (runtime-error
locations) is exposed the same way. Fix: put the entry's realpath (`entry_real`) into the key,
at least when the artifact embeds it, and add a test that compiles one source from two
directories and checks the second binary's report path.

## 2026-11-09: fixed

Both source-level digests in `bin/main.ml` (the walk digest and `depend_digest`, which keys the
next run and the stored artifact) now start with the entry path **as written on the command
line**. That spelling, not the realpath, is what a build embeds: a runtime panic prints
`-- RUNTIME -- p.march` for `march --compile p.march` and the absolute path for
`march --compile /abs/p.march`, and a `--test` failure report does the same. So `/a/m.march`
then `/b/m.march` no longer share an artifact, while two projects that both build `m.march`
from their own directory embed the same text and still share one (B7.3's global-store hit is
unchanged).

Pinned by `test/test_cas_b7.ml` "the entry path as written is part of the source-level key"
(red before the fix: B was a source-level hit and its panic named A's file).
