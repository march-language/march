# Driver built its runtime from a partially staged `_build/default/runtime`

The stdlib doctest step in `conformance (ubuntu-24.04)` took 180-310 s on CI
(PR #663 hit its 5 min timeout). The same script takes ~25-30 s cold locally
and in an Ubuntu 24.04 container. #672 raised the budget to 15 min. This entry
records the actual cause and fix.

## Cause

Per-session timing (#675) showed every one of the 7 REPL sessions taking
~25 s, each printing:

    march JIT: stdlib cache load failed (... stdlib_prelude_...so:
      undefined symbol: march_ed25519_seed_keypair)

- `dune build @vault-scale` (an earlier step in the same job) builds two C
  runners whose rules in `test/dune` list individual runtime files as deps.
  That stages a partial `_build/default/runtime`: `march_runtime.c` but not
  `march_nacl.c` or `tweetnacl.c`.
- `Toolchain.runtime_dir` accepted the first candidate containing
  `march_runtime.c`, which was that partial directory. `ensure_runtime_so`
  guards every other file with an existence check, so it silently built a
  runtime `.so` without the ed25519 builtins.
- The REPL's stdlib prelude `.so` references those symbols, so its dlopen
  failed in every session. Each session recompiled the prelude (~25 s) and
  then fell back to lazy lowering without a type map, which `repl_jit.ml`
  documents as a miscompile hazard.

Reproduced locally: `dune build --root . test/test_vault_distinct_keys_scale_runner`
followed by the doctest script with a fresh `HOME` takes 107 s, against 25 s
without the partial staging.

## Fix

- `bin/toolchain.ml`: `runtime_dir` prefers a candidate that is complete,
  meaning it has a `sources.list` and every `core` file that manifest names. A
  partial staging has no `sources.list`, so the driver uses the source tree
  instead. If no candidate qualifies, the old rule (first with
  `march_runtime.c`) still applies, so layouts without a manifest keep
  working. Installed toolchains ship `runtime/sources.list`.
- `scripts/check-stdlib-doctests.py` prints each session's time and the REPL's
  `[timing]` lines, and fails on any `march JIT:` prelude-load error. Checked
  both ways: forcing the partial directory with `MARCH_RUNTIME_DIR` gives
  13 failures and exit 1; the default run gives exit 0.
- `.github/workflows/ci.yml`: the doctest step budget goes back to 5 min.

`lib/cas/cas.ml` keeps its own march_runtime.c-only search, but it is only a
fallback: the driver registers the directory it chose through
`Cas.set_runtime_dir`.
