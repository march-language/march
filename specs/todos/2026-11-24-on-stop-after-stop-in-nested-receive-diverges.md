`[P2]`

# `on_stop` after a stop that interrupts a nested `receive()`: interpreter runs it, compiled does not (2026-11-24)

Found while writing the authority catch-site fixtures. Not a capability bug.

An actor blocked in a `receive()` inside a handler is stopped with
`Actor.stop`. The interpreter then runs its `on_stop`; a compiled program does
not (the stop trap in `actor_green_thread`, `runtime/march_runtime.c`, sets
`stopped_in_handler` and jumps past the `on_stop` call, because the state
fields were moved into the abandoned handler's locals).

Repro: the program in
`specs/todos/2026-11-24-interp-send-then-nested-receive-stop-hangs.md` with the
`send` before `receive()` removed and this added to `Waiter`:

```march
    on_stop do
      match state.log do
      Some(l) -> send(l, Note("on_stop ran"))
      None -> None
      end
    end
```

Interpreted: `log lines: 1`. Compiled: `log lines: 0`.

`specs/lang/actors.md` ("on_stop") says it runs on a graceful stop, after the
drain; it does not say what happens when the handler itself is what the stop
interrupts. Needs a decision, then one engine changes and the reference says
which.

Also blocks one fixture: the stop trap is the one authority catch site with no
test (`specs/todos/2026-11-19-ocap-catch-sites-untested.md`), because a fixture
that reaches it prints different output on the two engines.
