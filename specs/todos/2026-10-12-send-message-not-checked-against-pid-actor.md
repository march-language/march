# `[P3]` `send` does not check a message against the actor its pid belongs to

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
