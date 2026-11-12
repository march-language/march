# LSP jsonrpc suite: hang guards too tight for the CI `rest` shard

**Fixed 2026-11-12.**

`test (ubuntu-24.04, rest)` failed intermittently on `main` (run 43222014062) and on
PRs that do not touch the LSP (#1250, #1255, #1258): `stdio 4` (pull diagnostics on a
clean buffer) timed out with "march-lsp did not respond (timeout)" and `stdio 6` with
"a document with no project root hung the server".

Neither was a hang. Each `test_jsonrpc` session arms a `SIGALRM` guard; five of them
were 10-30s. On a green CI run the 37 cases take 150-220s in all (about 4s each run
alone locally), because the shard runs this suite beside the other test executables,
so one slow session crossed 25s.

Fix: those five alarms use one `hang_guard_s = 120` in `lsp/test/test_jsonrpc.ml`.
They still fail a server that never answers, including the unbounded
filesystem walk `stdio 6` was written to catch, which never finishes.
