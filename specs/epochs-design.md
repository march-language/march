# Supervision Trees with Protocol Epochs

**Date:** 2026-03-17
**Status:** Draft
**Area:** Concurrency / Actors

## Problem

Session types guarantee protocol adherence — if actor A expects to receive message M from actor B, B will send it. But supervision assumes actors can crash mid-protocol. These are in direct conflict.

Erlang/OTP solves this with monitors and `{'DOWN', ...}` messages, but has no session types. Existing session type literature mostly ignores failure; the closest prior work introduces a `?end` bottom type that any session can degrade to, but this gives up the per-step guarantees that make session types useful. March needs a design that composes both guarantees without sacrificing either.

## Design: Protocol Epochs

Every actor capability and session channel carries an **epoch** — a monotonically increasing `UInt64` tied to the actor's generation. When a supervised actor crashes and is restarted, its epoch increments. Capabilities and channels at the old epoch become stale; the type system and runtime together ensure holders cannot silently ignore this.

---

## Section 1: Core Types

### `ActorId`, `Cap`, and `Chan`

Three distinct types are involved:

```march
type Epoch = UInt64

-- Stable identity for an actor; survives epoch changes; non-linear and freely copyable
-- Used only for supervision operations (restart, monitor)
type ActorId(A) = ...

-- An unforgeable reference authorizing message sends to an actor at a specific epoch
-- Non-linear: a Cap can be copied and used multiple times; it is not consumed by use
-- Phantom type parameter e tracks the epoch at the time the Cap was issued
type Cap(A, e : Epoch) = ...

-- An open session type channel; linear — must be consumed by the protocol or explicitly dropped
type Chan(P, e : Epoch) = linear ...

-- Spawn returns both a stable identity and an epoch-0 capability
let (worker_id : ActorId(FileWorker), worker_cap : Cap(FileWorker, 0)) = spawn(FileWorker)

-- Opening a session creates a Chan at the same epoch as the Cap; does not consume the Cap
let ch : Chan(FileTransfer, 0) = open(worker_cap)
```

`Cap` is **non-linear** — it is an unforgeable reference, not a linear ownership token. An actor can hold a `Cap` and open multiple sessions, send ad-hoc messages, and store it in data structures without consuming it. `Chan` is **linear** — it tracks a single open session and must be driven to completion or explicitly dropped.

### Regular Message Sends vs. Session Operations

Two distinct send/receive forms exist:

```march
-- Ad-hoc message send via Cap; does not advance a session type
-- Returns Result to surface epoch staleness
send(cap, Increment()) : Result(Unit, DeadActor)

-- Session send via Chan; advances the session type
-- Returns SessionResult (defined in Section 4)
send_session(ch, Upload(file)) : SessionResult(Chan(FileTransfer_after_upload, e))
```

Epoch staleness for a `Cap` is surfaced as `DeadActor` in the `Result` return of `send`. For session operations on `Chan`, it is surfaced as `Dead` in `SessionResult` (Section 4). In both cases the operation is fallible, not a type error, because the epoch mismatch may not be detectable at compile time (the actor may have restarted between when the `Cap` was obtained and when it is used).

When epoch staleness **is** detectable at compile time — because the `Cap` is provably from a superseded epoch — the compiler emits a type error. The runtime check handles cases where this cannot be determined statically.

### `LiveCap`: Supervisor-Managed Capabilities

Supervisors hold capabilities that must remain valid across restarts. Rather than epoch-stamping these with a fixed phantom type, supervisor state uses `LiveCap(A)` — a distinct type maintained by the runtime:

```march
-- A runtime-managed capability that always reflects the current live epoch
-- Valid only in supervisor-declared state; not directly usable as a Cap outside the supervisor
type LiveCap(A) = ...

-- Supervisor state uses LiveCap, not Cap
actor FileWorkerSupervisor do
  supervise do
    worker_id  : ActorId(FileWorker)
    worker_cap : LiveCap(FileWorker)
  end
  ...
end
```

`LiveCap` is not a `Cap(A, _)` phantom type — it avoids the existential/universal ambiguity entirely. When the supervisor needs to send a message or open a session, it calls `use_cap(state.worker_cap)`, which extracts a `Cap(A, e)` at the current epoch:

```march
fn use_cap(lc : LiveCap(A)) : Cap(A, e)   -- e is existentially bound; callers treat it as an opaque live epoch
```

The returned `Cap` is valid for the current epoch. If the actor is restarted before the `Cap` is used, the `Cap` becomes stale and `send` will return `DeadActor` — the same as any other stale `Cap`.

