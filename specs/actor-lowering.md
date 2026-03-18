# Actor Lowering — Design Plan

Actors currently work end-to-end through the tree-walking interpreter but are silently dropped during TIR lowering (`DActor` → `()`). This document plans the full lowering path from actor declarations to native LLVM.

## Current State

| Stage | Status |
|---|---|
| Parsing | Complete — `DActor`, `ESend`, `ESpawn`, `on`-handlers |
| Desugaring | Pass-through — only recurses into exprs |
| Typechecking | Complete — state type, message ctors, handler return types |
| Interpreter | Complete — synchronous dispatch, drop semantics, kill/is_alive |
| TIR lowering | **Missing** — `DActor` → `()`, spawn/send use `unknown_ty` |
| LLVM emit | **Missing** |

---

## Design Overview

Every actor declaration generates four things in TIR:

1. **Message variant type** — one constructor per handler
2. **Actor struct type** — flat heap object holding dispatch ptr + alive flag + inlined state fields
3. **Handler functions** — one per `on`-clause; reads state from struct, runs body, writes new state back
4. **Spawn function** — allocates the actor struct, runs `init`, wires dispatch ptr

`send`, `kill`, and `is_alive` are lowered to calls against a small C runtime extension.

---

## Object Layout

An actor instance is a standard March heap object:

```
offset  0  : i64   rc          (reference count)
offset  8  : i32   tag         (always 0 for actors)
offset 12  : i32   pad
offset 16  : ptr   dispatch    (field 0 — pointer to ActorName_dispatch fn)
offset 24  : i64   alive       (field 1 — 1 = alive, 0 = dead)
offset 32  : ...   state[0]    (field 2 — first state field, alphabetical order)
offset 40  : ...   state[1]    (field 3 — second state field)
...
```

State fields are embedded directly (flat layout, alphabetical order matching `TRecord`). There is no separate heap allocation for state — this keeps spawning cheap and gives the handler functions a single pointer to thread through.

The field indices used in GEP ops:
- Field 0 → dispatch fn ptr
- Field 1 → alive flag
- Field 2 + i → state field i (sorted alphabetically)

---

## Generated TIR

For the actor:

```march
actor Counter do
  state { value : Int }
  init  { value = 0 }

  on Increment(n : Int) do
    { state with value = state.value + n }
  end

  on Reset() do
    { state with value = 0 }
  end
end
```

### 1. Message variant type

```
TDVariant("Counter_Msg", [
  ("Increment", [TInt]);
  ("Reset",     []);
])
```

Constructor tags are assigned in declaration order (not alphabetical) so that handler lookup in the dispatch switch is stable.

### 2. Actor struct type

```
TDRecord("Counter_Actor", [
  ("$dispatch", TPtr TUnit);   (* field 0 *)
  ("$alive",    TBool);        (* field 1 *)
  ("value",     TInt);         (* field 2 — state fields follow, alphabetical *)
])
```

A `TDRecord` entry for the actor struct gets added to `tm_types`. The `field_map` in the LLVM emitter is populated from it so normal `EField`/`EUpdate` lowering handles state field access correctly.

### 3. Handler functions

Each `on Msg(params) do body end` becomes a TIR function:

```
fn Counter_Increment(actor : TPtr TUnit, n : TInt) : TUnit
  -- Load current state from actor struct
  let value  = EField(AVar actor, "value")      -- field index 2
  -- Run handler body (functional; returns new state record)
  let $state = ERecord [("value", AVar value)]
  let $new   = EUpdate(AVar $state, [("value", EApp("+", [AVar value, AVar n]))])
  -- Write new state fields back to actor struct in-place
  ESeq(EUpdate_actor_field(actor, "value", EField($new, "value")),
       EAtom(ALit(LitInt 0)))    (* return unit *)
```

In practice, the handler body is lowered in an environment where `state` is bound to a synthetic record expression that loads each field from the actor struct. The result record's fields are then stored back via `EReuse`-style in-place writes where possible (the state record is local to the handler and not observable by anyone else, so FBIP always applies).

More precisely:

1. Bind `state` to a local record that reads each field from the actor struct via `EField(AVar actor_param, field_name)`.
2. Lower the handler body in this extended environment.
3. After the body, write each field of the result back to the actor struct via `emit_store_field`.

The handler function signature is always:
```
fn ActorName_MsgName(actor : TPtr TUnit, param1 : T1, ...) : TUnit
```

