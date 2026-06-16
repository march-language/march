# Async Mailbox Dispatch — Design Plan

## Overview

Currently, actor message dispatch in the interpreter is synchronous and single-threaded.
`run_scheduler()` is a flat while-loop that drains one message per actor per pass, calling
handlers inline. `receive()` inside a handler errors immediately if the mailbox is empty.

This document plans **Phase 4**: making `receive()` a true blocking operation — cooperative
blocking in the interpreter, and real green-thread parking in the compiled path.

The compiled C runtime already supports true blocking `receive()` via `march_sched_recv()`
(which parks the green thread as `PROC_WAITING` and resumes it when `march_sched_send`
deposits a message). The work is wiring `receive()` at the language level into both paths.

---

## Current State

| Component | Status |
|---|---|
| `run_scheduler()` in `eval.ml` | Synchronous flat loop; no blocked-actor concept |
| `receive()` builtin (interpreter) | `Queue.pop` — errors if empty |
| `receive()` → LLVM (compiled) | **Missing** — no `EApp` → `march_sched_recv` translation |
| `march_sched_recv()` in C runtime | **Complete** — parks green thread, returns on message |
| `Scheduler.ml` park/wake (OCaml) | **Dead code** — defined but never called by `run_scheduler` |

---

## Known Design Issues (must resolve before implementation)

### BLOCKING: Cooperative blocking requires a decision on replay hazard

When `receive()` blocks in the interpreter, the entire handler body must retry from the
beginning on the next scheduler pass (no continuations in OCaml 4). This means any side
effects before `receive()` execute multiple times.

**Decision required** — choose one of:

**(A) Restrict `receive()` to be the first operation in a handler body.**
A typecheck or linting rule enforces this. Safe, but limits expressivity: handlers that
compute something before waiting for an additional message are disallowed.

**(B) Accept and document the replay hazard.**
Document that effects before `receive()` (e.g. sending a message) may replay. The safe
pattern is `receive()` as the first expression. Mark with a typecheck warning.

**(C) OCaml 5 effects (correct long-term solution).**
Wrap each handler dispatch in `Effect.Deep.match_with`. `receive()` performs a `Blocked`
effect that the scheduler catches, saves the continuation, and resumes with the message
as the effect return value. Requires adopting OCaml 5 effects in the eval path.
Higher investment; eliminates the replay hazard entirely.

**Recommendation:** Start with (B) for immediate unblocking. Plan (C) as a follow-up.

### BLOCKING: `receive()` has no compiled-mode wiring

`receive()` is in the interpreter builtin table and in `defun.ml`'s actor-aware passthrough
list, but it has no translation in `llvm_emit.ml`. Any compiled actor that calls `receive()`
falls through to a default `EApp` case, emitting a call to a nonexistent `@receive` function
and failing at link time.

**Fix:** Add `"receive" -> "march_sched_recv"` to the `builtin_c_name` dispatch table in
`llvm_emit.ml`, and add `declare ptr @march_sched_recv()` to the LLVM preamble.

### MAJOR: `receive()` type signature is unsound

Current type: `poly1(fun a -> a)` — a free type variable. The actual return type is the
actor's message union type, which the typechecker cannot verify.

For Phase 4, keep `poly1` for backward compatibility but add a typecheck warning when
`receive()` is called outside an actor handler body (a `tc_in_actor_handler` context flag).
Narrowing to the exact message union type is a larger type system change — deferred.

### MAJOR: `run_scheduler()` never uses `Scheduler.ml` park/wake

`eval.ml:6835` has its own inline scheduler loop that never calls `March_scheduler.Scheduler`
at all. The `PReady/PWaiting` states in `scheduler.ml` are dead code at runtime. For Phase 4
cooperative blocking, the interpreter does not need to wire into `Scheduler.ml` — the
`BlockedOnReceive` exception approach is self-contained in `eval.ml`.

### MINOR: Snapshot-based scheduler has one-pass latency for chained sends

`run_scheduler()` snapshots all pids at the start of each outer iteration. If actor A's
handler sends to actor B, B won't be scheduled until the next outer iteration. This introduces
artificial latency in ping-pong scenarios (one extra scheduler pass per message hop) but is
invisible in tests where all messages are pre-queued.

**Fix (optional):** After running a handler that calls `send()`, immediately check if the
target actor became ready and prepend it to the current iteration's work list. Or switch to a
FIFO work queue of `(pid, msg)` pairs that new sends push to the back.

