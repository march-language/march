# Actor Lowering — Design Plan

Actors currently work end-to-end through the tree-walking interpreter but are silently dropped during TIR lowering (`DActor` → `()`). This document plans the full lowering path from actor declarations to native LLVM.

## Current State

| Stage | Status |
|---|---|
| Parsing | Complete — `DActor`, `ESend`, `ESpawn`, `on`-handlers |
| Desugaring | Pass-through — only recurses into exprs |
| Typechecking | Complete — state type, message ctors, handler return types |
| Interpreter | Complete — synchronous dispatch, drop semantics, kill/is_alive |
| TIR lowering | **Partial** — `lower_actor` exists (line 1383) but has a blocking field-order bug |
| LLVM emit | **Partial** — actor struct and handler IR emit, but dispatch/alive field indices are wrong |
| `march_send_checked` | **Stub** — capability-checked send is a no-op in C runtime |
| Supervision in compiled path | **Missing** — child actors not spawned in compiled supervisor |
| End-to-end binary test | **Missing** — no native test actually runs a compiled actor binary |

---

## Known Design Issues (must fix before shipping)

### BLOCKING: Actor struct field-order mismatch

`lower_actor` constructs `actor_struct_fields` in the order `[$dispatch, $alive, state...]`
(insertion order, not alphabetical). But `get_record_fields` in `llvm_emit.ml` sorts the
`field_map` entries alphabetically on every GEP lookup. Since `$` sorts before all letters,
`$alive < $dispatch` alphabetically, so:

- `EAlloc` stores `$dispatch` at slot 0 and `$alive` at slot 1 (insertion order)
- `EField(actor, "$alive")` resolves to index **0** (alphabetical sort)
- `EField(actor, "$dispatch")` resolves to index **1** (alphabetical sort)

Result: every `$dispatch` load reads the alive flag and vice versa. The C runtime also
hardcodes `a[2]` = dispatch and `a[3]` = alive, which disagrees with the alphabetical sort.

**Fix (preferred):** Rename the built-in fields so they sort in the C runtime's preferred order:

```
"$d_dispatch"  → sorts to index 0  (matches C word index 2 = first field)
"$e_alive"     → sorts to index 1  (matches C word index 3 = second field)
```

This avoids touching `march_runtime.c` at all. Rename in `lower_actor` only.

**Alternative fix:** Sort `actor_struct_fields` alphabetically before `TDRecord` construction,
then update C runtime indices (`a[2]↔a[3]` swap in `actor_green_thread`, `march_kill`,
`march_is_alive`, `march_send`, `march_is_cap_valid`). More invasive.

**Files affected:**
- `lib/tir/lower.ml:1406–1410` — field list construction
- `runtime/march_runtime.c:1122,1131,1194,1202,1330,2740` — if taking the alternative fix

### BLOCKING: No end-to-end compiled actor test

All 8 `actor_compile` tests only check LLVM IR string patterns (function names, `march_spawn`
present). None compile to a binary and run it. The field-order bug above is completely
invisible to the existing test suite.

**Fix:** Add `test/native/actor_counter/` with a March source file and an `.expected` output
file. Wire into the dune native test runner (same pattern as existing `test/native/` tests).

### MAJOR: `march_send_checked` is a no-op stub

The capability-checked send in `runtime/march_runtime.c:2868` does nothing — it ignores the
capability entirely and never validates epoch or pid_index. Any compiled program using
`Cap`-typed actor channels has zero runtime enforcement.

**Fix:** Implement `march_send_checked` using the VCap layout from the interpreter (3 fields:
actor ptr, pid_index, epoch). See code stub below.

### MAJOR: Supervision not wired in compiled path

`lower_actor` emits a `march_register_supervisor` call but never spawns or links the declared
child actors. The C runtime has no restart logic wired to `march_register_supervisor`.

**Fix (near-term):** Emit spawn calls for each `sc_field` child actor inside the supervisor's
spawn body, linking children via a C runtime call. Or gate compiled supervision with a clear
error message (interpreter-only for now).

