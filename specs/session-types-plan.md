# Binary Session Types — Implementation Plan

> Status: **Design / Pre-implementation**
> Compiler pass order position: Step 4 — after type checking, before strip-provenance
> Design background: `specs/design.md §Session Types (Binary, v1)`

---

## 1. What Are Session Types?

Session types are a discipline for typed communication channels. Instead of sending arbitrary messages, two endpoints of a channel obey a *protocol* — a script of sends, receives, and branches — and the type system verifies at compile time that both sides follow it.

**What they guarantee:**
- **No deadlocks** — if both sides try to receive simultaneously, the protocol is ill-formed at the *type* level, caught before the program runs.
- **No protocol violations** — sending a `String` when the protocol expects an `Int` is a type error.
- **Exhaustive case coverage** — when one side offers a choice, the other side must handle *every* branch; the usual pattern-match exhaustiveness machinery enforces this.

**The key idea — duality:** every protocol has two complementary views, one per endpoint. What one side *sends*, the other *receives*. What one side *chooses*, the other *offers*. The compiler derives both views from a single declaration and checks each participant against their view.

**Scope for v1:** Binary (two-party) sessions only. Multi-party global choreography is deferred post-v1 (see `progress.md`).

---

## 2. March's Session Type Syntax

### 2.1 Protocol declarations

The existing `protocol` keyword introduces a global session type visible to both participants. The current AST supports `ProtoMsg`, `ProtoLoop`, and `ProtoChoice`. This plan extends that with a dual representation and channel creation syntax.

```march
-- Global two-party protocol declaration.
-- Names (Client, Server) are *role* names, not actor types.
-- The same protocol can be instantiated between any two actors.
protocol FileTransfer do
  Client -> Server : Open(String)
  Server -> Client : Ready | Err(String)
  loop do
    Client -> Server : Chunk(Bytes) | Done
  end
end
```

For branching (choice/offer), the existing `|` syntax inside a step is extended:

```march
protocol Auth do
  Client -> Server : Credentials(String, String)
  Server -> Client : Accepted(Token) | Denied(String)
  -- After branching, each branch can have its own continuation:
  choose do
    | Accepted(tok) ->
        Client -> Server : Request(String)
        Server -> Client : Response(String)
        Client -> Server : Close()
    | Denied(_) ->
        -- protocol ends here
  end
end
```

The `choose` block is the multi-step branching construct. The first step inside each arm originates from the chooser side; the *offer* side sees these as alternatives it must handle.

### 2.2 Local session types (per-endpoint view)

These are the types that appear on channel variables in user code. They are computed by *projecting* the global protocol onto a single role.

| Constructor | Meaning |
|---|---|
| `Send(T, S)` | Send a value of type `T`, then follow session `S` |
| `Recv(T, S)` | Receive a value of type `T`, then follow session `S` |
| `Choose { lbl1: S1, lbl2: S2 }` | Actively select a branch label; one of S1, S2 must be followed |
| `Offer { lbl1: S1, lbl2: S2 }` | Passively wait for the other side to pick; match on the label |
| `End` | Session is complete; channel must be closed |
| `Rec(X, S)` | Recursive session binding (for `loop` blocks) |
| `Var(X)` | Back-reference to a recursive binding |

**Example — FileTransfer projected onto Client:**
```
Send(String,                    -- Open(String)
Offer {
  Ready: Send(Bytes | Done,     -- Chunk or Done, repeating
         ...),
  Err:   Recv(String, End)
})
```

### 2.3 Channel variables and types

A channel endpoint is a *linear* value — it must be used exactly once per step. After each operation the type state advances.

```march
-- Channel.new creates a linked pair of endpoints.
-- Both endpoints are linear; they must be distributed to the two participants.
let (client_ch, server_ch) = Chan.new(FileTransfer)

-- client_ch : linear Chan(Client, FileTransfer)
-- server_ch : linear Chan(Server, FileTransfer)
```

The type `Chan(Role, Protocol)` carries the role name and protocol name. The typechecker looks up the protocol and projects it onto the role to obtain the local session type.

