# Supervision Trees Implementation Plan

**Date:** 2026-03-19
**Status:** Draft
**Depends on:** actors (implemented), scheduler framework (partially implemented), epochs-design.md, scheduler-design.md

## What Exists Today

### Implemented and Working
| Component | Location | Status |
|-----------|----------|--------|
| Actor spawn/send/kill/is_alive | `lib/eval/eval.ml:1584-1667` | Synchronous dispatch, global `actor_registry` |
| Actor AST/parser | `lib/ast/ast.ml:130,191-201`, `lib/parser/parser.mly:166-181` | `DActor`, `ESend`, `ESpawn`, handler syntax |
| Actor TIR lowering | `lib/tir/lower.ml:518-802` | Complete: dispatch fn, message variant type, FBIP state |
| Reduction counting | `lib/scheduler/scheduler.ml:1-29` | `max_reductions=4000`, `tick()`, `yielded` flag |
| Run queues | `lib/scheduler/scheduler.ml:46-73` | FIFO with enqueue/dequeue/park/wake |
| Proc state machine | `lib/scheduler/scheduler.ml:32-44` | PReady/PRunning/PWaiting/PDone/PDead |
| Chase-Lev deques | `lib/scheduler/work_pool.ml:8-84` | Lock-free push/pop/steal with CAS |
| Work-stealing pool | `lib/scheduler/work_pool.ml:86-110` | N-worker deque array, submit/try_steal |
| Lock-free mailbox | `lib/scheduler/mailbox.ml` | Michael-Scott MPSC queue |
| Task types | `lib/scheduler/task.ml` | task_id, status, tier (Cooperative/WorkStealing) |
| Task builtins (interpreter) | `lib/eval/eval.ml:1533-1598` | Eager eval: task_spawn, task_await, task_await_unwrap |
| Task builtins (compiled) | `lib/tir/llvm_emit.ml` | Inline LLVM IR: closure call + box/unbox |

### Not Implemented
| Component | Spec location | Notes |
|-----------|--------------|-------|
| Async actor messaging | scheduler-design.md | Currently synchronous; needs mailbox integration |
| Actual scheduler loop | scheduler-design.md | Run queue + reduction counting exist but aren't wired |
| Supervision trees | epochs-design.md §3 | No supervisor actors, no restart strategies |
| Monitors / Down messages | epochs-design.md §4 | No monitor/demonitor builtins |
| Task linking | scheduler-design.md | No spawn_link, no crash propagation |
| Epochs / LiveCap | epochs-design.md §1 | No epoch tracking on capabilities |
| Drop handlers | epochs-design.md §2 | No linear cleanup on crash |
| Sendable enforcement | scheduler-design.md | No cross-thread closure validation |

---

## Implementation Phases

The key insight is that supervision can be built **incrementally** on the existing synchronous interpreter without requiring true multi-threaded scheduling. The interpreter already has actors with state, a registry, and synchronous dispatch. We can add supervision semantics on top of this single-threaded foundation, then later wire in the async scheduler.

### Phase 1: Monitors and Links (Foundation)

**Goal:** Actors can observe each other's deaths. When an actor dies (via `kill` or crash), monitors receive `Down` messages and linked actors are killed.

#### 1.1 Monitor Registry

**Files:** `lib/eval/eval.ml`

Add to the actor instance:

```ocaml
type monitor_ref = int  (* unique ID *)

type actor_inst = {
  pid          : int;
  mutable ai_state    : value;
  mutable ai_alive    : bool;
  ai_handlers  : (string * string list * expr) list;
  ai_env_ref   : env ref;
  ai_def       : actor_def;
  (* NEW *)
  mutable ai_monitors : (monitor_ref * int (* watcher pid *)) list;
  mutable ai_links    : int list;  (* bidirectional *)
  mutable ai_mailbox  : value Queue.t;  (* for async Down delivery *)
}
```

The `ai_monitors` list records `(monitor_ref, watcher_pid)` pairs. When this actor dies, each watcher gets a `Down(monitor_ref, reason)` message.

