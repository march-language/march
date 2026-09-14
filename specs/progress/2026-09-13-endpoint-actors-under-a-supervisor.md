# `[P2]` Endpoint actors under a supervisor: what a restart means for a session

**Status:** specced 2026-09-13. The last item both endpoint records list as
not done. `2026-09-11-actor-hosted-session-endpoint.md` answered "is the
host replaceable?" by direct respawn (yes, for the callback API); this
answers it under a real `supervise` block, for both APIs, and settles the
case the event API traded away.

## The question

Two ways to host an endpoint in an actor now exist, and they keep the session
state in different places:

| API | session state lives in | after the host actor dies |
|---|---|---|
| callback (`recv_*`, `offer_*`) | the transport's stored continuation | nothing the session needs is lost |
| event (`await_*`, `resume`) | the actor's state (`Parked_<Role>`) | the parked state dies with it; the replacement starts `Idle` |

A supervisor restarts a crashed child with a **fresh pid** and fresh state.
So the two questions are: how does a delivery find the current incarnation,
and what does the transport do when the incarnation that parked the endpoint
is gone.

## Design

### Route by name, not by pid (callback API)

Names survive supervisor restarts (`specs/lang/actors.md`, "Hold names, not
Pids, across a restart boundary"). The mailbox transport therefore registers
each endpoint's host under a **name** (`Actor.register(pid, "ep<N>")`) at the
spawn site and routes every delivery through `Actor.whereis` at delivery
time. A restarted host is reached without the transport learning the new pid,
and the callback API's continuation resumes inside the replacement's turn.
The protocol continues from exactly where it was, as the direct-respawn
fixture measured, now with `supervise` doing the respawning.

`whereis` can be `None` while a child waits out restart backoff; the first
restart is zero-delay, so this fixture never sees it. A driver that can is the
one place the transport should retry rather than panic.

### Route by capability, and abandon on a stale one (event API)

For an event-shaped endpoint the replacement holds `Idle`, and a delivery to
it would hit `resume`'s "delivery before the endpoint was started" panic,
crash the replacement, and — under `one_for_one` — loop until the restart
budget escalates. The transport must not deliver to an incarnation that did
not park the endpoint. Actor capabilities carry the incarnation's **epoch**
(`get_cap`, `send_checked`: `:error` for a stale cap), so the transport takes
a cap when the host parks and sends through it; `:error` means the host that
parked this endpoint is gone, and the transport **abandons the session**:
it reports which endpoint's host restarted, closes the peer's endpoint so it
is not left awaiting forever, and stops routing.

That is the honest outcome of the event API's trade: the step can read the
actor's state because the session state *is* actor state, and actor state
does not survive a restart. Recovering it would need the actor to
re-establish the session on `Start` (a protocol-level resume, which `Stream`
does not have) or a durable place for `Parked` outside the actor, which is
the callback design again.

### Not a generator change

Both policies are transport-level: where a delivery goes and what a rejected
delivery means. `Session.Ops` does not change, the generated APIs do not
change, and a network transport would make the same two choices with a node
in place of a pid.

## Tests

- `test/session/stream_actor_supervised.march`: the callback fixture's two
  `Ep` actors as children of one `one_for_one` supervisor, routed by name.
  After the first delivery, `kill` the Cons host; the supervisor restarts it;
  the remaining trace is `stream_endpoints.expected`'s, with a marker line
  where the kill happened. Non-vacuous: without the name-based route (a pid
  captured at spawn), the second delivery goes to a dead pid and the trace
  stops.
- `test/session/stream_actor_events_supervised.march`: the event fixture's
  two actors under the same supervisor, routed by cap. After the first
  delivery, `kill` the Cons host; the next delivery's `send_checked` is
  `:error`, the transport prints the abandonment, closes Prod's endpoint, and
  the program exits 0 with the peer's `close` in the trace.
- Existing session goldens unmoved.

## Out of scope

- Restart backoff and `whereis = None` handling under a real timer: the
  driver's retry is one line, but a fixture needs a deterministic clock.
- A protocol-level "resume from state X" message. Session types would have
  to express it (a loop entry with the state as payload); that is a language
  design, not a transport policy.
- A network transport.

---

## What shipped (2026-09-13)

Both fixtures, as designed, with traces identical on both backends:

- `stream_actor_supervised.march` (callback API, routed by name): the full
  eight-line `Stream` trace with the marker `-- Cons host killed; supervisor
  restarted it --` after the first delivery. The killed host's replacement,
  reached by `Actor.whereis`, resumed the transport's continuation. Proved
  non-vacuous: routing by the pid captured at spawn instead, the delivery
  after the kill finds a dead actor and the trace stops.
- `stream_actor_events_supervised.march` (event API, routed by cap): after the
  kill, Prod's own delivery still goes through (its cap is current), Prod
  sends `Item(2)`, and the delivery to Cons is refused by `send_checked` —
  the transport prints the abandonment and closes Prod's endpoint (`close 1`).
  Neither `resume`'s "before the endpoint was started" panic nor the restart
  budget is reached.

Two things learned while building:

- **A user function named `own` with two arguments is miscompiled** into the
  resource-registration builtin's `Drop$<Type>.drop` call (link error on the
  compiled backend only; the interpreter is fine). The first version of the
  callback fixture hit it; the helper is named `claim`. Filed as
  [[2026-09-13-user-fn-named-own-miscompiled-as-resource-builtin]].
- `kill` on a supervised child restarts it within the same `run_until_idle`:
  the first restart has no backoff, so `whereis` never returned `None` here.
  A driver that can see backoff should retry, as the design says; untested.

The docs' "Generated endpoints" section gained an "Under a supervisor"
paragraph in both trees.
