# Protocol errors draw the conversation so far

Design note for the sequence diagram that protocol and session errors raised in a role's
body now carry (follow-on to §F3 of `2026-11-02-diagnostics-depth-plan.md`). Landed with
`specs/progress/2026-11-05-diag-protocol-sequence-diagram.md`.

```
    The conversation so far, in protocol `Relay`:

      first:  A -> B : Int      done
      second: B -> C : Int
      reply:  C -> A : Bool     <- `A` must do this next
      third:  A -> B : String   <- `A` tried this
```

## Where the steps come from

The diagram draws the **global** protocol, not one role's projection: `Protocol_states`
(`lib/ast/protocol_states.ml`) keeps each protocol's `Ast.protocol_step list` as written
(`record_protocol`, filled by `desugar_endpoints.expand` and by the typechecker's
`DProtocol` arm), so a step the role takes no part in is still a row, and a labelled
step is drawn with its label.

A state's place in it is a **position** (`Protocol_states.pos`): one index per nesting
level into the steps `visible` counts (`may crash` and `role R needs` are declarations,
not steps). Into a `loop` the next index is into its body; into a `choose` the next index
picks the branch and the one after it the step inside. An index equal to a list's length
is the slot after its last step, which at the top level is the end of the conversation.

Both projections tag the states they build with their position as they build them:
`Desugar_endpoints.project` (the `@[endpoints]` states, recorded as `ps_pos` next to the
other per-state facts) and `Typecheck_session.project_steps_at` (the `Chan`/`MPST` session
types, kept per role in `proto_info.pi_positions`). Nothing is recomputed from the
state's shape afterwards: the generator knew which step it was projecting, so it says.

A position is dropped, and no diagram is drawn, when it is not certain:

- the branches of a `choose` a bystander merges (every branch projects alike, so the
  role never learns which was taken);
- anything inside a crash branch, and anything after `ACrashOr` splices steps;
- a role whose conversation ends in more than one place: `S_end`/`SEnd` is one value
  however many `stop`s and ends reach it, so it has a position only when exactly one does;
- a session state that is structurally equal to states at two different positions.

## Which errors get it

Those that name a step the role tried and the step it should take, with a state whose
position is known:

| code | here | tried |
|---|---|---|
| `protocol_step_order` | the state's step | the call's step; "tried this again" when it comes earlier (a loop's next round), "tried to close here" for `close` |
| `protocol_wrong_role` | the state's step (role B) | the other role's step: "`B` tried this, but it is `A`'s step" |
| `session_state_mismatch` (`Chan.*`, `MPST.*`) | the channel's step | none: the call is not a protocol step, and the headline already says what it tried |
| `linear_used_twice` on a protocol state | carried over from the `protocol_step_order` the reuse suppresses (`Errors.suppress_cascades`), so the step taken again is marked and the end row reads "can only close here" |

Not drawn: the protocol well-formedness errors (`protocol_invalid`, `role_needs_invalid`,
`endpoints_*`, …), which are about the protocol text, not a body's place in it;
`session_offer_nonexhaustive`, where the step is the right one and the note already lists
the branches; and the wrong-payload `type_mismatch`, whose label points at the step.

## Length

Three rows of context before the step the role is at, three after it on the way to the
step tried; longer runs collapse to `… N earlier steps` / `… N more steps`. An opened
`loop` or `choose` header is never elided (it says what the kept rows are inside), nor is
the row of the step tried. A protocol that would draw in two rows or fewer gets no
diagram (`Echo` in `session_state_mismatch_1`): it adds nothing to the headline.

## Rendering

- One note, through the existing renderer (`Errors.render_diagnostic` indents each line;
  a blank line inside a note is now left blank rather than indented). `--check-json`
  carries it as a `notes` entry, newlines and all.
- ASCII only: `->` for messages, `<-` for the markers. The style lint allows it (it checks
  quoting, capitals and sentence ends of the headline and the notes).
- Rows: `label: From -> To : Payload`; `loop do` with `(repeats)` and its body indented;
  an opened choice as `choose by R: taken` with `other branch: …` in the mark column; a
  closed one as `choose by R: a | b`; `stop`; `(end of conversation)`. Labels and marks
  are aligned columns (code-point widths, so the `…` row lines up).
- Marks: `done` on the role's own steps before its place; `<- `R` must do this next`
  (or `can only close here` on an end row); the tried text from the table above.
- No generated name appears: rows show roles, labels and payload types the program wrote
  (the internals lint checks).

## Position rules the marks rely on

A `choose` the role is at is drawn closed, so a step tried inside one of its branches is
not on the path and gets no mark (the role has not chosen yet). A step tried inside a
later `loop` or `choose` opens it along the tried position (`type_mismatch_9`: `close`
only comes after `done`, so the `done` branch is drawn to its `stop`). When the two
positions descend into different branches of one choice, the path follows `here`.
