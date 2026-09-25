---
layout: docs
title: Choreography
nav_order: 10.8
permalink: /docs/choreography/
---

> Part of the March Language Reference; see [specs/lang/index.md](https://github.com/march-language/march/blob/main/specs/lang/index.md).

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
  number: A -> C : Int
  second: B -> C : Int
  verdict: C -> A : Bool
end
```

This is the whole protocol. Nothing else in the program says who talks to whom. The word
before each step is the message's name; the functions the compiler generates are called
after it. The same example runs in CI as `test/two_node/fan`, with each role in its own OS
process.

## Writing a protocol

A protocol is a list of steps. There are three kinds.

A message step names the sender, the receiver and the type of the value, and may name the
message itself with a lowercase label in front:

```march
number: A -> C : Int
```

The label is what the generated functions are called after (`send_Number`, `recv_Number`).
A step without one gets a name made up from its endpoints; see the table in the next
section. Two steps may share a label when they carry the same type and no single role takes
both of them.

A loop repeats its body until a branch says `stop`:

```march
loop do
  item: Prod -> Cons : Int
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

After its first message a branch can go on for as many steps as it needs, one per line,
labelled or not. A new line starting `name ->` begins the next branch; anything else
(`A -> B : T`, `tick: A -> B : T`, `stop`, a nested `loop` or `choose`) continues the
current one:

```march
choose by A:
  go -> A -> B : Int
        tick: A -> B : Int
        B -> A : String
  no -> A -> B : Bool
end
```

A protocol may also say what each role's code is allowed to do:

```march
@[endpoints]
protocol Checkout do
  role Client needs IO.NetConnect
  role Ledger needs IO.FileWrite, IO.NetConnect
  ...
end
```

These grant lines come before the first message step, one per role, and take the same
capability paths as a module's `needs` (a misspelt one gets the same did-you-mean). A grant
is a claim about the role's code, not about the conversation, so it is not part of the
protocol's fingerprint: two nodes built with different grants still talk. What a grant
does is the subject of [Per-role grants](#per-role-grants) below.

## What the compiler generates

For a protocol `P` you get one module of shared definitions, one module per role, and one
module that runs roles on the network. For `Fan`:

| Module | Contents |
|---|---|
| `Fan_Msg` | The message type and its JSON codec (`encode`, `decode`, `try_decode`); the role numbers `role_A()`, `role_C()`, `role_B()` and `role_name(n)` back; `peers_A()` and `others_A()` (the roles A talks to, and every role but A); `role_names()`; `fingerprint()`, a digest of the protocol |
| `Fan_A`, `Fan_B`, `Fan_C` | One type per point in the conversation, and one function per step that role takes |
| `Fan_Run` | The entry points that run a role on a node (see [Running a role on a node](#running-a-role-on-a-node)), `addrs_from_env()`, and `error_message(e)`, which spells a `RunError` with role names |

**Names `P` reserves.** The generated modules are `P_Msg`, `P_<Role>` and `P_Run`, and the
message type inside `P_Msg` is `P_Message`. Those names are yours to avoid: a type of your
own called `P_Message` that also derives an interface the generated codec derives is
rejected as an overlapping implementation. Two protocols in one module is fine: each one's
message type is named after its own protocol, which is what keeps their `Json` codecs apart
(before 2026-09-22 both were called `Msg`, and the first protocol's sends encoded through the
second's codec).

Roles are numbered in the order they first appear in the protocol. In `Fan` that is A = 1,
C = 2, B = 3. You never need to write these numbers; use the generated functions.

Every message has a name, and every generated function and state carries it. Where the
name comes from:

| Step in the protocol | Message name |
|---|---|
| a labelled step, `number: A -> C : Int` | `Number`, the label capitalised |
| an unlabelled step, `A -> C : Int` | `Msg_A_C_1`: sender, receiver, and its position among the messages from A to C (`Msg_A_C_2` for the second) |
| the first message of a `choose` branch, `more -> Cons -> Prod : Bool` | `More`, the branch label; the step takes no label of its own |

A label that would spell a made-up name (`msg_a_c_1`) is an error, so the two cannot
collide. Two steps may share a label when their types agree and no single role takes both
steps; the message type then has one constructor for both.

Each role module has a type for every state the role can be in, and a function for every
step out of that state:

| Step in the protocol | Function in the role module |
|---|---|
| this role sends `Msg` | `send_Msg(s, state, value)` returns the next state |
| this role receives `Msg` | `recv_Msg(s, state, fn (value, next) -> ...)` |
| this role picks `label` | `choose_label(s, state, value)` returns the next state |
| another role picks | `offer_l1_l2(s, state, on_l1, on_l2)`, one callback per branch |
| the conversation ends | `close(s, state)` |

`register(s, 0)` gives a role its first state. Each role module names that state
`Entry`, so `Fan_C.Entry` is C's first state and you never have to work out which
`S_` name it is.

## Writing a role

A role is a function from its first state to `Yield`. Here is C:

```march
pfn role_c(s : Cap(Session.Live), st : Fan_C.Entry) : Fan_C.Yield do
  Fan_C.recv_Number(s, st, fn (a, st1) ->
    println("C: got " ++ int_to_string(a) ++ " from A")
    Fan_C.recv_Second(s, st1, fn (b, st2) ->
      println("C: got " ++ int_to_string(b) ++ " from B")
      Fan_C.close(s, Fan_C.send_Verdict(s, st2, a + b == 16))))
end
```

`Yield` is the type of a finished role. Only `close` (and, later, `cancelled`) produce one,
so a callback cannot return without either finishing the conversation or handing it on.

The state types are what make this safe. Each one is linear: you must use it exactly once.
`recv_Number` accepts only the state C is in before hearing from A, and it hands the
callback the only value that lets C take the next step. So the compiler rejects a program
that sends before it has received, receives twice, sends a `String` where the protocol says
`Int`, or stops halfway through. The return type `Yield` can only be produced by a generated
step function, so a callback cannot quietly drop the conversation either.

And A:

```march
pfn role_a(s : Cap(Session.Live), st : Fan_A.Entry) : Fan_A.Yield do
  let st1 = Fan_A.send_Number(s, st, 7)
  Fan_A.recv_Verdict(s, st1, fn (ok, st2) ->
    println("A: got " ++ bool_to_string(ok))
    Fan_A.close(s, st2))
end
```

Sends, choices and `close` are ordinary calls that return the next state, so only a receive
nests. A role with several receives reads better as one function per receive than as one
pyramid of closures:

```march
pfn role_c(s : Cap(Session.Live), st : Fan_C.Entry) : Fan_C.Yield do
  Fan_C.recv_Number(s, st, fn (a, st1) -> after_a(s, a, st1))
end

pfn after_a(s : Cap(Session.Live), a : Int, st : Fan_C.S_recv_Second) : Fan_C.Yield do
  Fan_C.recv_Second(s, st, fn (b, st2) ->
    Fan_C.close(s, Fan_C.send_Verdict(s, st2, a + b == 16)))
end
```

If a step is called in the wrong state, the error names both states and says so: the
state types are `S_` followed by the step the role takes next, so `S_recv_Number` is
"about to receive `Number`". `Entry` is the same type as whichever of them a role
starts in, so an error about one may name the `S_` spelling where you wrote `Entry`.

Every callback has to return. The runner calls it when its message arrives, and until it
returns, that node handles nothing else for the session: no other message, no failure, not
even the end of the session. A callback can compute for as long as it needs to. What it must
not do is wait on something that only the session can bring about, such as a reply the peer
sends only after it hears from this role, or a task that is itself waiting on the session.
That would stop the conversation for good. The same holds for cancel handlers. The promise
that a correct protocol cannot deadlock assumes every callback returns.

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

### The entry points

| Function | Transport | Body | Returns |
|---|---|---|---|
| `run_<Role>(io, node_id, secret, addrs, body)` | its own connections, from an address table | callbacks | `Result(Session.Outcome, RunError)` |
| `host_<Role>(io, node_id, secret, addrs, actor, start, deliver)` and `host_<Role>_or(…, cancel)` | its own connections | an actor (see [Hosting a role in an actor](#hosting-a-role-in-an-actor)) | `Result(Session.Outcome, RunError)` |
| `cluster_<Role>(io, node, session, body)` | a running `ClusterNode`, one session under a given id | callbacks | `Result(Session.Outcome, RunError)` |
| `offer_<Role>(io, node, capacity, body)` | a running `ClusterNode`, any number of sessions | callbacks | `Result(Offer, RunError)` |
| `initiate_<Role>(io, node, body)` | a running `ClusterNode`, one session it starts | callbacks | `Result(Session.Outcome, RunError)` |
| `offer_hosted_<Role>(io, node, capacity, actor, start, deliver, cancel)` | a running `ClusterNode`, any number of sessions | one actor for all of them (see [Many sessions in one actor](#many-sessions-in-one-actor)) | `Result(Offer, RunError)` |
| `cluster_hosted_<Role>(io, node, session, actor, start, deliver, cancel)` | a running `ClusterNode`, one session under a given id | an actor, with the same callbacks | `Result(Session.Outcome, RunError)` |

`<P>_Run.error_message(e)` turns any `RunError` into a line that names the roles.

## Per-role grants

A protocol's grant lines (see [Writing a protocol](#writing-a-protocol)) become parameters
of the role's body. For

```march
@[endpoints]
protocol Checkout do
  role Ledger needs IO.FileWrite, IO.NetConnect
  ...
end
```

the body `run_Ledger` and every other front takes is

```march
(Cap(Session.Live), Cap(IO.FileWrite), Cap(IO.NetConnect), Checkout_Ledger.Entry) -> Checkout_Ledger.Yield
```

one capability per path, in the order the line lists them, after the session and before
the entry state. The runner narrows them from the `Cap(IO)` it was given and passes them,
so a body is written as

```march
pfn ledger(s : Cap(Session.Live), fw : Cap(IO.FileWrite), nc : Cap(IO.NetConnect), st : Checkout_Ledger.Entry) : Checkout_Ledger.Yield do
  ...
end

Checkout_Run.run_Ledger(c, "ledger-1", secret, addrs, fn (s, fw, nc, st) -> ledger(s, fw, nc, st))
```

and a body with a different parameter list does not compile against the runner. For a role
hosted in an actor, the grant arrives through `start`: `start(s, fw, nc)`, or
`start(sid, s, fw, nc)` for the many-session fronts. A role with no grant line keeps the
plain `(s, st)` body.

Because the grant is a value, the composition root is explicit from `main` to every role,
and a test can hand a body any dictionary it likes in place of the runner's (the
[Capabilities]({{ site.baseurl }}/docs/capabilities/) page, "Mocking an IO capability in
tests"). It is also checked: what a body reaches must fit under its grant.

### What the grant checks

Two things stop a role from doing more than its line says. The first is the type: a
granted body holds `Cap(IO.FileWrite)`, not `Cap(IO)`, and `Cap(IO.FileWrite)` does not
unify with `Cap(IO)`, so it cannot hand its capability to anything that wants the wider
one. The second is a walk, because a body that never touches its capability value can
still call `file_write` through any helper. At every call of a runner front the compiler
walks everything the callback reaches (helpers, functions passed as values, local closures
it captures, actors it spawns; for a hosted role, `start`, `deliver`, `cancel` and the
actor behind `host`) and requires every capability in that reach to sit under the role's
grant, exactly as `main`'s grant bounds the program:

```
Role `Stream.Cons` is granted `Cap(IO.Console)` (`role Cons needs IO.Console`), but the
body passed to `Stream_Run.run_Cons` reaches `IO.FileWrite` (reached from the body:
body → cons → save). A role's grant bounds everything its code reaches, as `main`'s
grant bounds the program.
help: add `IO.FileWrite` to `role Cons needs ...` in protocol `Stream`, or remove the use.
```

The root of the walk is the *value* that reaches the body parameter, not the expression
at the call. A body bound with `let` in the calling function, a body passed in through a
parameter (resolved at each call site), an alias such as `let sv = save`, a local closure
the body calls, and a body returned by a function (charged that function's reach) are all
walked; the chain names a local closure by its name (`body → sv → save`). When the value
has no static origin, because it was read from a record field or a data structure or
received in a message, the compiler cannot walk it. A closure received as a value is its
creator's authority, so this is reported, not refused:

```
warning: cannot verify role grant for the body passed to `Stream_Run.run_Cons` at
app.march:28: value not statically known (it is read from a data structure, a record
field or a message, not bound in this function). ...
help: pass a lambda or a named function here, or bind the body with `let` in this
function, to have it checked.
```

A role's grant must also fit within `main`'s: the runner narrows the role's capabilities
from what `main` holds, so `role Cons needs IO.FileWrite` under `fn main(c :
Cap(IO.Console))` is an error at the grant line. And a grant names IO capabilities only:
`role Cons needs Session.Live` (or `ClusterNode.Live`, or `LibC`) is one error at the
grant line, because the runner narrows each path from `main`'s `Cap(IO)` and no narrowing
produces a proof or foreign capability. The session capability is passed to every body
already.

The grant bounds the role's *code*, not its *authority*. A body handed a pid to an actor
with wider capabilities can message it, and a closure it receives can do whatever its
creator could; both are delegation, charged to whoever created the reference, and the
walk does not refuse them. So the compiler can also show what a role can reach that way:

```bash
march --dump-role-authority app.march
```

prints, per runner call, the role's grant, what its code reaches, the functions it
references as values, the local closures it captures (with the function that made them
and the line), the pids it holds without having spawned them (`holds: h -> Keeper ->
IO.FileWrite`) and the actors it spawns or hosts, each with the capabilities behind it. It
is a report, not a check; it exists so that a narrow grant is never mistaken for narrow
authority.

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
setup fails instead of waiting for ever: `run_<Role>` returns `Err(Accept(why))`, whose text
names the roles still missing, or `Err(Connect(role, why))`, and closes the connections it already made,
so the roles it did reach fail too instead of waiting on it. Set
`MARCH_SESSION_CONNECT_MS` to change the 20 seconds; 0 waits for ever. If a required variable is missing, the node stops at startup with a
message that names the role, for example
`session_node: role 2 needs an address for role(s) 1`, before it opens any socket.
`addrs_from_env()` itself does not fail on a missing variable: it leaves that role out, and
the runner reports it.

Two nodes that run with different secrets do not connect: the listening side reports
`accept: Handshake: peer failed authentication` and the dialing side
`connect to role A: Handshake: peer failed authentication (do both nodes run with the same
secret?)`, at once rather than after the setup time.

You can also build the list yourself instead of reading the environment. It is a
`List(SessionNode.Addr)`, one `{ role, host, port }` per role.
`SessionNode.parse_addr(role, "host:port")` parses one entry and returns a `Result`.

## Running over a cluster node

If your nodes already run a [`ClusterNode`]({{ site.baseurl }}/docs/clustering/#a-running-node-clusternode),
a role can use it instead of opening connections of its own. The generated
`<P>_Run.cluster_<Role>(io, node, session, body)` takes the running node (the
`Cap(ClusterNode.Live)` that `ClusterNode.start` returned) and a session id, which is any
string the roles agree on, fresh for each session:

```march
match Fan_Run.cluster_C(c, node, "fan-" ++ int_to_string(round), fn (s, st) -> role_c(s, st)) do
  Ok(_) -> println("C: closed")
  Err(SessionNode.Cancelled(role, cause)) -> println("C: cancelled: " ++ cause)
  Err(e) -> println(SessionNode.run_error_message(e))
end
```

- **No addresses.** Each role registers its endpoint under the session's name and finds the
  others by name (waiting up to 30 seconds, a fixed limit), so there are no
  `<P>_<ROLE>_ADDR` variables and no listen/connect rule.
- **Shared connections.** Frames ride the node's one connection pair to each peer node,
  alongside every other session between those nodes. Every frame carries the session id, so
  a frame from another session is refused rather than delivered.
- **The node is the failure detector.** There is no session heartbeat. A peer is gone when it
  closes or is cancelled, or when its node's connection ends: the node declared it dead
  (`node node-b dead: suspect timeout`, `... connection refused`), or the connection was
  lost. The drain rule still holds: the node reports the death only after the last message
  that arrived from that peer.
- Roles may share a node, even two roles of one session: frames between parties on the
  same node go over the node's loopback link (`ClusterNode.queue_for(node, own_id)`),
  in order and without flow control.

## Access points: many sessions, and starting again

`cluster_<Role>` runs one session whose id the nodes agree on beforehand. An **access
point** is the other way round: a node offers a role for any number of sessions, and a
session forms when some other node invites it.

A node that plays a role for others **offers** it:

```march
match Echo_Run.offer_Server(c, node, 64, fn (s, st) -> serve_one(s, st)) do
  Ok(offer) -> ...        -- offering now; each session runs in its own task
  Err(why)  -> panic(why) -- this role of this protocol is already offered on this node
end
```

A node that wants a conversation **initiates** one:

```march
match Echo_Run.initiate_Client(c, node, fn (s, st) -> ask(s, st)) do
  Ok(_) -> println("done")
  Err(SessionNode.NoOffer(role, why)) -> println("nobody would take role " ++ int_to_string(role) ++ ": " ++ why)
  Err(e) -> println(SessionNode.run_error_message(e))
end
```

Every role gets both functions, so a protocol needs no annotation saying which side
starts: the client initiates and the server offers, and a pipeline's first stage can
initiate just as well.

**How a session forms.** The initiator mints a fresh session id (its node, that node's
incarnation, a counter: never reused, so a restarted or partitioned node can never be
addressed by an old session), then invites one offer of each other role, trying an offer on
its own node first. An offer refuses when it is full, when it is closing, or when it was
built from a version of the protocol this one cannot form a session with: each protocol has
a fingerprint, so two nodes built from incompatible versions refuse each other instead of
exchanging messages the other cannot read (see [Changing a protocol](#changing-a-protocol)
for the versions that can mix). On a refusal, or no answer, the initiator tries the next offer, all
within the setup time (`MARCH_SESSION_CONNECT_MS`, 20 seconds). If a role cannot be
filled, `Err(NoOffer(role, why))` says what each offer said, and the offers that had
already accepted are released.

**What the fingerprint covers.** A protocol's fingerprint digests its roles, its steps,
and, since 2026-09-21, what each payload type is MADE OF, not only its name: two nodes
whose `Thing` is `{ x : Int }` on one and `{ x : String }` on the other no longer agree,
so the skew is refused when the session is set up instead of surfacing mid-session as an
undecodable message. A payload type declared in ANOTHER module is out of reach when the
digest is computed and is recorded by name alone, so a change below such a type's name is
still invisible to the check. The direct runner (`run_<Role>`) exchanges the fingerprint
in its handshake too, not only the access points, and a peer built before that change --
which sends no fingerprint -- is refused with a message saying so rather than joining
unchecked. Every fingerprint changed when the digest widened: a node built before the
change and one built after will refuse each other, which is the check working.

**Capacity** is the second argument to `offer_<Role>`: how many sessions it will run at
once. Past that it answers "full" and the initiator looks elsewhere.

**Starting again after a failure.** A failed session is cancelled and discarded (see
[When a role fails](#when-a-role-fails)); nothing resumes it. What the access point adds
is that the next session forms by itself: a supervisor restarts the actor or the program,
it offers again, and the next invitation finds it. No node coordinates the restart with
any other.

`SessionNode.close_offer(offer)` stops offering: new invitations are refused and the name
is released, while sessions already running finish.

The [cluster limits](#running-over-a-cluster-node) still apply: every role on a different
node, and one offer per role and protocol version per node.

## Messages from different peers

Each connection delivers its messages in order, but two connections are not ordered against
each other. In `Fan`, C expects A's number first. If B is faster, B's message arrives first.
The runner holds it until C has received from A and asked for B. You do not need to write
anything for this; the generated code tells the runner which role each receive is waiting
for.

## Large messages and slow peers

A message can be any size, and a role can send as many messages in a row as it likes without
waiting for the receiver. Whatever the receiving node has not taken yet waits on the sending
node and goes out as the receiver catches up. Nothing is dropped while the peer keeps
reading. A peer that stops reading altogether is caught by the heartbeat (see [When a role
fails](#when-a-role-fails)), or, over a cluster node, once `MARCH_SESSION_QUEUE_MAX_BYTES`
(64 MiB) is queued for it unread; either way it is treated as gone and whatever was waiting
for it is thrown away.

## How a session ends

`run_<Role>` returns one of these:

| Result | Meaning |
|---|---|
| `Ok(Session.Finished)` | This role reached the end of the protocol. |
| `Ok(Session.Drained(n))` | The session was ended at a loop boundary because a node it runs on is draining (see [Draining a session](#draining-a-session)). `n` is how many of this role's own messages came back undelivered. A clean end, like `Finished`. |
| `Err(Cancelled(role, cause))` | This role was waiting on `role`, that role failed, and nothing it had sent was still waiting to be read. `cause` says what went wrong: `"connection lost"`, `"no heartbeat"`, or a chain such as `"role 3: connection lost"` when the failure reached this role through another one. |
| `Err(Protocol(role, why))` | That role sent something this role cannot accept: a message that does not decode, or one the protocol does not allow at this point. |
| `Err(HostGone(ep))` | Only for a role hosted in an actor (below): the actor died. |
| `Err(Left(why))` | This role left the session on purpose (below). |
| `Err(Listen(port, why))`, `Err(Accept(why))`, `Err(Connect(role, why))` | Startup failed: the port was taken, a handshake was refused, a peer never came up. |

`SessionNode.run_error_message(e)` turns any of these into a readable line. The `Ok` value
is a `Session.Outcome` (`Finished | Drained(Int)`); code that matches `Ok(_)` needs no change.

## Draining a session

A node that is being upgraded or shut down *drains*: its old code has to stop running, but a
session in the middle of an exchange cannot just be cut. A session drains at a **loop
boundary**: the point where one iteration of a `loop` in the protocol has finished and the
next has not begun. Every `loop` is a drain point unless it is written `loop atomic`.

What happens, for any number of roles:

1. **The role that would receive the first message of the next iteration does not take it.**
   When that message arrives and the receiving role's node is draining, or the sender's node
   was draining when it sent it, the message goes back to its sender, marked undelivered.
   The receiving role *drains*: it ends there.
2. **A drained role returns everything sent to it that it has not taken**, whenever it
   arrives, so no message is silently lost.
3. **The other roles are told.** A message sent to a drained role comes straight back to its
   sender.
4. **A role waiting for a message from a drained role drains too**, at that receive. So a
   role in the middle of an iteration finishes the iteration's work up to its next receive
   from a drained role, and ends there.

`run_<Role>` then returns `Ok(Session.Drained(n))` on every role, where `n` counts the
role's own messages that came back. Between them, the roles' `n`s add up to exactly the
messages that were in flight. A role whose messages came back but that finished the
protocol anyway (it never had to receive from the drained role again) also returns
`Drained(n)`.

A drained role does not run any more of its session code. Every receive has a third form,
ending in `_or_drain`, that takes a **drain handler**:

```march
Stream_Prod.offer_more_done_or_drain(s, st1,
  fn (_b, st2) -> prod(s, st2, next + 1),
  fn (_b, st2) -> Stream_Prod.close(s, st2),
  fn (role, undelivered, d) ->
    requeue(undelivered)          -- the messages that came back, decoded
    Stream_Prod.drained(s, d))
```

Like a cancel handler it gets no session state: the drained role it was waiting on (0 when
this role drained at its own loop boundary), the messages this role sent that came back,
and a token whose only use is `<Role>.drained(s, token)`. A receive without `_or_drain`
simply ends. A role hosted in an actor hears of a drain through its cancel callback, with
the cause `"drained"`.

**Why a loop boundary, and not a `choose`.** The runner only has control when it delivers a
message, so a receive is the one place it can end a session without handing your code a
state it did not expect. A `choose_*` returns the next state and your code carries on with
it; ending the session there would mean returning a state the types cannot express.

**`loop atomic do ... end`** is a loop whose iterations must not be split from each other:
its head is not a drain point, so its sessions run until they end on their own, or until the
drain's hard deadline stops them (`Err(Left("draining"))`). It changes no message, so it
does not change the protocol's fingerprint.

`SessionNode.drain_epochs(io, soft_ms, hard_ms)` drains every session on the node (and every
actor still on old code; see [hot reload]({{ site.baseurl }}/docs/hot-code-reload/)).
`Topology.drain_on_signal` calls it on SIGTERM, and a hot deploy's `DRAIN` does the same for
the epochs it retires.

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
change the two numbers. The heartbeat runs from the moment two nodes connect, so a role can
work for as long as it likes before its first send or receive. The heartbeat can mistake a
very slow peer for a dead one. That
cancels a session that could have finished, which costs a retry but never corrupts
anything.

### Handling a failure

Every receive has a second form, ending in `_or`, that takes a cancel handler. Offers have
the same (`offer_more_done_or`):

```march
Fan_C.recv_Second_or(s, st1,
  fn (b, st2) ->
    Fan_C.close(s, Fan_C.send_Verdict(s, st2, b > 0)),
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
`Fan_C.leave_recv_Number(s, st, "shutting down")` for C before it has heard from A. The
other roles are told, and `run` returns `Err(Left(why))`.

The names, in one place:

| | |
|---|---|
| `recv_<Msg>_or(s, st, on_msg, on_cancel)` | a receive with a cancel handler; `offer_<labels>_or` likewise |
| `on_cancel : (Int, String, Cancelled_<Role>) -> Yield` | the failed role's number, the cause, and the token |
| `<Role>.cancelled(s, token)` | the only way a cancel handler can finish |
| `leave_<state>(s, st, why)` | leave on purpose from that state (`leave_recv_Number` from `S_recv_Number`) |
| `recv_<Msg>_or_drain(s, st, on_msg, on_drain)` | a receive with a drain handler; `offer_<labels>_or_drain` likewise ([Draining a session](#draining-a-session)) |
| `on_drain : (Int, List(<P>_Msg.<P>_Message), Drained_<Role>) -> Yield` | the drained role (0: this one), the messages that came back, and the token |
| `<Role>.drained(s, token)` | the only way a drain handler can finish |

### Starting again

A session cannot be resumed. To try again, call `run_<Role>` again on every node, which
starts a new session with new connections. Deciding when to do that, and making sure every
node does, is up to whatever runs the nodes, for example a supervisor around
`run_<Role>`. The runner does not restart anything by itself.

## When a role may crash

The rules above cancel a session when a role it needs has failed. Sometimes that is more
than you want: a protocol may need to carry on without the failed role, if only to tell the
others that it is gone. For that, a protocol can name the roles that may crash, and say at
each receive from such a role what happens if it crashes instead of sending.

```march
@[endpoints]
protocol Logging do
  may crash C
  L -> I : Int
  C -> I : String
    or crash do
      I -> L : String
    end
  I -> L : String
  L -> I : Bool
  I -> C : Bool
end
```

`may crash C` says that C may crash. Every other role is reliable, as every role is without
the declaration, so a protocol that does not say `may crash` means exactly what it meant
before. The `or crash do ... end` after `C -> I : String` is the crash branch: what happens
if C crashes before sending. I is the role that detects the crash, because it is the one
waiting for the message. The crash branch is the rest of the conversation in that case; it
does not rejoin the normal continuation, which usually involves the crashed role. Inside a
`loop`, a crash branch ends the loop. In a `choose by C` where C may crash, a branch labelled
`crash` is the crash branch: `choose by C: read -> ... done -> ... crash -> ... end`.

The compiler checks the protocol:

- every receive from a role that may crash has a crash branch;
- a crash branch is only on a step whose sender may crash;
- the crashed role takes no part in its own crash branch;
- any other role that takes part in the normal continuation or the crash branch is told
  which one it is in: its first interaction in each must be a message from the detector,
  and the two messages must differ. In `Logging`, L hears from I either way, a `Read` or a
  `Fatal`. Without that, L could not know whether to wait for anything;
- in a `choose` with a `crash` branch, every other branch begins with a message to the same
  role, the detector.

The runtime takes the crash branch by the same rule that decides a cancellation: the crashed
role is gone, and nothing it sent is still waiting to be read. Messages sent before the crash
are still delivered, so a role that crashes after its last send is no different from one that
finished. The other roles learn of the crash only from the messages in the crash branch,
just as they learn which branch of a `choose` was taken. Messages sent to the crashed role
are dropped. A reliable role that fails anyway is cancelled, as above.

For the detector, a receive with a crash branch takes a second callback in place of the
`_or` form's cancel handler:

```march
Logging_I.recv_Msg_C_I_1(s, st1,
  fn (read, st2) -> ...,             -- the message arrived
  fn (crashed, st2) -> ...)          -- C crashed: st2 is the crash branch's first state
```

Unlike a cancel handler, the second callback gets a live state, and the conversation goes
on. `crashed` is a `Crashed_I` record with the crashed role's number (`crashed.role`) and
the cause (`crashed.cause`), the same information a cancel handler gets. A receive with a
crash branch has no `_or` form: the sender may crash, and that is what the second callback
is for. The two messages I can send L are named in reading order, `Msg_I_L_1` for the
`Fatal` in the crash branch and `Msg_I_L_2` for the `Read` after it, and L, which can be
sent either, gets an offer over the two, `offer_Msg_I_L_2_Msg_I_L_1`, with one callback per
message, exactly as for a `choose`. C's module has no trace of the crash branch. In
`test/two_node/crash_before_send` and `crash_after_send` this protocol runs over three
processes, with C killed before and after its send: in the first, I takes the crash branch
and L gets the `Fatal`; in the second, the `Read` is delivered and the conversation completes
without C. In both, every surviving role returns `Ok`.

A role [hosted in an actor](#hosting-a-role-in-an-actor) takes its crash branch too, through
the event API. The `await_` function of a receive with a crash branch tells the transport
there is a branch to take, and `resume` then returns a `Crashed_` event beside the `Got_`
ones, carrying the same `Crashed_<Role>` record and the crash branch's first state:

```march
match Logging_I.resume(state.parked, from, msg, ep) do
  Got_Msg_C_I_1(read, st) ->
    { state with parked: Logging_I.await_Msg_L_I_2(s, Logging_I.send_Msg_I_L_2(s, st, read)) }
  Crashed_Msg_C_I_1(crashed, st) ->
    { state with parked: Logging_I.finish(s, Logging_I.send_Msg_I_L_1(s, st, crashed.cause)) }
  ...
end
```

The crash reaches the actor through the delivery callback it already has, so nothing in the
runner changes: `host_<Role>`, `offer_hosted_<Role>` and `cluster_hosted_<Role>` all take
crash branches. The event is named after the receive, so for a `choose` with a `crash`
branch it is `Crashed_read_done_crash`, as the `await_` function is.
`test/two_node/crash_hosted` is `crash_before_send` with I in an actor, and it ends the same
way. The two-party `Chan` API does not run a protocol with crash branches at all: the
compiler refuses to give one a channel type.

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
    { state with parked: Stream_Cons.await_Item(s, Stream_Cons.register(s, 0)) }
  end
  on DeliverC(s : Cap(Session.Live), from : Int, msg : Bytes, ep : Int) do
    match Stream_Cons.resume(state.parked, from, msg, ep) do
      Got_Item(n, st) ->
        if state.budget > 1 do
          let st2 = Stream_Cons.choose_more(s, st, true)
          { state with budget: state.budget - 1,
                       parked: Stream_Cons.await_Item(s, st2) }
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

Call `host_<Role>` from `main` or a task, as above, and never from one of the actor's own
handlers. It returns only when the session is over, and every delivery for the role goes to
the actor's mailbox, where it would wait behind the handler that is still inside
`host_<Role>`. The session would never move.

The runner watches the actor. If it crashes, or is killed, or its supervisor restarts it,
its role is cancelled: `host_<Role>` returns `Err(HostGone(ep))`, and the other roles are
cancelled or carry on by the rules in [When a role fails](#when-a-role-fails). A restarted
actor starts idle and cannot pick up the old conversation; start a new session instead.

For the actor to hear that its role was cancelled, use `host_<Role>_or`, which takes a
fourth function after `deliver`. It is called with the session, the failed role, the cause
and the endpoint. Send those to the actor; its handler stores
`Stream_Cons.cancel(s, state.parked)`, which gives back a closed value, and can update the rest
of its state. Like a cancel handler, it cannot send in the failed session. This is the cost of keeping the session in the actor's state. The
callback style does not have it, because there the session state lives in the runner.

Different nodes can make different choices. In `test/two_node/hosted`, Prod is a plain body
on one node and Cons is an actor on the other.

### Many sessions in one actor

An [access point](#access-points-many-sessions-and-starting-again) hosted in an actor
serves every session it accepts from that one actor, so the actor keeps one parked
endpoint per session. `Parked_<Role>` is linear and a `Map` cannot hold a linear value,
so the sessions live in a `LinearMap` keyed by the session id, and every callback carries
the session id: `start(sid, s)`, `deliver(sid, s, from, msg, ep)` and
`cancel(sid, s, role, cause, ep)`. Here is a server for a protocol `Echo` in which the
client sends twice and the server answers each time:

```march
actor ServerActor do
  state { done : Int, sessions : LinearMap(String, Echo_Server.Parked_Server) }
  init  { done: 0, sessions: LinearMap.empty_string() }
  on Start(sid : String, s : Cap(Session.Live)) do
    let parked = Echo_Server.await_Msg_Client_Server_1(s, Echo_Server.register(s, 0))
    match LinearMap.put(state.sessions, sid, parked) do
      (None, m) -> { state with sessions: m }
      (Some(old), m) ->
        Echo_Server.take_closed(Echo_Server.cancel(s, old))
        panic("session " ++ sid ++ " is already hosted")
    end
  end
  on Deliver(sid : String, s : Cap(Session.Live), from : Int, msg : Bytes, ep : Int) do
    match LinearMap.take_slot(state.sessions, sid) do
      (None, slot) -> { state with sessions: LinearMap.vacate(slot) }
      (Some(parked), slot) ->
        match Echo_Server.resume(parked, from, msg, ep) do
          Got_Msg_Client_Server_1(n, st) ->
            let st2 = Echo_Server.send_Msg_Server_Client_1(s, st, n * 10)
            { state with sessions: LinearMap.fill(slot, Echo_Server.await_Msg_Client_Server_2(s, st2)) }
          Got_Msg_Client_Server_2(n, st) ->
            Echo_Server.take_closed(Echo_Server.finish(s, Echo_Server.send_Msg_Server_Client_2(s, st, n * 10)))
            { state with done: state.done + 1, sessions: LinearMap.vacate(slot) }
        end
    end
  end
  on Cancel(sid : String, s : Cap(Session.Live), _role : Int, _cause : String, _ep : Int) do
    match LinearMap.take(state.sessions, sid) do
      (None, m) -> { state with sessions: m }
      (Some(parked), m) ->
        Echo_Server.take_closed(Echo_Server.cancel(s, parked))
        { state with sessions: m }
    end
  end
end
```

Each handler takes the session's parked value out of the map by its id, resumes it,
and puts the next parked value back with `fill`, or `vacate`s the slot once the
session is over. A delivery for an id that is no longer in the map (a session that was
cancelled while it had a message in flight) is dropped. The `Cancel` handler is the
`host_<Role>_or` cancel function with the id in front, and runs for that one session.
Any other state the actor keeps per session, such as a counter, goes in an ordinary
`Map` keyed by the same id.

A finished or cancelled session leaves a `Closed_Server` value, which nothing can
resume. `Echo_Server.take_closed(p)` is what consumes one: it takes the closed value and
returns `()`. It panics on an endpoint that has not finished, so it cannot be used to drop
a session that is still live.

To offer the role, spawn the actor and pass it with the three callbacks:

```march
let srv = spawn(ServerActor)
let start = fn (sid, s) ->
  let _ = send(srv, Start(sid, s))
  ()
let deliver = fn (sid, s, from, msg, ep) ->
  let _ = send(srv, Deliver(sid, s, from, msg, ep))
  ()
let cancel = fn (sid, s, role, cause, ep) ->
  let _ = send(srv, Cancel(sid, s, role, cause, ep))
  ()
match Echo_Run.offer_hosted_Server(c, node, 64, srv, start, deliver, cancel) do
  Ok(offer) -> ...        -- offering now; every session goes to srv
  Err(e) -> panic(Echo_Run.error_message(e))
end
```

The runner watches the actor once per session (one small watcher actor each). If the
actor crashes or is restarted, every session it hosts ends with `HostGone`, as for
`host_<Role>`. `cluster_hosted_<Role>(io, node, session, actor, start, deliver, cancel)`
is the same for one session under an id the nodes agreed on, with the same callbacks,
so one actor can serve both.

`test/two_node/cluster_ap_hosted` runs three sessions at once through one actor, then a
fourth; `test/two_node/cluster_ap_hosted_cancel` kills one of three clients half way
through its session, and only that session is cancelled.

## Testing without a network

The generated role modules do not know about sockets. They talk to whatever transport the
session was created with. For unit tests, attach the standard library's in-process transport
and run every role in one program:

```march
let t = Session.in_process()
let s = Session.attach(io, t.ops)
let _ = cons(s, Stream_Cons.register(s, 0), 2)
let _ = prod(s, Stream_Prod.register(s, 0), 1)
t.drain(())
```

Failure paths are testable in-process too. A role that leaves or is cancelled cancels the
peers waiting on it, a message the receiver cannot decode cancels the receiver, and
`t.crash(role, cause)` makes a role crash without running it, so a peer's `or crash`
branch runs. `Session.in_process_with(print_line)` prints what the transport itself does.
The [Session Types]({{ site.baseurl }}/docs/session-types/#swapping-the-transport-session)
page has the details, and `test/session/in_process.march` in the compiler repository runs
each case. The same role functions then run unchanged on the network.

### Scripted and chaos peers

You do not have to write the other side of a conversation to test one role. Every role
module carries two bodies of the role's own type, derived from its projection, so the
protocol is its own test oracle:

- `Stream_Cons.script(s, st, steps)` runs a list of `Stream_Cons.Step`: `Send_<Msg>(v)`
  and `Choose_<label>(v)` send, `Expect_<Msg>(fn v -> ...)` receives and hands the payload
  to the callback, and `Expect_crash_<Msg>(fn c -> ...)` takes a crash branch. Each step is
  checked against the state the role is in when it runs. A step the state cannot take, a
  message the peer sent that the script did not expect, a script that runs out before the
  protocol ends or that has steps left after it: each panics, naming the state, what was
  expected and what came. That fails the test, not the session.
- `Stream_Cons.chaos(s, st, seed)` walks the projection by a seeded generator: every
  choice is taken by the seed, every payload is generated, and at every point the role
  `may crash` (a send with an `or crash` branch, a `choose` with a `crash` branch) the
  seed decides, one time in four, to leave the session instead. Run the real role against
  `chaos` peers for fifty seeds and you have a property test of its protocol handling,
  crash branches included. Payloads of built-in types are generated for you; for each of
  your own types a role sends, `chaos` takes one more argument, a `Gen.Generator` for it,
  in order of first appearance and named after the type (`gen_Thing`).

```march
let t = Session.in_process()
let s = Session.attach(io, t.ops)
let _ = Stream_Cons.script(s, Stream_Cons.register(s, 0), [
  Stream_Cons.Expect_Msg_Prod_Cons_1(fn n -> assert(n == 1)),
  Stream_Cons.Choose_done(true)
])
let _ = prod(s, Stream_Prod.register(s, 0), 1)
t.drain(())

let t2 = Session.in_process()
let s2 = Session.attach(io, t2.ops)
let _ = cons(s2, Stream_Cons.register(s2, 0), 2)
let _ = Stream_Prod.chaos(s2, Stream_Prod.register(s2, 0), seed)
t2.drain(())
```

A granted role's peers take its capabilities too, after the session:
`Checkout_Ledger.script(s, fw, nc, st, steps)`. Both peers are ordinary bodies, so they
also run over the network; a chaos "crash" is a `leave` there, which cancels the peers,
while the in-process transport treats a role that has left as gone, so a peer waiting on
it takes its crash branch. `test/session/stream_peers.march` in the compiler repository
runs the real Stream, Fan and Logging roles against both kinds of peer.

## Changing a protocol

A protocol is a contract between binaries that are deployed separately, so changing one
is a deploy question, not only a source edit. There are three kinds of change.

1. **Same fingerprint.** Nothing any peer can see changed: a handler body, a role's
   `needs` line (grants are about the role's code, not the wire, and are left out of the
   fingerprint on purpose). Deploy in any order.
2. **Compatible.** A session may mix the two versions. One change qualifies so far:
   **a `choose` gains a branch**, and nothing else changes.
3. **Breaking.** Anything else: a new message, a changed payload type, a removed branch,
   a renamed label, a new role. Old and new binaries refuse each other when a session
   forms, so both versions have to be offered while the deploy rolls through.

**Compatibility is about the wire.** Every message crosses the network as JSON tagged
with its constructor name. A labelled step (`item: Buyer -> Shop : Int`) is named after
its label, and a `choose` branch's first message after the branch label. An unlabelled
step is named by its position among the messages between the same two roles,
`Msg_<From>_<To>_<k>`. A new branch that contains an unlabelled `A -> C` message
therefore renumbers every later `A -> C` message, and an old peer can no longer decode
them. The compiler compares the two versions' tags, not only their shapes: that change
is breaking, and the explanation names the tags that moved (`Msg_A_C_1 is now
Msg_A_C_2`). Label the steps and it becomes compatible.

**Label the steps of any protocol a topology app uses.** When `topology.toml` names a
protocol (in `[roles]`, or in a pool's `initiates`), each unlabelled step is a warning at
the step, in the compiler's output and in the editor, with a suggested label. A branch's
first message needs no label of its own: the branch label names it.

**Rollout order: receivers of a choice before its chooser.** An old chooser never picks
the new branch, so a new receiver is safe beside it. A new chooser may pick the new
branch towards a receiver that cannot handle it. So the compatible change is safe only in
one direction: upgrade every role that receives the choice first, then the role that
makes it. This has nothing to do with which role initiates the session. In a replicated
monolith, where one binary holds both the chooser and the receivers, that order cannot
happen inside one deploy, and the change has to go out as two.

**The compatibility table.** Every `@[endpoints]` protocol's `<P>_Msg` module has
`compat() : List((String, String, List(String)))`: one row `(fingerprint, role,
accepts)` for each role that may form a session with peers on another fingerprint. It is
computed at compile time against the previous version of the protocol, which the compiler
reads from `--protocol-baseline <file>`. `forge build` keeps that file for you, in
`.forge/protocols/<P>.json`, rewriting it on every build (`--emit-protocols`). Only the
receivers of a compatible change get a row, naming the previous fingerprint. The chooser,
and every role after a breaking change or a change with no wire effect, has no row:
same fingerprint only.

```march
-- v2 added `later` to `choose by Shop`; Buyer receives the choice
Order_Msg.compat()
-- [("8e44…", "Buyer", ["d248…"])]
```

**One version back.** The baseline file keeps the version last built and the one before
it, and the table reaches exactly one version back. A peer two versions behind is
"protocol differs". That is enough for a rollout, which moves one version at a time, and
for the monolith's two-deploy split.

**How a session forms across versions.** An access point's registry name carries its
fingerprint (`ap:<P>/<role>/<fp>/<node>`), so a node can offer two versions of one role side
by side, and an initiator can tell an offer's version before inviting it. The initiator
invites, in this order, offers at its own fingerprint, then older ones its table accepts,
then ones it does not know (a newer version decides for itself). It never invites an offer
its own table rules out, and it lets a session hold at most two fingerprints. An offer
accepts an initiator at its own fingerprint, at an older one its table accepts, or at a
newer one that has checked the pair against its own table and says so in the invitation.
A new chooser and an old receiver never meet: the chooser's table has no row for the
receiver's older version.

**Hosted access points across a change.** An actor hosting sessions holds each session's
epoch, so it cannot move to a new protocol version while it hosts old sessions (plan 6.1).
`Topology.reoffer(node)` opens each open offer again with the code now running: a role whose
fingerprint changed gets a new offer and, for an actor role, a fresh hosting actor. The old
offer closes, its sessions finish on the old version, and its actor is stopped once they
have. The placement loop runs this after a deploy, but see the limits below: today it
reopens with the code the role's `open` function was built from.

**A monolith needs two deploys (D21).** When one binary both makes and receives a changed
choice, no rollout order exists inside one deploy. Build the first deploy with
`--protocol-expand <P>:<label>`: the receivers take the new version, while the chooser
keeps offering and initiating under the previous fingerprint, and its `choose_<label>`
panics. Then deploy the plain build. `forge`'s `Protocol_split.plan` works out which
case applies from `.forge/protocols/` and the topology's pools.

## Configuration

| Variable | Default | Meaning |
|---|---|---|
| `<PROTOCOL>_<ROLE>_ADDR` | unset | `host:port` of a role that listens, for `addrs_from_env()` |
| `MARCH_SESSION_CONNECT_MS` | 20000 | how long setup waits to dial, accept and handshake; 0 waits for ever |
| `MARCH_SESSION_HEARTBEAT_MS` | 1000 | the heartbeat interval; 0 turns the heartbeat off |
| `MARCH_SESSION_TIMEOUT_MS` | 10000 | silence after which a peer is taken for dead |
| `MARCH_SESSION_QUEUE_MAX_BYTES` | 67108864 | bytes queued unread for one peer before it is given up on; 0 for no limit |

These apply to the runner's own connections. Over a cluster node, failure detection is the
node's (SWIM) and the heartbeat settings do not apply.

## Limits

- The network runner is compiled-only for now.
- A session cannot be resumed after a failure, and nothing restarts it for you.
- Every role that exchanges messages with another needs a direct connection to it. There is
  no relaying.
- Over a cluster node (`cluster_<Role>`), a
  connection lost for any reason cancels the sessions using it, even if the peer node
  reconnects at once. Frames in flight on the old connection may be gone, so the session
  cannot safely continue.
- Messages are encoded as JSON, so every payload type needs a JSON codec. Built-in types
  have one; for your own types, add `derive Json for YourType`.
- After a hot deploy, `Topology.reoffer` calls each role's `open` function, which the old
  code built, and that runs the old code: the role is reopened under the old fingerprint
  (a no-op). It reopens under the new one only when new code builds the role, until calls
  from entry-module code and its closures go through the reload dispatch table (today a
  call is dispatched only when both caller and callee are reloadable). A hosting actor
  whose handler the
  deploy replaces can re-offer from there.
- A hot patch currently carries its own copy of the runtime, so a session started by
  patched code can crash the process; the two-node test of a hot protocol change is
  pending on that fix (`specs/todos/2026-09-25-hcr-patch-so-private-runtime-copy.md`).

## See also

- [Session Types]({{ site.baseurl }}/docs/session-types/): the type rules behind the
  generated states, and the two-party `Chan` API.
- [Clustering]({{ site.baseurl }}/docs/clustering/): node identity, the handshake, and
  `SessionNode`, the transport the runner uses.
- [Actors]({{ site.baseurl }}/docs/actors/): supervisors, which you would use to decide when
  to run a failed session again.