### MINOR: `march_send()` takes global table lock on every call

`march_send()` in the C runtime calls `find_or_create_meta()` which acquires `g_tbl_mu`.
Tight send loops contend on this lock.

**Fix (optional / post-v1):** Cache `march_actor_meta*` in the actor struct as a side-channel
field (outside the March-visible region) so the fast path skips the mutex entirely.

---

## Design: Interpreter Cooperative Blocking

Add `exception BlockedOnReceive` to `eval.ml`. The `receive()` builtin raises it when the
mailbox is empty. `run_scheduler()`'s handler dispatch catches it, re-inserts the consumed
message at the front of the mailbox, and skips the actor for the current pass.

The outer `while !changed` loop already terminates correctly when all actors are blocked:
no actor makes progress → `changed` stays false → loop exits. No explicit waiting-list
bookkeeping is needed.

**Kill-while-blocked:** When `kill(pid)` is called on a blocked actor, it sets `ai_alive = false`.
The next scheduler pass checks `inst.ai_alive` before processing — the actor is skipped and
never re-scheduled.

**Restriction (with Option B):** `receive()` must be the first (or only) blocking call in a
handler body to avoid side-effect replay. Document this as the "safe receive pattern".

---

## Design: Compiled Path

`receive()` in March source lowers to `call ptr @march_sched_recv()` in LLVM IR.

`march_sched_recv()` in the C runtime:
1. Checks if the current actor's mailbox has a message.
2. If yes: dequeues and returns the message pointer (RC=1, transferred from sender via Perceus).
3. If no: sets the green thread's status to `PROC_WAITING`, yields to the scheduler.
4. The scheduler resumes this green thread when `march_sched_send` delivers a message.
5. Returns the message pointer.

If the actor is killed while waiting, `march_sched_recv()` returns `NULL`. The
`actor_green_thread` loop checks for `NULL` and exits — the actor dies cleanly.

RC contract: the returned pointer has RC=1 (handed off by the sender). No additional
`incrc` is needed at the call site.

---

## Code Stubs

### `lib/eval/eval.ml` — `BlockedOnReceive` exception + receive() builtin

```ocaml
exception BlockedOnReceive

(* Replace the existing receive builtin body: *)
; ("receive", VBuiltin ("receive", function
      | [] ->
        (match !current_pid with
         | Some pid ->
           (match Hashtbl.find_opt actor_registry pid with
            | Some inst when not (Queue.is_empty inst.ai_mailbox) ->
              Queue.pop inst.ai_mailbox
            | Some _ ->
              (* Mailbox empty — block. The scheduler will retry this handler
                 when a message arrives. Side effects before this point will
                 be replayed on retry (Option B: documented hazard). *)
              raise BlockedOnReceive
            | None -> eval_error "receive: actor %d not found" pid)
         | None -> eval_error "receive: called outside an actor handler")
      | _ -> eval_error "receive: expected 0 arguments"))
```

### `lib/eval/eval.ml` — catch `BlockedOnReceive` in `run_scheduler`

```ocaml
(* In run_scheduler, replace the eval_expr_hook call section with: *)
(match !eval_expr_hook handler_env handler.ah_body with
 | new_state ->
   inst.ai_state <- new_state;
   changed := true
 | exception BlockedOnReceive ->
   (* Actor is waiting for a message. Re-insert the popped message at the
      front of the mailbox so the next scheduler pass can retry.
      Do NOT set changed := true — no progress was made. *)
   let front_q = Queue.create () in
   Queue.push msg front_q;
   Queue.transfer inst.ai_mailbox front_q;
   inst.ai_mailbox <- front_q
 | exception exn ->
   clear_march_stack ();
   crash_actor pid (Printexc.to_string exn))
```

### `lib/tir/llvm_emit.ml` — wire `receive()` to `march_sched_recv`

```ocaml
(* In builtin_c_name dispatch table (~line 753), add: *)
| "receive" -> "march_sched_recv"

(* In the LLVM preamble declarations (non-REPL block), add: *)
"declare ptr @march_sched_recv()\n"

(* In EApp lowering for zero-arg builtins, receive() becomes:
   call ptr @march_sched_recv()
   The returned ptr is the message object with RC=1 from sender's Perceus transfer.
   No additional incrc is needed. *)
```

### `lib/typecheck/typecheck.ml` — warn on `receive()` outside handler

