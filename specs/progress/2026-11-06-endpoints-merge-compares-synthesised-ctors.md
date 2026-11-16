`[P2]` `@[endpoints]`: a bystander is not merged when its branches differ only in synthesised constructor names

Found 2026-11-06 by translation validation (`march --validate-projections`, lemmas design §5.2,
M6, progress `2026-11-06-session-theory-and-projection-validation`).

```march
@[endpoints]
protocol Three do
  choose by A:
    go -> A -> B : Int
          B -> C : Int
    halt -> A -> B : String
            B -> C : Int
  end
end
```

C receives `B -> C : Int` on either branch. The `Chan(Role, Proto)` projector
(`Typecheck_session.project_steps_at`) and `Session.Theory.project` merge C's branches into
one receive. The `@[endpoints]` generator does not: `annotate` names the two unlabelled
messages `Msg_B_C_1` and `Msg_B_C_2`, `merge` compares branches with `lty_equal` (constructor
names included), finds them different, and C's head is a receive from B, not the chooser, so
it falls back to an offer from A with fabricated `Got_Go`/`Got_Halt` messages. `march --check`
then fails with `type_mismatch` errors in generated code ("expected `()` but got `Int`",
"the excerpt cannot be shown"), with nothing pointing at the protocol.

The validator reports it honestly (C is "not told which branch a choice took" in the
generator's view, where the two messages are different), so this is not a disagreement with
the theory; it is the generator refusing a protocol the typechecker accepts, badly.

Fix, one of:
- name an unlabelled message by its endpoints and payload type within a choice's branches,
  so the same message in two branches gets one constructor (it already shares one when the
  user labels both alike); or
- reject the protocol at the protocol with "C is not told which branch `choose by A` took;
  label `B -> C` alike in both branches, or have A tell C", instead of generating code that
  does not typecheck.

## Resolution (2026-11-07)

`annotate` now shares synthesized wire constructors across equivalent whole
choice tails. Equality ignores synthesized names and type spans, but preserves
explicit labels, payload types, step order, nested choices, and atomic-loop
flags. Choice heads always retain their labels, including `msg_`-prefixed
labels. Sequential equal-payload steps retain separate constructor identities.
The generator also reuses structurally equal continuation states, avoiding
multiple nominal states/functions for the shared sender transition, while
keeping ordinary-loop drain boundaries distinct from atomic-loop states.

This deliberately does not implement general local-projection equivalence for
different global tails. Such protocols may still fail to merge even when one
bystander's local behavior agrees. Divergent continuations retain their original
wire tags and API identities.

Validation:

- Before the fix, the original CLI `--check` reproducer produced generated
  `Got_Go`/`Got_Halt` unit-versus-payload errors; all three initial regression
  cases failed against the original generator.
- The six focused endpoint tests pass: the original shared receive and both
  sender callbacks, generated shape without a fabricated chooser offer,
  nested/sequential tags, distinct continuations, explicit `Msg_` choice heads,
  and atomic versus ordinary receive drain behavior.
- A real in-process session exercises both branches and delivers `11` then
  `22`; `scripts/triage.sh` confirmed matching interpreter/native output. An
  enduring Slow endpoint test performs the same two-backend check.
- With `MARCH_STDLIB` pointing to the current source stdlib,
  `--check --validate-projections` confirms all three typechecker and all
  three endpoint projections agree with `Session.Theory.project`, and
  reports the protocol in the fragment for the model's laws. The initial
  attempt used an incomplete staged stdlib and reported not-compared;
  that incomplete result was not counted as a successful comparison.
- The final complete `run_compiler.exe test endpoints -e` run passed all 140
  endpoint cases, including the enduring interpreter/native regression
  (202.980 seconds). A fresh CLI check also accepts nested choices with two
  successive equal-payload messages per branch.
