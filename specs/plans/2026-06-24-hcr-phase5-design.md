# HCR Phase 5 — Actor State Migration Design

**Date:** 2026-06-24
**Status:** Approved for implementation
**Depends on:** HCR Phases 1–4 complete; Phase 1 Merkle `impl_hash` landed; Phase 4 `forge deploy hot` CAS-native + ed25519 signing verified end-to-end.
**Spec parent:** `specs/hot-code-reload.md` Parts 5 and 6

---

## Goal

Make hot deploys correct for stateful actors. Phase 4 can hot-swap pure functions; Phase 5 adds per-actor versioned handler dispatch with migrate-before-run ordering so an actor never runs new handler code against old-typed state.

Two slices ship together:
- **Part A — Migration runtime**: per-actor version tracking, system migrate message, state indirection, ACTIVATE actor walk, `migrate_state` compilation.
- **Part B — Type-level guardrails**: schema-evolution checking at deploy time, `@compat` annotations, backward-compat enforcement.

---

## Decisions

| Question | Answer |
|---|---|
| Scope | Both Part A and Part B |
| `RawRecord` | Compile-time fiction — typechecker unifies `old : RawRecord` with the prior CAS State type; users write `old.field` as normal field access |
| Prior type source | Magic-name convention + CAS lookup; return type of `migrate_state` disambiguates when a module has multiple actor State types |
| Migration delivery | System message (`MARCH_MIGRATE_TAG`) injected at front of actor mailbox by ACTIVATE |
| Absent `migrate_state` | Supervisor restart for all actors on the old version |
| `@compat` default | Strict — every actor `State` type gets implicit `@compat(full)` unless annotated |
| Architecture | Typecheck-time CAS elaboration (Approach 1) |

---

## Part A: Migration Runtime

### Actor layout for `--hot-reload` builds

In `--hot-reload` builds, actor state is stored behind an indirection pointer so migration is a pointer swap, not a struct realloc. Changing `{ count: Int }` → `{ count: Int, history: List(Int) }` changes the struct size; heap objects cannot be realloced while other code holds pointers to them.

**Current layout (all builds):**
```
[0]=rc  [1]=tag+pad  [2]=dispatch_closure  [3]=alive  [4+]=state_fields_inline
```

**`--hot-reload` actor layout:**
```
[0]=rc  [1]=tag+pad  [2]=dispatch_closure  [3]=alive  [4]=state_ptr → heap record
```

`state_ptr` at `actor[4]` points to a separately heap-allocated record containing the actor's state fields. Handlers for hot-reload actors do one extra load before any field access. Non-hot-reload actors are unchanged — the compiler switches layouts based on the `--hot-reload` flag.

**Spawn (`init()`) with state indirection:**

When a hot-reload actor is spawned, `init()` returns a state record (a normal heap-allocated March record). The runtime stores this pointer at `actor[4]`:
```llvm
%state = call ptr @ActorName_init()   ; returns heap record ptr
store ptr %state, ptr %actor_field4   ; actor[4] = state_ptr
```
This is natural: `init()` already returns a record; the only change is where the pointer is stored.

**Field access codegen:**

Non-hot-reload (unchanged):
```llvm
%val = load i64, ptr (getelementptr i64, ptr %actor, i32 <4+field_idx>)
```

Hot-reload:
```llvm
%state = load ptr, ptr (getelementptr i64, ptr %actor, i32 4)
%val   = load i64, ptr (getelementptr i64, ptr %state, i32 <field_idx>)
```

The `llvm_emit.ml` actor-field access path switches on a `hot_reload_actor` flag propagated from the build mode.

### System migrate message

New constant `MARCH_MIGRATE_TAG` (a heap tag value distinct from any March ADT tag, defined in `march_runtime.h`). The migrate message payload is a two-word struct:
```c
typedef struct {
    void *new_closure_ptr;
    void *(*migrate_fn)(void *);  /* NULL when state type is unchanged */
    char  new_impl_hash[65];      /* hex impl_hash of the new handler version */
} march_migrate_msg_t;
```

Injected at the **front** of the actor's save queue (before any pending user messages) so it runs as the actor's next turn.

**`actor_green_thread` extension** (in `march_runtime.c`):