After projection, the type that the typechecker tracks internally is the local session type (a tree of `Send`/`Recv`/`Choose`/`Offer`/`End`/`Rec`/`Var` nodes). The surface-level `Chan(Client, FileTransfer)` is sugar.

### 2.4 Send and receive operations

```march
-- Session-typed send: advances the session state from Send(T, S) to S.
let ch2 = Chan.send(ch, value)
-- ch is consumed (linear); ch2 is the new endpoint at continuation state S.

-- Session-typed receive: advances the session state from Recv(T, S) to (value, S).
let (value, ch2) = Chan.recv(ch)

-- Choose (active selection): advances from Choose{ok: S1, err: S2} to S1.
let ch2 = Chan.choose(ch, :ok)

-- Offer (passive selection): match on what the other side chose.
let ch2 = Chan.offer(ch) do
  | :ok  -> fn ch -> ...   -- ch : Chan at continuation S1
  | :err -> fn ch -> ...   -- ch : Chan at continuation S2
end

-- Close: consumes an End-typed channel.
Chan.close(ch)
```

The key invariant: **each channel operation consumes the input endpoint and produces a new one** (or consumes it for `close`). This is enforced by the linear type system already in place — the typechecker's `bind_linear` / `record_use` machinery prevents using a channel endpoint twice.

### 2.5 Session initiation between actors

Two actors establish a session by one spawning/creating the channel and distributing the endpoints via their existing actor mailboxes:

```march
-- Actor A creates the channel and sends the server endpoint to B.
let (client_ch, server_ch) = Chan.new(FileTransfer)
send(b_cap, StartSession(server_ch))
-- A holds client_ch and proceeds with the client-side protocol.
Chan.send(client_ch, Open("report.csv"))
...
```

The message type of `StartSession` carries a `linear Chan(Server, FileTransfer)` field, so the actor message type system enforces that the endpoint is transferred (not copied).

---

## 3. Type System Integration

### 3.1 Session type as a first-class type

Add `TChan` to the internal type representation:

```ocaml
(* In typecheck.ml, extend the `ty` type: *)
| TChan of session_ty ref  (* mutable ref so the session state can be advanced *)

(* The local session type — computed by projection: *)
and session_ty =
  | SSend   of ty * session_ty      (* Send(T, S) *)
  | SRecv   of ty * session_ty      (* Recv(T, S) *)
  | SChoose of (string * session_ty) list  (* Choose { lbl: S } *)
  | SOffer  of (string * session_ty) list  (* Offer { lbl: S } *)
  | SEnd                             (* End — channel must be closed *)
  | SRec    of string * session_ty   (* Rec(X, S) — recursive binding *)
  | SVar    of string                (* Var(X) — back-reference *)
  | SError                           (* Error sentinel, like TError *)
```

The surface `Chan(Role, Protocol)` annotation is resolved during type checking by looking up the protocol in `env.protocols`, projecting it onto Role, and returning a `TChan` with the resulting `session_ty`.

### 3.2 Linearity of channel endpoints

Channels are always `Linear`. The `TChan` constructor implicitly carries `Linear` linearity — no explicit `linear Chan(...)` annotation needed from the user (though it is accepted). The typechecker's `bind_linear` will reject:
- Using a channel endpoint more than once (double-send, double-recv).
- Dropping a channel endpoint without closing it (un-consumed `linear` binding).

The existing `check_linear_all_consumed` machinery, called at the end of each function scope, enforces that every channel bound in that scope was either closed or passed to another function.

### 3.3 Session state advancement

Each channel operation has a *pre-condition* on the current session type and produces a channel with the *continuation* session type. The typechecker enforces this by:

1. When `Chan.send(ch, v)` is seen:
   - Unify `type_of(ch)` with `TChan(ref (SSend(T, S)))`.
   - Unify `type_of(v)` with `T`.
   - Consume `ch` (linear use).
   - Return `TChan(ref S)` — the continuation channel.