After a restart, `state.worker_cap` is updated by the runtime to reflect the new epoch. **`LiveCap` is a type-level restriction:** the type `LiveCap(A)` is only constructible by the runtime (via `spawn` and `restart`) and is only storable in `supervise` block field positions. The compiler rejects any attempt to assign a `LiveCap` to a non-supervisor binding, pass it as a function argument, or include it in a message payload. This is enforced statically, not at runtime.

---

## Section 2: Drop Handlers

Linear values must be cleaned up when abandoned — whether by normal program flow or by actor crash. Cleanup is divided into two tiers.

### Tier 1 — Automatic (OS Resources)

OS resources declare their cleanup function at the FFI boundary.

```march
foreign type File    = ffi_file_t    cleanup ffi_close
foreign type Socket  = ffi_socket_t  cleanup ffi_close_socket
foreign type FfiPtr  = ffi_ptr_t     cleanup ffi_free
```

The runtime calls the declared cleanup function automatically when the value is dropped. No user-written handler is needed.

### Tier 2 — Explicit (Protocol-Level Cleanup)

When abandoning a value requires sending messages or executing application logic, a `Drop` implementation is required.

```march
interface Drop(a : linear) do
  fn drop(value : linear a) : Unit
end

-- Channel drop: attempt to notify the other session participant
impl Drop(Chan(FileTransfer, e)) do
  fn drop(ch : linear Chan(FileTransfer, e)) do
    try_send_abort(ch)   -- best-effort; failure is silently ignored
  end
end
```

**Drop handler execution context:** Drop handlers run in the runtime's crash-cleanup phase — not in the crashed actor's thread and not in the supervisor's actor loop. This means:

- Drop handlers must not block indefinitely.
- Drop handlers have no ambient actor capabilities; any message sends must go through channels or `Cap` values captured in the dropped value itself.
- If a drop handler panics, the runtime logs the failure and continues cleanup. Drop handlers are best-effort; their failure cannot be recovered.
- Cascading crashes triggered by drop handler activity (e.g., a `try_send_abort` causing a fault in another actor) are handled by that actor's own supervisor independently. This spec does not define cross-crash ordering.

**`try_send_abort` signature:**

```march
fn try_send_abort(ch : linear Chan(P, e)) : Unit
```

`try_send_abort` operates directly on the channel's runtime handle, bypassing the actor message queue. It attempts to enqueue an out-of-band abort signal in the counterparty's receive buffer. If the target port is unreachable (counterparty crashed or recycled), the call is a no-op. It always returns `Unit` and consumes the channel. It does not require an ambient actor send context.

**Why `try_send_abort`:** The abort target may be unreachable — the other session participant may have also crashed. The other participant discovers the dead channel via monitor `Down` or session operation returning `Dead` independently.

### Acquisition Order

"Reverse acquisition order" means the reverse of the sequential order in which linear values were bound in the actor's execution trace. For values received via message, acquisition order is defined by mailbox delivery timestamp, recorded by the runtime when each linear value is transferred into the actor. This requires the runtime to maintain a lightweight ordered list of live linear value handles per actor (one pointer-sized entry per live linear value).

### Crash Sequence

The crash sequence has a strict ordering to preserve the `Down`-before-`Dead` guarantee (Section 4):

```
actor B crashes
  ↓
1. runtime queues Down(mon, reason) in the mailbox of every actor monitoring B
   — this happens BEFORE any drop handlers execute
  ↓
2. runtime collects all linear values held by B
   calls drop() on each in reverse acquisition order
     Tier 1: invoke FFI cleanup function
     Tier 2: invoke user Drop impl (try_send_abort is best-effort; panics are logged)
  ↓
3. supervisor receives Crashed(actor_id, reason)
   applies restart strategy
   B' starts at epoch + 1
   supervisor's LiveCap(B) is updated by the runtime to reflect the new epoch
```

`Down` is queued in step 1 before drop handlers run in step 2. Any `try_send_abort` executed in step 2 therefore finds that `Down` is already in the target's mailbox. The ordering guarantee holds by construction.

**The old `LiveCap` transition:** When the supervisor's `on Crashed` handler returns a new state record, the runtime replaces the `LiveCap` in the supervisor's state with one reflecting `epoch + 1`. The old `LiveCap` is retired by the runtime — there is no user-visible `drop` call for it, since `LiveCap` is a runtime-internal type.

---

## Section 3: Supervisor API & Restart Strategies

