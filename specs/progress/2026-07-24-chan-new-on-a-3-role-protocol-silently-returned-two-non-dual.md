- Session types: **`Chan.new` on a 3+-role protocol silently returned two
  non-dual endpoints (session-types-review Task 3, 2026-07-24)**. The
  `Chan.new` arm of `infer_expr` (`lib/typecheck/typecheck.ml`) ended in an
  explicit `(* 3+ roles: just return first two as a pair *)` fallback that
  handed back the first two roles' projections as a `(Chan, Chan)` pair with
  no diagnostic — those two endpoints are not duals of each other, so this
  was a real, silent unsoundness. `MPST.new` already had the mirror-image
  "requires at least 3" guard, but nothing on the `Chan.new` side stopped it
  being called on a multi-party protocol. Fixed by replacing the fallback
  with an `Err.error` reporting the protocol name and its actual role count,
  pointing the caller at `MPST.new`, plus `TError`. New regression test
  `test_session_chan_new_multiparty_error` in `test/test_compiler.ml`
  (registered next to `session Chan.new unknown`) and new reject-conformance
  witness `specs/lang/types/reject/t94_chan_new_multiparty_protocol.march`
  (a 3-role protocol passed to `Chan.new`, expecting `` Chan.new: protocol
  `Tri` has 3 roles ``). `specs/lang/types/INDEX.md` reject table 83 → 84
  (175 / 175 total).