#### 1.2 Monitor/Demonitor Builtins

Add to `base_env` in eval.ml:

```ocaml
(* monitor(pid) → MonitorRef *)
("monitor", VBuiltin ("monitor", function
  | [VInt target_pid] ->
    let mon_ref = fresh_monitor_id () in
    (match Hashtbl.find_opt actor_registry target_pid with
     | Some inst ->
       inst.ai_monitors <- (mon_ref, current_actor_pid ()) :: inst.ai_monitors;
       VInt mon_ref
     | None ->
       (* Already dead — immediately queue Down *)
       VInt mon_ref)
  | _ -> eval_error "monitor: expected pid"))

(* demonitor(mon_ref) → Unit *)
("demonitor", VBuiltin ("demonitor", function
  | [VInt mon_ref] ->
    Hashtbl.iter (fun _ inst ->
      inst.ai_monitors <- List.filter (fun (m, _) -> m <> mon_ref) inst.ai_monitors
    ) actor_registry;
    VUnit
  | _ -> eval_error "demonitor: expected monitor ref"))
```

#### 1.3 Link Builtins

```ocaml
(* link(pid_a, pid_b) — bidirectional link *)
("link", VBuiltin ("link", function
  | [VInt a; VInt b] ->
    (match Hashtbl.find_opt actor_registry a, Hashtbl.find_opt actor_registry b with
     | Some ia, Some ib ->
       ia.ai_links <- b :: ia.ai_links;
       ib.ai_links <- a :: ib.ai_links;
       VUnit
     | _ -> eval_error "link: both actors must be alive")
  | _ -> eval_error "link: expected 2 pids"))
```

#### 1.4 Death Notification

Modify `kill` to trigger the crash sequence:

```ocaml
let crash_actor pid reason =
  match Hashtbl.find_opt actor_registry pid with
  | None -> ()
  | Some inst when not inst.ai_alive -> ()
  | Some inst ->
    inst.ai_alive <- false;
    (* Step 1: Queue Down messages to all monitors *)
    List.iter (fun (mon_ref, watcher_pid) ->
      match Hashtbl.find_opt actor_registry watcher_pid with
      | Some watcher when watcher.ai_alive ->
        Queue.push (VCon ("Down", [VInt mon_ref; VString reason])) watcher.ai_mailbox
      | _ -> ()
    ) inst.ai_monitors;
    (* Step 2: Kill linked actors (crash propagation) *)
    List.iter (fun linked_pid ->
      crash_actor linked_pid (Printf.sprintf "linked to %d which crashed: %s" pid reason)
    ) inst.ai_links
```

#### 1.5 Tests

```
test "monitor receives Down on kill"
  — spawn A, spawn B, B monitors A, kill A → B's mailbox has Down

test "demonitor prevents Down delivery"
  — spawn A, spawn B, B monitors A, B demonitors, kill A → B's mailbox empty

test "link kills both on crash"
  — spawn A, spawn B, link(A, B), kill A → B is also dead

test "monitor on already-dead actor delivers Down immediately"
  — spawn A, kill A, monitor A → Down queued immediately

test "multiple monitors on same actor all fire"
  — spawn A, B monitors A, C monitors A, kill A → both B and C get Down
```

---

### Phase 2: Supervisor Actor Pattern

**Goal:** A supervisor actor can declare children, receive `Crashed` messages, and restart them. Implements `one_for_one` strategy first.

#### 2.1 AST Extensions

**Files:** `lib/ast/ast.ml`, `lib/parser/parser.mly`

```ocaml
(* ast.ml — extend actor_def *)
type supervise_field = {
  sf_name : string located;
  sf_ty   : ty;
}

type restart_strategy = OneForOne | OneForAll | RestForOne

type supervise_config = {
  sc_fields   : supervise_field list;
  sc_strategy : restart_strategy;
  sc_max_restarts : int;
  sc_window_secs  : float;
  sc_order    : string located list option;  (* for rest_for_one *)
}

(* Extend actor_def *)
type actor_def = {
  actor_name     : string located;
  actor_state    : (string located * ty) list;
  actor_init     : expr;
  actor_handlers : actor_handler list;
  actor_supervise : supervise_config option;  (* NEW *)
}
```

