---
layout: docs
title: Choreography
nav_order: 10.8
permalink: /docs/choreography/
---

# Choreography

A choreography is one description of a conversation between several parties. You write
down every message once, from the point of view of the whole system: who sends what to
whom, and in what order. The compiler turns that into code for each party. Each party then
runs as its own program, usually on its own machine, and the compiler has already checked
that the programs agree with each other.

In March you write the choreography as a `protocol` marked `@[endpoints]`. The compiler
generates a typed module for each role, and a runner that connects the roles over the
network. This page walks through one complete example, from the protocol to three
processes talking over TCP.

The network runner needs the compiled backend (`march --compile`). The interpreter cannot
run socket code yet. The generated types and the same-process transports work on both
backends; see [Session Types]({{ site.baseurl }}/docs/session-types/) for those.

## The example

Three roles. A and B each send a number to C. C adds them and tells A whether the sum is 16.

```march
@[endpoints]
protocol Fan do
  A -> C : Int
  B -> C : Int
  C -> A : Bool
end
```

This is the whole protocol. Nothing else in the program says who talks to whom. The same
example runs in CI as `test/two_node/fan`, with each role in its own OS process.

## Writing a protocol

A protocol is a list of steps. There are three kinds.

A message step names the sender, the receiver and the type of the value:

```march
A -> C : Int
```

A loop repeats its body until a branch says `stop`:

```march
loop do
  Prod -> Cons : Int
  choose by Cons:
    more -> Cons -> Prod : Bool
    done -> Cons -> Prod : Bool
            stop
  end
end
```

A choice lets one role decide which branch the conversation takes. `choose by Cons` means
Cons picks. Each branch starts with a label (`more`, `done`) and must begin with a message
from the chooser. That first message is how the other side learns which branch was
picked. The compiler rejects a branch that starts any other way.

## What the compiler generates

For a protocol `P` you get one module of shared definitions, one module per role, and one
module that runs roles on the network. For `Fan`:

| Module | Contents |
|---|---|
| `Fan_Msg` | The message type, its JSON codec (`encode`, `decode`, `try_decode`), and the role numbers `role_A()`, `role_C()`, `role_B()` |
| `Fan_A`, `Fan_B`, `Fan_C` | One type per point in the conversation, and one function per step that role takes |
| `Fan_Run` | `run_A`, `run_B`, `run_C` to run a role on a node, and `addrs_from_env()` |

Roles are numbered in the order they first appear in the protocol. In `Fan` that is A = 1,
C = 2, B = 3. You never need to write these numbers; use the generated functions.

Protocol steps have no names of their own, so each message is named after its sender, its
receiver and its position: the first message from A to C is `Msg_A_C_1`, the second would
be `Msg_A_C_2`. The first message of a `choose` branch takes the branch label instead, so
the `more` branch above sends `More`.

Each role module has a type for every state the role can be in, and a function for every
step out of that state:

| Step in the protocol | Function in the role module |
|---|---|
| this role sends `Msg` | `send_Msg(s, state, value)` returns the next state |
| this role receives `Msg` | `recv_Msg(s, state, fn (value, next) -> ...)` |
| this role picks `label` | `choose_label(s, state, value)` returns the next state |
| another role picks | `offer_l1_l2(s, state, on_l1, on_l2)`, one callback per branch |
| the conversation ends | `close(s, state)` |

`register(s, 0)` gives a role its first state.

## Writing a role

A role is a function from its first state to `Yield`. Here is C:

```march
pfn role_c(s : Cap(Session.Live), st : Fan_C.S_recv_Msg_A_C_1) : Fan_C.Yield do
  Fan_C.recv_Msg_A_C_1(s, st, fn (a, st1) ->
    println("C: got " ++ int_to_string(a) ++ " from A")
    Fan_C.recv_Msg_B_C_1(s, st1, fn (b, st2) ->
      println("C: got " ++ int_to_string(b) ++ " from B")
      Fan_C.close(s, Fan_C.send_Msg_C_A_1(s, st2, a + b == 16))))
end
```

The state types are what make this safe. Each one is linear: you must use it exactly once.
`recv_Msg_A_C_1` accepts only the state C is in before hearing from A, and it hands the
callback the only value that lets C take the next step. So the compiler rejects a program
that sends before it has received, receives twice, sends a `String` where the protocol says
`Int`, or stops halfway through. The return type `Yield` can only be produced by a generated
step function, so a callback cannot quietly drop the conversation either.

And A:

```march
pfn role_a(s : Cap(Session.Live), st : Fan_A.S_send_Msg_A_C_1) : Fan_A.Yield do
  let st1 = Fan_A.send_Msg_A_C_1(s, st, 7)
  Fan_A.recv_Msg_C_A_1(s, st1, fn (ok, st2) ->
    println("A: got " ++ bool_to_string(ok))
    Fan_A.close(s, st2))
end
```

## Running a role on a node

Each role becomes a program whose `main` calls its runner:

```march
fn main(c : Cap(IO)) do
  match Fan_Run.run_C(c, "node-c", "fan-secret", Fan_Run.addrs_from_env(), fn (s, st) -> role_c(s, st)) do
    Ok(_) -> println("C: closed")
    Err(e) -> panic(SessionNode.run_error_message(e))
  end
end
```

The arguments are:

- `c`: the program's IO capability.
- `"node-c"`: this node's name, used in the handshake.
- `"fan-secret"`: a secret every node in the session shares. A node with a different secret
  is refused.
- `Fan_Run.addrs_from_env()`: where the roles are, read from the environment (next section).
- The body: a function from the session and C's first state to `Yield`. Its type comes from
  the protocol, so passing A's body to `run_C` does not compile.

`run_C` connects to the other roles, runs the body, delivers messages until every role has
closed, and disconnects. It returns `Ok` when the conversation finished, or an `Err` that
says why it did not.

## Telling the nodes where to find each other

Every pair of roles that exchange a message needs a connection, and one side of each pair
has to listen. The rule: **of any two roles, the one with the lower number listens and the
higher one connects.** The runner connects to every lower-numbered role first, in order,
and then accepts one connection from each higher-numbered role. Because every role only
ever waits on roles below it, the startup cannot deadlock.

Addresses come from environment variables named `<PROTOCOL>_<ROLE>_ADDR`, set to
`host:port`. A role needs its own address if any role above it will connect to it, and the
address of every role below it that it talks to.

For `Fan` (A = 1, C = 2, B = 3):

| Node | Listens for | Connects to | Needs |
|---|---|---|---|
| A | C | nobody | `FAN_A_ADDR` |
| C | B | A | `FAN_A_ADDR`, `FAN_C_ADDR` |
| B | nobody | C | `FAN_C_ADDR` |

So:

```bash
FAN_A_ADDR=10.0.0.1:7001 ./node_a
FAN_A_ADDR=10.0.0.1:7001 FAN_C_ADDR=10.0.0.2:7002 ./node_c
FAN_C_ADDR=10.0.0.2:7002 ./node_b
```

The nodes can start in any order, but they all have to be up within 20 seconds of each
other. A node that connects before its peer is listening retries for up to 20 seconds, and
a listening node waits up to 20 seconds for the next role to connect. If one never does,
setup fails instead of waiting for ever: `run_<Role>` returns `Err(Accept(...))` or
`Err(Connect(...))` naming the missing roles, and closes the connections it already made,
so the roles it did reach fail too instead of waiting on it. Set
`MARCH_SESSION_CONNECT_MS` to change the 20 seconds; 0 waits for ever. If a required variable is missing, the node stops at startup with a
message that names the role, for example
`session_node: role 2 needs an address for role(s) 1`, before it opens any socket.

You can also build the list yourself instead of reading the environment. It is a
`List(SessionNode.Addr)`, one `{ role, host, port }` per role.
`SessionNode.parse_addr(role, "host:port")` parses one entry and returns a `Result`.

## Running over a cluster node

