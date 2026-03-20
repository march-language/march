# Two-Tier Scheduler Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement a two-tier cooperative + work-stealing scheduler for March's actor/task runtime, with reduction-counted preemption as the default and `Cap(WorkPool)` gated work-stealing as an opt-in escape hatch.

**Architecture:** The interpreter's single-threaded synchronous eval loop gains a reduction counter that yields after 4,000 reductions. A cooperative run-queue schedules actors and tasks round-robin. A separate work-stealing pool (Chase-Lev deques) handles CPU-bound tasks, gated by an unforgeable `Cap(WorkPool)` capability threaded from `main()`. Cross-tier communication uses lock-free MPSC mailbox queues.

**Tech Stack:** OCaml 5.3.0 (Domains for parallelism, Atomic for lock-free structures), Alcotest (tests), existing March compiler pipeline.

**Spec:** `specs/2026-03-19-scheduler-design.md`

---

## File Structure

| File | Responsibility |
|------|---------------|
| `lib/scheduler/scheduler.ml` | **NEW** — Cooperative scheduler: run queues, reduction counting, round-robin dispatch |
| `lib/scheduler/work_pool.ml` | **NEW** — Work-stealing pool: Chase-Lev deques, steal-half, Domain workers |
| `lib/scheduler/mailbox.ml` | **NEW** — Lock-free MPSC mailbox queues for actor/task message passing |
| `lib/scheduler/task.ml` | **NEW** — Task type, spawn/await/link API |
| `lib/scheduler/dune` | **NEW** — Dune build config for `march_scheduler` library |
| `lib/ast/ast.ml` | No changes needed (value types live in eval.ml) |
| `lib/eval/eval.ml` | **MODIFY** — Integrate reduction counter, scheduler dispatch, task builtins |
| `test/test_march.ml` | **MODIFY** — Add scheduler test groups |

---

### Task 1: Create the `march_scheduler` library skeleton

**Files:**
- Create: `lib/scheduler/dune`
- Create: `lib/scheduler/scheduler.ml`
- Create: `lib/scheduler/mailbox.ml`
- Create: `lib/scheduler/task.ml`
- Create: `lib/scheduler/work_pool.ml`

- [ ] **Step 1: Create `lib/scheduler/dune`**

```ocaml
(library
 (name march_scheduler)
 (libraries march_ast))
```

- [ ] **Step 2: Create `lib/scheduler/mailbox.ml` with MPSC queue**

```ocaml
(** Lock-free multi-producer/single-consumer mailbox queue.
    Based on Michael-Scott queue using OCaml 5 Atomic. *)

type 'a node = {
  value : 'a option;
  next  : 'a node option Atomic.t;
}

type 'a t = {
  head : 'a node Atomic.t;
  tail : 'a node Atomic.t;
}

let create () : 'a t =
  let sentinel = { value = None; next = Atomic.make None } in
  { head = Atomic.make sentinel; tail = Atomic.make sentinel }

let push (q : 'a t) (v : 'a) : unit =
  let new_node = { value = Some v; next = Atomic.make None } in
  let rec loop () =
    let tail = Atomic.get q.tail in
    let next = Atomic.get tail.next in
    match next with
    | None ->
      if Atomic.compare_and_set tail.next None (Some new_node) then
        (* Try to swing tail; OK if another thread does it *)
        ignore (Atomic.compare_and_set q.tail tail new_node)
      else loop ()
    | Some next_node ->
      (* Tail is behind; try to advance it *)
      ignore (Atomic.compare_and_set q.tail tail next_node);
      loop ()
  in
  loop ()

let pop (q : 'a t) : 'a option =
  let rec loop () =
    let head = Atomic.get q.head in
    match Atomic.get head.next with
    | None -> None  (* empty *)
    | Some next ->
      if Atomic.compare_and_set q.head head next then
        next.value
      else loop ()
  in
  loop ()

let is_empty (q : 'a t) : bool =
  let head = Atomic.get q.head in
  Option.is_none (Atomic.get head.next)
```

- [ ] **Step 3: Create `lib/scheduler/task.ml` with task types**

```ocaml
(** Task representation for the scheduler.
    A task is a lightweight unit of work — either cooperative or work-stealing. *)

type task_id = int

type task_status =
  | Ready
  | Running
  | Blocked   (** Waiting on receive/await *)
  | Done
  | Failed of string

type 'a task = {
  id         : task_id;
  mutable status : task_status;
  mutable result : 'a option;
  mailbox    : 'a Mailbox.t;    (** For delivering the result *)
  tier       : tier;
}

and tier =
  | Cooperative   (** Default: reduction-counted, round-robin *)
  | WorkStealing  (** Opt-in: run-to-completion on stealing pool *)

let next_task_id : task_id Atomic.t = Atomic.make 0

let fresh_id () : task_id =
  Atomic.fetch_and_add next_task_id 1
```

- [ ] **Step 4: Create `lib/scheduler/scheduler.ml` with reduction counter and run queue**

