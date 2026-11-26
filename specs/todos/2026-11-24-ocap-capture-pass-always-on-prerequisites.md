`[P2]` Before capture inference runs on every build (phase 8b) (2026-11-24)

Phase 8a runs capture inference on demand only (`--dump-captures`, hover, the soundness
oracle; `MARCH_CAPTURES=1` forces it for measurement). Phase 8b's escape errors need it on
every check. What that needs first:

- **A pass failure must not be silent or fatal by accident.** Today the editor path catches
  any exception and shows the plain type. An always-on pass needs a decided behaviour: an
  internal compiler error with the usual report.
- **Cost.** `scripts/capture-cost.sh` measures it. On demand the pass walks only what the
  entry file reaches; the numbers are in `specs/progress/2026-11-24-ocap-p8a-capture-sets.md`.
  The stdlib's schemes are recomputed for each program; caching them beside the stdlib
  typecheck-env cache (`get_stdlib_tc_env`, `bin/main.ml`) removes that. Schemes hold
  `Typecheck_types.ty` values and set-variable ids, so they marshal with the env.
- **Every checker entry point.** `Typecheck.check_module_with_env` (the editor and the REPL)
  records no `fn_row_bodies` for the user's file; the pass reads plain functions, top-level
  lets and actor handlers from the declarations instead (`extra_bodies`), which skips impl
  methods and interface default bodies there. An error-producing pass must see those.
- **`Unknown` must be treated as holding every tracked name** (design §3, plan decision 5), or
  a value the pass does not follow could carry a scoped handle out of its callback.