The first parameter is always the actor struct pointer (`$actor` of type `TPtr TUnit`).

### 4. Dispatch function

```
fn Counter_dispatch(actor : TPtr TUnit, msg : TPtr TUnit) : TUnit
  ECase(AVar msg_tag, [
    { br_tag = "Increment"; br_vars = [n]; br_body =
        EApp(Counter_Increment, [AVar actor, AVar n]) };
    { br_tag = "Reset"; br_vars = []; br_body =
        EApp(Counter_Reset, [AVar actor]) };
  ], None)
```

The dispatch function loads the message tag and switches on it, unpacking constructor fields and forwarding them to the appropriate handler.

### 5. Spawn function

```
fn Counter_spawn() : TPtr TUnit
  let actor = EAlloc(TCon("Counter_Actor", []), [
    AVar Counter_dispatch;    (* field 0: dispatch fn ptr *)
    ALit(LitBool true);       (* field 1: alive = true   *)
    -- init expression lowers here, fields extracted alphabetically:
    ALit(LitInt 0);           (* field 2: value = 0      *)
  ])
  EAtom(AVar actor)
```

The `init` expression is lowered and its fields are extracted in the same alphabetical order as the struct layout. The spawn function is a zero-argument function returning `TPtr TUnit`.

---

## Lowering `spawn`, `send`, `kill`, `is_alive`

### `spawn(Counter)` in expressions

```ocaml
| Ast.ESpawn (Ast.EVar {txt = actor_name; _}, _) ->
  Tir.EApp ({ v_name = actor_name ^ "_spawn"; v_ty = Tir.TPtr Tir.TUnit; v_lin = Unr }, [])
```

The actor name is resolved to the generated spawn function at lowering time.

### `send(pid, Msg(args))` in expressions

`send` becomes a call to a runtime helper `march_send` which:
1. Loads the alive flag (field 1 of the actor struct).
2. If dead, returns `None` (allocates `VCon("None", [])`).
3. Loads the dispatch fn ptr (field 0).
4. Calls `dispatch(actor, msg)`.
5. Returns `Some(())`.

```
fn march_send(actor : ptr, msg : ptr) -> ptr   ; returns Option(Unit)
```

Signature in TIR:
```ocaml
Tir.EApp ({ v_name = "send"; v_ty = Tir.TFn([Tir.TPtr Tir.TUnit; Tir.TPtr Tir.TUnit],
                                              Tir.TCon("Option", [Tir.TUnit]));
             v_lin = Unr }, [cap_atom; msg_atom])
```

`send` is added to the `mangle_extern` table in `llvm_emit.ml` → `march_send`.

### `kill(pid)` and `is_alive(pid)`

Added to the C runtime:

```c
// march_runtime.c additions
void march_kill(void *actor) {
    int64_t *fields = (int64_t *)actor;
    fields[3] = 0;   // field 1 at byte offset 24 → int64 index 3
}

int64_t march_is_alive(void *actor) {
    int64_t *fields = (int64_t *)actor;
    return fields[3];
}
```

In TIR/LLVM these are declared as:
```llvm
declare void @march_kill(ptr %actor)
declare i64  @march_is_alive(ptr %actor)
```

The LLVM emitter already handles `kill` and `is_alive` as `EApp` calls if they appear in `mangle_extern`. Add them to that table.

---

## Changes Required by File

### `lib/tir/lower.ml`

Replace `| Ast.DActor _ -> ()` with a full lowering pass:

```
lower_actor : Ast.actor_def -> Ast.name -> type_map
           -> Tir.type_def list * Tir.fn_def list
```

Steps:
1. Build `Counter_Msg` variant type from handler names + param types (from `type_map`).
2. Build `Counter_Actor` record type: `[("$dispatch", TPtr TUnit); ("$alive", TBool)] @ sorted_state_fields`.
3. For each handler: generate `Counter_MsgName` function (load state, run body, write back).
4. Generate `Counter_dispatch` function (switch on tag, call handler).
5. Generate `Counter_spawn` function (alloc + init).
6. Return `(type_defs, fn_defs)` to be appended to the module.

The `type_map` threading already exists — actor state field types come from the typechecker's record expansion.

### `lib/typecheck/typecheck.ml`

No changes needed for the lowering logic — actor state types and message constructor types are already in `type_map`. The only addition is ensuring the spawn function signature (`ActorName_spawn : Unit -> Pid(State)`) is reachable for type-checking call sites that use it directly.

