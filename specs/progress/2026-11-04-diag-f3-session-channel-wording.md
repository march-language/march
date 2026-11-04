Third slice of §F3 of `specs/plans/2026-11-02-diagnostics-depth-plan.md` (mechanism 3: session
channels in plain terms). Earlier slices: `2026-11-04-diag-f3-protocol-step-order.md`,
`2026-11-04-diag-f3-wellformed-spans-or-crash-fix.md`.

A `Chan.*` / `MPST.*` call at the wrong step of its protocol used to print the raw session type:
"Chan.send: channel is at `Recv(Int, End)` but I expected `Send(T, ...)`." It now reads:

```
-- PROTOCOL ---------------------------------------------------------------
`Chan.send` can't send here: at this point the channel must receive an `Int`. [session_state_mismatch]
20 |     let cc3 = Chan.send(cc2, 43)
    What is left on this channel: receive an `Int`, then close.
    the channel is `Client`'s end of protocol `Echo`, declared here:
12 |   protocol Echo do
```

`report_session_state` (`lib/typecheck/typecheck.ml`) replaces the seven wrong-state reports
(`Chan.send`/`recv`/`close`/`choose`/`offer`, `MPST.send`/`recv`). It says:
- what the call tries and what the channel must do instead (`session_step_text`);
- the steps left on the channel, up to a choice or four steps (`session_plan`);
- the protocol and role the channel follows, as a label on the protocol declaration, when exactly
  one protocol's projection has the state among its states (`channel_origin`, structural match).

The code stays `session_state_mismatch`, now with an `--explain` page
(`specs/lang/errors/session_state_mismatch.md`).

Poisoning needed no change: every wrong-state report already returns `TError`, and the
"expected a channel endpoint but got `a`" follow-on is already dropped by `suppress_cascades`. The
remaining multi-error session cases (`session_state_mismatch_1`, `cap_grant_27`, `type_mismatch_15`)
are about the OTHER endpoint, closed at the wrong step, which is genuine.

Updated with the wording: EXPECT lines of `test/errors/session_state_mismatch_1`–`3` and
`cap_grant_27`, conformance `t30`, `t31`, `t34`, `t91` and their INDEX rows, and a dated note in
`specs/lang/core-march-types.md` where it quotes the old messages.

Not done: the protocol label points at the declaration, not the step (session types carry no step
spans); `Chan.*` with a wrong payload is still the ordinary `type_mismatch` with a reason.
