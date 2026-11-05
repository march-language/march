First slice of §F3 of `specs/plans/2026-11-02-diagnostics-depth-plan.md` (choreography and session
messages): a role body that takes a step out of order is reported in protocol terms.

Before, a body calling `Stream_Cons.choose_done(s, st, true)` while `Cons` still had to receive said
"expected `S_choose_more_done` but got `S_recv_Msg_Prod_Cons_1`", two generated state names, plus a
note explaining that both are states of a generated role. Now:

```
-- PROTOCOL --------------------------------------------------------------
Role `Cons` tries to choose `more` or `done` here, but at this point protocol `Stream` says it
must receive an `Int` from `Prod`. [protocol_step_order]
    Take that step with `Stream_Cons.recv_Msg_Prod_Cons_1` first.
    `Cons` is here: it must receive an `Int` from `Prod`:
10 |       Prod -> Cons : Int
```

**State-name map.** `Desugar_endpoints.record_states` records, for each generated state of each
role, what the role does there ("send an `Int` to `Cons`", "choose `more` or `done`", "wait for
`Cons` to choose …", "close the conversation"), the generated function that takes the step, and the
protocol step's span, in `March_ast.Protocol_states` (a display-only side table; nothing reads it
to decide a type). `annotate` records each message's and each `choose`'s span in `step_spans` for it.

**Report.** `report_type_mismatch` (`lib/typecheck/typecheck_unify.ml`) checks whether the two sides
are states of one role (`protocol_step_pair`; the checker sees state names bare, so the pair belongs
to the one role that has both) and reports `protocol_step_order` instead: what the call tries to do,
what the role must do, a "you are here" label on that protocol step, the function that takes it,
and the bound state's binder. Two steps that read alike are told apart by their protocol line. The
new code is in the PROTOCOL category, has an `--explain` page
(`specs/lang/errors/protocol_step_order.md`), and joins the follow-ons `suppress_cascades` drops
while the protocol itself is invalid.

Correction to the 2026-11-04 note on the todo: `linear_used_twice_6`'s two `S_end` mismatches are
not X3 follow-ons. In the `more` branch the loop goes round again, so `close` there is out of order
in both offer calls; they are now two `protocol_step_order` errors, and its internals-allowlist line
is gone.

Corpus: new `test/errors/protocol_step_order_1` (the plan's choose-before-receive case);
`type_mismatch_9` and `linear_used_twice_6` now report `protocol_step_order`.

Not in this slice (still on the todo): `Chan.*` session-channel wording and poisoning, step spans
and an `or crash` fix for the well-formedness errors (`protocol_invalid`, `role_needs_invalid`, …),
wrong payload / wrong role / missing branch / use after `close` cases, and explain pages for the
other protocol codes.
