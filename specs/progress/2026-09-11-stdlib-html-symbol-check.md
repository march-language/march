> **Landed 2026-09-11.** `scripts/check-docs.sh` Check D (gated by
> `CHECK_STDLIB_HTML=1`) reads every generated `docs/docs/stdlib/<Mod>.html`
> back against its `stdlib/*.march` source: each top-level public `fn`/`type`
> must have its `id="fn-…"`/`id="type-…"` anchor on the page named after the
> `mod` declaration. It runs in `gen-stdlib-docs.yml` BEFORE the bot pushes (so
> the bot cannot publish a page set that omits a symbol) and in the nightly
> `stdlib-docs-smoke`; not on PRs, where the pages are stale by design until the
> bot runs. 2140 symbols checked green on landing; red control: renaming one
> anchor fails naming module and symbol. The bot workflow also gained an
> `if: failure()` step summary. Design: `specs/2026-09-11-ci-tooling-fixes-design.md` §1.
> The original filing follows.

# CI should assert the generated stdlib HTML is in sync with `stdlib/*.march`

Filed 2026-09-08, split out of
`specs/progress/2026-08-13-stale-generated-stdlib-html.md` when that item was
closed. That item was a real, shipped documentation defect: the published
`docs/docs/stdlib/NativeArray.html` kept asserting that `fold_int`/`fold_float`
had "no compiled implementation yet — calling them from a `--compile` build
will fail to link" for months after both grew C runtime implementations, and it
omitted three functions (`fold_f32`, `fold_i32`, `fold_u8`) plus
`System.mem_peak_bytes` entirely.

## Why it went unnoticed

The failure mode is **silent by construction**. `docs/docs/stdlib/*.html` is a
generated artifact; nothing reads it back and compares it to its source. The
only existing guard, `scripts/check-docs.sh`, lints *stdlib module counts* —
and the module count did not change, because the drift was inside existing
modules (new functions, changed prose), not new modules. So every check was
green while the published page told readers to avoid a working API.

Nothing prevents this recurring the next time a branch adds a stdlib function
and does not regenerate.

## What to do

Add a CI check that fails when `docs/docs/stdlib/` is stale relative to
`stdlib/*.march`. Sketch:

- Regenerate the stdlib pages into a scratch directory in CI, and diff against
  the committed ones; fail with the diff when they differ.
- That requires the doc-generation tool to run in CI. Note the original item
  recorded that the generator was broken on the machine that branch was
  developed on — confirm it runs headlessly and deterministically (stable
  ordering, no timestamps or absolute paths baked into the output) before
  wiring it to a hard failure, or the check becomes a flaky blocker.
- If full regeneration in CI turns out to be too slow or non-deterministic, a
  cheaper approximation is a per-module *symbol-set* check: extract the public
  `fn`/`type` names from each `stdlib/<m>.march` and assert each appears in
  `docs/docs/stdlib/<Module>.html`. That would have caught the missing
  `fold_f32`/`mem_peak_bytes` half of this bug, though not the stale prose
  half.

## Acceptance

- A CI job fails on a branch that adds a public stdlib function without
  regenerating `docs/docs/stdlib/`.
- The check is proven to go RED on a deliberate perturbation (delete a function
  from a generated page, or add a stdlib function without regenerating) before
  it is trusted GREEN.

> **Design spec (2026-09-11):** `specs/2026-09-11-ci-tooling-fixes-design.md` — root cause re-verified against the tree, chosen fix, test plan with a RED control, effort and risk.
