# March Application Model Specification

## Design Philosophy

March draws a hard line between two kinds of programs: **scripts** and **services**. A script computes a result and exits. A service starts a supervision tree and runs until stopped. Today, both are shoehorned into `main()`, which forces the user to manually orchestrate supervisor lifecycle, call `run_until_idle()`, and accept that the program exits when the scheduler drains. This conflation is the root of three problems: (1) the runtime cannot distinguish "I'm done" from "I'm waiting for messages," (2) graceful shutdown requires user-written signal handling, and (3) there is no declarative description of the system's process topology that the runtime, tooling, or hot-reload mechanism could inspect.

The solution is two distinct entry points with distinct semantics. `main()` remains the entry point for scripts. A new `app` declaration becomes the entry point for long-lived supervised systems. The runtime's behavior is determined by which entry point exists — no return-type inspection, no magic, no ambiguity.

This design follows three principles that guide March's broader architecture:

1. **Explicit over implicit.** Two entry points are more surface area than one, but they eliminate a class of silent bugs (service accidentally exiting because main() returned void) and make the programmer's intent legible to both humans and tools.

2. **Declarative where possible, imperative where necessary.** The `app` body is an expression that evaluates to a supervision spec — a value. This means specs are composable, testable, and inspectable. But the body can contain arbitrary code (config loading, environment checks) before returning the spec, so you aren't locked into a purely declarative DSL.

3. **The REPL is a first-class citizen.** Every feature must work in the REPL. For `app`, this means you can evaluate a supervision spec as a value, inspect it, modify it, and — crucially — start and stop application trees interactively during development.

## Surface Syntax

### Script entry point (unchanged)

```march
fn main() do
  let result = compute_stuff()
  println(result)
end
```

Semantics: evaluate `main()`, drain the scheduler, exit. Exactly as today.

### Application entry point (new)

```march
app MyServer do
  let config = load_config("server.toml")

  Supervisor.spec(one_for_one, [
    worker(DbPool, [size: config.pool_size, url: config.db_url]),
    worker(HttpServer, [port: config.port]),
    worker(MetricsReporter, [interval: 30])
  ])
end
```

Semantics: evaluate the `app` body, which must return a value of type `Supervisor.Spec`. The runtime spawns the supervision tree, enters an infinite scheduler loop, and handles OS signals for graceful shutdown. The program runs until it receives SIGTERM/SIGINT or the root supervisor exhausts its restart budget.

### Mutual exclusivity

A module may define `main()` or `app`, never both. This is a compile-time error:

```march
-- ERROR: module defines both main() and app
fn main() do ... end
app MyApp do ... end
```

The error message: `Module defines both main() and app MyApp. Use main() for scripts that run to completion. Use app for long-lived supervised systems.`

### Nested supervision trees

```march
app ProductionServer do
  let db_url = env("DATABASE_URL")
  let port = env_int("PORT", 8080)

  Supervisor.spec(one_for_all, [
    worker(CacheWarmer, []),
    supervisor(one_for_one, [
      worker(SessionStore, [ttl: 3600]),
      worker(AuthService, [db: db_url])
    ]),
    supervisor(one_for_one, [
      worker(WebHandler, [port: port]),
      worker(ApiHandler, [port: port + 1])
    ])
  ])
end
```

`supervisor(strategy, children)` is sugar for an anonymous inline supervisor spec. Named supervisors (defined as actor declarations with `supervise` blocks) can also appear in the child list.

## The Supervisor.Spec Type

### Type definition

```march
mod Supervisor do

  type Strategy = OneForOne | OneForAll | RestForOne

  type RestartPolicy = Permanent | Transient | Temporary

  type ChildSpec =
    | Worker(WorkerSpec)
    | Sup(SupervisorSpec)

  type WorkerSpec = {
    actor    : ActorType,
    args     : List(Dynamic),
    restart  : RestartPolicy,
    shutdown : ShutdownPolicy
  }

  type SupervisorSpec = {
    strategy     : Strategy,
    max_restarts : Int,
    within       : Int,
    children     : List(ChildSpec)
  }

  type ShutdownPolicy =
    | Timeout(Int)
    | Brutal
    | Infinity

  type Spec = SupervisorSpec

end
```

### Restart policies

Borrowed from Erlang/OTP with March naming:

- **Permanent** (default): always restarted, regardless of exit reason. Use for core services.
- **Transient**: restarted only on abnormal exit (crash). Normal termination is not restarted. Use for workers that complete a finite task.
- **Temporary**: never restarted. Use for one-shot tasks spawned under a supervisor for resource tracking.

### Shutdown policies

When the runtime shuts down (SIGTERM, supervisor escalation, or programmatic stop):

- **Timeout(ms)**: send `Shutdown` message, wait up to `ms` milliseconds, then force-kill.
- **Brutal**: force-kill immediately, no message.
- **Infinity**: send `Shutdown` message, wait forever. Use for supervisors (they need time to shut down their children).

### Builder functions

```march
-- Convenience constructors with sensible defaults
fn worker(actor : ActorType, args : List(Dynamic)) : ChildSpec do
  Worker({
    actor    = actor,
    args     = args,
    restart  = Permanent,
    shutdown = Timeout(5000)
  })
end

fn supervisor(strategy : Strategy, children : List(ChildSpec)) : ChildSpec do
  Sup({
    strategy     = strategy,
    max_restarts = 5,
    within       = 30,
    children     = children
  })
end

fn spec(strategy : Strategy, children : List(ChildSpec)) : Spec do
  {
    strategy     = strategy,
    max_restarts = 5,
    within       = 30,
    children     = children
  }
end
```

