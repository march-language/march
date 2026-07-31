- Session types: **post-`choose` protocol steps dropped from every projection
  (session-types-review Task 1, 2026-07-24)**. `project_steps`' `ProtoChoice`
  arm projected each branch with the projection call's outer continuation
  (`cont`, which is `SEnd` at top level) instead of `rest_ty ()`, the steps
  that actually follow the `choose ... end` block — so both roles silently
  lost the protocol's tail, consistently enough that binary duality still
  passed and a program that skipped the trailing message typechecked and ran
  clean. Fixed by projecting each branch with `let after_choice = rest_ty ()`
  in place of `cont`. Compile-time-only fix (channel runtime is untyped; no
  lowering/codegen changes). New regression test
  `test_session_choice_tail_survives_projection` in `test/test_compiler.ml`
  asserts every branch of a `Tail` protocol's Client projection carries the
  post-choice `Send(String, End)` tail. New reject-corpus witness
  `specs/lang/types/reject/t91_choice_tail_step_required.march` pins the
  behavior change: pre-fix this program (closes instead of driving the
  trailing `Client -> Server : String`) was wrongly ACCEPTED; post-fix it
  rejects with `` Chan.close: channel is at `Send(String, End)` but I expected
  `End`. ``. `specs/lang/types/INDEX.md` reject table 81 → 82 (172 / 172
  total).