### MAJOR: Object layout diagram contradicts field-order fix

The plan's "Object Layout" section says `$dispatch` is at offset 16 (field 0) and `$alive` is
at offset 24 (field 1). If the preferred fix (rename to `$d_dispatch`/`$e_alive`) is taken,
the diagram remains correct. If the alternative fix is taken, the diagram must be updated.
The current diagram is **only valid for the preferred rename fix**.

### MINOR: Spawn function var has wrong TIR type annotation

`ESpawn` lowering stores the spawn function as `{ v_ty = TPtr TUnit }` but it's actually a
zero-arg function. This is harmless at codegen time but misleading. Fix: use
`TFn([], TPtr TUnit)` for the spawn var.

---

## Object Layout

An actor instance is a standard March heap object:

```
word index   offset   type    field
─────────────────────────────────────────────────────────────
[0]          0        i64     rc          (reference count)
[1]          8        i32+i32 tag + pad   (tag always 0 for actors)
[2]          16       ptr     $d_dispatch (field 0 — pointer to ActorName_dispatch fn)
[3]          24       i64     $e_alive    (field 1 — 1=alive, 0=dead)
[4]          32       ...     state[0]    (field 2 — first state field, alphabetical)
[5]          40       ...     state[1]    (field 3 — second state field)
...
```

State fields are embedded directly (flat layout, alphabetical order matching `TRecord`). There
is no separate heap allocation for state — this keeps spawning cheap and gives the handler
functions a single pointer to thread through.

The field indices used in GEP ops (sorted alphabetically):
- Field 0 → `$d_dispatch` fn ptr  (sorts before `$e_alive`)
- Field 1 → `$e_alive` flag
- Field 2 + i → state field i (sorted alphabetically)

The C runtime reads actors as `int64_t *a`:
- `a[2]` → `$d_dispatch` (byte 16)
- `a[3]` → `$e_alive`    (byte 24)

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

Constructor tags are assigned in declaration order (not alphabetical) so that handler lookup
in the dispatch switch is stable.

### 2. Actor struct type

```
TDRecord("Counter_Actor", [
  ("$d_dispatch", TPtr TUnit);   (* field 0 — sorts first *)
  ("$e_alive",    TBool);        (* field 1 — sorts second *)
  ("value",       TInt);         (* field 2 — state fields follow, alphabetical *)
])
```

A `TDRecord` entry for the actor struct gets added to `tm_types`. The `field_map` in the LLVM
emitter is populated from it so normal `EField`/`EUpdate` lowering handles state field access.

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

In practice, the handler body is lowered in an environment where `state` is bound to a
synthetic record expression that loads each field from the actor struct. The result record's
fields are then stored back via `EReuse`-style in-place writes (FBIP always applies here since
the state record is local to the handler and not observable by anyone else).

More precisely:

1. Bind `state` to a local record reading each field from the actor struct via
   `EField(AVar actor_param, field_name)`.
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

The dispatch function loads the message tag and switches on it, unpacking constructor fields
and forwarding them to the appropriate handler.

### 5. Spawn function

```
fn Counter_spawn() : TPtr TUnit
  let actor = EAlloc(TCon("Counter_Actor", []), [
    AVar Counter_dispatch;    (* field 0: $d_dispatch fn ptr *)
    ALit(LitBool true);       (* field 1: $e_alive = true   *)
    -- init expression lowers here, fields extracted alphabetically:
    ALit(LitInt 0);           (* field 2: value = 0         *)
  ])
  EAtom(AVar actor)
```

The `init` expression is lowered and its fields are extracted in the same alphabetical order
as the struct layout. The spawn function is a zero-argument function returning `TPtr TUnit`.

---

## Lowering `spawn`, `send`, `kill`, `is_alive`

### `spawn(Counter)` in expressions

```ocaml
| Ast.ESpawn (Ast.EVar {txt = actor_name; _}, _) ->
  Tir.EApp ({ v_name = actor_name ^ "_spawn";
               v_ty = Tir.TFn([], Tir.TPtr Tir.TUnit);   (* fix: was TPtr TUnit *)
               v_lin = Unr }, [])
```

