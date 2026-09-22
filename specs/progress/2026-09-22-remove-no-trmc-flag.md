# Remove `--no-trmc` / `--trmc`: TRMC always runs (2026-09-22)

## Why

Repo-owner decision, 2026-09-22: tail-recursion-modulo-cons is always on, with
no supported way to turn it off. `MARCH_NO_TRMC` and the `trmc-suite` CI job
were already gone (specs/progress/2026-09-21-ci-shard-test-drop-trmc-suite.md);
`--no-trmc` was the last off switch. The stdlib list-producer rewrite
(specs/todos/2026-09-09-rewrite-stdlib-list-producers-into-natural-style.md)
makes `List.map` and friends loops only because TRMC runs; with it off they
exit 138 with no output from roughly 30k elements. That todo's open question
("what should `--no-trmc` be") is answered there: option 1, drop it.

## What changed

- **`bin/main.ml`**: `--trmc` and `--no-trmc` removed from the arg specs, so
  both are the ordinary `unknown option` error. The `MARCH_TRMC` read went too
  (it was already a no-op against the default; a leftover setting is ignored).
- **`Trmc.enabled` deleted**, with the `?enabled` gate on
  `Trmc.transform_module`. No test needed the off path. The two `test_trmc`
  cases that saved/set/restored the ref just call the transform now.
- **`~trmc` threading removed** from `Contract_pipeline.run`,
  `Contract_pipeline.check_contracts` and `Alloc_contract.check`, and from
  their callers (bin/main.ml x3, lsp/lib/analysis.ml, test_compiler.ml).
- **CAS key**: the `"trmc"` tag in `codegen_cas_tags` was DROPPED rather than
  kept as a constant. It existed to separate TRMC from non-TRMC artifacts and
  there are no non-TRMC artifacts any more. Every CAS key changes once.
- **Dead diagnostic**: `Alloc_contract.trmc_note` ("TRMC-eligible ... check for
  `--no-trmc`") could only fire with TRMC off. It is deleted, along with the
  `trmc_eligible` analysis in `Contract_pipeline.run` that fed only it.
- **Warnings reworded**: the typechecker's structural-recursion warning and the
  LSP's constructor-blocked tail-position message said "on by default
  (`--no-trmc` disables it)"; both now say TRMC always runs. The shape advice
  is unchanged.
- **Tests**: `test_alloc_contract.ml`'s three flag cases became "accept: TRMC
  producer" (no flag), "no TRMC note on no_alloc" (the eligible-but-allocating
  fixture still gets a real `no_alloc` rejection, with no TRMC wording), and
  "--no-trmc is an unknown option". `test_compiler.ml` and `test_lsp_perf.ml`
  pin "always runs" and assert no TRMC flag is named.
- **Docs**: `specs/features/compiler-pipeline.md` (said "off by default"),
  `docs/upgrading-to-0-4-0.md` (told readers to pass `--no-trmc`), CHANGELOG.

## Verification

TIR snapshots unchanged (TRMC was already default-on, so the pipeline the
goldens pin did not move).