## AST Changes

### New declaration variant

In `lib/ast/ast.ml`, add to the `decl` type:

```ocaml
type decl =
  | DFn of fn_def * span
  (* ... existing variants ... *)
  | DApp of app_def * span    (* NEW: app Name do ... end *)

and app_def = {
  app_name : name;
  app_body : expr;            (* Must typecheck to Supervisor.Spec *)
}
```

### Parser changes

In `lib/parser/parser.mly`, add a new top-level declaration rule:

```
app_decl:
  | APP UIDENT DO block_body END
    { DApp ({ app_name = $2; app_body = $4 }, span $startpos $endpos) }
```

New token: `APP` keyword. Add to lexer (`lib/lexer/lexer.mll`):

```ocaml
| "app" -> APP
```

### Validation pass

After parsing, before desugaring, a validation pass checks:

1. At most one `DApp` per module.
2. No `DApp` and `main` function in the same module. (Detect by checking for `DFn` with `fn_name.txt = "main"` alongside `DApp`.)
3. The `app_name` is a valid module-level identifier (capitalized, like actor names).

Error on violation with a clear diagnostic explaining the two-entry-point model.

## Type Checking

### Spec type inference

The `app` body is type-checked as an expression that must unify with `Supervisor.Spec`. This is implemented as a checking-mode call in `lib/typecheck/typecheck.ml`:

```ocaml
| DApp (def, span) ->
  let expected_ty = TCon ("Supervisor.Spec", []) in
  let _body_ty = check_expr env def.app_body expected_ty in
  (* If check_expr fails, it reports a diagnostic:
     "app body must return Supervisor.Spec, but this expression has type ..." *)
  env
```

### ActorType as a first-class value

The `worker(Counter, [...])` call passes an actor type as a value. This requires a way to reference actor definitions as first-class values. Two options:

**Option A — Actor name as a compile-time constant.** `Counter` in `worker(Counter, [...])` is not a runtime value but a compile-time token that the type checker resolves to an actor definition. The `ActorType` parameter in `WorkerSpec` is a phantom — at runtime, it's an integer tag or string identifier.

**Option B — Reified actor descriptors.** Each `actor` declaration generates a companion value `Counter.descriptor : ActorDescriptor` containing the init function, handler table, and supervision config. `worker` takes an `ActorDescriptor`, which is a real runtime value.

**Decision: Option B.** Reified descriptors enable dynamic supervisor construction, REPL inspection, and testing. The descriptor is auto-generated by the compiler for each actor declaration, similar to how Elixir modules have `__struct__/0` and `child_spec/1`.

```march
-- Auto-generated for every actor declaration
-- (user never writes this; compiler emits it)
Counter.descriptor : ActorDescriptor
Counter.child_spec(args) : ChildSpec   -- convenience, equivalent to worker(Counter.descriptor, args)
```

## Desugaring

The desugaring pass (`lib/desugar/desugar.ml`) transforms `DApp` into a synthetic function and a module-level marker:

```ocaml
(* DApp { app_name = "MyServer"; app_body = body } becomes: *)

(* 1. A function that returns the spec *)
DFn {
  fn_name = { txt = "__app_init__"; ... };
  fn_vis = Private;
  fn_clauses = [{ fc_params = []; fc_body = body; ... }];
  ...
}

(* 2. A marker the runtime recognizes *)
DLet {
  bind_pat = PatVar { txt = "__app_marker__"; ... };
  bind_expr = ELit (LitBool true, ...);
  ...
}
```

This approach means the downstream passes (type checking, TIR lowering, monomorphization, defunctionalization, LLVM emission) don't need to know about `app` at all. They see a normal function. The runtime entry point logic checks for `__app_marker__` and calls `__app_init__()` instead of `main()`.

## Interpreter Changes (lib/eval/eval.ml)

### Entry point dispatch

Replace the current `run_module` with:

```ocaml
let run_module (m : module_) : unit =
  let env = eval_module_env m in
  (* Check for app entry point *)
  match List.assoc_opt "__app_marker__" env with
  | Some (VBool true) ->
    (* Application mode: get spec, spawn tree, run forever *)
    let init_fn = List.assoc "__app_init__" env in
    let spec = apply init_fn [] in
    let root_pid = spawn_from_spec spec in
    install_signal_handlers root_pid;
    run_scheduler_forever ()
  | _ ->
    (* Script mode: call main(), drain scheduler, exit *)
    (match List.assoc_opt "main" env with
     | None -> ()
     | Some v ->
       let _ = apply v [] in
       run_scheduler ())
```

### Spawning from spec

A new function `spawn_from_spec` recursively walks the `Supervisor.Spec` value and spawns actors:

```ocaml
let rec spawn_from_spec (spec : value) : pid =
  let strategy = extract_field spec "strategy" in
  let max_restarts = extract_int (extract_field spec "max_restarts") in
  let within = extract_int (extract_field spec "within") in
  let children = extract_list (extract_field spec "children") in
  let child_pids = List.map spawn_child children in
  create_runtime_supervisor strategy max_restarts within child_pids

and spawn_child (child : value) : pid * child_info =
  match extract_variant child with
  | "Worker", [worker_spec] ->
    let descriptor = extract_field worker_spec "actor" in
    let args = extract_list (extract_field worker_spec "args") in
    let pid = spawn_actor_from_descriptor descriptor args in
    (pid, { restart = extract_restart worker_spec; shutdown = extract_shutdown worker_spec })
  | "Sup", [sup_spec] ->
    let pid = spawn_from_spec sup_spec in
    (pid, { restart = Permanent; shutdown = Infinity })
  | _ -> eval_error "invalid child spec"
```

