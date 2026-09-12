# `[P1]` `send(self, …)` inside an actor handler does not deliver

Found 2026-09-12 while fixing
`2026-09-11-self-in-an-actor-handler-does-not-compile.md`, which made `self`
reach the compiled backend for the first time and so made this observable.
Distinct from that item: this one is wrong on **both** backends, and in
different ways.

## The bug

```march
mod Self5 do
  needs IO.Console
  actor A do
    state { n : Int }
    init  { n: 0 }
    on Tick() do
      if state.n > 0 do
        print_line("resumed via self: n=" ++ int_to_string(state.n))
      else
        let _ = send(self, Tick())
        print_line("re-sent to self")
      end
      { state with n: state.n + 1 }
    end
  end
  fn main(c : Cap(IO.Console)) do
    let p = spawn(A)
    send(p, Tick())
    run_until_idle()
  end
end
```

| backend | output | exit |
|---|---|---|
| interpreted | **nothing at all** | 0 |
| compiled | `re-sent to self`, then nothing | 0 |

Expected on both: `re-sent to self` followed by `resumed via self: n=1`.

The interpreter is the stranger of the two — not even the first `print_line`
runs, so the handler appears to abort at the `send` itself, silently, with the
process still exiting 0.

## It is specific to self-sends

A handler sending to a **different** actor works correctly on both backends,
with identical output:

```march
on Go(other) do
  let _ = send(other, Pong())
  print_line("A sent to B from inside a handler")
  { state with n: state.n + 1 }
end
-- both backends: "A sent to B from inside a handler" then "B got Pong"
```

So neither "sends from inside a handler" nor "delivery" is broken in general.
Only sending to one's own pid is.

## What is already ruled out

The compiled side is **not** a wrong-pointer problem any more. As of the
`self` fix, `march_self` returns the actor pointer, which is exactly what a
Pid is at the ABI (`march_send` takes one, `march_spawn` returns one,
`march_pid_of_int` hands back `meta->actor`), and `self` is usable as a value
in a handler on both backends —
`test/native/actor_self.march` pins that. Something about delivering to the
**currently-running** actor is what fails, so look at the mailbox push and the
scheduler's requeue of a proc that is mid-turn, not at the pid value.

## A second, smaller divergence found alongside

`self == p`, where `p` is the pid the spawner holds for that actor, is **true
compiled and false interpreted**. The compiled answer is the defensible one
(`self` and `spawn`'s result are the same actor pointer); the interpreter's
`self` yields a `VPid` that does not compare equal to what `spawn` returned.
`test/native/actor_self.march` deliberately avoids comparing them so the
golden pins only what both agree on. Decide which representation is canonical
and make the other match.

## What to build

- Find where a self-directed `march_send` diverges from a send to another
  actor: most likely the mailbox enqueue path for a proc that is currently
  running, or a requeue that is skipped because the proc is not parked.
- Fix the interpreter's silent handler abort first: it is the worse symptom
  (no output, exit 0) and the easier read, since `eval`'s actor loop is a few
  hundred lines rather than a work-stealing scheduler.
- Settle the `self == spawn(...)` question and make both backends agree.

## Tests

- A native golden: re-send to self once, then stop — the trace must show both
  lines, interpreted and compiled. It is red on both backends today, so prove
  it red before trusting it.
- An equality case for the divergence above, once the canonical answer is
  chosen.
- Keep `test/native/actor_self.march` green throughout; it is the guard that
  `self`-as-a-value does not regress while this is fixed.

## Why P1

Re-sending to oneself is the ordinary way an actor drives a state machine
forward or yields between steps, it is in every actor tutorial, and it fails
silently — no diagnostic, no non-zero exit, just a program that stops doing
anything. The actor-hosted session endpoint
(`specs/progress/2026-09-11-actor-hosted-session-endpoint.md`) routes around
it by driving deliveries from outside, and had no reason to notice.