### `send(pid, Msg(args))` in expressions

`send` becomes a call to `march_send` which:
1. Loads `$e_alive` (field 1 of the actor struct).
2. If dead, returns `None`.
3. Loads `$d_dispatch` (field 0).
4. Calls `dispatch(actor, msg)`.
5. Returns `Some(())`.

```
fn march_send(actor : ptr, msg : ptr) -> ptr   ; returns Option(Unit)
```

### `kill(pid)` and `is_alive(pid)`

```c
void march_kill(void *actor) {
    int64_t *a = (int64_t *)actor;
    a[3] = 0;   /* $e_alive at word index 3 */
}

int64_t march_is_alive(void *actor) {
    int64_t *a = (int64_t *)actor;
    return a[3];
}
```

In TIR/LLVM:
```llvm
declare void @march_kill(ptr %actor)
declare i64  @march_is_alive(ptr %actor)
```

---

## Code Stubs

### `lib/tir/lower.ml` — rename built-in fields to fix sort order

```ocaml
(* In lower_actor, replace the actor_struct_fields construction with: *)
let actor_struct_fields : (string * Tir.ty) list =
  (* Use names that sort in the C runtime's preferred order:
     $d_dispatch (word 2) sorts before $e_alive (word 3) alphabetically,
     matching get_record_fields' alphabetical sort in llvm_emit.ml. *)
  [("$d_dispatch", Tir.TPtr Tir.TUnit);
   ("$e_alive",    Tir.TBool)]
  @ state_fields_sorted
in
let actor_record = Tir.TDRecord (actor_type_name, actor_struct_fields) in

(* alloc_args must match the sorted field order: *)
let alloc_args : Tir.atom list =
  [Tir.AVar dispatch_fn_ptr_var;   (* $d_dispatch at slot 0 *)
   Tir.ALit (Ast.LitBool true)]    (* $e_alive    at slot 1 *)
  @ List.map (fun (_, v) -> Tir.AVar v) init_field_vars
in
```

### `runtime/march_runtime.c` — implement `march_send_checked`

```c
void march_send_checked(void *cap, void *msg) {
    if (!cap || !IS_HEAP_PTR(cap)) { march_decrc(msg); return; }
    /* Capability object layout (matches interpreter VCap):
     *   field 0 (word 2): actor ptr
     *   field 1 (word 3): pid_index (int64)
     *   field 2 (word 4): epoch (int64)
     */
    int64_t *cap_words = (int64_t *)cap;
    void    *actor    = (void *)(uintptr_t)cap_words[2];
    int64_t  pidx     = cap_words[3];
    int64_t  epoch    = cap_words[4];
    march_actor_meta *meta = find_meta(actor);
    if (!meta || meta->pid_index != pidx || meta->epoch != epoch) {
        march_decrc(msg);
        return;
    }
    march_send(actor, msg);
}
```

### `test/native/actor_counter/actor_counter.march` — minimal end-to-end binary test

```march
mod ActorCounter do
  actor Counter do
    state { value : Int }
    init { value = 0 }
    on Increment(n : Int) do
      { state with value = state.value + n }
    end
    on Probe() do
      println("value=" ++ int_to_string(state.value))
      state
    end
  end

  fn main() : Unit do
    let c = spawn(Counter)
    let _ = send(c, Increment(5))
    let _ = send(c, Probe())
    run_scheduler()
  end
end
```

Expected output (`actor_counter.expected`): `value=5`

### `test/test_march.ml` — TIR-level field-order regression test

