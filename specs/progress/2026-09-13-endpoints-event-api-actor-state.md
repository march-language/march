# `[P2]` `@[endpoints]`: an event-shaped API, so a session state can live in actor state

**Status:** specced 2026-09-13. The "handler-shaped generator variant" the two
shipped endpoint records list as not done
(`2026-09-03-protocol-projector-typed-endpoints.md`,
`2026-09-11-actor-hosted-session-endpoint.md`). Unblocked by the linearity
work of PR #442: a linear field of an actor's state is now tracked through
every handler turn (move-out rules R1–R5, strict branches), which is the
guarantee the first design needed and could not get.

## The gap

The generated API is callback-shaped: `recv_X(s, st, k)` and
`offer_…(s, st, on_a, on_b)` take closures, and the session state rides in the
closure the transport stores. That is why the actor-hosted fixture needs no
compiler change, and it is also its limit, recorded in its design: **a
callback cannot read the actor's state record.** The `Cons` role's budget has
to be threaded through the closure by hand, and an endpoint hosted in an actor
that also holds a database handle, a counter, or a supervisor's bookkeeping
cannot reach any of it from inside a session step.

Maty's answer is that the handler is chosen at suspension time and runs with
the actor's state. March's equivalent: the actor's own `on` handler receives
the delivery, and the session step becomes a value it matches on, with
`state` in scope.

## Design: an event API beside the callback API, in the same module

Not a new attribute. Which host drives a role is a property of the *instance*
(`main` can drive `Prod` as a function while `Cons` is an actor), not of the
protocol, so both APIs are generated for every role from one `@[endpoints]`.
The callback API is unchanged; `stream_endpoints`/`stream_actor` goldens must
not move.

For role `R` of protocol `P`, `P_R` additionally gets:

```march
always_linear type Parked =            -- "this endpoint is awaiting a delivery"
    Idle(Secret)                       -- not started; what `init` can hold
  | Awaiting_<state>(Int, Secret)      -- one per receiving state (LRecv, LOffer)
  | Closed(Secret)

type Received =                        -- one constructor per receivable message
    <Ctor>(<payload>, <next state>) | …

fn idle() : Parked                                -- for `init`
fn take_idle(p : Parked) : ()                     -- consume the Idle placeholder; panics otherwise
fn await_<ctor>(s, st : S_recv_<ctor>) : Parked   -- per LRecv state
fn await_<labels>(s, st : S_offer_<labels>) : Parked   -- per LOffer state
fn finish(s, st : S_end) : Parked                 -- Session.close; returns Closed
fn resume(p : Parked, from : Int, msg : Bytes, ep : Int) : Received
```

