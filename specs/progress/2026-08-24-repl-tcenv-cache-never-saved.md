# The REPL's stdlib typecheck cache had never once been written

Filed and fixed 2026-08-24. Symptom that surfaced it: `~/.cache/march` held
1,132 zero-byte files named `stdlib_tcenv_<build>_<hash>.bin.<pid>.tmp`, the
oldest dating to 2026-08-17 (the retention horizon of that directory, not the
age of the bug).

## What was actually happening

`Repl.save_cached_tc_env` staged the marshalled env through a pid-suffixed temp
and renamed it into place, with the whole body wrapped in `try ... with _ -> ()`.
`Marshal.to_channel oc tc_env []` raised
`Invalid_argument "output_value: functional value"` — **every time** — the
handler swallowed it, and the already-created temp was never unlinked.

The functional value is `Typecheck.import_entry.ie_matches : string -> bool`.
Any env that has folded a decl carrying a `use`/`import`/alias holds such an
entry in `import_tracker` (and in the `import_idx` that mirrors it), so a
post-stdlib env is structurally unmarshalable. There was no version of this
cache that worked: the `[timing] tc_env cache hit` line it prints on the load
path had never been reachable in a real session.

Three consequences, in descending order of how visible they were:

1. one 0-byte orphan per REPL launch, forever;
2. every REPL start paid the full stdlib typecheck fold (~0.7s here);
3. the entire cache-**hit** code path was dead — it had never run outside tests.

## The fix

`lib/repl/repl.ml`:

- **`marshalable_tc_env`** strips `import_tracker` and `import_idx` before the
  write. Sound for the same reason `Lsp.Typecheck_cache.derive` already does
  it: both fields exist only to drive unused-import warnings for the decls that
  populated them, and nothing reports those for stdlib. Imports the user types
  at the REPL register on the live env either way.
- **`Fun.protect`** around the staged write unlinks the temp on any failure, so
  a future unmarshalable field costs a slow start, not an orphan per launch.
- The `with _ -> ()` became a **loud stderr warning**. A cache whose only
  failure mode is "silently slower forever" is a cache that cannot be trusted
  to be working, which is exactly what happened here.
- **`sweep_stale_cache_tmps`** removes `<name>.<pid>.tmp` files in the cache dir
  whose owning pid is gone, run from `load_cached_tc_env` (i.e. on every REPL
  start). Same liveness-based shape as `Repl_jit.create`'s sweep of its per-pid
  tmp dirs, and deliberately conservative: a pid that has been recycled by an
  unrelated live process keeps its file.

`bin/main.ml`'s `get_stdlib_tc_env` writes into the same directory with the same
staging discipline, so it got the same three: sanitize, `Fun.protect`, sweep.
Its own writes were succeeding (its `stdlib_tcenv_cli_*.bin` blobs are valid),
but it had left five 0-byte orphans of its own from killed processes.

## Verification

- New `test/test_repl_cache.ml` (suite `repl_cache`, carried by
  `run_compiler.exe`): a save of an env with a populated import tracker must
  leave a non-empty blob that `load_cached_tc_env` reads back, and no `.tmp`;
  and a dead-pid temp must be swept while a live-pid one survives. Both fail on
  the pre-fix code — the first with exactly the observed orphan filename.
- Real REPL, fresh `HOME`: first start `load_decls 0.701s`, no temp left; second
  start `[timing] tc_env cache hit: 0.083s` + `eval_decls 0.111s`.
- Cache-hit/cache-miss parity: a 12-line REPL script (list/enum/option/result
  ops, a `type` decl, a user `fn`, `:type`) produces byte-identical output on
  both paths — worth doing precisely because the hit path had never executed
  before this change.
- `march warm-cache` now genuinely warms this cache: `tc_env 0.799s (built +
  cached)` on a cold `HOME`, `0.089s (cached)` on the second run. Before the
  fix it printed "built + cached" every single time — the subcommand's whole
  purpose, silently not happening.
- `scripts/run-tests.sh`: all five suites green (compiler 934, eval 262,
  codegen 587, stdlib 868, stdlib_march 61); `scripts/check-docs.sh` passes.
- Sweep against the real `~/.cache/march`: 1132 → 6 temps in one REPL start; the
  six survivors are pid-reuse false negatives, confirmed by `ps` (Slack, keybagd
  and friends now hold those pids).