### Infinite scheduler loop

```ocaml
let run_scheduler_forever () =
  (* Unlike run_scheduler which exits when all mailboxes are empty,
     this loop sleeps when idle and wakes on new messages or signals *)
  while true do
    if has_pending_messages () then
      dispatch_one_message ()
    else
      (* No messages: wait for external input (network, signal, timer) *)
      wait_for_event ()
  done
```

The key difference from `run_scheduler`: the current scheduler exits when all mailboxes are empty. For applications, empty mailboxes mean "waiting for external input" (HTTP requests, timer ticks, etc.), not "done." The infinite loop uses `wait_for_event()` which blocks on a select/epoll fd set (or a simple condition variable in the interpreter).

### Signal handling

```ocaml
let install_signal_handlers root_pid =
  Sys.set_signal Sys.sigterm (Sys.Signal_handle (fun _ ->
    initiate_shutdown root_pid
  ));
  Sys.set_signal Sys.sigint (Sys.Signal_handle (fun _ ->
    initiate_shutdown root_pid
  ))

let initiate_shutdown root_pid =
  (* Send Shutdown message to root supervisor *)
  (* Root supervisor shuts down children in reverse start order *)
  (* Each child gets Shutdown message + timeout *)
  (* After all children stop, root exits *)
  (* Scheduler loop detects root death and breaks *)
  send_system_message root_pid Shutdown;
  set_shutdown_flag ()
```

## TIR Lowering (lib/tir/lower.ml)

No changes needed. The desugaring step converts `DApp` into a normal function, so TIR lowering sees standard function definitions.

The `Supervisor.Spec` type is a normal ADT. Its constructors (`OneForOne`, `Worker`, etc.) lower to tagged unions like any other ADT. No special TIR nodes.

## Monomorphization (lib/tir/mono.ml)

No changes needed. `Supervisor.Spec` and its component types are concrete (no type parameters that need specialization). The `Dynamic` type in `WorkerSpec.args` is an existing concept — it lowers to a tagged union of possible value types, which monomorphization handles.

## Defunctionalization (lib/tir/defun.ml)

No changes needed. The `__app_init__` function is first-order (takes no arguments, returns a value). No closures are involved in spec construction unless the user passes lambdas as arguments, which defunctionalization handles normally.

## LLVM Code Generation (lib/tir/llvm_emit.ml)

### Entry point emission

