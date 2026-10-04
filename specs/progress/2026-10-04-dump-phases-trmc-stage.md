# DONE `--dump-phases` / `MARCH_DUMP_TXT` get a `tir-trmc` stage

Added 2026-10-04.

## The gap

`Contract_pipeline.run` calls `snap "tir-<stage>" tir` after each pass, but its
first checkpoint was `tir-mono`. `Trmc.transform_module` (and the WASM-island
`tm_exports` marking) ran before it, so neither `--dump-phases` nor
`MARCH_DUMP_TXT=tir-...` could show TRMC's output on its own; the earliest
readable TIR after `tir-lower` already had monomorphization folded in.

## The change

- `lib/tir/contract_pipeline.ml`: `snap "tir-trmc" tir` immediately after the
  `Trmc.transform_module` result is bound, following the existing
  `tir-<pass>` naming. `snap` is `run`'s optional callback (default no-op), so
  callers that do not dump see no change.
- `tools/phase-viewer.html`: a sidebar colour for `tir-trmc` in `phaseColor`
  (unknown labels fell back to grey; nothing else enumerates the labels, and
  the golden-snapshot suite pins only the `lower` and `perceus` stages).

## Verification

Written in a container without `dune`/`opam`: unbuilt and untested here. The
addition is one statement of the same shape as the `snap` calls below it.