```ocaml
(* Add to tc_env or a context record: *)
type tc_context = {
  (* ... existing fields ... *)
  mutable tc_in_actor_handler : bool;  (* set true inside ah_body lowering *)
}

(* When typechecking receive() call sites: *)
| "receive" ->
  if not ctx.tc_in_actor_handler then
    emit_warning span "receive() called outside an actor handler — \
                       this is only safe inside an `on` handler body";
  (* Keep existing poly1 type — narrowing to message union deferred *)
  poly1 (fun a -> a)
```

---

## Test Plan

| Test | File | What | Pass criterion |
|---|---|---|---|
| `test_receive_blocks_until_message` | `test/test_march.ml` | Handler calls `receive()` on empty mailbox; second send unblocks it | Actor state reflects both messages processed |
| `test_receive_does_not_deadlock_on_empty` | `test/test_march.ml` | All actors blocked; `run_scheduler()` terminates | Returns without hanging |
| `test_receive_kill_while_blocked` | `test/test_march.ml` | Kill actor that is blocked in `receive()` | `is_alive = false`; no crash |
| `test_ping_pong_two_actors` | `test/test_march.ml` | Pinger ↔ Ponger exchange: Ping → receive → Pong → receive | Both actors increment counters |
| `test_receive_ordering_fifo` | `test/test_march.ml` | Send M1, M2, M3 to receive()-blocked actor | Delivered in order M1, M2, M3 |
| `test_receive_side_effects_before_blocking` | `test/test_march.ml` | Side effect before `receive()` — document replay behaviour | Vault counter incremented exactly once (or twice if replay — documents the hazard) |
| `test_compiled_receive_blocks_green_thread` | `test/test_march.ml` | Compiled actor calls `receive()` mid-handler; second send unblocks | Binary exits 0; correct output |
| `test_receive_llvm_declaration` | `test/test_march.ml` | LLVM IR contains `declare ptr @march_sched_recv()` | IR grep passes |

**Example test (ping-pong):**

```march
actor Pinger do
  state { count : Int, ponger : Pid }
  init { count = 0, ponger = spawn(Ponger) }

  on Start() do
    let _ = send(state.ponger, Ping())
    let pong = receive()
    { state with count = state.count + 1 }
  end
end

actor Ponger do
  state { count : Int }
  init { count = 0 }

  on Ping() do
    { state with count = state.count + 1 }
  end
end
```

---

## Documentation Plan

| Section | File | What |
|---|---|---|
| Phase 4 interpreter semantics | `specs/features/actor-system.md` under "receive (Async)" | Replace "requires Phase 4 multi-threaded scheduler" with: cooperative blocking model using `BlockedOnReceive`; safe pattern; replay hazard note |
| Phase 4 compiled path | `specs/actor-lowering.md` new section "Async receive in compiled actors" | `receive()` → `march_sched_recv()` LC contract; kill-while-blocked path |
| Safe `receive()` patterns | `specs/features/actor-system.md` new sub-section "Using receive() safely" | Two valid use patterns; interpreter vs compiled differences |
| Phase 4 checklist | `specs/todos.md` Phase 4 bullet list | Split into: (a) interpreter cooperative blocking; (b) LLVM compiled path; (c) selective receive / timeout (Phase 5 extension) |
| `Scheduler.ml` scope | `lib/scheduler/scheduler.ml` header | "Interpreter-only scaffolding; not wired to C runtime; park/wake states are reserved for a future OCaml 5 Domains path" |

---

## Scope of Phase 4

**In scope:**
- `receive()` as the sole blocking call in a handler body (interpreter + compiled)
- `receive()` in a free-running actor server loop (compiled only; interpreter with Option C)
- Kill-while-blocked: actor correctly dies when killed during `receive()`

**Out of scope for Phase 4 (future work):**
- **Selective receive** — pattern-filtered receive with a save queue. The C runtime has
  `march_mailbox_t` with a save-pointer stub. March-level syntax not yet designed.
- **Timeout on receive** — `receive(timeout_ms)`. `actor_call` accepts a `timeout_ms`
  parameter that is currently ignored. Phase 4 does not add timeout enforcement.
- **Supervision + receive** — `receive()` inside a supervisor handler. Supervisor handlers
  use the same dispatch mechanism; safe with Option C only. For now: document as unsupported.
- **Remote actors** — networked message passing. No change here.
- **Session types** — protocol validation against actor message sequences.
- **`receive()` type narrowing** — narrowing `poly1` to the exact message union type requires
  per-actor type propagation. Deferred.