The LLVM `main` function (the C-level entry point, not March's `main()`) currently calls into the March runtime, which evaluates the module and calls `main()`. For applications, this changes:

```llvm
define i32 @main(i32 %argc, i8** %argv) {
entry:
  call void @march_init_runtime()
  call void @march_eval_module()

  ; Check for app marker
  %is_app = call i1 @march_has_app_marker()
  br i1 %is_app, label %app_mode, label %script_mode

app_mode:
  ; Call __app_init__ to get the spec
  %spec = call %march_value* @march__app_init__()

  ; Spawn the supervision tree from the spec
  %root_pid = call i64 @march_spawn_from_spec(%march_value* %spec)

  ; Install signal handlers
  call void @march_install_signal_handlers(i64 %root_pid)

  ; Enter infinite scheduler loop (only returns on shutdown)
  call void @march_run_scheduler_forever()

  ; Cleanup
  call void @march_shutdown_runtime()
  ret i32 0

script_mode:
  ; Existing behavior: call main(), drain scheduler, exit
  %has_main = call i1 @march_has_main()
  br i1 %has_main, label %call_main, label %exit

call_main:
  call void @march_main()
  call void @march_run_scheduler()
  br label %exit

exit:
  call void @march_shutdown_runtime()
  ret i32 0
}
```

### Runtime functions

New runtime functions needed in `runtime/march_runtime.c`:

```c
// Spawn a supervision tree from a Supervisor.Spec value
int64_t march_spawn_from_spec(march_value_t* spec);

// Infinite scheduler loop with event wait
void march_run_scheduler_forever(void);

// Signal handler installation
void march_install_signal_handlers(int64_t root_pid);

// Graceful shutdown initiation
void march_initiate_shutdown(int64_t root_pid);

// Event loop: blocks until a message arrives or a signal fires
void march_wait_for_event(void);
```

### Perceus RC considerations

Supervisor.Spec values are short-lived: they're constructed in `__app_init__`, consumed by `spawn_from_spec`, and then dead. The Perceus pass will insert a single `DecRC` after `spawn_from_spec` returns. No special handling needed.

The runtime supervisor data structures (child tables, restart counters) are managed outside the Perceus-tracked heap — they're internal runtime state, like the actor registry.

## REPL Behavior (lib/jit/repl_jit.ml)

### Evaluating app declarations

In the REPL, an `app` declaration does not start the application. Instead, it registers the spec and prints it:

```
march> app MyServer do
         Supervisor.spec(one_for_one, [
           worker(Counter, [])
         ])
       end
=> app MyServer : Supervisor.Spec
   strategy: one_for_one
   children: [Worker(Counter)]
```

### Starting and stopping applications

New REPL builtins:

```march
-- Start an application (returns the root PID)
march> let root = App.start(MyServer)
=> <pid:42> (MyServer running)

-- Stop an application gracefully
march> App.stop(root)
=> :ok (MyServer stopped)

-- Check application status
march> App.status(root)
=> :running

-- List running applications
march> App.list()
=> [MyServer(<pid:42>, :running)]
```

### Hot reload in the REPL

When you redefine an `app` in the REPL, it doesn't automatically restart. Instead:

```
march> app MyServer do
         Supervisor.spec(one_for_one, [
           worker(Counter, []),
           worker(Logger, [])       -- added a new worker
         ])
       end
=> app MyServer : Supervisor.Spec (updated, not yet applied)
   Use App.reload(MyServer) to apply changes.

march> App.reload(MyServer)
=> Diffing supervision tree...
   + Worker(Logger)          -- new child, will be started
   = Worker(Counter)         -- unchanged, kept running
   Applied. Logger started as <pid:47>.
```

This is the foundation for compiled hot reload: diff the old spec against the new one, start new children, stop removed children, leave unchanged children running.

### REPL JIT compilation

The `app` declaration compiles to the same `__app_init__` function as in batch mode. The REPL JIT compiles it as a new LLVM module fragment (same as any function), but instead of calling it immediately, it stores the resulting spec value in the REPL environment.

`App.start` calls `__app_init__`, passes the result to `spawn_from_spec`, and enters the scheduler in a background thread (or cooperative event loop) so the REPL prompt remains responsive.

```ocaml
(* In repl_jit.ml *)
| DApp (def, _span) ->
  (* Compile __app_init__ as a normal function *)
  compile_fragment "__app_init__" def.app_body;
  (* Don't call it — just register the app *)
  register_app def.app_name;
  Printf.printf "=> app %s : Supervisor.Spec\n" def.app_name.txt
```

## Process Registry

### The problem

When the runtime spawns children from a spec, it assigns PIDs. But PIDs are ephemeral — they change on restart. Code that needs to send messages to a specific service (e.g., the database pool) needs a stable way to find it.

Today, March uses `get_actor_field(supervisor_pid, "field_name")` to extract child PIDs from supervisor state. This is fragile: it requires knowing the supervisor's internal field names, returns raw integers, and breaks if the supervision tree is restructured.

### Named children

Children in a spec can have names:

```march
app MyServer do
  Supervisor.spec(one_for_one, [
    worker(DbPool, [], name: :db_pool),
    worker(HttpServer, [port: 8080], name: :http)
  ])
end
```

Names are atoms, scoped to the application. The runtime maintains a name → PID mapping that updates automatically on restart.

### Lookup API

```march
-- Find a named process (returns Option(Pid))
let db = App.whereis(:db_pool)

-- Find or crash (for when the process must exist)
let db = App.whereis!(:db_pool)
```

In the interpreter, this is a new builtin:

```ocaml
("whereis", VBuiltin ("whereis", function
  | [VAtom name] ->
    (match Hashtbl.find_opt process_registry name with
     | Some pid when is_alive pid -> VCon ("Some", [VPid pid])
     | _ -> VCon ("None", []))
  | _ -> eval_error "whereis: expected atom argument"))
```

### Automatic registration

When a supervisor starts a named child, it registers the name:

```ocaml
let spawn_named_child name child_spec =
  let pid = spawn_child child_spec in
  Hashtbl.replace process_registry name pid;
  pid

(* On restart, the old name is re-bound to the new PID *)
let restart_named_child name child_spec =
  let new_pid = spawn_child child_spec in
  Hashtbl.replace process_registry name new_pid;
  new_pid
```

## Lifecycle Hooks

### on Shutdown handler

Actors can define an `on Shutdown` handler for graceful cleanup:

```march
actor DbPool do
  state { connections : List(Connection) }
  init  { connections = [] }

  on Shutdown() do
    -- Close all connections before dying
    List.each(state.connections, fn conn -> Connection.close(conn) end)
    { connections = [] }
  end
end
```

The runtime sends `Shutdown()` as a normal message during graceful shutdown. The actor processes it like any other message. If the actor doesn't define `on Shutdown`, the runtime waits for the shutdown timeout and then force-kills.

### App-level hooks

The `app` block can include lifecycle hooks alongside the spec:

```march
app MyServer do
  let config = load_config("server.toml")

  on_start do
    println("MyServer starting on port ${config.port}")
    Metrics.init()
  end

  on_stop do
    println("MyServer shutting down")
    Metrics.flush()
  end

  Supervisor.spec(one_for_one, [
    worker(HttpServer, [port: config.port])
  ])
end
```

`on_start` runs after the supervision tree is fully started (all children alive). `on_stop` runs after all children have stopped during shutdown. Both are optional.

### AST extension for hooks

```ocaml
and app_def = {
  app_name  : name;
  app_body  : expr;              (* Returns Supervisor.Spec *)
  app_on_start : expr option;    (* Runs after tree is up *)
  app_on_stop  : expr option;    (* Runs after tree is down *)
}
```

## Shutdown Protocol

### Shutdown sequence

When the runtime receives SIGTERM (or `App.stop` is called):

1. Call `on_stop` hook if defined (pre-shutdown notification).
2. Send `Shutdown()` to the root supervisor.
3. Root supervisor shuts down children in **reverse start order** (last started = first stopped).
4. For each child:
   a. Send `Shutdown()` message.
   b. Wait up to `shutdown_timeout` milliseconds.
   c. If still alive after timeout, force-kill.
   d. If child is a supervisor, it recursively shuts down its children first.
5. After all children are stopped, root supervisor exits.
6. Call `on_stop` hook if defined (post-shutdown cleanup).
7. Runtime exits with code 0.

### Shutdown timeout cascade

Supervisors have `shutdown: Infinity` by default, meaning the parent waits indefinitely for the supervisor to finish shutting down its children. This creates a natural cascade: leaf workers have finite timeouts (default 5000ms), and the time bubbles up.

### Exit codes

| Scenario | Exit Code |
|---|---|
| Normal shutdown (SIGTERM, App.stop) | 0 |
| Root supervisor restart budget exceeded | 1 |
| Unhandled exception in app body | 1 |
| main() returns normally | 0 |
| main() throws unhandled exception | 1 |

## Dynamic Children

### The problem

Static child specs cover most cases, but some supervisors need to start children dynamically — connection handlers, job workers, session managers. Erlang's `simple_one_for_one` strategy handles this.

### Dynamic supervisor spec

```march
app MyServer do
  Supervisor.spec(one_for_one, [
    worker(Acceptor, [port: 8080]),
    dynamic_supervisor(:connections, one_for_one,
      max_restarts: 100, within: 10)
  ])
end
```

`dynamic_supervisor` creates a supervisor with no initial children. Children are added at runtime:

```march
-- Inside the Acceptor actor's handler:
on NewConnection(socket) do
  let handler_spec = worker(ConnectionHandler, [socket: socket],
                            restart: Temporary)
  Supervisor.start_child(:connections, handler_spec)
  state
end
```

### API

```march
-- Start a child under a dynamic supervisor
Supervisor.start_child(sup_name : Atom, spec : ChildSpec) : Result(Pid, String)

-- Stop a specific child
Supervisor.stop_child(sup_name : Atom, pid : Pid) : Result(Unit, String)

-- List current children
Supervisor.which_children(sup_name : Atom) : List({Pid, ActorType, RestartPolicy})

-- Count children
Supervisor.count_children(sup_name : Atom) : {active: Int, specs: Int}
```

## Testing

### Unit tests for spec construction

Specs are values, so they're directly testable without spawning actors:

```march
fn test_spec_construction() do
  let spec = Supervisor.spec(one_for_one, [
    worker(Counter, []),
    worker(Logger, [])
  ])

  assert(spec.strategy == OneForOne)
  assert(List.length(spec.children) == 2)
end
```

### Integration tests for app lifecycle

New test helpers in `test/test_march.ml`:

```ocaml
(* Test that an app starts and stops cleanly *)
let test_app_lifecycle () =
  let src = {|
    mod Test do
      actor Worker do
        state { n : Int }
        init  { n = 0 }
        on Ping() do { n = state.n + 1 } end
        on Shutdown() do state end
      end

      app TestApp do
        Supervisor.spec(one_for_one, [
          worker(Worker, [], name: :worker)
        ])
      end
    end
  |} in
  let result = run_app_with_timeout src ~timeout:1000 ~actions:[
    Send (Atom "worker", Msg "Ping");
    Send (Atom "worker", Msg "Ping");
    AssertField (Atom "worker", "n", Int 2);
    Stop;
  ] in
  Alcotest.(check bool) "app ran cleanly" true result.clean_exit

(* Test graceful shutdown *)
let test_graceful_shutdown () =
  let src = {|
    mod Test do
      actor Cleanup do
        state { cleaned : Bool }
        init  { cleaned = false }
        on Shutdown() do
          println("cleaning up")
          { cleaned = true }
        end
      end

      app TestApp do
        Supervisor.spec(one_for_one, [
          worker(Cleanup, [], name: :cleanup)
        ])
      end
    end
  |} in
  let result = run_app_with_timeout src ~timeout:1000 ~actions:[
    Stop;
    AssertOutput "cleaning up";
  ] in
  Alcotest.(check bool) "shutdown handler ran" true result.clean_exit
```

### Test categories

1. **Spec construction tests** (pure, no actors): verify that builder functions produce correct spec values.
2. **App lifecycle tests**: start an app, verify it's running, stop it, verify clean exit.
3. **Restart tests**: start an app, kill a child, verify restart behavior matches strategy.
4. **Registry tests**: start named children, look them up with `whereis`, verify names update on restart.
5. **Shutdown tests**: verify `on Shutdown` handlers run, verify reverse-order shutdown, verify timeout enforcement.
6. **Dynamic supervisor tests**: start dynamic children, verify they appear in the tree, stop them.
7. **REPL tests**: evaluate `app` in REPL, call `App.start`, call `App.stop`, verify REPL stays responsive.
8. **Mutual exclusivity test**: compile a module with both `main()` and `app`, verify compile error.
9. **Signal handling tests**: send SIGTERM to a running app binary, verify graceful shutdown.
10. **Hot reload tests** (REPL only): redefine an app, call `App.reload`, verify diff is applied correctly.

### Alcotest suite structure

```ocaml
let () =
  Alcotest.run "march_app" [
    "spec", [
      test_case "basic spec" `Quick test_basic_spec;
      test_case "nested supervisors" `Quick test_nested_spec;
      test_case "restart policies" `Quick test_restart_policies;
      test_case "shutdown policies" `Quick test_shutdown_policies;
    ];
    "lifecycle", [
      test_case "start and stop" `Quick test_app_lifecycle;
      test_case "graceful shutdown" `Quick test_graceful_shutdown;
      test_case "reverse order shutdown" `Quick test_reverse_shutdown;
      test_case "shutdown timeout" `Quick test_shutdown_timeout;
    ];
    "restart", [
      test_case "one_for_one" `Quick test_one_for_one;
      test_case "one_for_all" `Quick test_one_for_all;
      test_case "rest_for_one" `Quick test_rest_for_one;
      test_case "max restarts exceeded" `Quick test_max_restarts;
    ];
    "registry", [
      test_case "whereis named" `Quick test_whereis;
      test_case "name survives restart" `Quick test_name_restart;
      test_case "whereis unknown" `Quick test_whereis_unknown;
    ];
    "dynamic", [
      test_case "start child" `Quick test_dynamic_start;
      test_case "stop child" `Quick test_dynamic_stop;
      test_case "which children" `Quick test_which_children;
    ];
    "repl", [
      test_case "app in repl" `Quick test_repl_app;
      test_case "app start stop" `Quick test_repl_start_stop;
      test_case "app reload" `Quick test_repl_reload;
    ];
    "errors", [
      test_case "main and app conflict" `Quick test_main_app_conflict;
      test_case "bad spec type" `Quick test_bad_spec_type;
    ];
  ]