2. When `Chan.recv(ch)` is seen:
   - Unify `type_of(ch)` with `TChan(ref (SRecv(T, S)))`.
   - Consume `ch`.
   - Return `TTuple [T; TChan(ref S)]`.

3. When `Chan.choose(ch, lbl)`:
   - Unify with `TChan(ref (SChoose branches))`.
   - Look up `lbl` in branches; return `TChan(ref S_lbl)`.

4. When `Chan.offer(ch) do | lbl -> fn ch -> body end`:
   - Unify with `TChan(ref (SOffer branches))`.
   - Each arm receives `TChan(ref S_lbl)`.
   - All arm bodies must produce the same result type.

5. When `Chan.close(ch)`:
   - Unify with `TChan(ref SEnd)`.
   - Consume `ch` — nothing returned.

### 3.4 Duality computation

Duality is the function that maps a protocol's projection onto role A to the projection onto role B, asserting they are complementary. The typechecker verifies:
- `dual(SSend(T, S)) = SRecv(T, dual(S))`
- `dual(SRecv(T, S)) = SSend(T, dual(S))`
- `dual(SChoose branches) = SOffer (map dual branches)`
- `dual(SOffer branches) = SChoose (map dual branches)`
- `dual(SEnd) = SEnd`
- `dual(SRec(x, S)) = SRec(x, dual(S))`

Duality is computed at protocol *declaration* time (not use time), so errors are localized to the `protocol` block. After `Chan.new(Proto)` produces `(Chan(A, Proto), Chan(B, Proto))`, the typechecker just checks each use site against its respective local type.

### 3.5 Projection algorithm

Given a global protocol (list of `protocol_step`) and a role name, produce the local session type:

```
project([], _role) = SEnd

project(ProtoMsg(sender, receiver, T) :: rest, role)
  | sender = role   = SSend(T, project(rest, role))
  | receiver = role = SRecv(T, project(rest, role))
  | otherwise       = project(rest, role)    -- step doesn't involve this role

project(ProtoLoop(steps) :: rest, role) =
  let inner = project(steps, role) in
  SRec("loop", append_continuation(inner, project(rest, role)))
  -- or, if inner = SEnd: just project(rest, role) (role not involved in loop)

project(ProtoChoice(sender, branches) :: rest, role)
  | sender = role   = SChoose(map (fn arm -> project(arm @ rest, role)) branches)
  | otherwise       = SOffer(map (fn arm -> project(arm @ rest, role)) branches)
```

The projection is computed in `check_decl` for `DProtocol` nodes and memoized into `env.protocols` alongside the raw `protocol_def`.

### 3.6 Type inference considerations

Session type annotations on channel variables **cannot** generally be inferred from usage alone (would require solving protocol equations). The rule is:

- `Chan.new(ProtoName)` must be explicitly annotated with the protocol name. The endpoint types are then computed by projection — no annotation needed on the returned channel variables themselves.
- `Chan.send` / `Chan.recv` / `Chan.close` propagate the known session type; no annotation needed.
- `Chan.offer` match arms: the branch labels are checked against the `SOffer` type; explicit label annotation is not required on the match arm variable.

This is analogous to how `spawn(ActorName)` requires an explicit actor type but the returned `Pid` type is inferred.

---

## 4. Runtime Representation

### 4.1 Channel pairs as synchronized queues

The simplest runtime representation that matches the synchronous actor model already in the interpreter:

```ocaml
(* In eval.ml, add to the value type: *)
| VChan of chan_endpoint

type chan_endpoint = {
  ce_id      : int;           (* globally unique channel id *)
  ce_role    : string;        (* which side of the protocol *)
  ce_send_q  : value Queue.t; (* this side sends onto this queue *)
  ce_recv_q  : value Queue.t; (* this side receives from this queue *)
  mutable ce_closed : bool;
}
```

`Chan.new(Proto)` allocates two `chan_endpoint` records that share their queues in opposite directions (A's send_q = B's recv_q and vice versa).

### 4.2 Runtime protocol tracking (belt + suspenders)

