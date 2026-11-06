Protocol and session errors raised in a role's body now draw the conversation up to the bad
step (design: `specs/plans/2026-11-05-diag-protocol-sequence-diagram.md`; follow-on to §F3 of
`specs/plans/2026-11-02-diagnostics-depth-plan.md`).

```
    The conversation so far, in protocol `Pump`:

      hello: A -> B : String     done
      loop do                    (repeats)
        tick:  A -> B : Int      done   <- `A` tried this again
        tock:  B -> A : Int      done
        choose by A: go | quit   <- `A` must do this next
```

**Positions.** `March_ast.Protocol_states` keeps each protocol's steps as written
(`record_protocol`) and defines a state's place in them (`pos`: one index per nesting level,
a branch index under a `choose`, the slot after the last top-level step for the end).
`Desugar_endpoints.project` tags every state it builds with its position (`ps_pos` in the
per-state table), and `Typecheck_session.project_steps_at` does the same for the `Chan`/`MPST`
session types (`proto_info.pi_positions`). A position is dropped where it is not certain: a
bystander's merged branches, a crash branch, a role whose conversation ends in two places
(`S_end` is one value), a session state equal to states at two places. No position, no diagram.

**Diagram.** `Protocol_states.diagram` draws the global steps along the path to the role's
state and on to the step tried when that lies on the same path: a labelled message as
`label: A -> B : T`, an opened `loop do` marked `(repeats)`, an opened choice as
`choose by R: taken` with `other branch: …`, a closed one as `choose by R: a | b`, `stop`,
`(end of conversation)`. Marks: `done` on the role's own earlier steps, `<- `R` must do this
next` (`can only close here` on an end row), and the tried mark. Three rows of context each
side, the rest `… N earlier steps`; headers and the tried row are never elided. A protocol of
two rows or fewer gets none.

**Who draws it.** `protocol_step_order` and `protocol_wrong_role`
(`typecheck_unify.ml`), `session_state_mismatch` (`report_session_state`, no tried mark: the
call is not a protocol step), and `linear_used_twice` on a protocol state, whose reuse report
takes the diagram over from the step-order error `suppress_cascades` drops, so the step taken
again is marked and the end row says the role can only close. Protocol well-formedness errors,
`session_offer_nonexhaustive` and the wrong-payload `type_mismatch` draw none.

`Errors.render_diagnostic` no longer indents a blank line inside a note (it printed four
trailing spaces).

Corpus: new `protocol_step_order_2` (straight line), `_3` (inside a `choose` branch), `_4`
(a loop's step taken again), `protocol_wrong_role_2` (elision in a long protocol),
`linear_used_twice_32` (a step after `close`); regenerated `protocol_step_order_1`,
`protocol_wrong_role_1`, `type_mismatch_9`, `linear_used_twice_6`, `linear_used_twice_31`,
`session_state_mismatch_3`. `session_state_mismatch_1`/`_2` and `type_mismatch_15` are on the
two-step `Echo` and stay as they were.

Docs: the explain pages for `protocol_step_order`, `protocol_wrong_role` and
`session_state_mismatch` mention the diagram. The Error Messages tour (`docs/error-messages.md`)
explains how to read it after "A role that skips a step" (whose regenerated output now carries
one), and gains two examples: `35-channel-close-early` (section 7, a `Chan` channel closed
before the step after a `choose`) and `36-role-repeats-a-step` (section 8, a loop's step taken
again). Neither is in the playground's list: 36 needs the session runtime, and 35 is left out
so this change needs no browser-REPL rebuild to keep `browser-repl-smoke.js` green.
`24-channel-wrong-step` is on the two-step `Echo` and draws none.
