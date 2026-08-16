`[P2]` - [x] **LSP parity for the prelude/entry-fn name-collision check (Stage 2 of `specs/plans/2026-08-13-prelude-entry-fn-name-collision.md` §4.2). Fixed 2026-08-14.**

**Fixed.** `lsp/lib/analysis.ml` independently reimplements the same
parse/desugar/stdlib-merge sequence as `bin/main.ml` (§2.3 of the design
spec), and until now had not been updated to run the prelude-collision
check landed for PR #274. That meant a user's editor showed no diagnostic
at all for a top-level `fn` colliding with a name Prelude relies on
internally (e.g. `print`, `reverse`), even though `march --compile`/
`--check` now hard-rejects it — a compiler/LSP disagreement this codebase
treats as a real bug class, not a cosmetic gap.

**What changed:**

- `lib/typecheck/typecheck.ml`: added `prelude_collision_builtin_names` and
  `prelude_collision_iface_arities`, the shared source of truth both
  `bin/main.ml` and `lsp/lib/analysis.ml` now call into, so the two can
  never independently drift from each other or from what the typechecker
  itself treats as a builtin. `bin/main.ml`'s own previously-duplicated
  `ordinary_builtin_collision_names`/`iface_method_collision_arities`
  values were removed in favor of these.
- `lsp/lib/analysis.ml`: after merging desugar diagnostics into the
  typecheck error context, runs `March_modules.Prelude_collision.check`
  against the same `stdlib_decls`/`desugared.mod_decls` the rest of the
  analysis already computes, reporting into the same `errors` context so
  it surfaces through the existing `diag_to_lsp` path (user-file filter,
  span ordering) with no new plumbing.
- Skips the check when the open file IS itself a shipped stdlib module
  (matched by basename against `Stdlib_manifest.all_known`) — mirrors
  `bin/main.ml`'s `is_shipped_stdlib_file` exemption (added the same day
  for CI's `--refine-report stdlib/list.march` ratchet) for the identical
  reason: a stdlib file's own top-level names are only ever loaded
  namespaced in real use, and only collide when the file is itself treated
  as the flattened "entry" — which single-file LSP analysis does exactly
  as much as `--check` does on the CLI.
- `lsp/lib/dune`: added `march_modules` to the library's dependencies.

**Verification:**

- TDD: `lsp/test/test_lsp.ml`'s `"diagnostics"` group gained two cases —
  `test_analyse_prelude_collision_produces_diagnostic` (a bare `fn print`
  shadow, which IS in the dangerous set since `println` calls `print`
  internally, must produce an Error diagnostic naming "redefines") and
  `test_analyse_safe_shadow_no_collision_diagnostic` (a bare `fn head`
  shadow, which is NOT dangerous — nothing in Prelude calls `head`
  internally — must produce zero diagnostics). Watched both RED against
  the pre-fix `analysis.ml` before implementing; watched both GREEN after.
- Caught a test-authorship trap live: the first version of the positive
  test used the shared `analyse` helper's default filename `"test.march"`,
  which collides with the real shipped `stdlib/test.march` (the `Test`
  module) and silently tripped the shipped-stdlib-file exemption meant for
  exactly that file — the test read `is_shipped=true` and suppressed its
  own diagnostic. Confirmed via a temporary debug print, then fixed by
  giving both new tests explicit, non-colliding filenames
  (`shadow_repro.march`/`shadow_safe.march`).
- Full LSP suite: 353 tests, all green (`lsp/test/test_lsp.exe -e`).
- Full compiler suite (`scripts/run-tests.sh`): green — confirms the
  `bin/main.ml` de-duplication onto the new shared `Typecheck` values
  didn't change compiler-side behavior.