```ocaml
(** Cooperative scheduler with reduction-counted preemption.

    Each actor/task gets a budget of [max_reductions] reductions per quantum.
    A "reduction" is one function application, pattern match, or message send.
    When the budget is exhausted, the scheduler preempts and moves to the next
    item in the run queue. *)

(** Default reduction budget per quantum (BEAM-compatible). *)
let max_reductions = 4_000

(** Per-process reduction counter.
    Mutable for performance — decremented at every yield point in the evaluator. *)
type reduction_ctx = {
  mutable remaining : int;
  mutable yielded   : bool;
}

let create_reduction_ctx () : reduction_ctx =
  { remaining = max_reductions; yielded = false }

let reset_budget (ctx : reduction_ctx) : unit =
  ctx.remaining <- max_reductions;
  ctx.yielded <- false

(** Decrement the reduction counter. Returns true if budget is exhausted. *)
let tick (ctx : reduction_ctx) : bool =
  ctx.remaining <- ctx.remaining - 1;
  if ctx.remaining <= 0 then begin
    ctx.yielded <- true;
    true
  end else
    false

(** A scheduled entity — either an actor or a task. *)
type proc_id = int

type proc_state =
  | PReady
  | PRunning
  | PWaiting  (** Blocked on receive *)
  | PDone
  | PDead of string  (** Crashed with reason *)

type proc = {
  pid        : proc_id;
  mutable state : proc_state;
  tier       : Task.tier;
  reduction  : reduction_ctx;
}

(** The cooperative run queue — a simple FIFO queue. *)
type run_queue = {
  mutable procs : proc Queue.t;
  mutable wait  : proc list;  (** Blocked procs waiting on messages *)
}

let create_run_queue () : run_queue =
  { procs = Queue.create (); wait = [] }

(** Enqueue a process. *)
let enqueue (rq : run_queue) (p : proc) : unit =
  p.state <- PReady;
  Queue.push p rq.procs

(** Dequeue the next ready process, if any. *)
let dequeue (rq : run_queue) : proc option =
  if Queue.is_empty rq.procs then None
  else Some (Queue.pop rq.procs)

(** Move a process to the wait list. *)
let park (rq : run_queue) (p : proc) : unit =
  p.state <- PWaiting;
  rq.wait <- p :: rq.wait

(** Wake a waiting process (move from wait list to run queue). *)
let wake (rq : run_queue) (pid : proc_id) : bool =
  match List.partition (fun p -> p.pid = pid) rq.wait with
  | ([p], rest) ->
    rq.wait <- rest;
    enqueue rq p;
    true
  | _ -> false
```

- [ ] **Step 5: Create `lib/scheduler/work_pool.ml` placeholder**

```ocaml
(** Work-stealing pool — Phase 2.
    Uses Chase-Lev deques with steal-half semantics.
    Requires Cap(WorkPool) capability for access.

    This module is a placeholder. The cooperative scheduler (Phase 1) is
    implemented first. Work-stealing will be added in a subsequent task. *)

type t = {
  mutable active : bool;
}

let create () : t = { active = false }

let is_active (pool : t) : bool = pool.active
```

- [ ] **Step 6: Verify it builds**

Run: `/Users/80197052/.opam/march/bin/dune build`
Expected: Success, no errors

- [ ] **Step 7: Commit**

```bash
git add lib/scheduler/dune lib/scheduler/scheduler.ml lib/scheduler/mailbox.ml lib/scheduler/task.ml lib/scheduler/work_pool.ml
git commit -m "feat(scheduler): add march_scheduler library skeleton

Introduces the scheduler library with:
- Cooperative scheduler with reduction counting (4K budget)
- Lock-free MPSC mailbox queue
- Task type definitions
- Work-stealing pool placeholder"
```

---

### Task 2: Add `VTask` and `VWorkPool` value types to the AST

**Files:**
- Modify: `lib/ast/ast.ml` — no changes needed here (value types are in eval.ml)
- Modify: `lib/eval/eval.ml:21-33` — add VTask, VWorkPool to value type

- [ ] **Step 1: Add VTask and VWorkPool to the value type**

In `lib/eval/eval.ml`, add to the `value` type (after `VPid of int`):

```ocaml
  | VTask    of int                      (** Task handle *)
  | VWorkPool                            (** Work-stealing pool capability *)
```

In `value_to_string`, add cases:
```ocaml
  | VTask id -> Printf.sprintf "<task:%d>" id
  | VWorkPool -> "<work_pool>"
```

**Important:** Add `VTask _ | VWorkPool` cases to ALL exhaustive pattern matches on `value` in eval.ml to avoid compiler warnings. Search for `| VPid` and add the new cases after each occurrence.

- [ ] **Step 2: Write tests for new value types**

In `test/test_march.ml`, add after the existing `test_value_to_string` test:

```ocaml
let test_value_task_to_string () =
  let v = March_eval.Eval.VTask 42 in
  let s = March_eval.Eval.value_to_string v in
  Alcotest.(check string) "VTask prints" "<task:42>" s

let test_value_workpool_to_string () =
  let v = March_eval.Eval.VWorkPool in
  let s = March_eval.Eval.value_to_string v in
  Alcotest.(check string) "VWorkPool prints" "<work_pool>" s
```

Register in the `"eval"` test group:
```ocaml
Alcotest.test_case "task to_string"      `Quick test_value_task_to_string;
Alcotest.test_case "workpool to_string"  `Quick test_value_workpool_to_string;
```

**Note:** Tests and implementation are in the same step because OCaml is compiled — referencing `VTask` in tests without defining it causes a compile error that blocks ALL tests, not just the new ones.

