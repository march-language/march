Fourth and last slice of §F3 of `specs/plans/2026-11-02-diagnostics-depth-plan.md` (mechanism 5:
role-body mistakes beyond step order; mechanism 6: explain pages for the protocol codes). Earlier
slices: `2026-11-04-diag-f3-protocol-step-order.md`, `2026-11-04-diag-f3-wellformed-spans-or-crash-fix.md`,
`2026-11-04-diag-f3-session-channel-wording.md`.

`March_ast.Protocol_states` gained a second table, keyed by the generated function that takes a
step (`Fan_A.send_Number`, `Stream_Prod.offer_more_done`, each `choose_<label>`), filled by
`record_states` in `desugar_endpoints`. Offers also record their branch labels and whether the
role's conversation ends right after each (`ps_branches`). Display only, like the state table.

One corpus case per mistake:

- **Wrong payload** (`type_mismatch_42`): the argument's reason is the step, not the call: "This is
  the step's payload: protocol `Fan` says `A` must send an `Int` to `C` here", and "the expected
  type comes from here" points at the step's line in the protocol. `infer_app` takes an optional
  `?payload` reason for one argument index, set by the `EApp` arm when the callee is a recorded
  send or choose.
- **Wrong role** (`protocol_wrong_role_1`, new code `protocol_wrong_role`): a state of role `B`
  passed to role `A`'s step. `protocol_role_pair` (`typecheck_unify.ml`) matches the two state
  names to one protocol and two different roles, only when unambiguous (every role has an
  `S_end`). The report names both roles, labels where `B` is in the protocol and the binder, and
  says which call `B` takes instead or which state type to give the body to play `A`.
- **Missing branch** (`session_offer_nonexhaustive_2`): an offer call short of callbacks is
  `session_offer_nonexhaustive`, not `arity_mismatch`. It lists the choice's branches and the
  missing ones, labels the `choose by`, and when every missing branch ends the conversation, the
  fix appends `fn (_v, st) -> <Role>.close(s, st)` per branch (checked by the corpus's
  fix-must-fix run). `_or` and `_or_drain` variants are not matched (their trailing handler makes
  the count ambiguous).
- **Use after close** (`linear_used_twice_31`): a step on a state already consumed also produced a
  `protocol_step_order` telling the role to close first. `suppress_cascades` now drops a
  `protocol_step_order`/`protocol_wrong_role` on the span of a `linear_used_twice`, and gives the
  reuse report a note: "the first use closed the conversation: no step can follow `close`" (or,
  for any other step, that a protocol state takes exactly one step).

Name clashes: `endpoints_name_clash` was reported once per generated variant of the clashing
function (`recv_Line`, `recv_Line_or`, `recv_Line_or_drain`) and again by the event API, and the
broken role code then produced `protocol_step_order` errors reading "tries to receive … (the step on
line 9) … must receive … (the step on line 9)". Now one report per role, and `endpoints_name_clash`
joins the codes under which protocol follow-ons are dropped (`endpoints_name_clash_1`).

Explain pages (`specs/lang/errors/`, generated into `docs/errors/`) for 24 of the 27 protocol and
session codes without one: duplicate_protocol, endpoints_label_invalid, endpoints_name_clash,
protocol_crash_branches, protocol_empty, protocol_invalid, protocol_same_participants,
protocol_single_participant, protocol_wrong_role, role_needs_invalid, session_choice_label,
session_not_closed, session_offer_nonexhaustive, session_offer_unrefined, session_protocol_arg,
session_role_count, session_role_mismatch, session_type_mismatch, session_unreachable_branch,
transition_via_mismatch, undeclared_transition, unknown_protocol, unknown_role, unknown_session_op.
Each page's two programs were checked: the trigger reports the code first, the fix checks clean.
Four codes are warnings or hints (protocol_empty, protocol_same_participants,
session_unreachable_branch, undeclared_transition), so their trigger exits 0.

No page, because `--check FILE` cannot reach the code: `protocol_expand_invalid` (only the
`--protocol-expand`/`--protocol-baseline` flags), `protocol_unlabelled_step` (only protocols the
`--topology` app reads), and `protocol_projection` (the two sides' views come from the same steps;
no shape tried reaches it).

Follow-ups filed: `specs/todos/2026-11-04-endpoints-cancel-label-collides.md`,
`specs/todos/2026-11-04-choose-branch-head-from-non-chooser-accepted.md`.