**Parser syntax:**

```march
actor MySupervisor do
  supervise do
    worker_id  : ActorId(Worker)
    worker_cap : LiveCap(Worker)
  end

  strategy one_for_one
  max_restarts 3 within 5

  on Crashed(id, reason) do
    let (new_id, new_cap) = restart(state.worker_id)
    { worker_id = new_id, worker_cap = new_cap }
  end
end
```

Parser additions:
- `SUPERVISE` token
- `STRATEGY` token
- `MAX_RESTARTS`, `WITHIN` tokens
- `supervise_block` rule: `SUPERVISE DO supervise_fields END`
- `strategy_decl` rule: `STRATEGY strategy_name`
- `max_restarts_decl` rule: `MAX_RESTARTS INT WITHIN INT`
- `supervise_field` rule: `IDENT COLON type_expr`

#### 2.2 Supervisor Runtime (Interpreter)

**Files:** `lib/eval/eval.ml`

A supervisor is an actor with extra machinery:

1. **On spawn:** The supervisor auto-spawns its children (from the `init` block), monitors them all, and stores `(ActorId, LiveCap)` pairs in its state.

2. **On child crash:** The runtime delivers `Crashed(actor_id, reason)` to the supervisor's mailbox (same as how `Down` works for monitors, but supervisor-specific). The supervisor's `on Crashed` handler runs and returns a full replacement state.

3. **`restart(actor_id)` builtin:** Re-spawns the actor definition, increments epoch, returns `(new_id, new_cap)`.

```ocaml
(* Supervisor-aware kill *)
let crash_actor pid reason =
  match Hashtbl.find_opt actor_registry pid with
  | Some inst when inst.ai_alive ->
    inst.ai_alive <- false;
    (* Step 1: Down to monitors *)
    deliver_down_messages inst pid reason;
    (* Step 2: Crashed to supervisor (if supervised) *)
    (match inst.ai_supervisor with
     | Some sup_pid ->
       (match Hashtbl.find_opt actor_registry sup_pid with
        | Some sup when sup.ai_alive ->
          (* Deliver Crashed message and run handler *)
          run_supervisor_crashed_handler sup pid reason
        | _ -> ())
     | None -> ());
    (* Step 3: Kill linked actors *)
    propagate_links inst pid reason
  | _ -> ()
```

#### 2.3 Restart Strategies

**`one_for_one`:** Only restart the crashed child.

```ocaml
let restart_one_for_one supervisor crashed_pid reason =
  let handler = find_crashed_handler supervisor in
  let new_state = eval_handler handler supervisor.ai_state crashed_pid reason in
  supervisor.ai_state <- new_state
```

**`one_for_all`:** Kill all children, restart all.

```ocaml
let restart_one_for_all supervisor crashed_pid reason =
  (* Kill all other children *)
  List.iter (fun child_pid ->
    if child_pid <> crashed_pid then
      crash_actor child_pid "one_for_all restart"
  ) (get_supervised_children supervisor);
  (* Run on Crashed handler — returns full replacement state *)
  let new_state = eval_handler handler supervisor.ai_state crashed_pid reason in
  supervisor.ai_state <- new_state
```

**`rest_for_one`:** Kill children after the crashed one in declared order, restart forward.

```ocaml
let restart_rest_for_one supervisor crashed_pid reason order =
  let after_crashed = drop_until (fun id -> id = crashed_pid) order in
  (* Kill in reverse order *)
  List.iter (fun child_pid ->
    crash_actor child_pid "rest_for_one restart"
  ) (List.rev after_crashed);
  (* Run on Crashed handler *)
  let new_state = eval_handler handler supervisor.ai_state crashed_pid reason in
  supervisor.ai_state <- new_state
```

#### 2.4 Max Restarts Windowing

