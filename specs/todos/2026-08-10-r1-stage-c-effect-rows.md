# R1 stage C — per-function effect rows (implementation)

Filed 2026-08-10. Design: `specs/2026-08-10-r1-stage-c-effect-rows-design.md`
(approach B: row schemes `{C; D; U}` beside the type system, discharge at
concrete-`Cap(P)`-parameter functions, `U`/`IO.Foreign` refusal semantics).

Ordered stages, each gated as the design specifies:

1. Recording (d_seeds / u_seed / call_args beside `record_fn_refs`) +
   `lib/caps/cap_rows.ml` pure fixpoint + debug dump — analysis only, no
   diagnostics. Pin the C-projection ≡ flat-table golden property.
2. Measure transitive-`U` rate across stdlib + corpus (design gate: refusal
   severity depends on it).
3. Discharge check in `check_module_core` beside `check_main_grant`, with
   provenance-chain diagnostics. Default-on ONLY after the corpus sweep
   (`specs/lang/types/check_types.sh`) and examples/bench/native/stdlib
   compiles are clean; else behind `--cap-fn-grants` first.

TDD per convention: RED tests in test_compiler.ml (`cap_fn_grant` group)
before any typecheck.ml change; at least one test against the real
stdlib-prepended shape (postmortem:
`specs/progress/2026-08-09-cap-shadowing-false-positive.md`).
