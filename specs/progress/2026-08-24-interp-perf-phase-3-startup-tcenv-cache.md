# Phase 3: `march file.march` reuses the cached stdlib typecheck env

Filed and fixed 2026-08-24. Task 3.1 of
`.superpowers/sdd/2026-08-23-interpreter-and-repl-jit-performance/task-3.1-brief.md`,
scoped down to Step 4 (the `bin/main.ml` wiring) + Step 5 (validation) after
PR #337 (commit `2dff9d87`) already fixed the REPL's cache save path and
exported `stdlib_content_hash` / `load_cached_tc_env` / `save_cached_tc_env`
/ `marshalable_tc_env` / `sweep_stale_cache_tmps` from `lib/repl/repl.mli`,
with round-trip coverage in `test/test_repl_cache.ml`.

## What was slow

Every `march file.march` — interpreted run or `--compile` — typechecks
stdlib and the user module together as one combined `Ast.module_` via
`Typecheck.check_module_full` (`bin/main.ml`, the shared site before the
`if !do_compile` / interpreted-run split). Stdlib alone is the dominant
fixed cost of that call, paid again on every single invocation regardless of
whether the user's own file changed.

## The site, and why it isn't the REPL's cache

`bin/main.ml` already had a *second*, separate stdlib-typecheck-env disk
cache — `get_stdlib_tc_env` (added earlier, `stdlib_tcenv_cli_*.bin`) — used
only by `run_check_cmd` (`march check` / `march caps`). Its docstring
explains why it is deliberately NOT the REPL's `stdlib_tcenv_*.bin` cache:
the REPL's env is built by folding `Typecheck.check_decl` over stdlib decls
one at a time (and is known to tolerate real typecheck errors in some
stdlib modules — see `Repl.load_decls_into_env`), whereas `get_stdlib_tc_env`
is built via the same `check_module_core` pass-1/1b/2 machinery a combined
check already trusts, applied to stdlib alone first. Seeding a user-only
`check_module_core` call from that env is behaviorally identical to what a
full combined check would have produced for stdlib's own portion — not a
reduced approximation.

Reusing the REPL's own `March_repl.Repl.load_cached_tc_env` /
`save_cached_tc_env` directly at this site would have written to the exact
same cache filename (`stdlib_tcenv_<build>_<hash>.bin`, same hash function,
same build id) that a REPL session populates via the fold-based path — a
namespace collision that could hand `march file.march` a differently-shaped
env than a combined check would have produced, silently changing user-file
diagnostics. `get_stdlib_tc_env` already avoids this (`_cli` suffix, own
filename), so this change reuses it rather than duplicating a third cache.

## The fix

In `bin/main.ml`'s `compile` function (the single path both `--compile` and
interpreted runs go through up to the typecheck call):

- Captured `user_only_desugared` — the entry file + resolved imports, in the
  same form used later, but *before* stdlib decls get prepended into
  `desugared` for lowering.
- Replaced the single `check_module_full desugared` call with:
  ```
  let seed_env = get_stdlib_tc_env ~for_js:is_js_target stdlib_decls in
  March_typecheck.Typecheck.check_module_full ~seed_env user_only_desugared
  ```
  `stdlib_decls` here is the already shadow-filtered list (a user module
  reusing a stdlib module name has its stdlib copy stripped earlier in the
  same function), so a shadowed stdlib module naturally produces a different
  cache key instead of needing a separate no-shadowing fallback the way
  `run_check_cmd` needs one.
- `desugared` (stdlib-prepended, used for TIR lowering further down) is
  untouched — an earlier attempt at this exact optimization regressed
  `--compile` by also skipping the stdlib prepend into `desugared`, dropping
  stdlib bodies from what gets lowered (see the comment already in the code
  at the prepend site). This change only touches how `(errors, type_map,
  typecheck_env)` are computed, not what gets lowered.
- `check_module_core`'s `?seed_env` reuses the seed's own `type_map`
  hashtable in place, so the returned `type_map` still carries stdlib's span
  entries (needed by lowering) alongside the freshly-checked user entries.

## Verification

- `scripts/run-tests.sh` suites `compiler` (934 tests) and `eval` (273
  tests): both exit 0, cold and warm cache. `codegen` also run as an extra
  safety net given `--compile` shares this call site — exit 0.
- Diagnostics identity: a file with an undefined variable
  (`println(undefined_var)`) produces byte-identical stderr cold-cache vs
  warm-cache vs a pre-patch binary built by `git show HEAD:bin/main.ml`
  (file-copy swap, not `git stash`) — `diff` reports no difference across
  all three.
- Timing (`bench/interp/fib.march`, `HOME`'s real `~/.cache/march`):
  cold ≈1.24s, warm ≈0.36s (includes fib's own interpreted compute time).
  A trivial `println`-only program with `needs IO.Console`: cold ≈1.07s,
  warm ≈0.18-0.19s. The pre-patch binary pays ≈1.0-1.2s on *every* run
  (no caching existed at this shared site before).