```march
actor FileWorkerSupervisor do
  supervise do
    worker_id  : ActorId(FileWorker)
    worker_cap : LiveCap(FileWorker)
  end

  strategy one_for_one
  max_restarts 3 within 5s  -- sliding window

  on Crashed(id, reason) when id == state.worker_id do
    -- restart takes ActorId; returns a fresh (ActorId, LiveCap) pair
    let (new_id, new_cap) = restart(state.worker_id)
    -- return a full new state record (not a spread — on Crashed replaces the whole state)
    { worker_id = new_id, worker_cap = new_cap }
  end
end
```

`restart` takes an `ActorId` (not a stale `Cap`). The `on Crashed` handler returns a **full replacement state record**, not a spread update. The compiler requires that all fields of the supervisor's state type be present in the return value — partial record syntax is rejected. This is by design: the supervisor may need to replace multiple fields atomically after a restart, and requiring full specification prevents accidentally leaving a `LiveCap` for a restarted actor in a stale state. Normal actor message handlers use `{ state with field = value }` for incremental updates; `on Crashed` handlers explicitly cannot use spread syntax.

**`max_restarts` windowing:** The sliding-window algorithm is used. The supervisor tracks a list of restart timestamps; a restart is allowed if fewer than `max_restarts` timestamps fall within the last `within` seconds. When the limit is exceeded, the supervisor itself crashes.

### Reconnection for External Holders

Actors outside a supervision group may hold `Cap(B, old_epoch)` values. When B is restarted, these become stale. The external actor discovers staleness via monitor `Down` or by receiving `DeadActor` from `send`.

The external actor cannot call `restart` (that is a supervisor operation). To reconnect, it must obtain a fresh `Cap` through one of:

1. **Request from the supervisor:** Send a message to the supervisor requesting a new `Cap` for B. The supervisor replies with `use_cap(state.worker_cap)` — a snapshot of the live capability at the current epoch.
2. **Re-spawn:** If the external actor has permission to spawn B itself, it may do so.
3. **Give up:** Treat the crash as an unrecoverable error and escalate.

The runtime does not provide a global "get current Cap for ActorId" function. Capability acquisition must go through a trusted channel to preserve capability security guarantees.

### Restart Strategies

**`one_for_one`**

Only the crashed actor is restarted. Its epoch increments; all other supervised actors are unaffected. Use when workers are fully independent.

**`one_for_all`**

All actors in the supervision group are explicitly terminated, then all are restarted. The full `Down`-before-drop ordering applies across the group: before any drop handler runs for any actor in the group, `Down` messages are queued in the mailboxes of all external monitors of all group members. This is a group-wide step 1 — all `Down` messages for all group members are enqueued atomically before any intra-group drop handler executes. Only then does the per-actor drop sequence (reverse acquisition order) run for each terminated actor.

