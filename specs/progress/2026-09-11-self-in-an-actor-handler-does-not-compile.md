# `[P1]` `self` inside an actor handler emits invalid IR

**Shipped 2026-09-12.** See "What shipped" at the end.

Found 2026-09-11 while designing the mailbox transport for
`2026-09-11-actor-hosted-session-endpoint.md`. Interpreter-only feature: every
compiled program that names `self` in a handler fails to build.

## The bug

```march
mod Self1 do
  needs IO.Console
  fn note(p) : () do let _ = p  print_line("got a pid") end
  actor A do
    state { n : Int }
    init  { n: 0 }
    on Ping() do
      note(self)
      { state with n: state.n + 1 }
    end
  end
  fn main(c : Cap(IO.Console)) do
    let p = spawn(A)
    send(p, Ping())
    run_until_idle()
  end
end
```

- `march --check` — exit 0.
- interpreted — prints `got a pid`.
- `march --compile` — **exit 1**:

```
<file>.ll:620:20: error: use of undefined value '@self'
  620 |   %gl37 = call ptr @self()
```

`send(self, Ping())`, the re-send idiom, fails the same way. Measured on
`main` at `87101987`.

## Cause

`self` exists at three of the four layers a builtin needs and is missing from
the fourth:

| layer | state |
|---|---|
| typecheck | bound globally as `Int` (`typecheck_builtins.ml:1116`), shadowed inside a handler as `Pid(state)` (`typecheck.ml:4306`) |
| interpreter | a real builtin reading `current_pid` (`eval_builtins.ml:406`) |
| defunctionalisation | listed in `defun.ml:137`'s builtin names |
| **LLVM backend** | **absent from `llvm_builtins.ml`** — no `declare`, no `c_name` |

With no entry in the table the emitter still emits a direct call, so the
module reaches clang naming a symbol nothing defines. There is also **no
runtime accessor to point it at**: `march_self` / a current-actor getter does
not exist in `runtime/march_runtime.h` or `march_scheduler.h`, so the
scheduler's notion of the running actor is not reachable from generated code.

Nothing in the tree exercises it. The two native fixtures that mention `self`
only do so in comments, and one of them
(`test/native/actor_dispatch_rc_window.march:56`) explicitly routes around it:
"The pid index arrives in the message rather than via `self`".

## What to build

1. A runtime accessor for the currently-running actor's pid, alongside the
   scheduler state that already tracks it, in the same shape as the other
   actor builtins.
2. An entry in `llvm_builtins.ml` mapping `self` to it, with its `declare`.
3. Walk the rest of the builtin checklist rather than assuming two sites are
   enough — a new builtin has historically touched nine, including
   `emit_module` and the REPL-JIT finalizers.
4. Decide what compiled `self` does **outside** a handler. The interpreter
   raises "self: called outside an actor handler"; the typechecker binds a
   bare `Int` there, so the compiled answer must be defined rather than
   whatever the runtime happens to hold.

## Tests

- `test/native/`: a golden whose handler passes `self` to a function and
  re-sends to `self`, with the same trace interpreted and compiled. This is
  the load-bearing one — the compiled half of the pair does not build today.
- An interpreted/compiled parity case in the ordinary suite, since the bug
  class here is exactly a divergence between the two backends.
- A case for the out-of-handler decision from step 4.

Prove the golden RED first: it fails at clang, not at a diff, so check for
that error text rather than an output mismatch.

## Workaround until then

The spawner knows the pid (`let p = spawn(A)`), so anything that needs an
actor's own identity can be told it: register at the spawn site, or send the
pid in the actor's first message. `2026-09-11-actor-hosted-session-endpoint.md`
uses exactly this and needs no `self`, which is why that item is not blocked
on this one.

---

## What shipped (2026-09-12)

`self` inside a handler compiles and works as a value on both backends.
`test/native/actor_self.march` is the golden; it did not build at all before.

**The diagnosis in this file was half right, and the wrong half mattered.**
It said the runtime had no accessor to point the builtin at. It already had
one — `march_self` in `march_scheduler.c`, present and dead, because nothing
could reach it:

```c
/* self() builtin — returns the current green thread's proc pointer (the PID
 * value used as first arg to send/receive in the compiled binary). */
void *march_self(void) { return (void *)march_sched_current(); }
```

That comment is wrong, and had been invisible for exactly the reason this
item exists: with `self` missing from `llvm_builtins.ml`, no compiled program
ever called it, so nothing could notice that a **proc** pointer is not a Pid.
A Pid at the ABI is the **actor** pointer — `march_send` takes one,
`march_spawn` returns one, `march_pid_of_int` hands back `meta->actor`.

So the change is three lines of runtime plus the table entry, not a new
accessor:

- `march_proc` gains an `actor` field, published once by `actor_green_thread`
  (procs are `calloc`'d, so NULL is the default and non-actor procs keep it).
- `march_self` returns that actor pointer, and panics outside a handler
  instead of handing back something the caller will misread.
- `llvm_builtins.ml` gains the `self` entry and its `PDeclare`.

I briefly added a *second* `march_self` in `march_runtime.c` before noticing
the existing one — a duplicate symbol that only failed to break the build
because the staged runtime was stale. Reverted; the lesson is to grep the
runtime for the symbol before adding an accessor a spec says is missing.

### Step 4, the out-of-handler decision: not decidable here

The spec asked what compiled `self` should do outside a handler. It turns out
`march_self` is never called there: the typechecker binds the global `self`
as `Int`, so `let x = self` at top level lowers to the **closure address** of
`march_self$static_clo` cast to an integer, and prints a raw pointer. The
panic added above is unreachable on that path and is kept only as a backstop.

Making that case an error is a typechecker change — the global `self : Int`
binding is the actual defect — and belongs to its own item, not to a codegen
fix. Recorded here rather than silently left.

### Found while fixing it, filed separately

- **`send(self, …)` does not deliver**, on *either* backend and differently
  on each: `specs/todos/2026-09-12-send-to-self-does-not-deliver.md`. A
  handler sending to a *different* actor works on both, so this is specific
  to self-directed delivery, not to sends from handlers. Filed P1: it is the
  ordinary way an actor drives itself forward and it fails silently.
- **`self == spawn(...)`** is true compiled, false interpreted. The compiled
  answer is the defensible one. The golden deliberately avoids comparing them
  so it pins only what both backends agree on; the divergence is recorded in
  the file above.
