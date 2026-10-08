# CAS tests no longer leak synthetic artifacts into ~/.march/cas

`test_cas_cache_hit` ("track integration" case 6, run_stdlib) creates a temp
project store and asserts the first `Pipeline.compile_scc` pass calls the fake
compiler. Since B7.3 `Cas.create` also sets `global_root` from `$HOME`, artifacts
are written through to `~/.march/cas/artifacts-v2/`, and a local miss consults it.
The test's fake 3-byte `OBJ` artifacts therefore persisted, and every later run
(any worktree, same compiler key) got global hits on the first pass and failed
deterministically with `first pass: compile called`.

Fix: `Cas.create` takes `?(use_global = true)`; `~use_global:false` yields a store
with no global root (no write-through, no global lookup). Production callers
(`bin/main.ml`) are unchanged in behaviour. Every `Cas.create` in `test/test_cas.ml`
(including `test_cas_artifact_survives_source_overwrite`, which stored `AAA`/`BBB`
artifacts) and `test/test_stdlib_suite.ml` now passes `~use_global:false`.

Proof: with the flag removed from `test_cas_cache_hit` the case fails on the second
run against the polluted store; with it, it passes repeatedly.

Existing fake `OBJ` entries already in `~/.march/cas/artifacts-v2` are inert
(keys include the source digest) and can be removed with
`grep -rl -x OBJ ~/.march/cas/artifacts-v2`.
