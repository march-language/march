`[P2]` Before capture inference runs on every build (phase 8b) (logged 2026-11-24, closed 2026-11-25)

Phase 8a ran capture inference on demand only. Phase 8b's escape errors need it in every
check. This item listed what that needed first; this is what 8b did for each
(`specs/progress/2026-11-25-ocap-p8b-scoped-escape.md`).

- **A pass failure must not be silent or fatal by accident.** Done. On the build path a crash
  in the pass stops the build with "internal compiler error in the scoped-handle check"; in
  the editor and the REPL it is an `internal_error` diagnostic. Test: "a crash in the pass is
  an internal compiler error" (`test/test_captures.ml`, through `MARCH_CAPTURE_FAULT`).
- **Cost.** Avoided instead of paid: the pass runs only for a program whose own code names a
  function with a `scoped` callback parameter (`check_capture_escapes`,
  `lib/typecheck/typecheck.ml`). Such a program pays the pass over what it reaches, which 8a
  measured at 0.1% to 2.8% of a check. The stdlib's schemes are still recomputed for each
  program that runs the pass; caching them beside the stdlib environment is not done and is
  only worth it if 8c makes the pass run for every program.
- **Every checker entry point.** Done for what 8b checks. `check_module_core` and
  `check_module_with_env` both run the escape check, and on the path that records no reach
  bodies the pass now also reads impl methods and interface default bodies from the
  declarations. The REPL reports the error from its whole-program check of a `mod` typed at
  the prompt. A bare `fn` typed at the prompt is not re-checked as a program, as for the
  other whole-program capability checks.
- **`Unknown` must be treated as holding every tracked name.** Done differently, and soundly:
  `?` alone holds no name (or every function that opens a table would be rejected), but a
  scoped handle *passed to* a function value of unknown origin, or to a construct the pass
  does not model, is an escape. The origin is a mark on the set
  (`Capture_set.unknown_origin`).