```

## Implementation Plan

### Phase 1: Core app declaration (interpreter only)

1. Add `APP` token to lexer, `app_decl` rule to parser, `DApp` to AST.
2. Add mutual-exclusivity validation pass.
3. Implement desugaring of `DApp` → `__app_init__` + marker.
4. Add `Supervisor.Spec` type to stdlib/prelude.
5. Implement `spawn_from_spec` in interpreter.
6. Implement `run_scheduler_forever` with event wait.
7. Wire up entry-point dispatch in `run_module`.
8. Add basic signal handling (SIGTERM/SIGINT → graceful shutdown).
9. Write Phase 1 tests (spec construction, lifecycle, restart).

**Estimated effort**: 3-4 sessions.

### Phase 2: Registry and named children

1. Implement process registry (hash table, atom → pid).
2. Add `name:` option to `worker()` builder.
3. Implement `whereis` and `whereis!` builtins.
4. Wire registry updates into supervisor restart logic.
5. Write registry tests.

**Estimated effort**: 1-2 sessions.

### Phase 3: Lifecycle hooks and shutdown protocol

1. Add `on Shutdown` handler recognition in actor evaluation.
2. Implement ordered shutdown sequence (reverse start order).
3. Implement shutdown timeout enforcement.
4. Add `on_start` / `on_stop` hooks to `app_def`.
5. Parse hooks in `app` block.
6. Write shutdown and hook tests.

**Estimated effort**: 2 sessions.

### Phase 4: Dynamic supervisors

1. Add `dynamic_supervisor` builder function.
2. Implement `Supervisor.start_child` / `stop_child` builtins.
3. Implement `which_children` / `count_children`.
4. Write dynamic supervisor tests.

**Estimated effort**: 1-2 sessions.

### Phase 5: REPL integration

1. Handle `DApp` in REPL JIT (register, don't start).
2. Implement `App.start`, `App.stop`, `App.status`, `App.list` builtins.
3. Implement background scheduler for REPL (cooperative or threaded).
4. Implement `App.reload` with spec diffing.
5. Write REPL tests.

**Estimated effort**: 2-3 sessions.

### Phase 6: LLVM codegen

1. Emit entry-point dispatch in LLVM `@main`.
2. Implement `march_spawn_from_spec` in C runtime.
3. Implement `march_run_scheduler_forever` with epoll/select.
4. Implement `march_install_signal_handlers` in C runtime.
5. Wire up the compiled app path end-to-end.
6. Write compiled-mode tests (binary start/stop, signal handling).

**Estimated effort**: 3-4 sessions.

### Total estimated effort: 12-17 sessions.

## Interaction with Existing Features

### Perceus RC

Supervisor.Spec values are normal heap-allocated ADTs. Perceus handles them like any other value — IncRC/DecRC as needed, freed when dead. The runtime supervisor structures (child tables, registries) are **not** RC-tracked; they live in the runtime's own allocator and are freed during shutdown.

### Linear types

Actor capabilities (`Cap(A, e)`) are non-linear by design. Named process lookup (`whereis`) returns a fresh capability, so there's no linearity conflict. If a user holds a linear capability to a supervised actor and the actor restarts, the capability's epoch is stale — `send_checked` returns `:error`, which is the correct behavior.

### Content-addressed storage

The `__app_init__` function gets a CAS hash like any other function. If the app body hasn't changed, its cached compilation result is reused. The app marker (`__app_marker__`) is a simple boolean let binding with a trivial hash.

### Session types

Session-typed channels between supervised actors work naturally. If an actor restarts mid-session, the other end's channel becomes invalid (type-level epoch mismatch). The protocol needs to handle reconnection — this is a design constraint on the user's protocol, not something the supervisor can magically fix. (Erlang has the same limitation: restart ≠ resume.)

### FBIP

Spec construction is allocation-heavy (building lists of child specs) but short-lived. FBIP won't apply here because the spec is constructed once and consumed once — there's no destructure-and-rebuild pattern. This is fine; spec construction is cold-path code.

## Message Linearity Rule (v1)

### The rule

**Actor messages must not contain linear types.** The type checker rejects any `send` or message handler where the message type transitively contains a `linear` field. Affine and unrestricted types are permitted.

```march
-- OK: all fields are unrestricted
send(worker, Update(42, "hello"))