- [ ] **Step 3: Run tests to verify pass**

Run: `/Users/80197052/.opam/march/bin/dune runtest`
Expected: All tests pass including the two new ones

- [ ] **Step 5: Commit**

```bash
git add lib/eval/eval.ml test/test_march.ml
git commit -m "feat(eval): add VTask and VWorkPool value types

Adds Task handle and WorkPool capability values to the interpreter,
needed for scheduler integration."
```

---

### Task 3: Integrate reduction counter into the evaluator

This is the core change — the evaluator gains a reduction counter that decrements at every yield point (EApp, EMatch, ESend). When the budget is exhausted, the evaluator raises a `Yield` exception that the scheduler catches.

**Files:**
- Modify: `lib/eval/eval.ml` — add reduction context, tick at yield points
- Modify: `lib/eval/dune` — add `march_scheduler` dependency
- Modify: `test/test_march.ml` — add reduction counting tests

- [ ] **Step 1: Write failing test — reduction counter decrements**

```ocaml
let test_reduction_counter_ticks () =
  (* After N function calls, the reduction counter should have decremented *)
  let ctx = March_scheduler.Scheduler.create_reduction_ctx () in
  let initial = ctx.remaining in
  let exhausted = March_scheduler.Scheduler.tick ctx in
  Alcotest.(check bool) "first tick not exhausted" false exhausted;
  Alcotest.(check int) "decremented by 1" (initial - 1) ctx.remaining

let test_reduction_counter_exhausts () =
  let ctx = March_scheduler.Scheduler.create_reduction_ctx () in
  (* Tick until exhausted *)
  let count = ref 0 in
  while not (March_scheduler.Scheduler.tick ctx) do
    incr count
  done;
  Alcotest.(check int) "exhausts after max_reductions - 1 ticks"
    (March_scheduler.Scheduler.max_reductions - 1) !count;
  Alcotest.(check bool) "yielded flag set" true ctx.yielded
```

Register in a new `"scheduler"` test group:
```ocaml
( "scheduler",
  [
    Alcotest.test_case "reduction counter ticks"    `Quick test_reduction_counter_ticks;
    Alcotest.test_case "reduction counter exhausts" `Quick test_reduction_counter_exhausts;
  ] );
```

- [ ] **Step 2: Run tests to verify they pass**

The scheduler module already has this code from Task 1, so these tests should pass immediately.

Run: `/Users/80197052/.opam/march/bin/dune runtest`
Expected: All tests pass

- [ ] **Step 3: Write failing test — evaluator yields after budget**

```ocaml
let test_eval_yields_after_budget () =
  (* A tight recursive function should trigger the Yield exception
     after the reduction budget is exhausted. We test this by running
     a function that makes more than 4000 calls. *)
  let src = {|mod Test do
    fn loop(n) do
      if n <= 0 then 0
      else loop(n - 1)
    end
  end|} in
  let env = eval_module src in
  (* Enable reduction counting *)
  March_eval.Eval.set_reduction_counting true;
  let yielded = ref false in
  (try
     ignore (call_fn env "loop" [March_eval.Eval.VInt 100_000])
   with March_eval.Eval.Yield ->
     yielded := true);
  March_eval.Eval.set_reduction_counting false;
  Alcotest.(check bool) "loop yields after budget" true !yielded
```

Register:
```ocaml
Alcotest.test_case "eval yields after budget" `Quick test_eval_yields_after_budget;
```

- [ ] **Step 4: Run test to verify failure**

Run: `/Users/80197052/.opam/march/bin/dune runtest 2>&1 | tail -20`
Expected: Compile error — `Yield` exception and `set_reduction_counting` not defined

- [ ] **Step 5: Add reduction counting to the evaluator**

In `lib/eval/dune`, add `march_scheduler` to libraries:
```
(library
 (name march_eval)
 (libraries march_ast march_scheduler))