```ocaml
type restart_history = {
  mutable timestamps : float list;
  max_restarts : int;
  window_secs  : float;
}

let check_restart_allowed history =
  let now = Unix.gettimeofday () in
  let recent = List.filter (fun t -> now -. t < history.window_secs) history.timestamps in
  history.timestamps <- recent;
  if List.length recent >= history.max_restarts then
    false  (* exceeded — supervisor should crash *)
  else begin
    history.timestamps <- now :: history.timestamps;
    true
  end
```

When `check_restart_allowed` returns false, the supervisor itself crashes, propagating to its own supervisor (escalation).

#### 2.5 Tests

```
test "supervisor restarts crashed child (one_for_one)"
  — supervisor with one worker, kill worker → worker respawned, supervisor state updated

test "supervisor max_restarts escalation"
  — supervisor with max_restarts=2 within 10, crash child 3 times → supervisor itself crashes

test "one_for_all kills all children"
  — supervisor with A, B, C; crash B → A, B, C all restarted

test "rest_for_one kills downstream only"
  — supervisor with [A, B, C]; crash B → C killed and restarted, A untouched

test "on Crashed returns full replacement state"
  — verify supervisor state is fully replaced, not spread-updated

test "supervisor escalation propagates to parent supervisor"
  — nested supervisors, inner exceeds max_restarts → outer receives Crashed
```

---

### Phase 3: Epochs and Capability Tracking

**Goal:** `Cap(A, epoch)` tracks actor generations. Stale caps surface as `DeadActor` at send time. `LiveCap` stays current across restarts.

#### 3.1 Epoch Counter

**Files:** `lib/eval/eval.ml`

```ocaml
type actor_inst = {
  ...
  mutable ai_epoch : int;  (* increments on restart *)
}

(* Cap is (pid, epoch) *)
(* LiveCap is a mutable ref to (pid, current_epoch), only in supervisor state *)
```

Values:
- `VCap (pid, epoch)` — epoch-stamped capability (non-linear, freely copyable)
- `VActorId pid` — stable identity (survives restarts)
- `VLiveCap (pid, epoch_ref)` — supervisor-managed, runtime-updated ref

#### 3.2 Spawn Returns (ActorId, Cap)

Change `spawn` to return a pair:

```ocaml
(* spawn(WorkerDef) → (ActorId, Cap) *)
let pid = fresh_pid () in
let epoch = 0 in
...
VTuple [VActorId pid; VCap (pid, epoch)]
```

#### 3.3 Epoch-Checked Send

```ocaml
(* send(cap, msg) → Result(Unit, DeadActor) *)
| [VCap (pid, cap_epoch); msg] ->
  (match Hashtbl.find_opt actor_registry pid with
   | Some inst when inst.ai_alive && inst.ai_epoch = cap_epoch ->
     (* dispatch message *)
     VCon ("Ok", [VUnit])
   | Some inst when inst.ai_alive ->
     (* epoch mismatch — actor was restarted *)
     VCon ("Err", [VCon ("StaleEpoch", [])])
   | _ ->
     VCon ("Err", [VCon ("DeadActor", [])]))
```

#### 3.4 Restart Increments Epoch

```ocaml
let restart_actor actor_id =
  match find_actor_by_id actor_id with
  | Some inst ->
    let new_epoch = inst.ai_epoch + 1 in
    let new_inst = spawn_fresh inst.ai_def in
    new_inst.ai_epoch <- new_epoch;
    (VActorId new_inst.pid, VCap (new_inst.pid, new_epoch))
  | None -> eval_error "restart: actor not found"
```

#### 3.5 LiveCap Auto-Update

When the supervisor's `on Crashed` handler calls `restart(id)`, the returned `LiveCap` reflects the new epoch. The runtime enforces that `LiveCap` can only exist in supervisor `supervise` fields — the typechecker rejects `LiveCap` in normal bindings.

#### 3.6 Tests