Termination order within the group (i.e., which actor's drop handlers run first) is unspecified. Monitors between actors within the same `one_for_all` group produce `Down` messages that are guaranteed to be discarded without delivery: actors being terminated do not process their mailboxes after termination begins, and any `Down` messages queued in their inboxes are discarded as part of teardown. This is by design — intra-group `Down` delivery to a fellow-terminated actor is meaningless and not guaranteed.

**`rest_for_one`**

The crashed actor B has already terminated naturally. Actors **after** B in the declared `order` list are explicitly terminated in reverse order (last first), each going through the normal crash sequence. Actors **before** B in the list are unaffected. After all downstream actors are terminated, B and the downstream actors are restarted in forward order.

```march
actor PipelineSupervisor do
  supervise do
    reader_id  : ActorId(Reader)
    parser_id  : ActorId(Parser)
    writer_id  : ActorId(Writer)

    reader_cap : LiveCap(Reader)
    parser_cap : LiveCap(Parser)
    writer_cap : LiveCap(Writer)
  end

  strategy rest_for_one
  order [reader_id, parser_id, writer_id]
end
-- If parser crashes naturally: writer is explicitly terminated (reverse order: writer first).
-- Then parser and writer are restarted. reader is unaffected.
```

The `order` declaration is the programmer's responsibility — the compiler does not statically verify that it matches actual protocol dependencies. Incorrect ordering produces incorrect restart behavior, not a compile error. Static verification is a future extension.

### Escalation

If `max_restarts` is exceeded within the sliding window, the supervisor itself crashes, propagating failure to its own supervisor.

---

## Section 4: Epoch Invalidation — How Dead Channels Are Discovered

### `SessionResult` Type

All session operations (`send_session`, `receive_session`) return `SessionResult`:

```march
type SessionResult(a) =
  | Cont(a)    -- step succeeded; a is the next channel state
  | Dead       -- epoch mismatch; channel is consumed by the operation
```

`send_session` and `receive_session` always consume the channel regardless of outcome. On `Cont`, the next channel state is returned. On `Dead`, the channel is consumed inside the call — no further drop is needed at the call site. This is what prevents double-drop.

```march
-- send_session: consumes ch; returns Cont(next_chan) on success or Dead on epoch mismatch
match send_session(ch, Upload(file)) with
| Cont(next_ch) -> -- ch consumed; next_ch : Chan(FileTransfer_after_upload, e)
| Dead          -> -- ch consumed by failed send; handle the failure
end

-- receive_session: consumes ch; returns Cont((msg, next_chan)) on success or Dead on epoch mismatch
-- Dead from receive means the counterparty's channel was abandoned before the message was sent;
-- the message was not transmitted. The caller cannot distinguish "crashed before sending" from
-- "crashed after sending but message was lost" — both appear as Dead.
match receive_session(ch) with
| Cont((Upload(file), next_ch)) -> -- file received; next_ch is the next channel state
| Dead                          -> -- ch consumed; no message received
end
```

The epoch check on `receive_session` is best-effort: if the counterparty's drop handler ran `try_send_abort` before the crash sequence completed, the abort signal may arrive and cause `Dead` before the epoch is locally known to be stale. In all cases, `Dead` from either operation means the session is over and no further operations on this channel are possible.

### `Monitor` Type

```march
-- Non-linear: a Monitor can be stored, copied, and discarded without consuming it
-- Multiple monitors on the same ActorId are allowed; each returns a distinct Monitor handle
type Monitor = ...

fn monitor(id : ActorId(A)) : Monitor
fn demonitor(m : Monitor) : Unit   -- cancels the monitor; subsequent Down for m are suppressed
```

`Monitor` is non-linear. If the monitoring actor crashes before the monitored actor, all its monitors are implicitly cancelled by the runtime during crash cleanup. Multiple monitors on the same `ActorId` produce multiple distinct `Monitor` handles, each generating independent `Down` messages. The `Down` message carries the `Monitor` handle to allow disambiguation when an actor monitors multiple targets.

### Monitors (Eager, Push)

When the monitored actor crashes, the runtime queues `Down(monitor, reason)` in the monitoring actor's mailbox in step 1 of the crash sequence — before any drop handlers run.

```march
let (worker_id, worker_cap) = spawn(FileWorker)
let ch  : Chan(FileTransfer, e) = open(worker_cap)
let mon : Monitor               = monitor(worker_id)

match receive() with
| FileReady(data)   ->
    -- ch still live; caller must eventually consume or drop ch
    let result = continue_protocol(ch, data)
    ...
| Down(mon, reason) ->
    -- Path A: Down received; ch epoch is stale at the runtime level.
    -- The type system permits send_session(ch, Abort()) because Abort may be a valid
    -- FileTransfer protocol step — whether it is depends on the protocol definition.
    -- The epoch check is a runtime concern; the type system allows any valid protocol step.
    match send_session(ch, Abort()) with
    | Cont(next_ch) -> -- Abort was a valid step and the counterparty acked it; continue from next_ch
    | Dead          -> -- expected in the crash case: ch consumed cleanly
    end
end
```

### Use-Site Detection (Lazy, Pull)

Without a monitor, staleness is detected when a session operation returns `Dead`, or when `send` returns `DeadActor`. An actor that does not set up a monitor will still discover the crash — just at the point of use rather than eagerly.

### Ordering Guarantee

If an actor holds both a monitor on B and an open channel to B:

- **`Down` is always delivered before `Dead` can be returned from any session operation on channels to B.** Guaranteed by crash sequence step ordering: `Down` is queued (step 1) before drop handlers run `try_send_abort` (step 2).
- **Path A** — actor processes `Down` first, then handles the dead channel explicitly.
- **Path B** — actor ignores `Down` and calls `send_session` on the channel, which returns `Dead`. The channel is consumed. The `Down` message remains in the mailbox and must eventually be matched and discarded (or used to trigger further recovery).

In both paths the channel is consumed exactly once.

### Full Mid-Protocol Crash Sequence

```
actor B crashes mid-protocol with actor A
  ↓
step 1: Down(mon, reason) queued in A's mailbox
  ↓
step 2: B's linear values dropped (reverse acquisition order)
        try_send_abort on B's open Chans (best-effort)
  ↓
step 3: B' starts at epoch + 1; supervisor's LiveCap(B) updated
  ↓
A processes Down → send_session(ch, Abort()) → Dead → ch consumed
  ↓
A decides: request new Cap from supervisor, or escalate
```

---

## Design Properties

| Property | How it's satisfied |
|---|---|
| No silent failures | `Chan` is linear; session operations return `SessionResult`; `send` returns `Result`; all staleness paths are typed |
| No shared state corruption | Actors are isolated; drop handlers run in runtime crash-cleanup, not in any actor loop |
| Deterministic cleanup | Drop order is reverse acquisition (by mailbox delivery timestamp); OS resources freed via FFI declaration |
| Protocol soundness | `Dead` is the typed early exit from any session step; session type advances only on `Cont`; `send_session` consumes channel regardless of outcome |
| `Down`-before-`Dead` ordering | `Down` queued before drop handlers run; guaranteed by crash sequence step ordering |
| Composability | Epoch model uses existing linear type machinery; no new syntax in protocol declarations |
| External holder safety | Stale `Cap` surfaces as `DeadActor` at use site; reconnection goes through a trusted channel |
| Capability security preserved | No global "get current Cap" lookup; reconnection must go through a supervisor or other authorized party |

## Alternatives Considered

**Failure as a protocol variant:** Model `Crashed` as an explicit branch in every protocol step. Maximally explicit and sound, but doubles the size of every protocol definition. Rejected as impractical.

**Session type `?end` bottom type:** Several session type systems introduce a top/bottom type that any session can degrade to on failure. This preserves type safety but gives up per-step guarantees — a session at `?end` carries no information about what remains. The epoch model preserves per-step session types on the success path, with `Dead` as a typed early exit, which is strictly more informative.

**`Cap(A, _)` existential epoch in supervisor state:** An earlier draft used `Cap(A, _)` with an existential phantom type for supervisor-held capabilities. This conflated two distinct type-level concepts — existential vs. universal quantification — and overloaded the `_` wildcard syntax with a meaning inconsistent with its use as a type inference hole elsewhere in March. `LiveCap(A)` avoids this ambiguity by making the supervisor-managed capability a distinct runtime type rather than a variant of the phantom-typed `Cap`.

**Checkpointed protocol resumption:** Supervisors serialize protocol state at declared checkpoint positions and resume mid-protocol after restart. More powerful but requires significant runtime machinery. Deferred as a future extension once the epoch model is stable.

## Open Questions

1. **Static epoch tracking:** Can the compiler detect epoch staleness statically in more cases? Phantom types help when capabilities flow through typed functions, but epoch values are often only known at runtime (e.g., after a restart in a loop). The boundary between compile-time type error and runtime `DeadActor`/`Dead` should be made precise.

2. **Monitor fan-out:** If many actors monitor a single actor, `Down` delivery at crash time is O(n) in the monitor count. For large fan-out, a lazy-only invalidation (use-site `Dead`) may be preferable above some threshold. The threshold and the switching policy are TBD.

3. **`use_cap` and capability attenuation:** When a supervisor replies to an external reconnection request with `use_cap(state.worker_cap)`, should it be able to issue an attenuated capability (e.g., one that can only send certain message types)? This interacts with the broader capability-security design and is deferred.

4. **Drop handler capability injection:** Drop handlers currently have no ambient capabilities. A future extension could allow supervisors to inject a restricted capability into the crash-cleanup context for more expressive drop behavior.

5. **Static verification of `rest_for_one` order:** The compiler does not verify that declared dependency order reflects actual protocol dependencies. Annotation-based or inference-based verification is a future extension.

6. **Checkpointing as future extension:** The checkpointed resumption approach is worth revisiting once this model is validated. Content-addressed protocol definitions already provide the serialization substrate needed.

## Resolved Design Decisions

- **Epoch integer type:** `UInt64`, unsigned. The counter saturates at `UUInt64.max` — it does not wrap. An actor whose epoch has reached `UUInt64.max` is considered permanently unrestartable; any subsequent `restart` call causes the supervisor to treat this as if `max_restarts` was exceeded, escalating to the supervisor's parent. Saturation (not wrapping) is required to preserve monotonicity: a wrapping counter would produce epoch values less than existing `Cap` phantom types, potentially allowing stale caps to appear live.
- **`max_restarts` windowing:** Sliding window. A restart is allowed if fewer than `max_restarts` timestamps fall within the most recent `within` seconds.
- **`send_session` channel ownership:** The channel is always consumed by `send_session`, regardless of whether the result is `Cont` or `Dead`. This is what makes double-drop structurally impossible.
- **`Cap` linearity:** `Cap` is non-linear. It is an unforgeable reference, not an ownership token.
- **`open(cap)` does not consume `cap`:** Opening a session creates a `Chan` but leaves the `Cap` live for further use.
- **`Monitor` linearity:** `Monitor` is non-linear. Monitors are cancelled implicitly on actor crash and explicitly via `demonitor`.