Even though the type system catches violations statically, the eval adds a runtime `session_state` field to each `chan_endpoint` to detect mismatches that slip through (typed holes, unsafe blocks, or interpreter bugs):

```ocaml
mutable ce_session  : session_ty;
```

Before each `Chan.send` / `Chan.recv` / `Chan.choose` / `Chan.offer` / `Chan.close`, the interpreter checks the runtime session state matches the operation being performed and raises `SessionViolation` if not. This makes protocol violations observable even in test code that bypasses the type checker.

### 4.3 Channel table

```ocaml
let chan_registry : (int, chan_endpoint * chan_endpoint) Hashtbl.t =
  Hashtbl.create 16
```

`Chan.new` allocates a fresh id, creates the pair, registers it. `Chan.close` marks `ce_closed = true` and removes the entry once both sides are closed.

### 4.4 Session delegation

Channels are linear values, so they can be *sent* through other channels or via actor messages. The runtime moves the `VChan` value — no copy. The sender loses the binding (linear use is recorded). This enables:

```march
-- Actor A creates channel, sends one end to B through actor messaging:
let (my_ch, their_ch) = Chan.new(Proto)
send(b, GotChannel(their_ch))   -- linear field: transfers ownership
-- my_ch remains valid in A's scope
```

---

## 5. Interaction with Existing Features

### 5.1 Actors and session initiation

Three patterns for establishing sessions between actors:

**Pattern 1 — Caller creates, sends endpoint:**
```march
-- A spawns B and immediately sends the channel endpoint in the Init message.
let (a_ch, b_ch) = Chan.new(Transfer)
let b_pid = spawn(B)
send(b_pid, Init(b_ch))
-- A proceeds with protocol on a_ch
```

**Pattern 2 — Rendez-vous via a broker actor:**
A dedicated `Chan.Broker` actor holds a `Chan.new` pair and distributes endpoints to two requesters. Useful when neither party knows the other at spawn time.

**Pattern 3 — Session types over a single actor mailbox:**
Actors can annotate their `receive` with a session protocol, turning their mailbox into a session-typed receive sequence. This is an advanced use case deferred to a later phase.

### 5.2 Supervision and crash recovery

When an actor crashes:
- All channel endpoints held by that actor are considered **abandoned**.
- The peer actor receives a `SessionAborted` message (analogous to Erlang `DOWN` monitors) on its channel instead of the expected value.
- The peer's `Chan.recv` returns `Err(SessionAborted)` when the peer is dead — the result type is `Result(T, SessionError)` rather than `T` for session-aware receive.

This changes the `Chan.recv` type signature to:

```march
fn Chan.recv(ch : linear Chan(R, Recv(T, S))) : (Result(T, SessionError), linear Chan(R, S))
```

For simplicity, Phase 1–3 can use a `panic`-on-crash model (the peer panics on receive from a dead channel), with the full monitor integration deferred to Phase 5.

### 5.3 Pattern matching on Offer branches

`Chan.offer` desugars to a match on a label value received from the channel:

```march
let ch2 = Chan.offer(ch) do
  | :accepted -> fn ch -> handle_accepted(ch)
  | :rejected -> fn ch -> handle_rejected(ch)
end
```

The match exhaustiveness checker applies: if `SOffer` has three labels but the match covers only two, a warning (or error) is emitted. This reuses the existing `PatCon`/`PatAtom` exhaustiveness machinery — offer labels map to atoms.

### 5.4 Module system

Session protocol declarations are top-level declarations (`DProtocol`) and follow module visibility:

```march
mod Auth do
  pub protocol Login do
    Client -> Server : Credentials(String, String)
    Server -> Client : Token(String) | Rejected
  end
end

-- In another module:
use Auth.Login
let (c, s) = Chan.new(Login)
```

Exported protocols are included in `sig` blocks by name. The `sig` hash covers the protocol definition, so downstream modules that depend on a protocol are invalidated if the protocol changes.

---

## 6. Implementation Phases

Each phase ends with a clean build (`dune build`) and passing tests (`dune runtest`).

### Phase 1: Session type declarations + duality computation

