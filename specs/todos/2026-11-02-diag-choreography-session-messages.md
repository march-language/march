`[P2]` Diagnostics for choreography and sessions: a role body taking steps out of order reports
`expected S_choose_more_done but got S_recv_Msg_Prod_Cons_1` plus a follow-on `linear_used_twice`; a wrong
`Chan.send` gives three errors including "got `a`"; `protocol_invalid`/`role_needs_invalid` point at the
protocol/role header, not the step, with no fix. Target: a generated-state → protocol-step map in
`desugar_endpoints`, errors in protocol terms with a "you are here" excerpt, poisoned follow-ons, step-level
spans, `or crash` fix. specs/plans/2026-11-02-diagnostics-depth-plan.md §F3.

2026-11-04: first slice landed (`specs/progress/2026-11-04-diag-f3-protocol-step-order.md`): a
generated-state → protocol-step map and `protocol_step_order` in protocol terms with a "you are
here" label. (The `linear_used_twice_6` follow-ons the §X3 note pointed at turned out to be genuine
out-of-order closes.) Open: mechanisms 3–6 of §F3 — `Chan.*` wording and poisoning, step-level spans
and an `or crash` fix for the well-formedness errors, the role-body cases beyond step order, and
explain pages for the other protocol codes.

2026-11-04: mechanism 4 landed (`specs/progress/2026-11-04-diag-f3-wellformed-spans-or-crash-fix.md`):
the after-`loop` errors point at the dead step, and a missing crash branch gets an `or crash` fix.
Open: mechanisms 3, 5 and 6.

2026-11-04: mechanism 3 landed (`specs/progress/2026-11-04-diag-f3-session-channel-wording.md`): `Chan.*`
wrong-state errors in plain terms with the steps left and the protocol they follow, and an explain
page for `session_state_mismatch`. Open: mechanism 5 (role-body cases beyond step order) and 6
(explain pages for the other protocol codes).
