# March Actor System

## Overview

The March actor system implements a lightweight, message-passing concurrency model inspired by the Erlang/OTP supervisor model. Actors are isolated processes that communicate exclusively through asynchronous message passing. The system supports spawning new actors, sending messages, monitoring/linking actors, and graceful termination through supervision hierarchies.

**Current Status**: Fully functional in the tree-walking interpreter. TIR lowering and LLVM code generation are planned (see [actor-lowering.md](../actor-lowering.md)).

---

## Core Concepts

### Actor Model

An **actor** is an independent computational entity defined by:

1. **State** — a record of typed fields representing the actor's mutable data
2. **Initialization** — an expression that creates the initial state
3. **Message handlers** — functions that process messages and return updated state

Actors communicate exclusively through **messages** — strongly typed constructor values sent to their mailbox. When a message arrives, the actor's handler for that message type executes, receives the current state, and returns a new state. All operations are fire-and-forget; senders do not block waiting for replies.

### Actor Declaration

```march
actor Counter do
  state { value : Int, label : String }
  init { value = 0, label = "default" }

  on Increment(n : Int) do
    { state with value = state.value + n }
  end

  on Reset() do
    { state with value = 0 }
  end
end
```

Key elements:
- **state** — defines the record type holding actor state (fields in any order; internally normalized alphabetically)
- **init** — expression returning a state record with all fields initialized
- **on Msg(params) do body end** — message handler; `body` is an expression returning new state

### Actor Identity

Actors are identified by a **process identifier (Pid)** — a unique integer assigned at spawn time. The Pid is an opaque value; the only meaningful operations are:
- **send** — enqueue a message
- **kill** — mark as dead
- **is_alive** — check liveliness
- **monitor** — install a watcher (Phase 1, partially stubbed)

---

## Core Operations

### spawn

```march
let counter_pid = spawn(Counter)
```

**Semantics**:
- Allocates a fresh actor instance with the actor's `init` expression as state
- Assigns a unique Pid
- Registers the actor in the global actor registry
- Returns the Pid

**Line references**:
- **AST**: `lib/ast/ast.ml:68` (`ESpawn` expression type)
- **Interpreter**: `lib/eval/eval.ml:2469–2536` (spawn implementation in `eval_expr_inner`)
- **Example**: `examples/actors.march:68`

### send

```march
send(counter_pid, Increment(5))
```

**Semantics**:
- Enqueues a message to the target actor's mailbox
- Returns `Some(())` if the actor is alive
- Returns `None` if the actor is dead (fire-and-forget, message is silently dropped)
- Messages must be constructor values (`VCon` or `VAtom`); non-constructor values are rejected

**Drop semantics**: When an actor is killed, its mailbox is drained but not processed. New messages sent to a dead actor are dropped silently—no error, no exception.

**Line references**:
- **AST**: `lib/ast/ast.ml:69` (`ESend` expression type)
- **Interpreter**: `lib/eval/eval.ml:2538–2559` (send implementation)
- **Runtime C**: `runtime/march_runtime.c:362–402` (`march_send` function)
- **Example**: `examples/actors.march:57–62` (safe_send wrapper)

### kill

```march
kill(counter_pid)
```

**Semantics**:
- Marks the actor as dead (sets `ai_alive = false`)
- Does **not** free the actor's memory (reference counting handles that)
- Does **not** drain or process the mailbox
- Subsequent sends to this actor return `None`

**Line references**:
- **Interpreter**: `lib/eval/eval.ml:1063–1065` (kill builtin)
- **Runtime C**: `runtime/march_runtime.c:404–412` (`march_kill` function)

### is_alive

```march
bool_to_string(is_alive(counter_pid))
```

**Semantics**: Returns `true` if the actor is alive, `false` if killed or never existed.

**Line references**:
- **Interpreter**: `lib/eval/eval.ml:1066–1071` (is_alive builtin)
- **Runtime C**: `runtime/march_runtime.c:414–419` (`march_is_alive` function)

### receive (Async-only)

```march
let msg = receive()
```

**Semantics** (interpreter only):
- Pops the next message from the current actor's mailbox
- Can only be called from within a handler (when `!current_pid` is set)
- Errors if the mailbox is empty
- **Note**: True blocking receive requires a multi-threaded scheduler (Phase 4). Current implementation requires messages to be queued in advance (not truly asynchronous).