**Goal:** Parse and validate `protocol` declarations; compute and verify dual projections; register local session types in the type environment.

**Work items:**

1. **Extend `session_ty`** — add the OCaml type to `typecheck.ml` (listed in §3.1).
2. **Projection function** — implement `project : Ast.protocol_def -> string -> session_ty` in `typecheck.ml`. Handle `ProtoMsg`, `ProtoLoop`, `ProtoChoice`.
3. **Duality function** — implement `dual : session_ty -> session_ty`. Assert `dual(project(proto, A)) = project(proto, B)` for two-participant protocols.
4. **Extend `env.protocols`** — store `(string * (Ast.protocol_def * (string * session_ty) list))` — protocol name → (raw def, [(role, local_ty)]).
5. **Update `DProtocol` checking** in `check_decl` — call project/dual; populate the extended protocols map; emit errors for:
   - Loops with no participating steps.
   - Unbalanced choice arms (sender names different roles across arms).
6. **Test:** `protocol A do Client -> Server : Int end` — verify projection onto Client = `SSend(TInt, SEnd)`, Server = `SRecv(TInt, SEnd)`, dual check passes.

**New tests:** 6–8 tests covering valid protocols, projection correctness, duality failure detection.

### Phase 2: Channel creation + send/recv with session type tracking

**Goal:** `Chan.new`, `Chan.send`, `Chan.recv`, `Chan.close` are typechecked against session types; linear consumption is enforced.

**Work items:**

1. **Extend AST `ty`** — add `TyChan of name * name` (role, protocol) to `ast.ml`.
2. **Extend typechecker `ty`** — add `TChan of session_ty ref` to `typecheck.ml`.
3. **Normalize `TyChan`** in `check_annot` — look up protocol, project onto role, return `TChan(ref session_ty)`. Emit error if protocol unknown or role not mentioned.
4. **`Chan.new` builtin** — type `TArrow(TyCon("Protocol",[]), TTuple [TChan(ref proj_A); TChan(ref proj_B)])`. In practice this is a polymorphic builtin keyed by protocol name; implement as a pseudo-builtin that takes a protocol name atom and returns the pair.
5. **`Chan.send` / `Chan.recv` / `Chan.close` builtins** — typed functions that check the runtime session state:
   - `send : linear Chan(Recv(T, S)) * T -> linear Chan(S)` — session advances.
   - `recv : linear Chan(Recv(T, S)) -> (T, linear Chan(S))`.
   - `close : linear Chan(End) -> Unit`.
6. **Linearity enforcement** — channels are bound via `bind_linear`; each use records a use; `check_linear_all_consumed` catches un-closed channels.
7. **Eval builtins** — implement `Chan.new` / `Chan.send` / `Chan.recv` / `Chan.close` in `eval.ml` using `VChan` and synchronized queues. Add runtime session state check.

**New tests:** 10–12 tests: basic send/recv, linearity violation (double-use), un-closed channel warning, type mismatch on send payload.

**Example at end of Phase 2:**
```march
protocol Ping do
  A -> B : Int
  B -> A : Int
end

fn ping_client(ch : linear Chan(A, Ping)) do
  let ch2 = Chan.send(ch, 42)
  let (n, ch3) = Chan.recv(ch2)
  Chan.close(ch3)
  n
end
```

### Phase 3: Choose/Offer branching

**Goal:** `Chan.choose` and `Chan.offer` are typechecked and evaluated.

**Work items:**

1. **Extend `protocol_step` parsing** — the existing `ProtoChoice` node covers choice; extend the parser to handle `choose do | Label -> steps end` syntax (multi-step per arm).
2. **Update projection** — `ProtoChoice` where `sender = role` → `SChoose`; otherwise → `SOffer`.
3. **`Chan.choose` builtin** — type: consumes `TChan(ref (SChoose branches))`, takes label atom, returns `TChan(ref S_lbl)`. Error if label not in branches.
4. **`Chan.offer` builtin** — desugars in the typechecker to a match expression over label atoms received from the channel. Each arm receives `TChan(ref S_lbl)`. All arms must have the same result type.
5. **Exhaustiveness** — reuse existing pattern exhaustiveness machinery; `SOffer` branches define the set of required labels.
6. **Eval** — `Chan.choose` sends the label tag over the queue; `Chan.offer` receives it and dispatches.

