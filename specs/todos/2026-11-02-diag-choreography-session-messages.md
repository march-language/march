`[P2]` Diagnostics for choreography and sessions: a role body taking steps out of order reports
`expected S_choose_more_done but got S_recv_Msg_Prod_Cons_1` plus a follow-on `linear_used_twice`; a wrong
`Chan.send` gives three errors including "got `a`"; `protocol_invalid`/`role_needs_invalid` point at the
protocol/role header, not the step, with no fix. Target: a generated-state → protocol-step map in
`desugar_endpoints`, errors in protocol terms with a "you are here" excerpt, poisoned follow-ons, step-level
spans, `or crash` fix. specs/plans/2026-11-02-diagnostics-depth-plan.md §F3.

2026-11-04: §X3 closed (`specs/progress/2026-11-04-diag-x3-poison-call-results.md`). Its one leftover
is here: a role body's out-of-order step reports `linear_used_twice` plus `S_end` mismatches
(`test/errors/linear_used_twice_6`); poisoning the step's generated state should absorb them.

2026-11-04: mechanism 3 landed (`specs/progress/2026-11-04-diag-f3-session-channel-wording.md`): `Chan.*`
wrong-state errors in plain terms with the steps left and the protocol they follow, and an explain
page for `session_state_mismatch`. Open: mechanism 5 (role-body cases beyond step order) and 6
(explain pages for the other protocol codes).
