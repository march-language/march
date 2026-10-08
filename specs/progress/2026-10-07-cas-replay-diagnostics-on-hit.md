# DONE 2026-10-07: B7.1, a cache hit replays the build's warnings

Observability plan (`specs/plans/incremental-codegen-cas-plan.md`) §17, B7.1.

## The bug

A `--compile` that succeeded with warnings cached its binary under the
source-level key. The next identical build hit that entry before the front end
ran, printed `compiled out (cached)` and nothing else: every warning and hint
silently disappeared on a warm cache. The one case anyone had noticed,
`@[no_alloc(warn)]`, was patched by refusing the early exit whenever the hashed
sources contained the text `no_alloc`
(`if contains_substring cache_input "no_alloc" then raise Exit`). That also
threw away every cache hit for any program that merely mentioned it.

## The fix

- `bin/main.ml`: the three places a successful compile prints diagnostics now
  go through `emit_diag_text`, which also appends the text to `replay_log`.
  - desugar warnings (the compact `file:line:col:` form);
  - the user typecheck diagnostics;
  - the `@[vectorize]`/`@[no_alloc]` diagnostics.

  The capability-ceiling report always exits 1, so it never caches.
- `lib/cas/cas.ml`: `store_diagnostics` writes `<blob>.diag` (temp+rename) and
  `lookup_diagnostics` reads it. It is stored with the source-level artifact at
  both the native and the WASM store site, and holds an empty string when the
  compile printed nothing.
- **On a source-level hit**, the stored text is printed before
  `compiled … (cached)`. An entry with no `.diag` (cached before this) is a
  miss, like a missing `.sidecars` record, so the first warm build after upgrade
  rebuilds once.
- **The `no_alloc` text bailout is removed.**
  - `--check` needs neither the bailout nor replay: it caches only runs that
    printed nothing (the existing `printed_user_diag` rule).
  - Runs whose output is a report (`--refine-*`, `--report-contracts`,
    `--dump-role-authority`, `--emit-protocols`) are still bypassed before the
    lookup, as the comment there says.
- The `.diag` record is written per source-level key only. A post-TIR hit
  happens after the front end has already printed this run's diagnostics.

## Test

`test/test_cas_b7.ml` (in `run_compiler`, group `cas_b7`) compiles a program
whose `@[no_alloc(warn)]` contract warns, twice in a fresh project with a
private HOME. It asserts that the second compile is a `(cached)` hit and prints
the same diagnostics as the first. Red: with the replay line disabled, the
case fails.