```
test "send with stale cap returns StaleEpoch"
  — spawn A (epoch 0), get Cap, restart A (epoch 1), send via old Cap → Err(StaleEpoch)

test "send with current cap succeeds"
  — spawn A (epoch 0), send via Cap → Ok(Unit)

test "restart increments epoch"
  — spawn A, verify epoch=0, restart, verify epoch=1

test "LiveCap tracks current epoch after restart"
  — supervisor restarts child, LiveCap reflects new epoch

test "spawn returns (ActorId, Cap) pair"
  — let (id, cap) = spawn(Worker), verify types

test "DeadActor on send to killed actor"
  — spawn A, kill A, send via Cap → Err(DeadActor)
```

---

### Phase 4: Async Mailbox Dispatch (Wiring the Scheduler)

**Goal:** Actor message dispatch becomes asynchronous. Messages go into mailboxes, the scheduler loop processes them.

This is the biggest change — it moves from synchronous `send` (handler runs inline) to async `send` (message queued, handler runs on next scheduler turn).

#### 4.1 Scheduler Loop

**Files:** `lib/eval/eval.ml`, `lib/scheduler/scheduler.ml`

```ocaml
let rec scheduler_loop (rq : run_queue) =
  match dequeue rq with
  | None -> ()  (* all done *)
  | Some proc ->
    proc.state <- PRunning;
    reset_budget proc.reduction;
    (* Run actor: process one message from mailbox *)
    (match proc.tier with
     | Cooperative ->
       run_actor_one_message proc;
       if proc.state = PRunning then begin
         proc.state <- PReady;
         enqueue rq proc
       end
     | WorkStealing -> ());  (* handled separately *)
    scheduler_loop rq
```

#### 4.2 Async Send

```ocaml
(* send(cap, msg) enqueues instead of dispatching inline *)
| [VCap (pid, epoch); msg] ->
  match Hashtbl.find_opt actor_registry pid with
  | Some inst when inst.ai_alive && inst.ai_epoch = epoch ->
    Queue.push msg inst.ai_mailbox;
    VCon ("Ok", [VUnit])
  | ...
```

#### 4.3 Receive

New builtin for actors to explicitly receive from their mailbox:

```ocaml
(* receive() → blocks until a message arrives *)
(* receive_timeout(ms) → returns None on timeout *)
```

This is a fundamental semantic change — actors go from "handler runs on send" to "handler runs when scheduled and a message is available."

#### 4.4 Tests

```
test "async send queues message"
  — send to actor, verify message in mailbox before handler runs

test "scheduler processes messages round-robin"
  — spawn 3 actors, send messages to all, verify interleaved processing

test "actor blocks on empty mailbox"
  — actor with no messages → moves to wait queue

test "reduction budget exhaustion yields to next actor"
  — spawn actor doing expensive work, verify it yields after 4K reductions
```

---

### Phase 5: Task Linking and Supervision Integration

**Goal:** Tasks participate in the supervision tree. `task_spawn_link` creates linked tasks whose crashes propagate.

#### 5.1 Task Linking Builtins

```ocaml
(* task_spawn_link(fn) → Task(a) — linked to spawning actor *)
("task_spawn_link", VBuiltin ("task_spawn_link", function
  | [thunk] ->
    let parent_pid = current_actor_pid () in
    let task_id = Task.fresh_id () in
    (try
       let result = apply thunk [VInt 0] in
       register_task task_id result;
       VTask task_id
     with exn ->
       (* Task crashed — propagate to parent via link *)
       crash_actor parent_pid (Printexc.to_string exn);
       VTask task_id)
  | _ -> eval_error "task_spawn_link: expected 1 argument"))
```

#### 5.2 Supervised Tasks

Tasks under a supervisor follow the same restart rules as actors:

```march
actor TaskSupervisor do
  supervise do
    cleanup_task : TaskId
  end

  strategy one_for_one
  max_restarts 5 within 60

  on Crashed(id, reason) do
    let new_task = task_spawn_link(fn x -> periodic_cleanup())
    { cleanup_task = new_task }
  end
end
```

