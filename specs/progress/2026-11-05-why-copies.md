`[P2]` Diagnostics: `--why-copies`, say why an update copies instead of reusing in place

Filed and done 2026-11-05. Design: `specs/2026-11-05-why-copies-design.md`.

- `lib/tir/copy_report.ml`: on the post-Perceus TIR, a site is an `inc_rc x` right before a call
  passing `x` at a parameter the callee reuses (`reuse`/`reuse_hole`, directly or passed on).
  Mapped back to source through `Provenance` and the host function's AST, with a reason (used
  again later / also passed to the enclosing call / captured by a closure); a site with no reason
  in the source is dropped. The reorder fix is offered only when the move is safe, judged with
  `Purity` on the pre-Perceus module.
- `Contract_pipeline.run` gains an `after_perceus` hook (a no-op unless the flag is set);
  `bin/main.ml` adds `--why-copies` / `--why-copies-json`, which imply `--compile`, bypass the
  CAS early exit like `--report-contracts`, and stop before code generation.
- New code `copy_shared` (category COPY), explain page, memory-model paragraph.
- `test/run_errors.ml`: `-- MARCH-MODE: why-copies` runs a case with the report flags; the fix
  check requires the fixed program to report no copy. Cases `copy_shared_1`..`_7`.
- Error Messages tour: a new section 10 with a `--why-copies` example; `scripts/gen-error-tour.py`
  markers may name `--why-copies` in place of the default `--check`.

Measured: `bench`-style loop over a 200,000-element list, `List.map` then `List.length` vs the
fixed order, `--opt 2`: peak RSS 29 MB -> 10 MB, user time 0.35 s -> 0.25 s. Over `bench/*.march`:
56 programs run, 5 report copies (`merkle`, `par_map`, `float_closure_calls`, ...), each
reason checked by hand; `sort_small_batched`'s tuple-held values are correctly not reported.

Not done: run-time-only copies (a value shared through a data structure), `match` on a borrowed
parameter, LSP surfacing, and a second call site of the same (callee, variable) in one function
is reported once.