**New tests:** 8–10 tests: valid choose/offer pair, missing arm, wrong label, nested branching inside a loop.

**Example at end of Phase 3:**
```march
protocol Auth do
  Client -> Server : Credentials(String, String)
  choose do
    | accepted ->
        Server -> Client : Token(String)
    | denied ->
        Server -> Client : Reason(String)
  end
end

fn client_side(ch) do
  let ch2 = Chan.send(ch, ("alice", "hunter2"))
  let ch3 = Chan.offer(ch2) do
    | :accepted -> fn ch ->
        let (tok, ch4) = Chan.recv(ch)
        Chan.close(ch4)
        Ok(tok)
    | :denied -> fn ch ->
        let (reason, ch4) = Chan.recv(ch)
        Chan.close(ch4)
        Err(reason)
  end
  ch3
end
```

### Phase 4: Integration with linear types (channels must be consumed)

**Goal:** Full enforcement of channel linearity — un-consumed channels at end of scope are compile errors, not warnings.

**Work items:**

1. **Promote un-consumed channel warning → error** — in `check_linear_all_consumed`, distinguish `TChan` from other linear types and emit an error (not hint) for un-consumed channels.
2. **Channel drop handler** — if an actor crashes with open channels, the runtime calls `Chan.abort` on all live `VChan` values held in `ai_linear_values`; the peer receives `SessionAborted`.
3. **Register channels via `own`** — at `Chan.new`, register both endpoints with the respective actors via the existing `own` builtin (Phase 6b, already implemented). This ensures the drop handler fires on crash.
4. **Test:** un-consumed channel in a function body is a type error; crash-with-open-channel aborts the peer.

### Phase 5: Session delegation (passing a channel endpoint to another actor)

**Goal:** A channel endpoint can be transferred through actor messages or as a function argument, enabling more complex session compositions.

**Work items:**

1. **Linear fields in actor messages** — actor handler params already support `param_lin`; extend message constructor types to allow `linear Chan(R, Proto)` fields. The type checker's `ESend` handler should propagate linearity from the message payload.
2. **Session handoff** — when a `VChan` is moved via `send`, mark the sender's endpoint as consumed (linear use) and give the new owner the `VChan` value.
3. **Higher-order session functions** — functions that take a channel as a parameter and advance it are typed with the session type flowing through. The typechecker tracks channel state across call boundaries: `fn process(ch : linear Chan(R, S)) : linear Chan(R, S') do ... end`.
4. **Delegation in the eval** — `VChan` values are passed by reference (they contain mutable state); the linear tracking in the typechecker ensures only one owner at a time.
5. **Test:** actor A creates channel, delegates one end to actor B via message, B advances the session, A receives on the remaining end.

---

## 7. Concrete OCaml Types

### 7.1 AST additions (`lib/ast/ast.ml`)

```ocaml
(* Add to ty: *)
| TyChan of name * name
(** Session-typed channel endpoint: Chan(RoleName, ProtocolName) *)

(* Existing protocol_step — extend ProtoChoice with label names: *)
and protocol_step =
  | ProtoMsg    of name * name * ty
  | ProtoLoop   of protocol_step list
  | ProtoChoice of name * (name * protocol_step list) list
  (**  ProtoChoice(chooser_role, [(label, steps); ...])
       chooser_role sends the branch label; the other side offers it. *)
```

### 7.2 Typechecker additions (`lib/typecheck/typecheck.ml`)