```ocaml
let test_actor_field_index_consistency () =
  (* Verify that the field names used in EAlloc args match what EField
     resolves for the same TDRecord. After the rename fix, $d_dispatch
     must resolve to index 0 and $e_alive to index 1. *)
  let ir = emit_actor_ir {|mod Test do
    actor Counter do
      state { value : Int }
      init { value = 0 }
      on Inc() do { value = state.value + 1 } end
    end
    fn main() : Unit do let _ = spawn(Counter) () end
  end|} in
  Alcotest.(check bool) "Counter_spawn in IR" true
    (ir_contains ir "Counter_spawn");
  Alcotest.(check bool) "Counter_dispatch in IR" true
    (ir_contains ir "Counter_dispatch");
  (* The dispatch field must be loaded as field index 0, not 1 *)
  Alcotest.(check bool) "dispatch at GEP index 0" true
    (ir_contains ir "getelementptr %Counter_Actor, ptr %actor, i32 0, i32 2")
    (* index 2 = first struct field, 0-based after rc+tag header *)
```

---

## Changes Required by File

### `lib/tir/lower.ml`

- Rename `"$dispatch"` → `"$d_dispatch"` and `"$alive"` → `"$e_alive"` in `actor_struct_fields`.
- Update all `EField(_, "$dispatch")` → `EField(_, "$d_dispatch")` and `"$alive"` → `"$e_alive"` references in handler lowering.
- Fix spawn function var type: `v_ty = Tir.TFn([], Tir.TPtr Tir.TUnit)`.

### `lib/tir/llvm_emit.ml`

- Add `march_kill`, `march_is_alive` to `mangle_extern` and the preamble `declare` list.
- Add `march_send` and `march_send_checked` to the preamble.
- No special-casing needed for `kill`/`is_alive` once `mangle_extern` covers them.
- Actor struct field access goes through the existing `EField`/`EUpdate` path since the actor
  struct is registered as a `TDRecord` in `field_map`.

### `runtime/march_runtime.c`

- Implement `march_send_checked` (capability validation before dispatch).
- Verify `march_kill`, `march_is_alive` use `a[3]` for the alive flag (field 1 at word 3).
- Verify `actor_green_thread` reads `a[3]` for alive and `a[2]` for dispatch.

### `test/test_march.ml`

- Add `test_actor_field_index_consistency` (TIR-level, checks IR patterns).
- Add `test_actor_send_checked_compiled` (verify IR contains `march_send_checked` for Cap sends).

### `test/native/`

- Add `actor_counter/` — spawn, Increment(5), Probe, verify output `value=5`.
- Add `actor_kill/` — spawn, assert alive, kill, assert dead, verify send returns None.
- Add `actor_two_state_fields/` — actor with `{ alpha: Int; beta: Int }`, update each independently.

---

## Test Plan

| Test | File | What | Pass criterion |
|---|---|---|---|
| `actor_binary_counter_correct_output` | `test/native/actor_counter/` | Compile Counter actor, run binary | stdout = `value=5` |
| `actor_kill_and_is_alive_compiled` | `test/native/actor_kill/` | Kill after spawn, check is_alive | stdout = `false` |
| `actor_multi_state_field_correct_slot` | `test/native/actor_two_state_fields/` | Two state fields updated independently | stdout = `alpha=1 beta=2` |
| `actor_tir_struct_field_indices` | `test/test_march.ml` | `$d_dispatch` at GEP index 0 in IR | IR grep passes |
| `actor_handler_reuse_state` | `test/test_march.ml` | TIR pipeline produces EReuse for state write | Walk fn_body for EReuse |
| `actor_dispatch_uses_correct_tag_indices` | `test/test_march.ml` | Counter_Msg ctor tags match Counter_dispatch branches | One-to-one correspondence |
| `actor_send_returns_option` | `test/native/actor_send_option/` | Send to alive → Some(()); send to dead → None | Binary stdout |
| `actor_send_checked_validates_epoch` | `test/test_march.ml` | IR contains `march_send_checked` for Cap sends | IR grep |

---

## Documentation Plan

| Section | File | What |
|---|---|---|
| Object layout diagram | This file | Update field names to `$d_dispatch`/`$e_alive` — done above |
| Actor struct field naming convention | This file, "Design Issues" | Explain why `$d_`/`$e_` prefix: forces alphabetical sort to match C layout |
| Compiled path status | `specs/features/actor-system.md` | Update "Current Status" from "TIR lowering planned" to "partially implemented, field-order bug tracked" |
| `march_send_checked` | `specs/features/actor-system.md` under "Capability-secure messaging" | Note that compiled path was a no-op stub until this fix |
| Supervision in compiled path | `specs/features/actor-system.md` under "Supervision" | Document that compiled supervision does not restart child actors yet |