If your nodes already run a [`ClusterNode`]({{ site.baseurl }}/docs/clustering/#a-running-node-clusternode),
a role can use it instead of opening connections of its own. The generated
`<P>_Run.cluster_<Role>(io, node, session, body)` takes the running node and a session id,
which is any string the roles agree on, fresh for each session:

```march
match Fan_Run.cluster_C(c, node, "fan-" ++ int_to_string(round), fn (s, st) -> role_c(s, st)) do
  Ok(_) -> println("C: closed")
  Err(SessionNode.Cancelled(role, cause)) -> println("C: cancelled: " ++ cause)
  Err(e) -> println(SessionNode.run_error_message(e))
end
```

- **No addresses.** Each role registers its endpoint under the session's name and finds the
  others by name (waiting up to 30 seconds), so there are no `<P>_<ROLE>_ADDR` variables and
  no listen/connect rule.
- **Shared connections.** Frames ride the node's one connection pair to each peer node,
  alongside every other session between those nodes. Every frame carries the session id, so
  a frame from another session is refused rather than delivered.
- **The node is the failure detector.** There is no session heartbeat. A peer is gone when it
  closes or is cancelled, or when its node's connection ends: the node declared it dead
  (`node node-b dead: suspect timeout`, `... connection refused`), or the connection was
  lost. The drain rule still holds: the node reports the death only after the last message
  that arrived from that peer.
- Every role must run on a different node.

## Messages from different peers

Each connection delivers its messages in order, but two connections are not ordered against
each other. In `Fan`, C expects A's number first. If B is faster, B's message arrives first.
The runner holds it until C has received from A and asked for B. You do not need to write
anything for this; the generated code tells the runner which role each receive is waiting
for.

## Large messages and slow peers

A message can be any size, and a role can send as many messages in a row as it likes without
waiting for the receiver. Whatever the receiving node has not taken yet waits on the sending
node and goes out as the receiver catches up. Nothing is dropped. A peer that stops reading
altogether is caught by the heartbeat (see [When a role fails](#when-a-role-fails)), and
whatever was waiting for it is thrown away.

## How a session ends

`run_<Role>` returns one of these:

| Result | Meaning |
|---|---|
| `Ok(_)` | This role reached the end of the protocol. |
| `Err(Cancelled(role, cause))` | This role was waiting on `role`, that role failed, and nothing it had sent was still waiting to be read. `cause` says what went wrong: `"connection lost"`, `"no heartbeat"`, or a chain such as `"role 3: connection lost"` when the failure reached this role through another one. |
| `Err(Protocol(role, why))` | That role sent something this role cannot accept: a message that does not decode, or one the protocol does not allow at this point. |
| `Err(HostGone(ep))` | Only for a role hosted in an actor (below): the actor died. |
| `Err(Left(why))` | This role left the session on purpose (below). |
| `Err(Listen(port, why))`, `Err(Accept(why))`, `Err(Connect(role, why))` | Startup failed: the port was taken, a handshake was refused, a peer never came up. |

`SessionNode.run_error_message(e)` turns any of these into a readable line.

## When a role fails

A role that crashes, is killed, or stops responding is *cancelled*. Three rules decide what
happens to the others:

- **A role fails only if it needs the failed role.** If it is waiting for a message from the
  failed role, and nothing that role sent is still waiting to be read, it is cancelled too.
  Messages the failed role sent before it went are always delivered first.
- **A role that no longer needs the failed role carries on.** In `Fan`, if B sends its
  number and then crashes, C already has B's number, so C answers A and the session
  finishes: A and C both return `Ok`.
- **Messages sent to a cancelled role are dropped.**

A cancelled role tells its own peers, so a failure goes only as far as it has to. In `Fan`,
if B crashes before it sends, C is cancelled because it was waiting on B, and then A is
cancelled because it was waiting on C, even though A never talks to B. A gets
`Cancelled(2, "role 3: connection lost")`.

A crashed process is noticed when its connection closes. A process that is still running
but has stopped answering (hung, paused, or cut off by the network) is noticed by a
heartbeat: each connection is pinged every second, and a peer that sends nothing for 10
seconds is treated as failed. `MARCH_SESSION_HEARTBEAT_MS` and `MARCH_SESSION_TIMEOUT_MS`
change the two numbers. The heartbeat can mistake a very slow peer for a dead one. That
cancels a session that could have finished, which costs a retry but never corrupts
anything.

### Handling a failure

Every receive has a second form, ending in `_or`, that takes a cancel handler. Offers have
the same (`offer_more_done_or`):

```march
Fan_C.recv_Msg_B_C_1_or(s, st1,
  fn (b, st2) ->
    Fan_C.close(s, Fan_C.send_Msg_C_A_1(s, st2, b > 0)),
  fn (role, cause, cancel) ->
    println("gave up on role " ++ int_to_string(role) ++ ": " ++ cause)
    Fan_C.cancelled(s, cancel))
```

The handler runs if this receive's sender fails with nothing queued. It gets the failed
role, the cause and a token, but no session state, so it cannot send or receive in the
failed session. The only way for it to finish is `Fan_C.cancelled(s, cancel)`. Use it to
record the failure, release a resource, or report what happened somewhere else. A receive
without `_or` behaves the same way, with no handler.

To leave a session on purpose, call the `leave_` function for the state you are in:
`Fan_C.leave_recv_Msg_A_C_1(s, st, "shutting down")` for C before it has heard from A. The
other roles are told, and `run` returns `Err(Left(why))`.

### Starting again

A session cannot be resumed. To try again, call `run_<Role>` again on every node, which
starts a new session with new connections. Deciding when to do that, and making sure every
node does, is up to whatever runs the nodes, for example a supervisor around
`run_<Role>`. The runner does not restart anything by itself.

## Hosting a role in an actor

The body in the examples above is a chain of callbacks. The session state lives inside those
callbacks, so they cannot read an actor's state. If a role needs to consult state it keeps
between messages (a counter, a cache, a database handle), host the role in an actor instead.

The role module has a second set of functions for this. The actor keeps a
`Parked_<Role>` value in its state. It starts idle, the actor parks it by calling an
`await_` function, and each delivery wakes it with `resume`, which returns the message and
the next state. Here is the consumer of the `Stream` protocol from earlier, deciding from its
own `budget` whether to ask for more:

```march
actor ConsActor do
  state { budget : Int, parked : Stream_Cons.Parked_Cons }
  init  { budget: 2, parked: Stream_Cons.idle() }
  on StartC(s : Cap(Session.Live)) do
    Stream_Cons.take_idle(state.parked)
    { state with parked: Stream_Cons.await_Msg_Prod_Cons_1(s, Stream_Cons.register(s, 0)) }
  end
  on DeliverC(s : Cap(Session.Live), from : Int, msg : Bytes, ep : Int) do
    match Stream_Cons.resume(state.parked, from, msg, ep) do
      Got_Msg_Prod_Cons_1(n, st) ->
        if state.budget > 1 do
          let st2 = Stream_Cons.choose_more(s, st, true)
          { state with budget: state.budget - 1,
                       parked: Stream_Cons.await_Msg_Prod_Cons_1(s, st2) }
        else
          let st2 = Stream_Cons.choose_done(s, st, true)
          { state with parked: Stream_Cons.finish(s, st2) }
        end
    end
  end
end
```

`Parked_Cons` is linear too, so every handler must consume the parked value and store a new
one. A handler that forgets to park again does not compile.

To run it, use `host_<Role>` in place of `run_<Role>`. It takes the actor, a function that
starts it, and a function that hands it each delivery:

```march
fn main(c : Cap(IO)) do
  let pc = spawn(ConsActor)
  let start = fn s ->
    let _ = send(pc, StartC(s))
    ()
  let deliver = fn (s, from, msg, ep) ->
    let _ = send(pc, DeliverC(s, from, msg, ep))
    ()
  match Stream_Run.host_Cons(c, "node-b", "stream-secret", Stream_Run.addrs_from_env(), pc, start, deliver) do
    Ok(_) -> println("Cons: closed")
    Err(e) -> panic(SessionNode.run_error_message(e))
  end
end
```

The actor gets one delivery at a time. A message that arrives while it is still handling
the previous one waits until it has parked again.

The runner watches the actor. If it crashes, or is killed, or its supervisor restarts it,
its role is cancelled: `host_<Role>` returns `Err(HostGone(ep))`, and the other roles are
cancelled or carry on by the rules in [When a role fails](#when-a-role-fails). A restarted
actor starts idle and cannot pick up the old conversation; start a new session instead.

For the actor to hear that its role was cancelled, use `host_<Role>_or`, which takes a
fourth function after `deliver`. It is called with the session, the failed role, the cause
and the endpoint. Send those to the actor; its handler stores
`Stream_Cons.cancel(state.parked)`, which gives back a closed value, and can update the rest
of its state. Like a cancel handler, it cannot send in the failed session. This is the cost of keeping the session in the actor's state. The
callback style does not have it, because there the session state lives in the runner.

Different nodes can make different choices. In `test/two_node/hosted`, Prod is a plain body
on one node and Cons is an actor on the other.

## Testing without a network

The generated role modules do not know about sockets. They talk to whatever transport the
session was created with. For unit tests, attach an in-process transport with
`Session.attach` and run every role in one program; the [Session Types]({{ site.baseurl }}/docs/session-types/#swapping-the-transport-session)
page shows how. The same role functions then run unchanged on the network.

## Limits

- The network runner is compiled-only for now.
- A session cannot be resumed after a failure, and nothing restarts it for you.
- A cancel handler cannot keep the conversation going. A protocol that must keep talking
  after a role fails (to send a partial result, say) cannot be written yet.
- Every role that exchanges messages with another needs a direct connection to it. There is
  no relaying.
- Over a cluster node (`cluster_<Role>`), every role must be on a different node, and a
  connection lost for any reason cancels the sessions using it, even if the peer node
  reconnects at once. Frames in flight on the old connection may be gone, so the session
  cannot safely continue.
- Messages are encoded as JSON, so every payload type needs a JSON codec. Built-in types
  have one; for your own types, add `derive Json for YourType`.

## See also

- [Session Types]({{ site.baseurl }}/docs/session-types/): the type rules behind the
  generated states, and the two-party `Chan` API.
- [Clustering]({{ site.baseurl }}/docs/clustering/): node identity, the handshake, and
  `SessionNode`, the transport the runner uses.
- [Actors]({{ site.baseurl }}/docs/actors/): supervisors, which you would use to decide when
  to run a failed session again.
