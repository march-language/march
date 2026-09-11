# march-lean oracle: repository_dispatch on corpus/checker changes + the two-repo rule

**Landed 2026-09-11 (march side).** Design: `specs/2026-09-11-ci-tooling-fixes-design.md` §6.

- `.github/workflows/march-lean-dispatch.yml`: on a push to `main` touching
  `specs/lang/types/**`, `lib/typecheck/**` or `lib/caps/**` (or by hand),
  POSTs a `repository_dispatch` (`march-corpus-changed`, payload `march_sha`)
  at `march-language/march-lean`. A missing `MARCH_LEAN_DISPATCH_TOKEN` fails
  the job loudly rather than skipping.
- `specs/lang/types/INDEX.md` now states the two-repo rule: an ERROR-level
  check or a new `reject/` fixture is a change to two repositories; confirm the
  dispatched run is green or file a ledgered skip there.

**Still open (in the todo):** the secret must be created by a repo admin; the
Lean side must re-baseline against the 303-fixture corpus (top `t185`) and add
the grant check. Neither is doable from this repo.
