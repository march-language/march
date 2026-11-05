Second slice of §F3 of `specs/plans/2026-11-02-diagnostics-depth-plan.md` (mechanism 4: protocol
well-formedness errors point at the step, and `role_needs_invalid` gets an `or crash` fix). The
first slice is `specs/progress/2026-11-04-diag-f3-protocol-step-order.md`.

**Spans.** A survey of the well-formedness codes found most already on the step at fault (`stop`,
a sender's name, a label, a `may crash` name). The two that weren't were the "steps after a `loop`
can never run" rules in `Typecheck`'s protocol check, which put the caret on the whole `protocol`
declaration. `report_dead_after` now puts it on the first step that can never run, with a label
on the loop ("this `loop` repeats forever"), and the message is about that step:
- "Protocol `Bad`: this step can never run — it comes after a `loop`, and a `loop` block repeats
  forever, so it must be the last step." (`protocol_invalid_4`, conformance `t93`);
- "Protocol `Q`: this step can never run in the `choose` branch that ends in a `loop` — the steps
  after a `choose` are projected into EVERY branch. Move it inside the branches that can reach
  it." (`protocol_invalid_1`, conformance `t101`).

**Fix.** A receive from a role that `may crash` without a crash branch (`role_needs_invalid`, "what
does `I` do if `C` crashes before sending?") now carries an `FInsert` of the branch after the step's
line. The crash rule requires every role still in the conversation to hear first from the
detector, so the branch holds one `<detector> -> <role> : T` per such role, in order of
appearance. `T` is the payload of that role's first message from the detector in the normal
continuation, or `String`. A note says the messages are placeholders. `run_errors`'
fix-must-fix check confirms that applying the fix leaves `role_needs_invalid_1` checking clean.
An empty branch was not enough: the checker rejects it ("`L` cannot tell whether `C` crashed").

Updated with the wording: `test/errors/protocol_invalid_1`/`_4` EXPECT lines, conformance `t101`'s
EXPECT and INDEX row, and `test_compiler`'s `session loop branch hides post-choose tail` assertion.

Still open on the todo: `Chan.*` session-channel wording and poisoning (mechanism 3), the role-body
cases beyond step order (mechanism 5), and explain pages for the other protocol codes (6).
