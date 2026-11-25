`[P2]`

# Interpreter hangs when a handler sends, blocks in `receive()`, and is stopped (2026-11-24)

Found while writing the authority catch-site fixtures. Not a capability bug.

A handler that sends a message to another actor and then blocks in a nested
`receive()` is stopped with `Actor.stop`. Compiled, the program finishes.
Interpreted, `Actor.stop` returns `true`, a later `Actor.call` to the other
actor fails with "no reply (timeout or unhandled Call)", and the process never
exits.

```march
mod Main do
  needs IO
  needs IO.Console

  type GetLog = GetLog
  type LogState = { lines : List(String) }

  actor Log do
    state { lines : List(String) }
    init  { lines: [] }
    on Read(reply_to) do
      Actor.reply(reply_to, List.reverse(state.lines))
      state
    end
    on Note(s : String) do
      { lines: Cons(s, state.lines) }
    end
  end

  actor Waiter do
    state { log : Option(Pid(LogState)) }
    init  { log: None }
    on UseLog(l : Pid(LogState)) do
      { log: Some(l) }
    end
    on Block() do
      let _ = match state.log do
        Some(l) -> send(l, Note("before the block"))
        None -> None
      end
      let _m = receive()
      state
    end
  end

  fn main() do
    let log = spawn(Log)
    let w = spawn(Waiter)
    send(w, UseLog(log))
    send(w, Block())
    println("stop: " ++ bool_to_string(Actor.stop(w, 2000)))
    match Actor.call(log, GetLog, 2000) do
    Ok(ls) -> println("log lines: " ++ int_to_string(List.length(ls)))
    Err(e) -> println("log error: " ++ e)
    end
  end
end
```

Compiled: `stop: true`, `log lines: 1`, exit 0. Interpreted: hangs (killed after
25 s). Without the `send` before `receive()` both engines print `log lines: 0`
and exit.

What to do: find why the interpreter's nested `receive()` leaves the scheduler
unable to deliver to the other actor after the stop (`lib/eval/`), fix it, and
add the program above to `test/native` (interpreted and compiled, one expected
file).