Restart policies:
- `:permanent` — always restart (task's thunk is re-invoked)
- `:transient` — restart only on exception (normal return = stay dead)
- `:temporary` — never restart

#### 5.3 Tests

```
test "task_spawn_link propagates crash to parent actor"
  — actor spawns linked task, task crashes → actor receives crash signal

test "supervised task restarts on crash (permanent)"
  — task under supervisor crashes → re-spawned

test "transient task: normal exit no restart"
  — task returns normally → stays dead

test "transient task: crash triggers restart"
  — task throws → restarted
```

---

### Phase 6: Drop Handlers and Linear Cleanup

**Goal:** When an actor crashes, its linear values are cleaned up in reverse acquisition order.

This phase depends on the linear type system being further along. The initial implementation can be simplified:

#### 6.1 Simplified Drop Protocol

For Phase 1, skip full linear tracking. Instead:
- Track OS resources (file handles, sockets) per actor
- On crash, close all OS resources in reverse order
- User-defined `Drop` impls come later when linear types are complete

```ocaml
type actor_inst = {
  ...
  mutable ai_resources : (string * (unit -> unit)) list;  (* (name, cleanup_fn) pairs *)
}

let crash_actor pid reason =
  ...
  (* After Down messages, before restart *)
  List.iter (fun (name, cleanup) ->
    try cleanup ()
    with _ -> Printf.eprintf "warning: drop handler for %s failed\n" name
  ) (List.rev inst.ai_resources);
  ...
```

#### 6.2 Future: Full Linear Drop

When the linear type system is complete:
- Track linear value acquisition order per actor
- `interface Drop(a : linear)` with `fn drop(value : linear a) : Unit`
- `try_send_abort` for session channels
- Reverse acquisition order cleanup in crash sequence

---

## Dependency Graph

```
Phase 1: Monitors & Links
    ↓
Phase 2: Supervisor Pattern ←── depends on monitors for Crashed delivery
    ↓
Phase 3: Epochs & Caps ←── depends on supervisor restart mechanics
    ↓
Phase 4: Async Mailbox ←── can be done in parallel with Phase 3
    ↓
Phase 5: Task Supervision ←── depends on Phases 1-3
    ↓
Phase 6: Drop Handlers ←── depends on linear types (partially independent)
```

Phases 1-3 are the critical path. Phase 4 (async) is a large refactor but orthogonal to supervision semantics. Phase 5 layers on top. Phase 6 can wait for linear types.

## Estimated Scope

| Phase | Files touched | New tests | Effort |
|-------|--------------|-----------|--------|
| 1: Monitors/Links | eval.ml | ~10 | Small — extends existing actor builtins |
| 2: Supervisors | ast.ml, parser.mly, eval.ml | ~10 | Medium — new AST nodes, parser rules, restart logic |
| 3: Epochs | eval.ml, typecheck.ml | ~8 | Medium — new value types, epoch-checked send |
| 4: Async mailbox | eval.ml, scheduler.ml | ~8 | Large — fundamental dispatch model change |
| 5: Task supervision | eval.ml | ~6 | Small — extends task builtins with link/restart |
| 6: Drop handlers | eval.ml, typecheck.ml | ~4 | Medium — depends on linear type progress |

## Open Decisions

1. **Supervisor syntax:** The `supervise do ... end` block is new syntax vs reusing `state { ... }`. The spec uses `supervise`; the alternative is a `@supervisor` annotation on a regular actor. Recommendation: new `supervise` block — it's clearer and enforces the full-state-replacement rule for `on Crashed`.

2. **`receive` semantics:** The current interpreter dispatches handlers synchronously on `send`. Phase 4 introduces `receive`. Should the intermediate phases (1-3) keep synchronous dispatch? Recommendation: yes — defer the async refactor. Supervision semantics are testable with synchronous dispatch.

3. **Epoch representation:** `VCap (pid, epoch)` or a wrapper type? Using a tagged value keeps the interpreter simple. The LLVM backend will use a struct `{pid: i64, epoch: i64}`.

4. **Where to draw the Phase 1 boundary:** Monitors and links can be built without any parser changes. This makes Phase 1 a pure eval.ml change — fast to implement, easy to test. Recommendation: start here.
