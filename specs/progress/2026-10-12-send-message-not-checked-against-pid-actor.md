# `[P3]` `send` does not check a message against the actor its pid belongs to (fixed 2026-10-15, one-sided)

**Logged:** 2026-10-12, found while fixing
`specs/progress/2026-09-22-stdlib-distributed-module-errors.md`.

`send(pid, Msg(...))` typechecks the pid and the message separately and never relates
them. A message constructor of actor A sent to a typed `Pid` of actor B is accepted
(confirmed on the compiler before and after that fix, once both actors are declared).
At run time the receiving actor gets a message tag it has no handler for.

## Repro

```march
mod WrongActor do
  needs IO.Console
  actor A do
    state { n : Int }
    init { n: 0 }
    on Ping(k : Int) do { state with n: state.n + k } end
  end
  actor B do
    state { s : String }
    init { s: "" }
    on Note(t : String) do { state with s: t } end
  end
  fn main(_c : Cap(IO.Console)) do
    let b = spawn(B)
    send(b, Ping(1))
  end
end
```

Expected: a type error at `Ping(1)` (B has no `Ping` handler).

## Fix direction

When the pid's type names an actor (`Pid(B)`), unify the message with `B_Msg`
(the type actor message constructors already get in the typechecker, `ci_type =
<Actor>_Msg`). An untyped/raw pid keeps today's behaviour. Check the stdlib and corpus
for code that relies on the leniency before landing.

## Resolution (2026-10-15)

Two corrections to the premise first. The compiled outcome was not a misroute:
since 2026-07-07 (`967c99782`) every `<Actor>_Msg` gets a globally unique tag and
each actor's dispatch has a default drop arm, so a foreign message is dropped on
both backends (verified on the pre-change compiler). And the fix direction above
cannot be done as written: a pid is `Pid(state)`, not `Pid(B)`, and the state is a
STRUCTURAL record, so two actors with identically-shaped state share one pid type.

`check_send_target` (`lib/typecheck/typecheck.ml`, called from the `ESend` arm)
rejects a send, with the new code `send_wrong_actor`, when the pid's type is
`Pid(state)` with a concrete record state and the message's owner actor's state
cannot be that record. Unification variables and non-record types are wildcards,
so an unannotated or generic pid is never rejected. One-sided by construction:
a message for an actor whose state has the same shape as the target's still
typechecks and is dropped at run time.

The check also catches a pre-existing backend split: when two actors share a
handler name, a bare constructor resolves to one owner, so the interpreter ran
the target's same-named handler (dispatch by name) while compiled code dropped
the other actor's message (`counter 1` vs `counter 0`). The error's advice is to
rename a handler, because no qualified spelling selects an actor's message
(`specs/todos/2026-10-15-actor-message-ctor-cannot-be-qualified.md`).

Tests: `specs/lang/types/reject/t323_send_message_of_other_actor.march`,
`specs/lang/types/accept/t324_send_target_check_no_false_positive.march`,
`test/errors/send_wrong_actor_{1,2}`. The full typing corpus (444) passes.
`specs/lang/core-march-types.md` §2.6.4 and finding 19, and `specs/lang/actors.md`,
are updated; finding 19's "misrouted, memory-unsafe" text was stale.