```ocaml
(* Extend ty: *)
| TChan of session_ty ref
(** Internal type for a linear channel endpoint.
    The ref is advanced by Chan.send/recv/choose/offer to reflect consumed state. *)

(* New type: *)
and session_ty =
  | SSend   of ty * session_ty
  | SRecv   of ty * session_ty
  | SChoose of (string * session_ty) list   (* label -> continuation *)
  | SOffer  of (string * session_ty) list   (* label -> continuation *)
  | SEnd
  | SRec    of string * session_ty          (* recursive binder *)
  | SVar    of string                       (* back-reference *)
  | SError                                  (* error sentinel *)

(* Extend env: *)
type env = {
  ...
  protocols : (string * proto_info) list;
  (* was: (string * Ast.protocol_def) list *)
}

and proto_info = {
  pi_def         : Ast.protocol_def;
  pi_projections : (string * session_ty) list;  (* role -> local type *)
  pi_span        : span;
}
```

### 7.3 Eval additions (`lib/eval/eval.ml`)

```ocaml
(* Extend value: *)
| VChan of chan_endpoint

(* New type: *)
type chan_endpoint = {
  ce_id      : int;
  ce_role    : string;
  ce_proto   : string;
  mutable ce_session  : session_ty;   (* runtime state check *)
  mutable ce_closed   : bool;
  ce_out_q   : value Queue.t;   (* values this endpoint puts out *)
  ce_in_q    : value Queue.t;   (* values this endpoint receives *)
}

(* Global channel table: *)
let chan_registry : (int, chan_endpoint * chan_endpoint) Hashtbl.t =
  Hashtbl.create 16

let next_chan_id : int ref = ref 0
```

### 7.4 TIR additions (`lib/tir/tir.ml`)

For the compiled path, channels become pointers to heap-allocated queue structs. New TIR nodes:

```ocaml
(* Extend expr: *)
| EChanNew   of string * string        (* proto_name, role_A -> returns pair *)
| EChanSend  of expr * expr            (* chan endpoint, value -> new endpoint *)
| EChanRecv  of expr                   (* chan endpoint -> (value, new endpoint) *)
| EChanClose of expr                   (* chan endpoint -> unit *)
| EChanChoose of expr * string         (* chan endpoint, label -> new endpoint *)
| EChanOffer of expr * (string * expr) list  (* chan endpoint, [(label, cont_fn)] *)
```

---

## 8. Example March Code at Each Phase

### Phase 1 — Declare, no channels yet

```march
protocol Counter do
  Client -> Server : Increment
  Server -> Client : Int
end

-- The typechecker validates this protocol and registers it.
-- Projection onto Client: SSend(Increment, SRecv(Int, SEnd))
-- Projection onto Server: SRecv(Increment, SSend(Int, SEnd))
-- Duality verified: dual(Client projection) = Server projection ✓
```

### Phase 2 — Basic send/recv

```march
fn server_side(ch : linear Chan(Server, Counter)) do
  let (_, ch2) = Chan.recv(ch)           -- receive Increment
  let ch3 = Chan.send(ch2, 42)           -- send Int
  Chan.close(ch3)
end

fn client_side(ch : linear Chan(Client, Counter)) do
  let ch2 = Chan.send(ch, Increment())
  let (n, ch3) = Chan.recv(ch2)
  Chan.close(ch3)
  n    -- returns 42
end

fn main() do
  let (client_ch, server_ch) = Chan.new(Counter)
  -- In a real program these would be different actors/threads.
  -- For testing, we can run both sides synchronously:
  let n = client_side(client_ch)
  server_side(server_ch)
  println(int_to_string(n))
end
```

### Phase 3 — Branching

```march
protocol Calc do
  choose do
    | add ->
        Client -> Server : (Int, Int)
        Server -> Client : Int
    | quit ->
        -- protocol ends
  end
end

fn calc_server(ch) do
  let ch2 = Chan.offer(ch) do
    | :add -> fn ch ->
        let ((a, b), ch3) = Chan.recv(ch)
        let ch4 = Chan.send(ch3, a + b)
        Chan.close(ch4)
    | :quit -> fn ch ->
        Chan.close(ch)
  end
  ch2
end

fn calc_client(ch) do
  let ch2 = Chan.choose(ch, :add)
  let ch3 = Chan.send(ch2, (3, 4))
  let (result, ch4) = Chan.recv(ch3)
  Chan.close(ch4)
  result   -- 7
end
```