### `lib/tir/llvm_emit.ml`

- Add `march_kill` and `march_is_alive` to `mangle_extern` and the preamble `declare` list.
- Add `march_send` to the preamble.
- `kill(pid)` and `is_alive(pid)` already pass through `EApp` → no special-casing needed once `mangle_extern` covers them.
- Actor struct field access goes through the existing `EField`/`EUpdate` path since the actor struct is registered as a `TDRecord` in `field_map`.

### `runtime/march_runtime.c`

Add three functions:
- `march_kill(void *actor)` — store `0` to alive field
- `march_is_alive(void *actor) -> int64_t` — load alive field
- `march_send(void *actor, void *msg) -> void *` — alive check + dispatch call + return `Some(())`/`None`

The `march_send` implementation needs to call the dispatch fn through the fn ptr at field 0. Declare the dispatch type as `void (*)(void *, void *)`.

---

## Handling `state` as a Contextual Variable

In handler bodies, `state` is an expression that refers to the current actor state. During TIR lowering of a handler body, the lowering environment maps `state` to a synthetic record expression:

```
ERecord [
  ("value", EField(AVar actor_param, "value"));
  ...
]
```

This record is let-bound at the top of the handler and serves as the `state` variable. Since it's a simple local struct (not heap-allocated), escape analysis will stack-promote it. Since the actor param is the only reference to the live state, Perceus will FBIP the in-place write of the result fields.

---

## Memory Management

Actor instances are reference-counted like all other heap values. `VPid` in the interpreter corresponds to a raw `ptr` in TIR — the same `march_alloc` / `march_decrc` machinery applies.

Key invariants:
- `spawn` allocates with RC=1; the `let pid = spawn(...)` binding owns the reference.
- State is embedded in the actor struct — no separate allocation, no inner RC.
- `kill` does not free the actor struct; it sets the alive flag to 0. The struct is freed when the last `Pid` reference is decremented.
- Handler functions do not hold their own reference to the actor — the dispatch call borrows the pointer. RC is not touched inside handlers.

Perceus RC analysis for the `send` call site should emit `EIncRC(pid)` if the pid is used after the send (which it almost always is). The `EFree` path triggers when the last `send` or assignment drops the pid.

---

## Implementation Order

1. **Runtime** (`march_runtime.c`) — add `march_kill`, `march_is_alive`, `march_send`. These are pure C additions; no compiler changes needed. Write a manual test in C to verify layout assumptions.

2. **LLVM preamble** (`llvm_emit.ml`) — add the three new runtime `declare` lines and mangle_extern entries. Verify `kill(pid)` and `is_alive(pid)` already round-trip through `EApp` correctly with a simple test program.

3. **Type generation** (`lower.ml`) — implement `lower_actor` up through type generation only (message variant + actor struct). Verify via `--dump-tir` that types appear correctly.

4. **Spawn function** (`lower.ml`) — implement `Counter_spawn`. Verify `spawn(Counter)` compiles and the returned pointer is non-null at runtime.

5. **Handler functions** (`lower.ml`) — implement one handler end-to-end (`Increment`). Verify state is loaded correctly, body runs, and state field is written back.

6. **Dispatch function** (`lower.ml`) — implement `Counter_dispatch`. Verify `send(c, Increment(5))` reaches the handler.

7. **Full actor example** — compile and run `examples/actors.march` via `--compile` and compare output against the interpreter.

8. **Tests** — add TIR-level and end-to-end tests for actor spawn, message dispatch, kill, is_alive, drop semantics.

---

## Open Questions

- **Mutual recursion between actors**: Two actors that hold `Pid` references to each other create a reference cycle. Perceus RC cannot collect these. Options: weak references, epoch-based collection, or require explicit `kill` before drop. Defer to post-v1.

- **Actor-to-actor messaging in handlers**: A handler may call `send` on another actor. This is fine in the synchronous model — it just recurses. In an async model this becomes a queue enqueue. For now: synchronous only, identical to the interpreter.

- **Polymorphic actors**: An actor whose state contains a type parameter would require monomorphization. The current monomorphizer handles `TCon` but actor structs are synthetic — they need to be monomorphized before actor lowering runs, or actor lowering must happen after mono. **Actor lowering should run after monomorphization** in the pass order (i.e., after `mono.ml`, before `defun.ml`).

- **Protocol validation**: Session types (`DProtocol`) are not yet validated against actors. Leave for a separate pass after actor lowering is complete.