```

In `lib/eval/eval.ml`, add after the `Eval_error` exception definition:

```ocaml
(** Raised when an actor/task's reduction budget is exhausted. *)
exception Yield

(** Global reduction context — None means reduction counting is disabled. *)
let reduction_ctx : March_scheduler.Scheduler.reduction_ctx option ref = ref None

(** Enable/disable reduction counting for the evaluator. *)
let set_reduction_counting (enabled : bool) : unit =
  if enabled then
    reduction_ctx := Some (March_scheduler.Scheduler.create_reduction_ctx ())
  else
    reduction_ctx := None

(** Reset the reduction budget (call between scheduling quanta). *)
let reset_reduction_budget () : unit =
  match !reduction_ctx with
  | Some ctx -> March_scheduler.Scheduler.reset_budget ctx
  | None -> ()

(** Check the reduction counter and raise Yield if exhausted.
    Called at every yield point: EApp, EMatch, ESend. *)
let check_reductions () : unit =
  match !reduction_ctx with
  | Some ctx ->
    if March_scheduler.Scheduler.tick ctx then
      raise Yield
  | None -> ()
```

Then insert `check_reductions ()` calls at the three yield points in `eval_expr_inner`:

At `EApp`:
```ocaml
  | EApp (f, args, _) ->
    check_reductions ();
    let fn_val = eval_expr env f in
    ...
```

At `EMatch`:
```ocaml
  | EMatch (scrut, branches, _) ->
    check_reductions ();
    let v = eval_expr env scrut in
    ...
```

At `ESend`:
```ocaml
  | ESend (cap_expr, msg_expr, _) ->
    check_reductions ();
    let pid_val = eval_expr env cap_expr in
    ...
```

- [ ] **Step 6: Run tests to verify pass**

Run: `/Users/80197052/.opam/march/bin/dune runtest`
Expected: All tests pass. The new `test_eval_yields_after_budget` should pass. Existing tests should still pass because reduction counting is disabled by default.

- [ ] **Step 7: Write test — existing eval works with counting disabled**

```ocaml
let test_eval_no_yield_when_disabled () =
  (* With reduction counting disabled (default), even a long computation
     should complete without yielding. *)
  March_eval.Eval.set_reduction_counting false;
  let src = {|mod Test do
    fn loop(n) do
      if n <= 0 then 0
      else loop(n - 1)
    end
  end|} in
  let env = eval_module src in
  let v = call_fn env "loop" [March_eval.Eval.VInt 100_000] in
  Alcotest.(check int) "completes without yield" 0 (vint v)
```

- [ ] **Step 8: Run full test suite**

Run: `/Users/80197052/.opam/march/bin/dune runtest`
Expected: All tests pass

- [ ] **Step 9: Commit**

```bash
git add lib/eval/eval.ml lib/eval/dune test/test_march.ml
git commit -m "feat(eval): integrate reduction counter into evaluator

Adds yield-point checks at EApp, EMatch, and ESend. When reduction
counting is enabled, the evaluator raises Yield after 4000 reductions.
Disabled by default so existing behavior is unchanged."
```

---

### Task 4: Add task builtins to the evaluator

The evaluator gets `task_spawn`, `task_await`, and `task_yield` builtins that create and manage tasks on the cooperative scheduler.

**Files:**
- Modify: `lib/eval/eval.ml` — add task registry, spawn/await/yield builtins
- Modify: `test/test_march.ml` — add task eval tests

- [ ] **Step 1: Write failing test — Task.spawn and Task.await**

```ocaml
let test_eval_task_spawn_await () =
  let src = {|mod Test do
    fn main() do
      let t = task_spawn(fn () -> 42)
      task_await_unwrap(t)
    end
  end|} in
  let env = eval_module src in
  let v = call_fn env "main" [] in
  Alcotest.(check int) "task returns 42" 42 (vint v)
```

Register in a new `"tasks"` test group:
```ocaml
( "tasks",
  [
    Alcotest.test_case "spawn and await" `Quick test_eval_task_spawn_await;
  ] );
```

- [ ] **Step 2: Run test to verify failure**

Run: `/Users/80197052/.opam/march/bin/dune runtest 2>&1 | tail -20`
Expected: FAIL — `task_spawn` not found in environment

- [ ] **Step 3: Implement task_spawn and task_await builtins**

In `lib/eval/eval.ml`, add a task registry near the actor registry:

```ocaml
(** Task registry — maps task IDs to their result. *)
type task_entry = {
  te_id     : int;
  mutable te_result : value option;
  te_thunk  : value;  (** The closure to execute *)
}

let task_registry : (int, task_entry) Hashtbl.t = Hashtbl.create 16
let next_task_id : int ref = ref 0
```

Add builtins to the `builtins` list:

```ocaml
  (* Task builtins *)
  ; ("task_spawn", VBuiltin ("task_spawn", function
    | [thunk] ->
      let tid = !next_task_id in
      next_task_id := tid + 1;
      (* For the cooperative single-threaded scheduler (Phase 1),
         we eagerly evaluate the thunk. In Phase 2, this will
         enqueue the task on the run queue. *)
      let result = apply thunk [] in
      let entry = { te_id = tid; te_result = Some result; te_thunk = thunk } in
      Hashtbl.add task_registry tid entry;
      VTask tid
    | _ -> eval_error "task_spawn: expected 1 argument (a function)"))

  ; ("task_await", VBuiltin ("task_await", function
    | [VTask tid] ->
      (match Hashtbl.find_opt task_registry tid with
       | Some entry ->
         (match entry.te_result with
          | Some v -> VCon ("Ok", [v])
          | None -> VCon ("Err", [VString "task not completed"]))
       | None -> VCon ("Err", [VString (Printf.sprintf "unknown task %d" tid)]))
    | _ -> eval_error "task_await: expected 1 argument (a Task)"))

  ; ("task_await_unwrap", VBuiltin ("task_await_unwrap", function
    | [VTask tid] ->
      (match Hashtbl.find_opt task_registry tid with
       | Some entry ->
         (match entry.te_result with
          | Some v -> v
          | None -> eval_error "task_await!: task %d not completed" tid)
       | None -> eval_error "task_await!: unknown task %d" tid)
    | _ -> eval_error "task_await!: expected 1 argument (a Task)"))

  ; ("task_yield", VBuiltin ("task_yield", function
    | [] ->
      (* Voluntary yield — exhaust the budget so check_reductions raises Yield.
         When reduction counting is disabled, this is a no-op. *)
      (match !reduction_ctx with
       | Some ctx ->
         ctx.remaining <- 0;
         ignore (March_scheduler.Scheduler.tick ctx)
       | None -> ());
      VUnit
    | _ -> eval_error "task_yield: expected 0 arguments"))
```

- [ ] **Step 4: Run test to verify pass**

Run: `/Users/80197052/.opam/march/bin/dune runtest`
Expected: All tests pass

- [ ] **Step 5: Write more task tests**

```ocaml
let test_eval_task_await_unwrap () =
  let src = {|mod Test do
    fn main() do
      let t = task_spawn(fn () -> 99)
      task_await_unwrap(t)
    end
  end|} in
  let env = eval_module src in
  let v = call_fn env "main" [] in
  Alcotest.(check int) "task unwrap returns 99" 99 (vint v)

let test_eval_task_multiple () =
  let src = {|mod Test do
    fn main() do
      let t1 = task_spawn(fn () -> 10)
      let t2 = task_spawn(fn () -> 20)
      let r1 = task_await_unwrap(t1)
      let r2 = task_await_unwrap(t2)
      r1 + r2
    end
  end|} in
  let env = eval_module src in
  let v = call_fn env "main" [] in
  Alcotest.(check int) "two tasks sum to 30" 30 (vint v)

let test_eval_task_captures_env () =
  let src = {|mod Test do
    fn main() do
      let x = 5
      let t = task_spawn(fn () -> x * x)
      task_await_unwrap(t)
    end
  end|} in
  let env = eval_module src in
  let v = call_fn env "main" [] in
  Alcotest.(check int) "task captures outer x" 25 (vint v)
```

Register:
```ocaml
Alcotest.test_case "await unwrap"        `Quick test_eval_task_await_unwrap;
Alcotest.test_case "multiple tasks"      `Quick test_eval_task_multiple;
Alcotest.test_case "task captures env"   `Quick test_eval_task_captures_env;
```

- [ ] **Step 6: Run all tests**

Run: `/Users/80197052/.opam/march/bin/dune runtest`
Expected: All pass

- [ ] **Step 7: Commit**

```bash
git add lib/eval/eval.ml test/test_march.ml
git commit -m "feat(eval): add task_spawn, task_await, task_await_unwrap builtins

Tasks are eagerly evaluated in the single-threaded interpreter (Phase 1).
The scheduler will dispatch them cooperatively in Phase 2."
```

---

### Task 5: Add `Cap(WorkPool)` gated `task_spawn_steal` builtin

**Files:**
- Modify: `lib/eval/eval.ml` — add `task_spawn_steal` that checks for VWorkPool
- Modify: `test/test_march.ml` — tests for capability gating

- [ ] **Step 1: Write failing test — spawn_steal requires WorkPool**

```ocaml
let test_eval_spawn_steal_requires_pool () =
  (* Calling task_spawn_steal without a WorkPool should fail *)
  let src = {|mod Test do
    fn main() do
      task_spawn_steal(42, fn () -> 1)
    end
  end|} in
  let env = eval_module src in
  let raised = ref false in
  (try ignore (call_fn env "main" [])
   with March_eval.Eval.Eval_error _ -> raised := true);
  Alcotest.(check bool) "rejects non-WorkPool" true !raised

let test_eval_spawn_steal_with_pool () =
  (* With a real WorkPool value, spawn_steal should work *)
  let src = {|mod Test do
    fn run(pool) do
      let t = task_spawn_steal(pool, fn () -> 77)
      task_await_unwrap(t)
    end
  end|} in
  let env = eval_module src in
  let v = call_fn env "run" [March_eval.Eval.VWorkPool] in
  Alcotest.(check int) "steal task returns 77" 77 (vint v)
```

Register in `"tasks"` group:
```ocaml
Alcotest.test_case "spawn_steal requires pool" `Quick test_eval_spawn_steal_requires_pool;
Alcotest.test_case "spawn_steal with pool"     `Quick test_eval_spawn_steal_with_pool;
```

- [ ] **Step 2: Run test to verify failure**

Run: `/Users/80197052/.opam/march/bin/dune runtest 2>&1 | tail -20`
Expected: FAIL — `task_spawn_steal` not found

- [ ] **Step 3: Add task_spawn_steal builtin**

In `lib/eval/eval.ml`, add to builtins:

```ocaml
  ; ("task_spawn_steal", VBuiltin ("task_spawn_steal", function
    | [VWorkPool; thunk] ->
      (* Cap(WorkPool) validated — spawn on the stealing pool.
         In Phase 1 (single-threaded), this is equivalent to task_spawn
         but validates the capability requirement. *)
      let tid = !next_task_id in
      next_task_id := tid + 1;
      let result = apply thunk [] in
      let entry = { te_id = tid; te_result = Some result; te_thunk = thunk } in
      Hashtbl.add task_registry tid entry;
      VTask tid
    | [_; _] ->
      eval_error "task_spawn_steal: first argument must be a Cap(WorkPool)"
    | _ -> eval_error "task_spawn_steal: expected 2 arguments (pool, function)"))
```

- [ ] **Step 4: Run tests**

Run: `/Users/80197052/.opam/march/bin/dune runtest`
Expected: All pass

- [ ] **Step 5: Write test — WorkPool passed from main**

```ocaml
let test_eval_workpool_threading () =
  (* Simulate the main() -> helper(pool) -> spawn_steal pattern *)
  let src = {|mod Test do
    fn helper(pool) do
      let t = task_spawn_steal(pool, fn () -> 55)
      task_await_unwrap(t)
    end

    fn main(pool) do
      helper(pool)
    end
  end|} in
  let env = eval_module src in
  let v = call_fn env "main" [March_eval.Eval.VWorkPool] in
  Alcotest.(check int) "threaded pool works" 55 (vint v)
```

- [ ] **Step 6: Run full suite**

Run: `/Users/80197052/.opam/march/bin/dune runtest`
Expected: All pass

- [ ] **Step 7: Commit**

```bash
git add lib/eval/eval.ml test/test_march.ml
git commit -m "feat(eval): add Cap(WorkPool) gated task_spawn_steal

Work-stealing tasks require an unforgeable VWorkPool capability.
In Phase 1 the tasks are still eager, but the capability gate
ensures the API contract is established from the start."
```

---

### Task 6: Add cooperative run-queue scheduling to the evaluator

Replace the eager task execution with actual run-queue scheduling. Tasks are enqueued and the scheduler runs them round-robin with reduction counting.

**Files:**
- Modify: `lib/eval/eval.ml` — replace eager eval with scheduler loop
- Modify: `test/test_march.ml` — add fairness tests

- [ ] **Step 1: Write failing test — tasks interleave**

```ocaml
let test_eval_tasks_interleave () =
  (* Two tasks that each do significant work should both complete.
     This verifies the scheduler doesn't let one starve the other. *)
  let src = {|mod Test do
    fn work(n, acc) do
      if n <= 0 then acc
      else work(n - 1, acc + 1)
    end

    fn main() do
      let t1 = task_spawn(fn () -> work(5000, 0))
      let t2 = task_spawn(fn () -> work(5000, 0))
      let r1 = task_await_unwrap(t1)
      let r2 = task_await_unwrap(t2)
      r1 + r2
    end
  end|} in
  let env = eval_module src in
  let v = call_fn env "main" [] in
  Alcotest.(check int) "both tasks complete" 10_000 (vint v)
```

- [ ] **Step 2: Add reduction counting telemetry (metric-only approach)**

The tree-walking interpreter cannot truly preempt mid-evaluation (that would require CPS-transforming the entire evaluator or using OCaml Domains per task). Instead, we keep the eager task evaluation from Task 4 and add reduction counting as an observable metric. This validates that yield-point insertion works correctly. True preemptive scheduling will come with the compiled LLVM backend.

Keep the eager task evaluation from Task 4. Add reduction counting as telemetry:

```ocaml
(** Get the number of reductions consumed during the last evaluation. *)
let last_reduction_count : int ref = ref 0

let eval_with_reduction_tracking (thunk : value) : value * int =
  let ctx = March_scheduler.Scheduler.create_reduction_ctx () in
  reduction_ctx := Some ctx;
  let result = apply thunk [] in
  let consumed = March_scheduler.Scheduler.max_reductions - ctx.remaining in
  reduction_ctx := None;
  last_reduction_count := consumed;
  (result, consumed)
```

Add a `task_reductions` builtin:
```ocaml
  ; ("task_reductions", VBuiltin ("task_reductions", function
    | [] -> VInt !last_reduction_count
    | _ -> eval_error "task_reductions: expected 0 arguments"))
```

- [ ] **Step 4: Write test — reduction count is accurate**

```ocaml
let test_eval_reduction_count () =
  (* A function that calls itself N times should consume roughly N reductions *)
  let src = {|mod Test do
    fn loop(n) do
      if n <= 0 then 0
      else loop(n - 1)
    end

    fn main() do
      loop(100)
    end
  end|} in
  let env = eval_module src in
  let thunk = List.assoc "main" env in
  let (_result, reductions) =
    March_eval.Eval.eval_with_reduction_tracking thunk in
  (* Each loop iteration has: EApp(loop) + EMatch(if) = 2 reductions
     Plus the initial EApp(main). Should be roughly 200+. *)
  Alcotest.(check bool) "reductions > 100" true (reductions > 100);
  Alcotest.(check bool) "reductions < 1000" true (reductions < 1000)
```

- [ ] **Step 5: Run all tests**

Run: `/Users/80197052/.opam/march/bin/dune runtest`
Expected: All pass

- [ ] **Step 6: Commit**

```bash
git add lib/eval/eval.ml test/test_march.ml
git commit -m "feat(eval): add reduction counting telemetry

Adds eval_with_reduction_tracking to measure reductions consumed.
This validates yield-point insertion without requiring full
preemptive scheduling in the tree-walking interpreter."
```

---

### Task 7: Add actor-to-task and task-to-actor messaging tests

Verify cross-tier communication works through the existing mailbox system.

**Files:**
- Modify: `test/test_march.ml` — add cross-tier messaging tests

- [ ] **Step 1: Write test — task sends to actor**

```ocaml
let test_eval_task_sends_to_actor () =
  let src = {|mod Test do
    actor Counter do
      state { count : Int }
      init { count = 0 }

      on Increment(n) do
        { count = state.count + n }
      end
    end

    fn main() do
      let pid = spawn(Counter)
      let t = task_spawn(fn () -> send(pid, Increment(10)))
      task_await_unwrap(t)
      send(pid, Increment(0))
    end
  end|} in
  (* Just verify it doesn't crash — the actor receives from the task *)
  let env = eval_module src in
  let _v = call_fn env "main" [] in
  (* If we get here without error, cross-tier messaging works *)
  ()
```

- [ ] **Step 2: Run test**

Run: `/Users/80197052/.opam/march/bin/dune runtest`
Expected: Pass

- [ ] **Step 3: Commit**

```bash
git add test/test_march.ml
git commit -m "test: add cross-tier actor-task messaging tests

Verifies tasks can send messages to actors, validating the
cross-tier communication model from the scheduler spec."
```

---

### Task 8: Add work-stealing pool with Chase-Lev deques (Phase 2)

Implement the actual work-stealing data structure and Domain-based parallel pool.

**Files:**
- Modify: `lib/scheduler/work_pool.ml` — full Chase-Lev deque implementation
- Modify: `test/test_march.ml` — deque unit tests

- [ ] **Step 1: Write failing test — Chase-Lev deque push/pop**

```ocaml
let test_deque_push_pop () =
  let d = March_scheduler.Work_pool.Deque.create 16 in
  March_scheduler.Work_pool.Deque.push d 1;
  March_scheduler.Work_pool.Deque.push d 2;
  March_scheduler.Work_pool.Deque.push d 3;
  (* Pop is LIFO from the bottom *)
  Alcotest.(check (option int)) "pop 3" (Some 3)
    (March_scheduler.Work_pool.Deque.pop d);
  Alcotest.(check (option int)) "pop 2" (Some 2)
    (March_scheduler.Work_pool.Deque.pop d);
  Alcotest.(check (option int)) "pop 1" (Some 1)
    (March_scheduler.Work_pool.Deque.pop d);
  Alcotest.(check (option int)) "pop empty" None
    (March_scheduler.Work_pool.Deque.pop d)

let test_deque_steal () =
  let d = March_scheduler.Work_pool.Deque.create 16 in
  March_scheduler.Work_pool.Deque.push d 1;
  March_scheduler.Work_pool.Deque.push d 2;
  March_scheduler.Work_pool.Deque.push d 3;
  (* Steal is FIFO from the top *)
  Alcotest.(check (option int)) "steal 1" (Some 1)
    (March_scheduler.Work_pool.Deque.steal d);
  Alcotest.(check (option int)) "steal 2" (Some 2)
    (March_scheduler.Work_pool.Deque.steal d)
```

Register in `"work_stealing"` test group:
```ocaml
( "work_stealing",
  [
    Alcotest.test_case "deque push/pop"  `Quick test_deque_push_pop;
    Alcotest.test_case "deque steal"     `Quick test_deque_steal;
  ] );
```

- [ ] **Step 2: Run test to verify failure**

Run: `/Users/80197052/.opam/march/bin/dune runtest 2>&1 | tail -20`
Expected: Compile error — `Deque` module not defined

- [ ] **Step 3: Implement Chase-Lev deque**

Replace `lib/scheduler/work_pool.ml`:

```ocaml
(** Work-stealing pool with Chase-Lev deques.

    Each worker thread maintains a deque. The owning thread pushes/pops
    from the bottom (LIFO). Stealing threads take from the top (FIFO).

    Reference: Chase & Lev, "Dynamic Circular Work-Stealing Deque" (2005). *)

module Deque = struct
  type 'a t = {
    mutable buffer : 'a option array;
    top    : int Atomic.t;    (** Steal from here (FIFO) *)
    bottom : int Atomic.t;    (** Push/pop here (LIFO) *)
    mutable capacity : int;
  }

  let create (cap : int) : 'a t =
    { buffer = Array.make cap None;
      top = Atomic.make 0;
      bottom = Atomic.make 0;
      capacity = cap }

  let push (d : 'a t) (v : 'a) : unit =
    let b = Atomic.get d.bottom in
    let t = Atomic.get d.top in
    let size = b - t in
    if size >= d.capacity then begin
      (* Grow buffer *)
      let new_cap = d.capacity * 2 in
      let new_buf = Array.make new_cap None in
      for i = t to b - 1 do
        new_buf.(i mod new_cap) <- d.buffer.(i mod d.capacity)
      done;
      d.buffer <- new_buf;
      d.capacity <- new_cap
    end;
    d.buffer.(b mod d.capacity) <- Some v;
    Atomic.set d.bottom (b + 1)

  let pop (d : 'a t) : 'a option =
    let b = Atomic.get d.bottom - 1 in
    Atomic.set d.bottom b;
    let t = Atomic.get d.top in
    let size = b - t in
    if size < 0 then begin
      (* Empty *)
      Atomic.set d.bottom t;
      None
    end else if size > 0 then begin
      (* More than one element — safe to take *)
      let v = d.buffer.(b mod d.capacity) in
      d.buffer.(b mod d.capacity) <- None;
      v
    end else begin
      (* Last element — race with steal *)
      let v = d.buffer.(b mod d.capacity) in
      if Atomic.compare_and_set d.top t (t + 1) then begin
        d.buffer.(b mod d.capacity) <- None;
        Atomic.set d.bottom (t + 1);
        v
      end else begin
        Atomic.set d.bottom (t + 1);
        None
      end
    end

  let steal (d : 'a t) : 'a option =
    let t = Atomic.get d.top in
    let b = Atomic.get d.bottom in
    let size = b - t in
    if size <= 0 then None
    else begin
      let v = d.buffer.(t mod d.capacity) in
      if Atomic.compare_and_set d.top t (t + 1) then begin
        d.buffer.(t mod d.capacity) <- None;
        v
      end else
        None  (* Lost race with another stealer or pop *)
    end

  let size (d : 'a t) : int =
    let b = Atomic.get d.bottom in
    let t = Atomic.get d.top in
    max 0 (b - t)
end

(** The work-stealing pool — a collection of worker deques. *)
type 'a t = {
  workers   : 'a Deque.t array;
  n_workers : int;
  mutable active : bool;
}

let create (n_workers : int) : 'a t =
  { workers = Array.init n_workers (fun _ -> Deque.create 64);
    n_workers;
    active = true }

let is_active (pool : 'a t) : bool = pool.active

(** Submit work to a specific worker's deque. *)
let submit (pool : 'a t) (worker_idx : int) (v : 'a) : unit =
  let idx = worker_idx mod pool.n_workers in
  Deque.push pool.workers.(idx) v

(** Try to steal work from a random other worker. *)
let try_steal (pool : 'a t) (my_idx : int) : 'a option =
  let victim = Random.int pool.n_workers in
  if victim = my_idx then None
  else Deque.steal pool.workers.(victim)
```

- [ ] **Step 4: Run tests**

Run: `/Users/80197052/.opam/march/bin/dune runtest`
Expected: All pass

- [ ] **Step 5: Write test — pool submit and steal**

```ocaml
let test_pool_submit_steal () =
  let pool = March_scheduler.Work_pool.create 2 in
  March_scheduler.Work_pool.submit pool 0 "task_a";
  March_scheduler.Work_pool.submit pool 0 "task_b";
  (* Steal from worker 0's deque *)
  let stolen = March_scheduler.Work_pool.Deque.steal pool.workers.(0) in
  Alcotest.(check (option string)) "stole task_a" (Some "task_a") stolen
```

- [ ] **Step 6: Run all tests**

Run: `/Users/80197052/.opam/march/bin/dune runtest`
Expected: All pass

- [ ] **Step 7: Commit**

```bash
git add lib/scheduler/work_pool.ml test/test_march.ml
git commit -m "feat(scheduler): implement Chase-Lev work-stealing deque

Adds a growable Chase-Lev deque with atomic top/bottom pointers.
Owner pushes/pops LIFO from bottom; stealers take FIFO from top.
Includes a work-stealing pool that manages per-worker deques."
```

---

### Task 9: Clean up task registries and add reset functions

The evaluator's global state (actor registry, task registry) needs proper reset for test isolation.

**Files:**
- Modify: `lib/eval/eval.ml` — add `reset_scheduler_state`
- Modify: `test/test_march.ml` — call reset before scheduler tests

- [ ] **Step 1: Add reset function**

In `lib/eval/eval.ml`:

```ocaml
(** Reset all scheduler/task state. Call between test runs. *)
let reset_scheduler_state () : unit =
  Hashtbl.clear task_registry;
  next_task_id := 0;
  Hashtbl.clear actor_registry;
  Hashtbl.clear actor_defs_tbl;
  next_pid := 0;
  reduction_ctx := None;
  last_reduction_count := 0
```

- [ ] **Step 2: Call reset in test setup**

Wrap scheduler/task tests with reset:

```ocaml
let with_reset f () =
  March_eval.Eval.reset_scheduler_state ();
  f ()
```

Use `with_reset` in test registrations:
```ocaml
Alcotest.test_case "spawn and await" `Quick (with_reset test_eval_task_spawn_await);
```

- [ ] **Step 3: Run all tests**

Run: `/Users/80197052/.opam/march/bin/dune runtest`
Expected: All pass

- [ ] **Step 4: Commit**

```bash
git add lib/eval/eval.ml test/test_march.ml
git commit -m "fix(eval): add reset_scheduler_state for test isolation

Clears task registry, actor registry, and reduction state between tests
to prevent cross-test contamination."
```

---

### Task 10: Run full test suite and benchmark

**Files:**
- No new files

- [ ] **Step 1: Run the full test suite**

Run: `/Users/80197052/.opam/march/bin/dune runtest`
Expected: All tests pass (existing + new scheduler tests)

- [ ] **Step 2: Run the existing benchmarks to check for regressions**

Run: `/Users/80197052/.opam/march/bin/dune exec march -- bench/tree_transform.march`
Run: `/Users/80197052/.opam/march/bin/dune exec march -- bench/list_ops.march`
Run: `/Users/80197052/.opam/march/bin/dune exec march -- bench/binary_trees.march`

Expected: No regressions — the `check_reductions()` call is a no-op when reduction counting is disabled (the default).

- [ ] **Step 3: Verify performance impact of yield-point checks**

If the benchmarks show measurable slowdown (>5%), the `check_reductions` function should be gated more efficiently — perhaps with a global boolean check before the function call, or by using `[@unrolled]` / `[@inlined]` attributes.

- [ ] **Step 4: Final commit if any benchmark fixes needed**

```bash
git add lib/eval/eval.ml
git commit -m "perf(eval): optimize yield-point checks when counting disabled"
```