### Phase 4 — Actor with sessions

```march
actor Calculator do
  state : Unit
  init : Unit

  on StartCalc(ch : linear Chan(Server, Calc)) do
    calc_server(ch)
    state
  end
end

fn main() do
  let calc = spawn(Calculator)
  let (client_ch, server_ch) = Chan.new(Calc)
  send(calc, StartCalc(server_ch))   -- linear transfer via message
  let result = calc_client(client_ch)
  println(int_to_string(result))
end
```

### Phase 5 — Session delegation

```march
-- Actor A starts a protocol, delegates partway to Actor B.
protocol Pipeline do
  Source -> Proc : Data(String)
  Proc -> Sink : Result(Int)
end

actor Processor do
  state : Unit
  init : Unit

  -- Receives the middle portion of the channel (after Source has sent Data)
  on Process(ch : linear Chan(Proc, Send(Int, End))) do
    -- Compute something with the received data and send result
    let ch2 = Chan.send(ch, 99)
    Chan.close(ch2)
    state
  end
end
```

---

## 9. Related Work / Design Influences

### Links language
Links (Cooper et al.) pioneered session types in a functional web language. March's approach is similar: session types are first-class, channels are linear. Key difference: Links uses a continuation-passing style internally; March uses the existing linear binding machinery and advances the session type at each use site.

### GV (Good Variation)
Gay and Vasconcelos's GV formalizes session-typed λ-calculus with cut elimination. March's `SRec`/`SVar` for recursive sessions is directly inspired by GV's equirecursive session types. The duality check at protocol declaration time mirrors GV's coherence condition.

### Rust session-types crate (sesh / session-types)
Rust's session-types crate (Jespersen et al.) encodes session types in Rust's type system via phantom types and linearity via `Drop`. March's approach is more direct — `session_ty` is a first-class type in the typechecker, not an encoding. This gives cleaner error messages: "expected `Send(Int, End)` but channel is at `End`" instead of Rust's trait-bound error cascades.

### Ferrite (Rust)
Ferrite is a more recent Rust session-type library using GATs. It supports more advanced features (multi-party via binary projections). March targets the same binary session subset for v1 but with native language support rather than library encoding.

### Elixir / Erlang
Elixir has no static session types; March adds them. The actor model inspiration is Erlang, but the type-checked message sequences replace ad-hoc `receive` matching. March's `Chan.offer` is semantically related to `receive` pattern matching in Erlang but statically guaranteed to be exhaustive.

### Pony
Pony uses capabilities (iso, ref, val, box, tag, trn) for reference uniqueness. March's linear types cover the same ground for channels. Pony does not have session types; March adds them on top of a simpler linear/affine model.

---

## Appendix: Open Questions

1. **Recursive protocols** — `ProtoLoop` maps to `SRec`. Should loops be limited to tail-recursive protocols (one loop point per protocol), or should arbitrary nesting be allowed? Initial implementation: one loop per protocol (simple `SRec`/`SVar`); nested loops deferred.

2. **Session type subtyping** — should a `Send(Int | String, S)` session type accept a `Send(Int, S)` channel? For v1, no subtyping — exact session type equality at each step. Subtyping deferred.

3. **Interleaved sessions** — can one actor hold multiple open channels simultaneously? Yes: each channel is a separate linear variable. The typechecker tracks them independently. No combining of sessions (tensor types) in v1.

4. **Timeout / non-blocking receive** — `Chan.recv` in Phase 1–3 blocks (synchronous eval). Async receive with timeout is a Phase 5+ concern; the eval's mailbox model would need `try_recv`.

5. **Session types in TIR / LLVM** — channels need a C runtime representation. For the compiled path, a channel is a heap-allocated struct with two mutex-protected queues (one per direction). The runtime's `march_chan_send` / `march_chan_recv` functions replace the eval-level builtins. This is Phase 4+ work alongside the general actor→TIR lowering.
