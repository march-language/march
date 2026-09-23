# Actor `on_stop`: the terminate callback

Landed 2026-09-22. Closes the first of the two pieces left open in
[`specs/todos/2026-08-12-graceful-shutdown-and-drain.md`](../todos/2026-08-12-graceful-shutdown-and-drain.md)
after the drain half landed
([`2026-09-08-graceful-shutdown-and-drain.md`](2026-09-08-graceful-shutdown-and-drain.md)).
The todo stays open, trimmed, for the reload drain-first story.

## Surface

```march
actor Batcher do
  state { buf : List(String) }
  init  { buf: [] }
  on Append(s : String) do { buf: Cons(s, state.buf) } end
  on_stop do
    match Actor.whereis("store") do
      Some(store) -> send(store, Save(List.reverse(state.buf)))
      None        -> None
    end
  end
end
```

`on_stop do ... end`, at most one per actor, anywhere among the `on`
handlers. It reuses the `ON_STOP` token the `app` block's `on_stop` already
lexes (so no new reserved word) and reads like a handler without a message:
`state` (the final state) and `self` are in scope, there are no parameters,
and the value is discarded. In the AST it is `actor_on_stop : actor_handler
option`, a zero-param handler named `on_stop`; `Ast.actor_body_handlers`
gives body walkers (caps, lint, refinement, LSP, sandbox cap keys) the
handlers plus it, while anything that treats `ah_msg` as a message
constructor keeps using `actor_handlers`. Menhir conflicts unchanged (11).

## Semantics (decided by the repo owner 2026-09-22, OTP `terminate/2`)

1. It may send messages (and block on a reply).
2. A panic inside it is logged (`march: actor on_stop callback failed (the
   actor still stops): panic: <msg>`) and the NORMAL death proceeds. No
   restart, and a tree teardown continues to the next child.
3. It does not run on the brutal path: `kill`, a crash, `shutdown brutal`.
4. It is bounded by the stop timeout (`Actor.stop`'s `timeout_ms`, or the
   child spec's `shutdown`): the budget covers drain plus `on_stop`, and the
   actor is killed when it runs out.

## Relation to child specs

[`2026-09-08-supervisor-restart-types-and-child-specs.md`](2026-09-08-supervisor-restart-types-and-child-specs.md)
already gave each supervised child OTP's `shutdown` field (`<ms> | infinity |
brutal`), which is exactly the budget OTP's `terminate/2` runs under. So
`on_stop` needed no child-spec change: `shutdown <ms>` bounds drain +
`on_stop`, `infinity` waits for both, and `brutal` skips both. The callback
itself lives on the actor rather than in the child spec (OTP puts
`terminate/2` in the callback module, not the spec), so an unsupervised
actor stopped with `Actor.stop` gets the same behaviour.

## Implementation

- **Compiled.** `lower_actor` lowers the block through the handler glue as
  `Name_on_stop(actor)` with body `user_body; state`, so the state fields the
  glue MOVES out of the Lin actor record are written back by the same
  `EReuse` a handler ends with (without it the record would point at fields
  `state` freed). The spawn glue registers it with
  `march_register_actor_on_stop(Name_dispatch, Name_on_stop)` right after the
  record is allocated, keyed by the dispatch closure every record of the
  type holds in word 2: no layout change, and a supervisor restart (which
  re-runs the glue) needs nothing extra. `actor_green_thread` runs it after
  the receive loop exits iff the actor is still alive, draining, the
  deadline is armed and not past; `actor_run_on_stop` installs its own crash
  trap for the call (every actor, not only supervised ones, whose handler
  panics are otherwise process-fatal). The deadline kill comes from
  `march_actor_stop`'s existing waiter; a callback parked in `receive()`
  then leaves through the loop's `stop_jmp`.
- **Interpreter.** `stop_actor` runs `run_on_stop` after the drain and
  before the NORMAL death. A blocked `receive()` inside it waits out the
  deadline and the actor dies Killed; a panic is caught and logged.

## Traps hit on the way (both would have shipped without a compiled test)

1. **The `$clo_wrap` trampoline released the actor.** The runtime calls
   `Name_on_stop` through its static closure, and the generic trampoline
   `decrc`s every owned argument after the call. That freed the live actor
   record while `stop`'s waiter was still polling it: a heap corruption that
   surfaced later as SIGBUS in `mfm_alloc` on the Log actor's thread, 20/20
   runs with an empty `on_stop`. libgmalloc pinned the first bad read to
   `march_actor_stop`. Dispatch already had the exemption
   (`Llvm_emit.clo_wrap_borrowed`); `Tir_names.is_actor_on_stop_fn` now
   shares it.
2. **The stop request is a sticky flag on the proc.** `march_actor_stop`
   wakes the actor with `march_sched_request_stop`, which sets
   `stop_requested`; left set, the callback's first `receive()` returned
   "stop" immediately, so a blocking `on_stop` was cut off at once instead of
   at the deadline (the deadline fixture's `took >= 190` line caught it). The
   loop now clears the flag before the callback and re-checks liveness after,
   so a kill landing in between re-sets it and is not lost.

A side fix: an interpreter self-stop (`Actor.stop(self, t)` from a handler)
used to end the actor inside `stop_actor`, before the handler returned, so
the returned state was never installed and the queue behind it was dropped.
It now records `ai_self_stop` and the scheduler finishes the stop after the
handler returns (`finish_self_stop`), which is what the compiled loop does.

## Tests (each run compiled AND interpreted against one `.expected`)

- `test/native/actor_on_stop.march`: runs on `Actor.stop` with the drained
  state; runs on a self-stop with the handler's returned state; can wait on
  an `Actor.call`; does not run on `kill`.
- `actor_on_stop_panic.march` (+ `.stderr.expected`, both backends): a
  panicking `on_stop` unsupervised and inside a tree.
- `actor_on_stop_deadline.march`: a `receive()`-blocked `on_stop` is killed
  at `Actor.stop(w, 200)` and at a child's `shutdown 200`, with `stop`
  returning no earlier than the budget and well before 3 s.
- `actor_on_stop_tree.march`: children's `on_stop` in reverse declaration
  order, then the supervisor's; the `shutdown brutal` child runs none. This
  is the in-language teardown-order witness the drain PR had to take from
  `MARCH_SUP_TRACE`.

Red before green: on origin/main all four fail to parse. Each semantic rule
was also perturbed on the new code and the relevant fixture went red:
never calling it (compiled: all four native RED; interpreter: all four
interp RED), running it on every exit incl. kill (native `actor_on_stop` +
`actor_on_stop_tree` RED; interpreter equivalent likewise), no crash trap
(`actor_on_stop_panic` RED on each backend), leaving the stop flag set
(native deadline RED), no deadline wait in the interpreter (interp deadline
RED), and a non-deferred interpreter self-stop (interp `actor_on_stop` RED).
