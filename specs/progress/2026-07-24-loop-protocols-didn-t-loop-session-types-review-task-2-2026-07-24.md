- Session types: **`loop` protocols didn't loop (session-types-review Task 2,
  2026-07-24)**. `project_steps`' `ProtoLoop` arm built the recursive body with
  an `SVar` back-reference to the binder and then called `subst_svar rec_var
  after_loop inner`, REPLACING that back-reference with the post-loop
  continuation — so the `SRec` binder it wrapped around the result contained
  no `SVar` anywhere in it: the projection was one unrolled iteration, and a
  second iteration was rejected with `` channel is at `End` ``. Fixed with the
  standard µ-type encoding `Rec X. S[X]`: the body's continuation IS the
  binder's own back-reference (`SVar rec_var`), so `unfold_srec` re-wraps the
  binder on every unfold and the channel state cycles indefinitely. Since such
  a loop never exits, any protocol step written after a `loop` block is now
  unreachable and rejected at protocol-declaration time (new
  `check_unreachable_after_loop` walk over `pdef.proto_steps` in the
  `Ast.DProtocol` validation, recursing into `ProtoChoice` branches). `subst_svar`
  is no longer called from the loop arm but stays in the file (still referenced
  elsewhere in the `and`-chain). De-vacuumed `test_session_loop_projection`
  (the old assertion `SRec (_, SSend _)` held even after the back-reference
  was destroyed) plus two new tests in `test/test_compiler.ml`:
  `test_session_loop_two_iterations_ok` (a two-role loop typechecks a second
  send/recv round) and `test_session_steps_after_loop_error` (a step after a
  top-level `loop` is now a protocol-declaration error). Fixed
  `test_srec_multi_turn_typechecks` as collateral: it called `Chan.close` on a
  channel still inside a loop, which the old bug's one-unrolled-iteration
  behavior wrongly allowed — a looping channel never reaches `End` so
  `Chan.close` on it is correctly rejected now; the test drops the channel
  instead (legal, since the must-close check fires only at `End`). New
  conformance witnesses `specs/lang/types/accept/t92_loop_protocol_two_iterations.march`
  (two full loop iterations typecheck and run identically interpreted and
  compiled, printing `3`) and
  `specs/lang/types/reject/t93_steps_after_loop_unreachable.march` (a step
  after `loop` is rejected with "can never run"). `specs/lang/types/INDEX.md`
  accept table 90 → 91, reject table 82 → 83 (174 / 174 total).
