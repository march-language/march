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