-- OK: affine capability is fine
send(worker, Connect(my_cap))

-- COMPILE ERROR:
send(worker, TransferFile(my_linear_file))
-- ERROR: Message type TransferFile contains linear field
--        `file : linear File`.
--        Linear values cannot be sent between actors.
--        Hint: use a capability handle instead, or manage
--        the resource inside the owning actor.
```

### Enforcement mechanism

The existing `Sendable(a)` constraint is extended. The compiler already derives `Sendable` for types composed of sendable parts and refuses it for closures, mutable references, and node-local capabilities. The rule adds one clause:

```
Sendable(a) fails if a contains any field with linearity = Linear
```

Implementation in `lib/typecheck/typecheck.ml`: the `check_sendable` function walks the type structure. When it encounters `TyLinear(Linear, _)`, it emits a diagnostic. When it encounters `TyLinear(Affine, inner)`, it recurses into `inner`. Unrestricted types pass unconditionally.

The check fires at two points:

1. **`send` and `send_checked` calls.** The second argument's type must satisfy `Sendable`.
2. **Actor handler declarations.** Each `on Msg(fields...)` handler's message fields must individually satisfy `Sendable`. This catches the problem at the definition site, not just at send sites.

### Why this rule exists

Linear values carry an obligation: they must be consumed exactly once. When a linear value crosses an actor boundary via a message, that obligation transfers to the recipient. But three shutdown/failure scenarios break the contract:

1. **Actor dies with linear message in mailbox.** The message was never processed. The linear value is never consumed. The obligation is violated.
2. **Actor dies with linear value in state (received via message).** The `on Shutdown` handler might not run (timeout, force-kill). The resource leaks.
3. **Supervisor restarts actor.** Old state is dropped, including any linear values received via messages. Without a guaranteed Drop mechanism, resources leak silently.

Banning linear values in messages eliminates all three scenarios. The only way an actor holds a linear resource is if it created one itself (in `init` or a handler). The actor's `on Shutdown` handler can consume it, and the type checker can verify that it does.

### What this means for actor design

**Before (with linear messages, hypothetical):**
```march
-- Actor A creates a file and sends it to Actor B
actor Producer do
  on Produce() do
    let f = File.open("data.csv")
    send(consumer, Process(transfer f))  -- ownership transfer
    state
  end
