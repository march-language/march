`[P2]` Diagnostics for choreography and sessions: a role body taking steps out of order reports
`expected S_choose_more_done but got S_recv_Msg_Prod_Cons_1` plus a follow-on `linear_used_twice`; a wrong
`Chan.send` gives three errors including "got `a`"; `protocol_invalid`/`role_needs_invalid` point at the
protocol/role header, not the step, with no fix. Target: a generated-state → protocol-step map in
`desugar_endpoints`, errors in protocol terms with a "you are here" excerpt, poisoned follow-ons, step-level
spans, `or crash` fix. specs/plans/2026-11-02-diagnostics-depth-plan.md §F3.