---

## Handling `state` as a Contextual Variable

In handler bodies, `state` is an expression that refers to the current actor state. During TIR
lowering of a handler body, the lowering environment maps `state` to a synthetic record expression:

```
ERecord [
  ("value", EField(AVar actor_param, "value"));
  ...
]
```

This record is let-bound at the top of the handler and serves as the `state` variable. Since
it's a simple local struct (not heap-allocated), escape analysis will stack-promote it. Since
the actor param is the only reference to the live state, Perceus will FBIP the in-place write.

Note: `state_var` in handler TIR is typed as `TCon(Name_State, [])`, so `EField` accesses on
it use the `field_map` TCon path in `llvm_emit.ml`. This is correct as long as state fields
are in the same alphabetical order in both the `TDRecord` and the synthetic record expression.

---

## Memory Management

Actor instances are reference-counted like all other heap values. `VPid` in the interpreter
corresponds to a raw `ptr` in TIR — the same `march_alloc` / `march_decrc` machinery applies.

Key invariants:
- `spawn` allocates with RC=1; the `let pid = spawn(...)` binding owns the reference.
- State is embedded in the actor struct — no separate allocation, no inner RC.
- `kill` does not free the actor struct; it sets the alive flag to 0. The struct is freed
  when the last `Pid` reference is decremented.
- Handler functions do not hold their own reference to the actor — the dispatch call borrows
  the pointer. RC is not touched inside handlers.
- Actor green threads should hold an RC reference to the actor struct (incrc on spawn, decrc
  on exit) so the struct cannot be freed while the green thread is alive. Verify this in
  `march_spawn` — the current code may not do the incrc.

Perceus RC analysis for the `send` call site should emit `EIncRC(pid)` if the pid is used
after the send. The `EFree` path triggers when the last send or assignment drops the pid.

---

## Implementation Order

1. **Fix field names** (`lower.ml`) — rename `$dispatch`→`$d_dispatch` and `$alive`→`$e_alive`.
   Verify C runtime word indices still match (they do: `a[2]` = dispatch, `a[3]` = alive).

2. **Add native test** (`test/native/actor_counter/`) — will fail until field-order fix is in.
   This test is the acceptance criterion for step 1.

3. **Runtime** (`march_runtime.c`) — implement `march_send_checked` (capability validation).

4. **LLVM preamble** (`llvm_emit.ml`) — add `march_send_checked` declare and `march_kill`/
   `march_is_alive` to mangle_extern. Verify `kill(pid)` and `is_alive(pid)` round-trip.

5. **Spawn fix** (`lower.ml`) — fix spawn function var type to `TFn([], TPtr TUnit)`.

6. **Supervision** — emit child-actor spawns in supervisor's spawn body, or document as
   interpreter-only with a compile-time error for compiled supervisor programs.

7. **Additional tests** — actor_kill, actor_two_state_fields, actor_send_returns_option.

---

## Open Questions

- **Mutual recursion between actors**: Two actors that hold `Pid` references to each other
  create a reference cycle. Perceus RC cannot collect these. Options: weak references,
  epoch-based collection, or require explicit `kill` before drop. Defer to post-v1.

- **Actor-to-actor messaging in handlers**: A handler may call `send` on another actor. This
  is fine in the synchronous model — it just recurses. In an async model this becomes a queue
  enqueue. For now: synchronous only, identical to the interpreter.

- **Polymorphic actors**: An actor whose state contains a type parameter would require
  monomorphization. **Actor lowering must run after monomorphization** in the pass order
  (after `mono.ml`, before `defun.ml`).

- **Protocol validation**: Session types (`DProtocol`) are not yet validated against actors.
  Leave for a separate pass after actor lowering is complete.