- `await_*` consumes the state, calls `Session.suspend(s, ep, h)` so the
  transport knows the endpoint awaits (the driver's "no continuation
  installed" guard keeps working), and returns `Awaiting_<state>(ep, Secret)`.
  `h` **panics**: an event-shaped endpoint is resumed by its actor, never by
  the transport calling a handler. Using one with the in-process transport,
  whose drain calls the handler directly, fails loudly with a message that
  says so.
- `resume` decodes the message against the parked state: it checks the
  delivery is for the parked endpoint, that the constructor is one the state
  can receive, and mints the next state on `ep`, exactly as the callback API's
  transport handler does. Everything unexpected panics with the protocol,
  role, state and message named.
- `Parked` is `always_linear`, so an actor state field `parked : P_R.Parked`
  must be consumed and replaced on every turn (R3/R4): a handler that resumes
  and forgets to park again, or parks twice, is rejected. `Secret` keeps both
  `Parked` and its states unforgeable, as `Yield` is.
- `Received` holds a linear state, so a `Received` binding is linear (the container
  rule), and matching it is its one use.

The user's actor, sketched:

```march
actor ConsActor do
  state { budget : Int, parked : Stream_Cons.Parked }
  init  { budget: 2, parked: Stream_Cons.idle() }
  on Start(s : Cap(Session.Live)) do
    Stream_Cons.take_idle(state.parked)
    { state with parked: Stream_Cons.await_Msg_Prod_Cons_1(s, Stream_Cons.register(s, 0)) }
  end
  on Deliver(s : Cap(Session.Live), from : Int, msg : Bytes, ep : Int) do
    match Stream_Cons.resume(state.parked, from, msg, ep) do
      Msg_Prod_Cons_1(n, st1) ->
        if state.budget > 1 do
          { state with budget: state.budget - 1,
                       parked: Stream_Cons.await_More_Done(s, Stream_Cons.choose_more(s, st1, true)) }
        else
          { state with parked: Stream_Cons.finish(s, Stream_Cons.choose_done(s, st1, true)) }
        end
    end
  end
end
```

`state.budget` is read inside the step. That is the whole point.

### Decisions

- **`Idle`, not `Option(Parked)`.** `init` must produce a value and cannot mint
  a real parked state, so `Parked` has an `Idle` placeholder that `take_idle`
  consumes. `Option(Parked)` would not be tracked: a record field of type
  `Option(S)` is not a linear field (`field_linearity` looks at the field's
  own type, not what it holds). That is a real gap, filed separately as
  [[2026-09-13-linear-field-holding-a-container-untracked]]; this design does
  not depend on it.
- **One actor type per role.** The callback fixture had to use one actor type
  for both roles, because the role lived in the continuation and two actor
  types would mint two `Deliver` constructors. Here the role *is* the actor's
  state type, so two actor types are the natural shape, and the router
  dispatches on the destination endpoint (`ep` = role index in this
  transport).
- **The capability travels in the message.** `Cap(Session.Live)` reaches a
  handler as a payload (verified in the projector design); putting it in
  state would need `Option` again.
- **`Received` constructor names are the message constructor names.** (Not `Event`: the stdlib already has two types of that name, and the flat constructor namespace made `match` exhaustiveness report their constructors as missing.) A message
  received in two states with different continuations would need two
  constructors of one name; the generator reports it rather than inventing
  names. It cannot happen for synthesised names (one per message step), only
  for a label reused across choices.

## Tests

- `test/session/stream_actor_events.march` + `.expected`: both roles as
  actors holding `Parked` in state, trace byte-identical to
  `stream_endpoints.expected`. Prove non-vacuous by disabling the router's
  send (trace collapses) and restoring.
- Reject witnesses (`specs/lang/types/reject/`): a handler that resumes and
  returns `{ state with budget: … }` (the parked state is dropped:
  "`state.parked` is used more than once", since the update keeps the consumed
  field); a handler that calls `resume` twice on one `Parked`; a `Start`
  that doesn't `take_idle` (never used).
- Accept witness: the sketch above.
- `stream_endpoints`, `stream_actor`, `stream_actor_restart`, `stream_replay`
  unmoved; `types-oracle` unmoved apart from the new fixtures.

## Out of scope

- A network transport; a supervisor tree. Unchanged from the parent records.
- A `Parked` that survives an actor restart: `Parked` is in the actor's state,
  so a restarted actor starts `Idle`. The callback design's "host is
  replaceable" property is traded for "the step can see the state". Both
  shapes stay available; say so in the docs.

---

## What shipped (2026-09-13)

`lib/desugar/desugar_endpoints.ml`, `role_module`: the event API generated
after the callback transitions, in the same module. `test/test_endpoints.ml`
gained a shape check and five guarantee cases; the corpus `reject/t236`–`t238`,
`accept/t239`; the fixture `test/session/stream_actor_events.march` whose
trace equals `stream_endpoints.expected` on both backends, proved non-vacuous
by replacing the router's send with `Some(())` (trace collapses to one line).
Docs: a subsection under "Generated endpoints" in `specs/lang/session-types.md`
and `docs/session-types.md`.

Three things changed from the design above while building it:

- **Every generated name carries the role** (`Parked_Cons`, `Received_Cons`,
  `Idle_Cons`, `Closed_Cons`, `Got_<msg>`). Types and constructors share one
  flat namespace (the FQN-identity plan is open), so two roles' `Parked`
  were one nominal type holding both roles' constructors, and a user's
  exhaustive `match` on `resume`'s result was told the other role's messages
  were missing. The first name tried, `Event`, additionally collided with two
  stdlib types of that name, which also broke the interpreter's `derive`
  dispatch for the generated `Msg` codec ("no Json derive for type Event"):
  bare-name collisions reach further than the checker.
- **`await_*` uses the endpoint once.** `ep` is bound by matching a linear
  state, inherits its linearity, and a second use is an error. The generated
  code parks `Session.suspend`'s result, which is the endpoint. The endpoint
  unit harness caught this; `march --check` did not, because diagnostics in
  generated code are filtered out at the CLI (file `"<none>"`) — filed as
  [[2026-09-13-generated-code-diagnostics-dropped-at-the-cli]].
- **`resume` takes and ignores `from`.** The projection knows who sends each
  message; the parameter is there so a handler passes the `Deliver` payload
  through unchanged.

The parked-state-in-actor design trades the callback design's "host is
replaceable" property (a restarted actor starts `Idle`) for "the step can see
the state"; both APIs are generated, and which one drives a role is chosen
per instance.
