# Published stdlib HTML for NativeArray/System is stale and now carries a FALSE claim

Filed 2026-08-13 during the final review of `feat/simd-followups`. The
generated pages under `docs/docs/stdlib/` were not regenerated for that
branch, and one of them no longer merely omits new API — it actively asserts
something the branch made untrue.

## What is wrong

`docs/docs/stdlib/NativeArray.html`

- **Carries a now-FALSE statement.** It still says `fold_int`/`fold_float`
  have "no compiled implementation yet — calling them from a `--compile`
  build will fail to link". As of this branch both have C runtime
  implementations and compiled programs link and run correctly (pinned by
  `test/native/native_arr_fold.march`). A reader following the published page
  will avoid a working API, or conclude the docs describe a different
  version.
- **Omits `fold_f32`, `fold_i32` and `fold_u8`** entirely — three functions
  added by this branch. `grep -c fold_f32` on the file returns 0.

`docs/docs/stdlib/System.html`

- **Omits `mem_peak_bytes`**, the stdlib wrapper for the new `peak_rss_bytes`
  builtin. `grep -c mem_peak_bytes` returns 0.

The source of truth — `stdlib/native_array.march` and `stdlib/system.march` —
is correct in both cases; only the generated HTML is behind.

## Why it was not fixed in that branch

The doc-regeneration tool is broken on the machine the branch was developed
on (tracked separately), so regenerating was not possible there and
hand-editing 300 KB of generated HTML would have been worse than leaving it —
it would produce output that the next real regeneration silently discards,
while making the file look current.

The staleness is otherwise low-risk (generated artifact, source is correct,
`scripts/check-docs.sh` does not lint generated stdlib pages), which is why it
was accepted as carry-forward rather than blocking the merge. The FALSE
link-error claim is the part that should not sit indefinitely.

## What to do

Regenerate `docs/docs/stdlib/` on a host where the doc tool works and commit
the result. Verify at minimum:

- `grep -c 'no compiled implementation yet' docs/docs/stdlib/NativeArray.html`
  is **0**
- `grep -c fold_f32 docs/docs/stdlib/NativeArray.html` is **> 0** (likewise
  `fold_i32`, `fold_u8`)
- `grep -c mem_peak_bytes docs/docs/stdlib/System.html` is **> 0**

While there, consider whether a CI check should assert that the generated
stdlib pages are in sync with `stdlib/*.march` — the failure mode here is
silent by construction, and `scripts/check-docs.sh`'s stdlib-module-count lint
did not catch it because the module count did not change.