**Line references**:
- **Interpreter**: `lib/eval/eval.ml:1127–1141` (receive builtin)
- **Design**: `specs/features/scheduler.md` (scheduler architecture)

### self

```march
let my_pid = self()
```

**Semantics**: Returns the Pid of the currently executing actor. Can only be called from within a handler.

**Line references**:
- **Interpreter**: `lib/eval/eval.ml:1121–1126` (self builtin)

---

## Actor State Management

### State Access in Handlers

Within a handler body, the variable `state` (type-checked as the actor's state record) refers to the current actor state before the handler executes. Handlers are **pure functions** — they receive state, compute a new state, and return it. The runtime automatically updates the actor struct with the returned state.

```march
on Increment(n : Int) do
  { state with value = state.value + n }
end
```

The `state` variable is implicitly available (not passed as a parameter). After the handler body executes and returns a state record, the runtime extracts each field and writes it back to the actor struct.

**State field updates in TIR/compiled code** (`lib/tir/lower.ml:778–856`):
- Handler functions receive the actor struct pointer as the first implicit parameter
- Each state field is loaded via `EField` at handler entry
- A synthetic record expression binding `state` to these loaded fields is created
- Handler body executes with `state` in scope
- Result fields are written back via `EReuse` (in-place update)

### Field Access from Outside

**get_actor_field**: Read a named field from an actor's state without sending a message

```march
get_actor_field(counter_pid, "value")  (* returns Some(field_value) or None *)
```

**actor_get_int**: Drain the mailbox, then read an integer state field by index

```march
actor_get_int(counter_pid, 0)  (* field 0 = first alphabetical state field *)
```

Waits for the mailbox to empty before reading, ensuring all pending messages are processed.

**Line references**:
- **Interpreter**: `lib/eval/eval.ml:1091–1105` (`get_actor_field`), `lib/eval/eval.ml:1085–1090` (`mailbox_size`)
- **Runtime C**: `runtime/march_runtime.c:421–433` (`march_actor_get_int`)

---

## Mailbox Implementation

### Queue Structure

The mailbox is a **lock-free multi-producer/single-consumer queue** based on Michael-Scott algorithm, implemented using OCaml 5's atomic operations.

**Data structure** (`lib/scheduler/mailbox.ml:4–16`):
```ocaml
type 'a node = {
  value : 'a option;
  next  : 'a node option Atomic.t;
}

type 'a t = {
  head : 'a node Atomic.t;
  tail : 'a node Atomic.t;
}
```

**Operations**:
- **push**: Multi-producer-safe; multiple threads can enqueue simultaneously
- **pop**: Single-consumer; only the actor's handler thread pops
- **is_empty**: Check without popping

**Key invariants**:
- A sentinel node is created at initialization; the actual queue starts behind it
- The tail pointer is always at or behind the head
- CAS operations ensure no messages are lost even under contention

**Implementation details** (`lib/scheduler/mailbox.ml`):
- `push` (lines 18–32): CAS loop to append new node
- `pop` (lines 34–44): CAS loop to advance head pointer
- `is_empty` (lines 46–48): Check if head's next is None

**Interpreter actor instance storage** (`lib/eval/eval.ml:55`):
```ocaml
mutable ai_mailbox : value Queue.t;  (* pending Down/Crashed messages *)
```

In the interpreter, mailboxes use a standard OCaml `Queue.t` for simplicity.

---

## Scheduler Architecture

The March runtime uses a **cooperative scheduler with reduction-counted preemption** in the interpreter and a **thread-pool-based scheduler** in compiled code.

### Interpreter Scheduler (Reduction-Counted)

**Design** (`lib/scheduler/scheduler.ml`):

- Each actor gets a budget of `max_reductions = 4000` reductions per quantum
- A "reduction" is one function application, pattern match, or message send (tracked by `check_reductions()`)
- When the budget is exhausted, the scheduler preempts and moves to the next actor in the run queue
- Actors in `PWaiting` state are not scheduled until a message arrives

**State machine** (`lib/scheduler/scheduler.ml:32–37`):
```ocaml
type proc_state =
  | PReady      (* In run queue, ready to execute *)
  | PRunning    (* Currently executing *)
  | PWaiting    (* Blocked on message; out of queue *)
  | PDone       (* Finished normally *)
  | PDead of string  (* Crashed *)
```

**Run queue** (`lib/scheduler/scheduler.ml:46–72`):
- FIFO queue of ready processes
- Waiting list for blocked processes
- `enqueue`, `dequeue`, `park`, `wake` operations

**Reduction context** (`lib/scheduler/scheduler.ml:10–28`):
- `remaining`: budget remaining in current quantum
- `yielded`: true if preempted
- `tick()`: decrement budget, return true if exhausted
- `reset_budget()`: restore budget for next quantum

**Invocation** (`lib/eval/eval.ml:256`):
- `check_reductions()` called at every yield point: `EApp`, `EMatch`, `ESend`
- Raises `Preempted` exception if budget is exhausted
- Scheduler catches exception, saves current continuation, reschedules

### Compiled Scheduler (Thread Pool)

**Design** (`runtime/march_runtime.c:225–331`):

- Fixed thread pool of worker threads (default: `MARCH_SCHEDULER_THREADS = 4`)
- Global run queue protected by mutex + condition variable
- Each process has a mailbox, alive flag, and dispatch function pointer
- Workers dequeue processes, drain one message, call the dispatch handler

**Process structure** (`runtime/march_runtime.c:213–223`):
```c
typedef struct march_process {
    void               *actor;           /* Actor struct pointer */
    pthread_mutex_t     lock;            /* Protects mailbox */
    pthread_cond_t      idle_cond;       /* Woken when mailbox empty & idle */
    msg_node           *mbox_head;       /* Mailbox queue head */
    msg_node           *mbox_tail;       /* Mailbox queue tail */
    int                 scheduled;       /* Already in run queue */
    int                 processing;      /* Currently executing handler */
    int                 alive;           /* Live flag (kill sets to 0) */
    struct march_process *next_runnable; /* Run queue link */
} march_process;
```

**Scheduler loop** (`runtime/march_runtime.c:272–321`):
1. Dequeue a process (blocks if queue empty)
2. Lock the process; dequeue one message
3. If alive, read dispatch function and handler arguments from actor struct
4. Force RC=1 temporarily (FBIP: in-place mutation)
5. Call `dispatch(actor, msg)`
6. Restore RC, check for more messages
7. If messages remain, re-enqueue; otherwise park

**Key properties**:
- Multiple messages processed per worker context switch (batch scheduling for throughput)
- Handlers are synchronous but non-blocking (can send to other actors)
- Messages to a dead actor are dropped before dequeuing

> **Update (March 20, 2026, Track C):** The scheduler now processes multiple messages per cycle instead of one, fixing a starvation issue where high-throughput actors incurred excessive queue management overhead. The `scheduled` flag race condition (H1 in correctness audit) has been fixed — messages are no longer silently lost when a sender and worker thread race on the scheduling decision. All changes passed ThreadSanitizer validation.

**Configuration**:
- `MARCH_SCHEDULER_THREADS` can be set at compile time
- Default 4 threads; tunable for workload

---

## Compilation Path

### Interpreter vs. Compiled

**Interpreter (`lib/eval/eval.ml`)**:
- Tree-walking evaluation of actor declarations
- Global `actor_registry : (int, actor_inst) Hashtbl.t` stores all actor instances
- Handlers dispatch via `run_scheduler` hook which iteratively pops from the run queue
- Fully functional, used for REPL and testing

**Compiled (`lib/tir/lower.ml` + `runtime/march_runtime.c`)**:
- Actor declarations lower to TIR: message variant type + actor struct + spawn/dispatch/handler functions
- Spawning allocates the actor struct and wraps it in a process handle
- Sending enqueues a message; the scheduler dispatches it
- Currently **not yet implemented** for full compilation (planned Phase 2)

### Lowering (Planned)

See `specs/actor-lowering.md` for detailed lowering strategy. Summary:

For each actor `Name`:
1. **Message type** — `Name_Msg` variant with one constructor per handler
2. **Actor struct** — `Name_Actor` record with dispatch ptr + alive flag + state fields (alphabetical)
3. **Handler functions** — `Name_MsgName(actor: ptr, params...)` for each handler
4. **Dispatch function** — `Name_dispatch(actor: ptr, msg: ptr)` switches on message tag
5. **Spawn function** — `Name_spawn() : ptr` allocates and initializes the actor struct

**Key lowering transformations** (`lib/tir/lower.ml:395–417`):
- `ESpawn(Counter)` → `EApp(Counter_spawn, [])`
- `ESend(pid, msg)` → `EApp(march_send, [pid, msg])`
- Handler body lowering: state is synthetic record reading fields from actor struct
- After body: fields written back via `EReuse` (in-place update)

---

## Capability System

The March actor system includes **epoch-based capabilities** for security and resource tracking. This is partially implemented; some features are stubbed.

### Capability Model

A **capability** is a cryptographic proof of authority to interact with an actor. Capabilities are represented as `(pid, epoch)` pairs:
- `pid`: the actor's process ID
- `epoch`: a monotonically increasing version number incremented each time the actor restarts

### Implemented Features

1. **get_cap** — Obtain the current capability for an actor

```march
let cap = get_cap(my_pid)  (* returns VCap(pid, epoch) *)
```

**Line reference**: `lib/eval/eval.ml:1147–1160`

2. **cap_to_pid** — Extract the Pid from a capability (revokes version info)

```march
let pid = cap_to_pid(cap)
```

**Line reference**: `lib/eval/eval.ml:1161–1166`

3. **Epoch tracking** — Each actor instance has an `ai_epoch` field incremented on restart

**Line reference**: `lib/eval/eval.ml:60` (actor instance definition)

### Stubbed Features

- **Revocation checking**: `send(cap, msg)` does **not** currently validate the epoch against a revocation list. This is stubbed in Phase 1 and will be fully implemented in Phase 3.
- **Capability-based authorization**: Access control based on capability possession is planned but not enforced.

**Design**: `specs/features/actor-system.md` (capability system section)

---

## Supervision and Monitoring

The actor system includes infrastructure for **supervision trees** (fault tolerance) and **monitoring** (observability). Both are partially implemented.

### Supervision (Phase 2)

A **supervisor actor** manages child actors and can restart them if they crash.

```march
actor Supervisor do
  supervise [Counter, Logger]
  state { counter : Pid, logger : Pid }
  init spawn children and inject their Pids

  on ChildDown(pid : Pid, reason : Atom) do
    (* Handle restart logic *)
  end
end
```

**Line references**:
- **AST**: `lib/ast/ast.ml:216` (`actor_supervise` field)
- **Spawning supervisor children**: `lib/eval/eval.ml:2481–2528` (in `ESpawn` handler)
- **Supervisor restart logic**: `lib/eval/eval.ml:515–570` (`supervise_actor` function)

**Current implementation**:
- Supervisors can declare child actors in the `supervise [...]` clause
- Children are spawned with `ai_supervisor` pointing to the parent
- When a child crashes, the supervisor can be restarted (if max restarts not exceeded)
- Restart policies (max restarts in time window) are tracked but not fully enforced

### Monitoring (Phase 1)

A **monitor** is a one-way watcher installed on an actor. When the monitored actor dies, the monitoring actor receives a `Down` message.

```march
let mon_ref = monitor(watcher_pid, target_pid)
send(watcher_pid, Down(target_pid))  (* Sent when target dies *)
demonitor(mon_ref)                   (* Remove the monitor *)
```

**Line references**:
- **Monitor installation**: `lib/eval/eval.ml:746–778` (`monitor_actor` function)
- **Demonitor**: `lib/eval/eval.ml:779–800` (`demonitor_actor` function)
- **Builtin wrappers**: `lib/eval/eval.ml:1075–1081`

**Current implementation**:
- Monitors are registered as `(monitor_ref, watcher_pid)` pairs in `ai_monitors`
- When an actor crashes, Down messages are enqueued to all watchers
- Monitoring is fully functional in the interpreter

### Linking (Phase 1)

**Links** are bidirectional; if either linked actor dies, both receive an `Exit` message.

```march
link(actor_a, actor_b)
dounlink(actor_a, actor_b)
```

**Line references**:
- **Link installation**: `lib/eval/eval.ml:801–828` (`link_actors` function)
- **Unlink**: `lib/eval/eval.ml:829–847` (`unlink_actors` function)
- **Builtin wrapper**: `lib/eval/eval.ml:1082–1084`

**Current implementation**:
- Links are bidirectional lists of Pids in `ai_links`
- When an actor dies, Exit messages are sent to all linked actors
- Linking is fully functional in the interpreter

---

## Data Structures and Key Types

### Actor Instance (`lib/eval/eval.ml:46–64`)

```ocaml
type actor_inst = {
  ai_name    : string;                        (* Actor type name *)
  ai_def     : actor_def;                     (* Definition from AST *)
  ai_env_ref : env ref;                       (* Module env at spawn *)
  mutable ai_state    : value;                (* Current state value *)
  mutable ai_alive    : bool;                 (* Live flag *)
  mutable ai_monitors : (int * int) list;     (* (ref, watcher_pid) *)
  mutable ai_links    : int list;             (* linked actor pids *)
  mutable ai_mailbox  : value Queue.t;        (* pending messages *)
  mutable ai_supervisor : int option;         (* supervising pid *)
  mutable ai_restart_count : (float * int) list;  (* restart history *)
  mutable ai_epoch    : int;                  (* restart epoch *)
  mutable ai_resources : (string * (unit -> unit)) list;  (* cleanup handlers *)
}
```

### Global Registries (`lib/eval/eval.ml:67–70`)

```ocaml
let actor_defs_tbl : (string, actor_def * env ref) Hashtbl.t = Hashtbl.create 8
let actor_registry : (int, actor_inst) Hashtbl.t = Hashtbl.create 16
let next_pid : int ref = ref 0
```

- `actor_defs_tbl`: Registers all declared actor types (reset per module eval)
- `actor_registry`: Maps Pid → live actor instance (reset per module eval)
- `next_pid`: Counter for assigning fresh Pids

### Value Types (`lib/eval/eval.ml:21–37`)

```ocaml
type value =
  | VInt of int
  | VFloat of float
  | VString of string
  | VBool of bool
  | VAtom of string
  | VUnit
  | VTuple of value list
  | VRecord of (string * value) list
  | VCon of string * value list      (* Constructor messages *)
  | VClosure of env * string list * expr
  | VBuiltin of string * (value list -> value)
  | VPid of int                      (* Actor identity *)
  | VTask of int                     (* Task handle *)
  | VWorkPool                        (* Work-stealing capability *)
  | VCap of int * int                (* Epoch-stamped capability *)
  | VActorId of int                  (* Opaque actor id *)
```

### Reduction Budget (`lib/scheduler/scheduler.ml:10–28`)

```ocaml
type reduction_ctx = {
  mutable remaining : int;
  mutable yielded   : bool;
}

let max_reductions = 4_000
```

---

## Runtime C Functions

### march_spawn

**Signature**: `void *march_spawn(void *actor)`

**Purpose**: Create a process wrapper around an actor struct, initialize the scheduler, and return a handle.

**Implementation** (`runtime/march_runtime.c:341–360`):
1. Allocate a `march_process` struct
2. Store actor pointer and initialize locks/condition variables
3. Increment actor RC (process owns a reference)
4. Allocate a handle object (16+8 bytes for header + process pointer)
5. Store process pointer in handle's field [2]
6. Return handle

**Handle layout**:
```
offset 0  : i64   rc           (reference count)
offset 8  : i32   tag+pad      (header)
offset 16 : i64*  process_ptr  (cast to int64)
```

### march_send

**Signature**: `void *march_send(void *handle, void *msg)`

**Returns**: `Some(())` on success, `None` if actor is dead.

**Implementation** (`runtime/march_runtime.c:364–402`):
1. Extract process pointer from handle (field [2])
2. Lock process
3. Check alive flag; if dead, unlock and return `None`
4. Append message to mailbox queue (FIFO)
5. If not already scheduled, enqueue process to global run queue and signal workers
6. Unlock and return `Some(())`

> **Update (March 20, 2026, Track C):** `march_send` no longer increments message RC. The previous double-increment (once by Perceus, once by `march_send`) caused every sent message to leak its payload. Perceus now handles the full ownership transfer.

**Message node structure** (`runtime/march_runtime.c:208–211`):
```c
typedef struct msg_node {
    void              *msg;
    struct msg_node   *next;
} msg_node;
```

### march_kill

**Signature**: `void march_kill(void *handle)`

**Implementation** (`runtime/march_runtime.c:406–412`):
1. Extract process pointer
2. Lock process
3. Set alive flag to 0
4. Broadcast condition variable to wake any waiting threads
5. Unlock

Note: Does **not** deallocate; reference counting handles that.

### march_is_alive

**Signature**: `int64_t march_is_alive(void *handle)`

**Returns**: 1 if alive, 0 if dead.

**Implementation** (`runtime/march_runtime.c:416–419`):
1. Extract process pointer
2. Return alive flag

### march_actor_get_int

**Signature**: `int64_t march_actor_get_int(void *handle, int64_t index)`

**Purpose**: Drain the mailbox, then read an integer state field.

**Implementation** (`runtime/march_runtime.c:423–433`):
1. Extract process pointer
2. Lock process
3. Wait (with condition variable) until mailbox empty and processing done
4. Index into actor struct's state fields: `fields[4 + index]` (fields 0–1 are dispatch and alive)
5. Return value

**Field offsets**:
- Field 0 (offset 16): dispatch function pointer
- Field 1 (offset 24): alive flag (i64)
- Field 2+ (offset 32+): state fields in alphabetical order

---

## Test Coverage

### Interpreter Tests (`test/test_march.ml`)

**Actor handler tests** (lines 1544–1628):
- `test_actor_handler_extra_field` — Reject handlers returning records with extra fields
- `test_actor_handler_missing_field` — Reject handlers returning records with missing fields
- `test_actor_handler_correct` — Correct state update through handler

**Actor list tests** (lines 1817–1845):
- `test_list_actors_empty` — Empty registry returns empty list
- `test_list_actors_alive` — Filters to alive actors only
- `test_list_actors_sorted` — Returns actors sorted by Pid

**Actor snapshot/restore** (lines 2026–2035):
- `test_actor_snapshot` — Snapshot captures current state; restore returns to clean state

### Example Programs

1. **examples/actors.march** (113 lines)
   - Demonstrates Counter and Logger actors
   - Shows spawn, send, kill, drop semantics
   - Supervisor pattern with child restart
   - Message wrapping with safe_send

2. **test_actor.march** (42 lines)
   - Simple Counter actor with Increment/Decrement handlers
   - Demonstrates `actor_get_int` for synchronous state inspection
   - Shows drop semantics on killed actor

3. **test_server_actor.march** (31 lines)
   - HTTP server integrating an actor
   - Actor state accessed from HTTP handler via `actor_get_int`

---

## Known Limitations and TODO

### Phase 1 (Current — Interpreter Only)

- ✅ Spawn, send, kill, is_alive (fully functional)
- ✅ Message dispatch, handlers, state update
- ✅ Monitoring and linking (functional in interpreter)
- ✅ Supervision (partial: spawn children, track restarts, no action on crash)
- 🔄 Capabilities (typed but epoch validation stubbed)
- ⚠️  Receive (can pop next message but no true blocking; requires async Phase 4)
- ❌ TIR lowering (actor declarations dropped)
- ❌ LLVM compilation (no native code generation)

### Phase 2 (Planned)

- [ ] Full TIR lowering (message types, actor structs, handler functions, dispatch)
- [ ] LLVM code generation and native compilation
- [ ] Compiled scheduler operation
- [ ] Performance benchmarks vs. interpreter

### Phase 3 (Planned)

- [ ] Epoch-based capability revocation checking
- [ ] Weak references for cycle breaking
- [ ] Supervisor restart policies (exponential backoff, max restarts)
- [ ] Crash reason tracking and reporting

### Phase 4 (Future)

- [ ] Asynchronous receive (true blocking receive with scheduler support)
- [ ] Multi-threaded async scheduler (not reduction-based)
- [ ] Remote actors (networked message passing)
- [ ] Session types (protocol validation against actors)

### Known Issues

1. **Circular references**: Two actors holding Pid references to each other create a cycle that RC cannot collect. Workaround: explicit `kill` before dropping. Fix: weak references (deferred).

2. **Supervisor state field injection**: When spawning a supervisor, child Pids are injected into the state record. Fields named differently in the definition are added as extras. This works but is error-prone.

3. **Type safety in handlers**: No static guarantee that handler returns the correct state record type. Type-checking passes this check, but runtime exceptions occur on mismatch. Interpreter rejects via `eval_error`.

---

## Source Files Reference

### Core System

| File | Lines | Purpose |
|---|---|---|
| `lib/ast/ast.ml` | 130, 212–225 | `DActor`, `actor_def`, `actor_handler` types |
| `lib/eval/eval.ml` | 46–70, 101–103, 1063–1166, 2469–2559 | Actor instances, registries, builtins, spawn/send/kill |
| `lib/scheduler/scheduler.ml` | 1–73 | Cooperative scheduler, reduction counting, proc states |
| `lib/scheduler/mailbox.ml` | 1–48 | Lock-free queue (Michael-Scott) |
| `lib/scheduler/task.ml` | 1–29 | Task representation |
| `lib/scheduler/work_pool.ml` | 1–110 | Work-stealing pool (Chase-Lev deques) |

### Lowering and Compilation

| File | Lines | Purpose |
|---|---|---|
| `lib/tir/lower.ml` | 395–417, 708–856 | Actor lowering (planned), handler function generation |
| `lib/tir/llvm_emit.ml` | TBD | LLVM emission (planned) |

### Runtime

| File | Lines | Purpose |
|---|---|---|
| `runtime/march_runtime.h` | 43–51 | Actor function declarations |
| `runtime/march_runtime.c` | 200–433 | Process structure, scheduler, march_spawn/send/kill/is_alive |

### Examples and Tests

| File | Lines | Purpose |
|---|---|---|
| `examples/actors.march` | 1–113 | Counter/Logger demo with supervision |
| `test_actor.march` | 1–42 | Simple Counter actor example |
| `test_server_actor.march` | 1–31 | Actor integrated with HTTP server |
| `test/test_march.ml` | 1544–2035 | Actor handler, list, snapshot tests |

### Documentation

| File | Purpose |
|---|---|
| `specs/actor-lowering.md` | Detailed lowering strategy and object layout |
| `specs/features/scheduler.md` | Scheduler architecture and design |
| `specs/features/actor-system.md` | Capability system (see Capability System section) |

---

## Performance Characteristics

### Interpreter

- **Spawn**: O(1) hashtable insert + env capture
- **Send**: O(1) queue push + scheduler enqueue
- **Kill**: O(1) state flag update
- **Receive**: O(1) queue pop
- **Scheduling overhead**: ~1% per reduction check (inline branch)

### Compiled (Planned)

- **Spawn**: O(1) allocation + RC increment
- **Send**: O(1) mailbox push + process enqueue (CAS-based lock-free)
- **Kill**: O(1) flag update + broadcasts
- **Dispatch**: O(log handlers) switch table lookup
- **Context switch**: One message per worker preemption (fair scheduling)

---

## Design Rationale

### Why Synchronous Dispatch in Interpreter?

The interpreter's scheduler handles preemption via reduction counting and exception-based control flow. True asynchronous scheduling (blocking receive, event-driven) requires a different threading model and is deferred to Phase 4. For now, `receive()` is a simple queue pop that errors if empty—suitable for REPL exploration and simple examples.

### Why Lock-Free Mailbox?

The Michael-Scott queue is used for performance in compiled code. The interpreter uses a simple `Queue.t` for simplicity. The compiled scheduler spawns multiple worker threads, so a lock-free queue avoids contention on send paths.

### Why Epoch-Based Capabilities?

Epochs allow revocation of a Pid without deallocating the actor (RC still owns it). A revocation list tracks dead epochs; capability checks compare `(pid, epoch)` against the list. This enables secure message passing and prevents use-after-free exploits in an adversarial setting.

### Why State Fields Alphabetical?

Alphabetical ordering of state fields ensures stable field indices for LLVM GEP operations and allows the TIR lowering to generate consistent code. The order is normalized at parsing time; the user-visible order is preserved in error messages and inspection, but the compiled layout is always alphabetical.

---

## Glossary

- **Actor**: An isolated computational unit with state, identity (Pid), and message handlers
- **Capability**: A `(Pid, epoch)` pair granting authority to interact with an actor
- **Dispatch**: Function that switches on message tag and calls the appropriate handler
- **Drop semantics**: Messages sent to dead actors are silently discarded
- **Epoch**: A version number of an actor (incremented on restart)
- **Handler**: A function that processes a message type and returns new state
- **Link**: A bidirectional connection; if one dies, both receive Exit messages
- **Mailbox**: Queue of pending messages for an actor
- **Monitor**: A one-way watcher; sends Down message when target dies
- **Pid**: Process identifier (unique integer assigned at spawn)
- **Preemption**: Interrupting execution to let other actors run
- **Reduction**: One function application, pattern match, or send (unit of work)
- **Spawn**: Create a new actor instance
- **State**: The mutable data of an actor (a record type)
- **Supervision**: A pattern where one actor manages restart of child actors