```c
while (a[3]) {
    void *msg = march_sched_recv();
    if (!msg) break;

    /* Check for system migrate message before user dispatch */
    if (march_obj_tag(msg) == MARCH_MIGRATE_TAG) {
        march_migrate_msg_t *m = (march_migrate_msg_t *)((char*)msg + 16);
        void *new_state = m->migrate_fn
            ? m->migrate_fn((void *)(uintptr_t)a[4])
            : (void *)(uintptr_t)a[4];
        a[2] = (int64_t)(uintptr_t)m->new_closure_ptr;
        a[4] = (int64_t)(uintptr_t)new_state;
        march_actor_meta *meta = find_meta(actor);
        if (meta) strncpy(meta->handler_impl_hash,
                          m->new_impl_hash, 64);
        march_decrc(msg);
        march_sched_tick();
        continue;  /* do NOT deliver to user handler */
    }

    /* Normal dispatch */
    char *closure = (char *)(uintptr_t)a[2];
    /* ... existing dispatch ... */
}
```

### `march_actor_meta` extension

Add two fields to the existing `march_actor_meta` struct:
```c
char    handler_impl_hash[65];  /* per-actor current handler version */
char    state_type_sig_hash[65]; /* sig_hash of the actor's State type */
```

`handler_impl_hash` is populated at spawn (from the NAME_ID's current impl_hash) and updated on each migrate turn. Used by the `VERSIONS` reload-server command to report per-actor drift. `state_type_sig_hash` is used by ACTIVATE to decide whether a migration function is needed.

### ACTIVATE extension in `march_reload.c`

The ACTIVATE command gains a `migrate_required` field:

```
ACTIVATE <name> <impl_hash> <cas_hash> <migrate_required> <sig64>
```

Where `migrate_required` is `1` if the deploy tool's schema diff determined the `State` type changed, `0` if only behavior changed.

After the existing sig-verify + CAS-load + `dlopen` + `march_dispatch_publish`:

1. `dlsym(handle, "__migrate_<mangled_module>_<actor_name>")` — returns NULL if absent.
2. **Snapshot actors under lock, inject messages outside lock:**
   ```c
   /* Phase 1: snapshot under lock */
   pthread_mutex_lock(&g_tbl_mu);
   actor_ptr_list_t *to_migrate = NULL;
   for (int b = 0; b < MARCH_SCHED_BUCKETS; b++) {
       for (march_actor_meta *m = g_actor_tbl[b]; m; m = m->tbl_next) {
           if (strncmp(m->handler_impl_hash, old_impl_hash, 64) == 0)
               actor_ptr_list_push(&to_migrate, m->actor);
       }
   }
   pthread_mutex_unlock(&g_tbl_mu);

   /* Phase 2: inject outside lock */
   for each actor in to_migrate:
       if (migrate_fn != NULL):
           inject_migrate_message(actor, new_closure_ptr, migrate_fn, new_impl_hash)
       else if (migrate_required):
           supervisor_restart(actor)   /* state type changed, no migrate_state */
       else:
           inject_migrate_message(actor, new_closure_ptr, NULL, new_impl_hash)
                                       /* closure-only swap, same state */
   ```
3. Free the snapshot list.

New actors spawned after ACTIVATE pick up the new version via `march_dispatch_publish` — no migration needed.

### `migrate_state` compilation

**Recognition:** The typechecker recognizes a function named exactly `migrate_state` with signature `(old : RawRecord) : SomeType` as a special migration function. The return type annotation determines which actor's prior State type to look up.

**Disambiguation:** If a module defines `CounterState` and `CacheState`, the two migration functions are:
```march
fn migrate_state(old : RawRecord) : CounterState do ... end
fn migrate_state(old : RawRecord) : CacheState do ... end
```
The return type annotation is mandatory. If two `migrate_state` functions have the same return type, that is a compile error.

**CAS lookup:** The typechecker fetches the prior deployed definition of the return type from the CAS. The prior type is the one whose `impl_hash` predecessor in the Merkle graph matches the currently deployed version (known from the `ABI_QUERY` baseline). If no prior version exists in the CAS (first deploy, or prior schema not stored), the compiler emits an error: `migrate_state requires a prior deployed version of CounterState in the CAS`.

**Elaboration:** The typechecker unifies `old` with the prior State type. From that point, `old.count` resolves normally to the prior type's `count` field at the correct GEP index. `RawRecord` has no runtime representation — it disappears after typechecking. The compiled function is:
```
fn __migrate_<mangled_module>_<actor_name>(old_state_ptr : ptr) : ptr
```
Exported as a named symbol from the hot artifact.

**Failure cases:**
- `RawRecord` used outside `migrate_state` → compile error: "RawRecord is only valid as the parameter type of migrate_state"
- Field access on `old` that didn't exist in the prior type → compile error: "field 'foo' does not exist in prior CounterState"
- Prior type not in CAS → compile error (see above)

---

## Part B: Type-Level Guardrails

### Schema storage

During `forge build --hot-reload`, the compiler emits a `.schemas.json` file alongside each CAS artifact. Format:

```json
{
  "MyApp.Counter": {
    "compat": "full",
    "state_type": "CounterState",
    "fields": [
      { "name": "count", "type": "Int" }
    ]
  },
  "MyApp.Cache": {
    "compat": "full",
    "state_type": "CacheState",
    "fields": [
      { "name": "ttl", "type": "Int" },
      { "name": "value", "type": "String" }
    ]
  }
}
```

The schema file is keyed in the CAS alongside the artifact (`<compilation_hash>.schemas.json`). `forge deploy hot` fetches both the current build's schema and the prior deployed artifact's schema from the CAS for diffing. The prior schema path is derived from the `impl_hash` returned by `ABI_QUERY`.

### `@compat` annotation

Parsed as `DAttr` before `DType` in the AST. Three values:

```march
@compat(full)    type State = { count: Int }    -- both forward and backward (default for actor State)
@compat(forward) type Msg   = Inc | Dec | Get   -- forward only
@compat(any)     type Config = { debug: Bool }  -- no checking; migrate_state still required if types differ
```

The annotation is stored on the `TypeDef` and included in the `.schemas.json` output. If absent on a type named `State` (or any type used as an actor's handler state), `full` is assumed.

### Schema-compat checking in `cmd_deploy_hot.ml`

A new `Schema_diff` module (pure OCaml):

```ocaml
type field_change =
  | AddField   of string * string  (* name, type *)
  | RemoveField of string * string
  | ChangeFieldType of string * string * string  (* name, old_type, new_type *)

type change =
  | RecordChange of field_change
  | VariantAddCase of string
  | VariantRemoveCase of string

val diff : schema_type -> schema_type -> change list

val check_compat : compat_mode -> has_migrate_state:bool -> change list
  -> [`Ok | `Error of string]
```

**Variance-duality rules applied in `check_compat`:**

| Change | Forward-safe | Backward-safe |
|--------|-------------|---------------|
| Add a record field | ✅ | ❌ |
| Remove a record field | ❌ | ✅ |
| Change a field type | ❌ | ❌ |
| Add a variant case | ❌ | ✅ |
| Remove a variant case | ✅ | ✅ |

**`@compat(full)` with `migrate_state` present:**
- Backward-unsafe changes (add field, change type) are permitted — `migrate_state` handles old→new.
- Forward-unsafe changes (remove field, add variant case) still error. Remove-field in a single-node Phase 5 context is practically safe, but `@compat(full)` is strict. Use `@compat(any)` to opt out.

**`@compat(full)` without `migrate_state`:**
- Only fully safe changes allowed: remove variant case only. Everything else errors.

**`@compat(forward)` (for message types, not state):**
- Only forward-safe changes allowed: add record field, remove variant case.

**`@compat(any)`:**
- No schema checking. `migrate_state` still required if types differ (enforced by ACTIVATE's `migrate_required` flag).

**Note on catch-all arms:** Adding a variant case to `Msg` with `@compat(full)` errors at deploy time (forward-unsafe). The typechecker already enforces exhaustive matching in the new code. Checking for catch-all arms in *already-deployed live matchers* (the forward-compat concern for distributed clusters) is deferred to Phase 7.

### `migrate_required` computation

`cmd_deploy_hot.ml` sets `migrate_required = 1` in the ACTIVATE payload when:
- The schema diff finds any backward-unsafe change (add field, change type), OR
- `@compat(any)` is set and the `state_type_sig_hash` differs between current and prior

It sets `migrate_required = 0` when only behavior changed (same State type hash across builds).

---

## Files Changed

| File | Change |
|------|--------|
| `runtime/march_runtime.h` | `MARCH_MIGRATE_TAG` constant; `march_migrate_msg_t` struct; updated actor layout doc |
| `runtime/march_runtime.c` | `actor_green_thread` migrate-message check; `march_actor_meta` extended with `handler_impl_hash` + `state_type_sig_hash`; spawn stores `init()` result at `actor[4]` in hot-reload mode |
| `runtime/march_reload.c` | ACTIVATE extended: `migrate_required` flag; actor table snapshot + message injection; `dlsym` for `__migrate_*`; supervisor restart path |
| `lib/typecheck/typecheck.ml` | `migrate_state` recognition; `RawRecord` elaboration against prior CAS type; return-type-based disambiguation; error cases |
| `lib/tir/llvm_emit.ml` | Hot-reload actor state indirection (extra load in field access); `init()` stores pointer at `actor[4]`; `__migrate_*` symbol export |
| `forge/lib/cmd_deploy_hot.ml` | `Schema_diff` module; `.schemas.json` fetch from CAS; `@compat` enforcement; `migrate_required` in ACTIVATE payload |
| `bin/main.ml` | Emit `.schemas.json` alongside CAS artifact in `--hot-reload` mode |

---

## Failure Modes

| Situation | Behavior |
|-----------|----------|
| `migrate_state` absent, state type changed | Supervisor restarts affected actors from `init()` |
| `migrate_state` absent, state type unchanged | Closure-only swap via migrate message with `migrate_fn = NULL` |
| `migrate_state` panics | Supervisor restarts that actor from `init()`; others continue |
| Prior State type not in CAS | Compile error; cannot compile `migrate_state` |
| Schema diff finds backward-unsafe change, no `migrate_state` | `forge deploy hot` errors before ACTIVATE is sent |
| Schema diff finds forward-unsafe change | `forge deploy hot` errors (suggest `@compat(any)` or Phase 7 follow-on) |
| `RawRecord` used outside `migrate_state` | Compile error |
| Field access on `old` not in prior type | Compile error |

---

## End-to-End Example

```march
-- v1: deployed with forge deploy hot
mod MyApp.Counter do
  type State = { count : Int }

  fn init() : State do { count = 0 } end
  fn handle(state : State, msg : Msg) : State do
    match msg do
      Inc -> { count = state.count + 1 }
      Get -> state
    end
  end
end

-- v2: new deploy adds history field + migrate_state
mod MyApp.Counter do
  type State = { count : Int, history : List(Int) }

  fn migrate_state(old : RawRecord) : State do
    -- Compiler looks up prior State = { count: Int } from CAS
    -- old.count is a direct GEP to field index 0 of prior State
    { count = old.count, history = Nil }
  end

  fn init() : State do { count = 0, history = Nil } end
  fn handle(state : State, msg : Msg) : State do
    match msg do
      Inc -> { count = state.count + 1, history = state.count :: state.history }
      Get -> state
    end
  end
end
```

`forge deploy hot` flow:
1. Build v2; compile `migrate_state` against prior `State = { count: Int }` from CAS; export `__migrate_MyApp_Counter` from artifact.
2. Schema diff: `AddField("history", "List(Int)")` — backward-unsafe; `migrate_state` present → permitted.
3. CAS_PUT artifact; ACTIVATE with `migrate_required=1`.
4. Server: dlsym `__migrate_MyApp_Counter` (found); walk actors on old impl_hash; inject migrate message at front of each mailbox.
5. Each Counter actor: pops migrate message as next turn; calls `migrate_state(old_state_ptr)` → `{count=N, history=Nil}`; atomically swaps closure + state pointer; continues mailbox.
6. Zero messages dropped, zero downtime.

---

## Testing

- `demo/hcr_actor_demo.march`: Counter actor with state migration end-to-end (v1→v2, add field, verify migrate message runs before user messages)
- Unit tests in `test/test_cas.ml`: schema emit + fetch round-trip; prior-type lookup
- Unit tests in `forge/test/test_forge.ml`: `Schema_diff.diff` + `check_compat` (add field, remove field, change type, add variant case, remove variant case — all four compat modes × has_migrate_state boolean)
- `march_reload.c` actor-walk test: spawn 3 actors on v1; ACTIVATE; verify all receive migrate message before next user message
- Typecheck error tests: `RawRecord` outside `migrate_state`; missing field; no prior type in CAS
