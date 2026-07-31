- Session types: **offer-label `match` exhaustiveness was backwards
  (session-types-review Task 5, 2026-07-27)**. Matching the `Atom` label
  returned by `Chan.offer` went through the ordinary Atom exhaustiveness
  path — an OPEN universe — so a `match` handling EVERY protocol branch
  still warned `` Non-exhaustive pattern match — missing case: _ `` while a
  `match` that genuinely omitted a branch produced the exact same warning,
  never an error. New helper `check_offer_label_exhaustiveness`
  (`lib/typecheck/typecheck.ml`, next to `offer_arm_label`) checks the arms
  against the protocol's CLOSED label set (from `env.offer_labels`) instead
  when the scrutinee is an offer-label variable: all labels covered (with or
  without a catch-all) is silent, a missing label with no catch-all is now
  an `Err.error` naming the branch. Both `check_exhaustiveness` call sites
  try the offer-label check first, falling back to the generic Atom checker
  when the scrutinee isn't a linked offer label. Inherits Task 4's shadowing
  discipline for free (a rebound label name simply isn't an offer label any
  more). Two Task-4-migrated witnesses (`accept/t43_choose_offer_roundtrip`,
  `golden/g39_chan_choose_offer`) keep their now-unnecessary catch-alls
  unchanged (re-verified clean, no new redundant-arm warning);
  `reject/t74_offer_wrong_branch_drive` still rejects for its ORIGINAL
  reason (wrong-branch payload type), confirming the new check stays silent
  there. New regression tests `test_session_offer_all_labels_no_warning` and
  `test_session_offer_missing_label_error` in `test/test_compiler.ml`. New
  reject-conformance witness
  `specs/lang/types/reject/t96_offer_missing_branch_arm.march`. `specs/lang/types/INDEX.md`
  reject table 86 → 87 (178 / 178 total).