end
```

**After (v1 rule: no linear messages):**
```march
-- Actor A creates and owns the file; Actor B requests operations on it
actor FileManager do
  state { file : linear File }
  init  { file = File.open("data.csv") }

  on Read(offset : Int, len : Int) do
    let data = File.read(state.file, offset, len)
    respond(data)  -- data is String, not linear
    state
  end

  on Shutdown() do
    File.close(state.file)
    { file = File.closed() }  -- sentinel or unit
  end
end
```

The pattern shifts from "send the resource" to "send messages about the resource." The actor that creates a linear resource owns it for its entire lifetime, cleaning it up in `on Shutdown`. Other actors interact with the resource via request/response messages containing only plain data.

### Interaction with the Sendable constraint

The full `Sendable` derivation rules in v1:

| Type | Sendable? | Reason |
|---|---|---|
| `Int`, `Float`, `Bool`, `String`, `Atom` | Yes | Value types, freely copyable |
| `List(a)`, `Option(a)`, `Result(a,e)` | If inner types are Sendable | Recursive check |
| `{field1: a, field2: b}` (records) | If all fields are Sendable | Recursive check |
| `Pid(a)` | Yes | Location-transparent reference |
| `Cap(a, e)` (affine) | Yes | Affine is OK to send; recipient gets a copy |
| `linear T` (any T) | **No** | v1 ban on linear message content |
| Closures / `fn` values | No | May capture mutable state |
| `Ptr(a)` (FFI pointer) | No | Node-local, not meaningful across actors |

### Interaction with shutdown protocol

With the linear message ban in place, shutdown simplifies dramatically:

1. **Mailbox cleanup.** When an actor dies, unprocessed messages in its mailbox contain only `Sendable` values. These are either unrestricted (Perceus frees them normally via DecRC) or affine (can be discarded, Perceus frees). No special walk needed.

2. **State cleanup.** An actor's state may contain linear values that the actor created itself. The `on Shutdown` handler consumes them. If the actor defines linear state fields but no `on Shutdown` handler, the type checker emits a warning: "Actor Foo has linear field `file` but no Shutdown handler. The resource will leak on shutdown."

3. **Restart cleanup.** When a supervisor restarts an actor, the old actor's state is dropped. For linear fields, the runtime calls the compiler-generated Drop function (see below). For non-linear fields, Perceus handles it.

### Drop for actor-local linear values

Even with the message ban, actors can still create and hold linear values in their state. These need cleanup on abnormal termination (crash without Shutdown handler running). The compiler generates a `__drop_state__` function for each actor that has linear fields:

```ocaml
(* Generated for actor DbPool with state { conn : linear Connection } *)
let __drop_state__DbPool (state : dbpool_state) : unit =
  Connection.drop(state.conn)
```

This function is called by the runtime when:
- The actor crashes (unhandled exception in a handler)
- The actor is force-killed (shutdown timeout exceeded)
- The `on Shutdown` handler itself crashes

The type checker requires that every `linear` type used in actor state has a `Drop` implementation:

```march
interface Drop(a) do
  fn drop(value : linear a) : Unit
end

impl Drop(File) do
  fn drop(f) do File.close(f) end
end

impl Drop(Connection) do
  fn drop(c) do Connection.disconnect(c) end
end
```

If an actor declares `state { f : linear File }` and `File` has no `Drop` impl, the type checker errors: "Actor state contains linear field `f : File`, but `File` does not implement `Drop`. Either implement `Drop(File)` or change the field to non-linear."

## Ownership Transfer (v2 — Future)

### Motivation

The v1 ban on linear messages is deliberately conservative. It simplifies shutdown, restart, and resource tracking at the cost of expressiveness. There are legitimate use cases for ownership transfer between actors:

- **Zero-copy pipelines.** Actor A reads a large buffer from a socket, sends it to Actor B for processing. With the v1 rule, A must copy the data into a non-linear message. With transfer semantics, the buffer moves without copying.
- **Resource delegation.** A setup actor creates database connections during initialization, then hands them off to worker actors. Without transfer, each worker must create its own connection.
- **Session-typed protocols.** A file transfer protocol where one side sends a file handle to the other. Session types can statically verify the protocol, but only if linear values can appear in messages.

### The `transfer` keyword

v2 introduces a `transfer` qualifier on message fields that permits linear values:

```march
-- Define a message type with a transferable field
type FileMsg =
  | Process(transfer file : linear File)
  | Done

-- Sending: the linear value is consumed at the send site
fn hand_off(worker : Pid, f : linear File) do
  send(worker, Process(f))
  -- f is consumed here; using it after this line is a compile error
end

-- Receiving: the handler receives ownership
actor Worker do
  state { current : Option(linear File) }
  init  { current = None }

  on Process(f : linear File) do
    { current = Some(f) }
  end

  on Shutdown() do
    match state.current with
    | Some(f) -> File.close(f)
    | None -> ()
    end
    { current = None }
  end
end
```

### Type checking rules for transfer

1. **At the send site**, the linear value is consumed. The use-counting pass treats `send(pid, Msg(linear_val))` as a consumption of `linear_val`. Using it after the send is a compile error.

2. **At the handler site**, the linear value is freshly bound. The handler's pattern variable for a `transfer` field has linearity `Linear`, and the type checker enforces that the handler body consumes it exactly once (or stores it in a linear state field for later consumption).

3. **The message type itself** must declare which fields are `transfer`. A message type with `transfer` fields satisfies a new `Transferable` constraint, which is a superset of `Sendable`:

```
Transferable(a) iff:
  - All non-transfer fields satisfy Sendable(a)
  - All transfer fields are linear (verified at declaration)
```

4. **`send` is overloaded.** Messages satisfying `Sendable` use the normal send path. Messages satisfying `Transferable` (but not `Sendable`) use a transfer-aware send path that marks the message as containing linear resources.

### Mailbox implications

With transfer, unprocessed messages in a dead actor's mailbox may contain linear values. The runtime must walk the mailbox and call Drop on any linear fields in `transfer` message slots:

```ocaml
let cleanup_mailbox (actor : actor_instance) =
  Queue.iter (fun msg ->
    match msg with
    | TransferableMsg (tag, fields) ->
      List.iter (fun (field, is_transfer) ->
        if is_transfer then
          call_drop field
        else
          decrc field
      ) fields
    | PlainMsg _ ->
      (* Only Sendable fields — Perceus handles it *)
      decrc_message msg
  ) actor.mailbox
```

This adds a cost to the kill path — iterating over potentially many messages. For actors with large mailboxes, this could be significant. The cost is bounded by the number of unprocessed transfer messages, which in practice is small (most messages are plain data).

### Restart implications

When a supervised actor is restarted and its old incarnation held transfer-received linear values in state, the same Drop logic applies. The compiler-generated `__drop_state__` function handles it identically to actor-created linear values — by the time the value is in the actor's state, it doesn't matter whether it was created locally or received via transfer.

### Implementation cost

Transfer semantics require changes across the stack:

1. **AST**: new `transfer` qualifier on ADT constructor fields.
2. **Type checker**: `Transferable` constraint, use-counting at send sites.
3. **Desugaring**: mark transfer messages for the runtime.
4. **TIR/codegen**: tag transfer message fields in the runtime representation so mailbox cleanup can identify them.
5. **Runtime**: mailbox walk-and-drop on actor death.
6. **REPL**: transfer semantics must work in the JIT, including proper linear value tracking across REPL expressions.

This is estimated at 4-6 sessions of work, contingent on the Drop infrastructure from v1 being in place.

### Migration path

v1 code works unchanged in v2. The only new capability is that message types can now declare `transfer` fields. Existing messages without `transfer` continue to satisfy `Sendable` and follow the same rules.

The compiler can offer an automatic migration hint when it sees the v1 workaround pattern (actor wrapping a resource with request/response messages): "Consider using `transfer` to send this resource directly instead of wrapping it in a manager actor." This is advisory only — the wrapping pattern remains valid and is often the better design.

## Open Questions

1. **Should `app` support parameterization?** E.g., `app MyServer(port : Int)` where the parameter comes from command-line args. This would require argument parsing before spec construction. Current design: no, keep it simple. Use `env()` or `load_config()` inside the body.

2. **Multiple apps per project?** Some projects have several runnable services (web server, worker, migrator). Should a project support multiple `app` declarations in different modules? If so, how does the runtime choose which one to start? Erlang uses `-s module` flag. Possible: `march run --app MyServer` vs `march run --app MyWorker`.

3. **App dependencies?** Erlang applications can depend on other applications (e.g., your web app depends on the logger app). This adds significant complexity (boot order, dependency DAG). Defer to post-v1.

4. **Distributed apps?** An application that spans multiple nodes. Requires cluster membership, actor migration, distributed registry. Far-future concern — note it, don't design it yet.

5. **Config reload without restart?** Some services need to reload configuration (e.g., log level, feature flags) without restarting the supervision tree. This could be a message-based pattern (`send(:config_manager, Reload)`) rather than a framework feature. Worth documenting as a pattern.

6. **Should the Drop interface be required or optional for linear types?** Current design requires it for any linear type used in actor state. But linear types used only in pure functions (never stored in actors) don't need Drop. Should the requirement be "Drop is needed when the linear type appears in actor state" rather than "all linear types need Drop"? The former is more permissive but requires more complex analysis.

7. **Transfer and session types interaction.** In v2, should session-typed channels automatically use `transfer` semantics for linear protocol steps? Or should the user explicitly annotate which protocol messages carry linear values? The former is more ergonomic; the latter gives more control.
