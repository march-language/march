# HCR Phase 5: Actor State Migration — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:subagent-driven-development` (recommended) or `superpowers:executing-plans` to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Enable live state migration for actors during hot code reload, so running actors adopt new state layouts without restart.

**Architecture:** Three layers work together: (A) the C runtime detects `MARCH_MIGRATE_TAG` system messages in `actor_green_thread` and swaps the state pointer; (B) the compiler lowers hot-reload actors with a separate state record (state indirection via `$f_state` ptr at `a[4]`) and exports `__migrate_*` symbols; (C) the forge deploy tool diffs schemas at deploy time and adds a `migrate_required` flag to the ACTIVATE payload that triggers actor-table walk + message injection in `march_reload.c`.

**Tech Stack:** C (runtime/runtime.c, march_reload.c), OCaml 5.3.0 (lower.ml, llvm_emit.ml, typecheck.ml), Forge OCaml (cmd_deploy_hot.ml, schema_diff.ml), March language (actor migration syntax), Dune build system.

## Global Constraints

- **OCaml/Dune path:** prefix all dune/opam commands with `/Users/80197052/.opam/march/bin/`
- **Never** `eval $(opam env)` or any opam env prefix
- **Never** `git add -A`, `git add .`, `git add *`, or `git commit -am` — always stage files explicitly
- **Never** add `Co-Authored-By` lines to commits
- **Build:** `/Users/80197052/.opam/march/bin/dune build`
- **Full test suite:** `scripts/run-tests.sh` (~17s)
- **Quick tests:** `scripts/run-tests.sh -q` (~2s, skips Slow)
- **Subset:** `scripts/run-tests.sh compiler eval`
- **March syntax:** `if cond do ... end` (NO `then`); lambdas: `fn x -> expr`; `mod Name do ... end`

---

## File Structure

**Create:**
- `forge/lib/schema_diff.ml` — Pure OCaml module: parse actor state schemas, diff two schemas, check @compat annotations
- `demo/hcr_actor_demo/` — End-to-end demo: Counter v1 and v2 March files, deploy script

**Modify:**
- `runtime/march_runtime.h` — Add `MARCH_MIGRATE_TAG`, `march_migrate_msg_t`, `dispatch_name_id` in `march_actor_meta`, declare `march_actor_broadcast_migrate` and `march_actor_set_dispatch_id`
- `runtime/march_runtime.c` — `actor_green_thread` migrate dispatch, `march_actor_broadcast_migrate`, `march_actor_set_dispatch_id`, dispatch-table path in the actor loop
- `runtime/march_reload.c` — ACTIVATE handler: parse `migrate_required`, dlsym `__migrate_*`, call `march_actor_broadcast_migrate`
- `lib/tir/lower.ml` — `lower_actor` with state indirection when `~hot_reload:true`; emit `march_actor_set_dispatch_id` in spawn; add `~hot_reload` param to `lower_module`
- `lib/tir/llvm_emit.ml` — Export `__migrate_<actor>` symbol alias for functions named `*_migrate_state`; emit `march_actor_set_dispatch_id` call for hot-reload spawns
- `bin/main.ml` — Pass `~hot_reload` to `lower_module`; emit `.schemas.json` alongside the CAS artifact when `--hot-reload`
- `forge/lib/cmd_deploy_hot.ml` — Load `.schemas.json` for old and new builds, run `Schema_diff`, add `migrate_required` to ACTIVATE sends
- `forge/lib/dune` — Add `schema_diff` to the library modules

---

## Tasks

### Task 1: Runtime Primitives — march_runtime.h

**Files:**
- Modify: `runtime/march_runtime.h`

**Interfaces:**
- Produces: `MARCH_MIGRATE_TAG`, `march_migrate_msg_t`, `dispatch_name_id` in `march_actor_meta`, declarations of `march_actor_set_dispatch_id` and `march_actor_broadcast_migrate`

- [ ] **Step 1: Add MARCH_MIGRATE_TAG and march_migrate_msg_t**

Open `runtime/march_runtime.h` and find the section near the top after the existing `#include` guards and before the first type declaration. Add after the `march_decrc_freed` and RC API block:

```c
/* ── Phase 5: Actor state migration ─────────────────────────────────── */

/* Tag value for system migrate messages.  Chosen to be far outside the range
 * of normal March ADT constructor tags (which start at 0 and are bounded by
 * the number of constructors per type, typically < 1000). */
#define MARCH_MIGRATE_TAG ((int64_t)0x4D494752L)   /* "MIGR" */

/* System message injected into an actor's mailbox to trigger state migration.
 * Layout: standard 16-byte march object header (rc at 0, tag at 8) so that
 * actor_green_thread can detect it by checking ((int64_t*)msg)[1].
 * Allocated with malloc() by march_actor_broadcast_migrate; freed with free()
 * (NOT march_decrc) by actor_green_thread after handling. */
typedef struct {
    int64_t  _rc;              /* always 1 (not reference-counted) */
    int64_t  _tag;             /* MARCH_MIGRATE_TAG */
    void    *(*migrate_fn)(void *);  /* migrate_fn(old_state_ptr) → new_state_ptr, or NULL */
} march_migrate_msg_t;
```

- [ ] **Step 2: Add dispatch_name_id to march_actor_meta**

Find `typedef struct march_actor_meta {` in `march_runtime.h`. It ends before `} march_actor_meta;`. Add one field at the end of the struct body, before the closing `}`:

```c
    /* Phase 5: non-zero for actors compiled with --hot-reload.
     * Holds the dispatch-table NAME_ID of this actor's _dispatch function.
     * Used by actor_green_thread to look up the current fn_ptr via the
     * dispatch table (enabling function hot-swap without closure update)
     * and by march_actor_broadcast_migrate to target only the right actors. */
    uint32_t dispatch_name_id;
```

- [ ] **Step 3: Declare the two new runtime functions**

After the existing public function declarations (near where `march_spawn` and `march_kill` are declared), add:

```c
/* Set the dispatch-table NAME_ID for a hot-reload actor.  Must be called
 * immediately after march_spawn().  name_id is the slot ID registered for
 * the actor's _dispatch function.  No-op if actor has no meta entry. */
void march_actor_set_dispatch_id(void *actor, uint32_t name_id);

/* Walk all live actors whose dispatch_name_id equals [dispatch_name_id] and
 * inject a MARCH_MIGRATE_TAG message so each actor migrates its state on
 * the next turn.  migrate_fn may be NULL (skip state transform; only used
 * when the state type is unchanged). */
void march_actor_broadcast_migrate(uint32_t dispatch_name_id,
                                   void *(*migrate_fn)(void *));
```

- [ ] **Step 4: Build to verify header compiles**

```bash
/Users/80197052/.opam/march/bin/dune build 2>&1 | head -20
echo "exit: $?"
```

Expected: exit 0 (or only type-error warnings unrelated to the new declarations).

- [ ] **Step 5: Commit**

```bash
git add runtime/march_runtime.h
git commit -m "feat(hcr5): add MARCH_MIGRATE_TAG, migrate msg type, dispatch_name_id in actor_meta"
```

---

### Task 2: actor_green_thread — Migrate Dispatch & Dispatch-Table Path

**Files:**
- Modify: `runtime/march_runtime.c`

**Interfaces:**
- Consumes: `MARCH_MIGRATE_TAG`, `march_migrate_msg_t` from Task 1
- Produces: `actor_green_thread` that detects migrate messages and uses the dispatch table for hot-reload actors

- [ ] **Step 1: Implement march_actor_set_dispatch_id**

In `runtime/march_runtime.c`, after the `march_spawn` function (around line 1299), add:

```c
void march_actor_set_dispatch_id(void *actor, uint32_t name_id) {
    march_actor_meta *meta = find_meta(actor);
    if (meta) meta->dispatch_name_id = name_id;
}
```

- [ ] **Step 2: Modify actor_green_thread**

The current `actor_green_thread` (starting at line 1188) is:

```c
static void actor_green_thread(void *arg) {
    march_actor_meta *meta = (march_actor_meta *)arg;
    void *actor = meta->actor;
    int64_t *a = (int64_t *)actor;

    while (a[3]) {  /* while alive */
        void *msg = march_sched_recv();
        if (!msg) break;  /* woken without message (killed) */

        if (!a[3]) {
            march_decrc(msg);
            break;
        }

        char *closure = (char *)(uintptr_t)a[2];
        typedef void (*closure_fn_t)(void *, void *, void *);
        closure_fn_t fn = *(closure_fn_t *)(closure + 16);

        int64_t saved_rc = a[0];
        a[0] = 1;  /* FBIP: force RC=1 for in-place reuse */
        fn(closure, actor, msg);
        a[0] = saved_rc;

        march_sched_tick();
    }
}
```

Replace it with the version below that (a) checks for migrate messages first and (b) uses the dispatch table for hot-reload actors:

```c
static void actor_green_thread(void *arg) {
    march_actor_meta *meta = (march_actor_meta *)arg;
    void *actor = meta->actor;
    int64_t *a = (int64_t *)actor;

    while (a[3]) {  /* while alive */
        void *msg = march_sched_recv();
        if (!msg) break;  /* woken without message (killed) */

        /* ── Phase 5: detect system migrate message ─────────────────────
         * Check BEFORE the alive gate so the message is always freed even
         * if the actor died between injection and receipt. */
        if (((int64_t *)msg)[1] == MARCH_MIGRATE_TAG) {
            march_migrate_msg_t *mm = (march_migrate_msg_t *)msg;
            if (a[3] && mm->migrate_fn) {
                /* a[4] is the state record pointer (state indirection layout).
                 * migrate_fn receives the old state ptr and returns the new one. */
                void *new_state = mm->migrate_fn((void *)(uintptr_t)a[4]);
                a[4] = (int64_t)(uintptr_t)new_state;
            }
            free(mm);  /* malloc'd, NOT a march heap object */
            march_sched_tick();
            continue;
        }

        if (!a[3]) {
            march_decrc(msg);
            break;
        }

        typedef void (*closure_fn_t)(void *, void *, void *);
        closure_fn_t fn;
        uint32_t tbl_version = 0;

        if (meta->dispatch_name_id) {
            /* Hot-reload actor: look up current dispatch fn in table.
             * Actor dispatch fns ignore their env arg, so passing the
             * (possibly stale) closure at a[2] as env is harmless. */
            void *fn_raw = march_dispatch_enter(meta->dispatch_name_id, &tbl_version);
            memcpy(&fn, &fn_raw, sizeof(fn));
        } else {
            /* Regular actor: direct closure dispatch. */
            char *closure = (char *)(uintptr_t)a[2];
            fn = *(closure_fn_t *)(closure + 16);
        }

        int64_t saved_rc = a[0];
        a[0] = 1;  /* FBIP: force RC=1 for in-place reuse */
        fn((void *)(uintptr_t)a[2], actor, msg);
        a[0] = saved_rc;

        if (meta->dispatch_name_id) {
            march_dispatch_leave(meta->dispatch_name_id, tbl_version);
        }

        march_sched_tick();
    }
}
```

Note: `memcpy(&fn, &fn_raw, sizeof(fn))` avoids the UB of directly casting `void*` to a function pointer. The `#include <string.h>` is already in `march_runtime.c`; verify it is.

- [ ] **Step 3: Build**

```bash
/Users/80197052/.opam/march/bin/dune build 2>&1 | head -20
echo "exit: $?"
```

Expected: exit 0.

- [ ] **Step 4: Quick test — no regressions**

```bash
scripts/run-tests.sh -q 2>&1 | tail -10
echo "exit: $?"
```

Expected: all quick tests pass, exit 0.

- [ ] **Step 5: Commit**

```bash
git add runtime/march_runtime.c
git commit -m "feat(hcr5): actor_green_thread: migrate dispatch + dispatch-table path for hot-reload actors"
```

---

### Task 3: march_actor_broadcast_migrate

**Files:**
- Modify: `runtime/march_runtime.c`

**Interfaces:**
- Consumes: `march_migrate_msg_t`, `MARCH_MIGRATE_TAG`, `dispatch_name_id` from Tasks 1–2
- Produces: `march_actor_broadcast_migrate(dispatch_name_id, migrate_fn)` — walks hash table, injects migrate messages

- [ ] **Step 1: Implement march_actor_broadcast_migrate**

In `runtime/march_runtime.c`, after the `march_actor_set_dispatch_id` function added in Task 2, add:

```c
#define MARCH_MIGRATE_SNAPSHOT 2048

void march_actor_broadcast_migrate(uint32_t dispatch_name_id,
                                   void *(*migrate_fn)(void *)) {
    if (!dispatch_name_id) return;

    /* Phase 1: snapshot matching actors under lock.
     * We incrc each actor so it stays alive while we hold the snapshot.
     * The lock is released before injecting messages to avoid holding
     * g_tbl_mu while calling march_sched_send (which may block). */
    march_actor_meta *snaps[MARCH_MIGRATE_SNAPSHOT];
    int n = 0;

    pthread_mutex_lock(&g_tbl_mu);
    for (int b = 0; b < MARCH_SCHED_BUCKETS && n < MARCH_MIGRATE_SNAPSHOT; b++) {
        for (march_actor_meta *m = g_actor_tbl[b];
             m && n < MARCH_MIGRATE_SNAPSHOT;
             m = m->tbl_next) {
            if (m->dispatch_name_id == dispatch_name_id && m->actor && m->green_thread) {
                march_incrc(m->actor);
                snaps[n++] = m;
            }
        }
    }
    pthread_mutex_unlock(&g_tbl_mu);

    /* Phase 2: inject migrate messages outside the lock. */
    for (int i = 0; i < n; i++) {
        march_migrate_msg_t *mm = (march_migrate_msg_t *)malloc(sizeof(*mm));
        if (mm) {
            mm->_rc        = 1;
            mm->_tag       = MARCH_MIGRATE_TAG;
            mm->migrate_fn = migrate_fn;
            march_sched_send(snaps[i]->green_thread, mm);
        }
        march_decrc(snaps[i]->actor);
    }
}
```

- [ ] **Step 2: Build**

```bash
/Users/80197052/.opam/march/bin/dune build 2>&1 | head -20
echo "exit: $?"
```

Expected: exit 0.

- [ ] **Step 3: Quick tests**

```bash
scripts/run-tests.sh -q 2>&1 | tail -5
echo "exit: $?"
```

Expected: exit 0.

- [ ] **Step 4: Commit**

```bash
git add runtime/march_runtime.c
git commit -m "feat(hcr5): implement march_actor_broadcast_migrate (snapshot walk + inject)"
```

---

### Task 4: ACTIVATE Extension in march_reload.c

**Files:**
- Modify: `runtime/march_reload.c`

**Interfaces:**
- Consumes: `march_actor_broadcast_migrate` from Task 3; `march_dispatch_name_to_id` from `march_dispatch.h`
- Produces: ACTIVATE handler that parses `migrate_required` flag, dlsyms `__migrate_*`, calls broadcast

The current ACTIVATE format is: `ACTIVATE <name> <impl_hash> <cas_hash> <sig_b64>`
New format adds an optional fifth field: `ACTIVATE <name> <impl_hash> <cas_hash> <sig_b64> [migrate_required]`
Where `migrate_required` is `1` if the actor needs state migration, `0` or absent otherwise.

- [ ] **Step 1: Find the ACTIVATE handler**

Read the current `handle_activate` (or `handle_client`) in `runtime/march_reload.c`. The ACTIVATE handler currently parses 4 fields with `sscanf` or `strtok`. Find the line that builds the 4-field parse and the `march_dispatch_publish` call that follows.

- [ ] **Step 2: Add migrate_required parsing and actor broadcast**

In `march_reload.c`, include the necessary headers at the top of the file (if not already present):

```c
#include "march_runtime.h"   /* march_actor_broadcast_migrate, march_actor_set_dispatch_id */
#include "march_dispatch.h"  /* march_dispatch_name_to_id */
```

In the ACTIVATE handler, after `march_dispatch_publish(slot_id, fn_ptr, impl_hash, NULL, MARCH_NATIVE)` succeeds, add:

```c
        /* ── Phase 5: optional actor migration ──────────────────────────
         * If migrate_required=1 was sent, look for a __migrate_<name>
         * symbol in the newly-loaded .so and broadcast a migrate message
         * to all live actors whose dispatch slot matches this name. */
        int migrate_required = 0;
        /* migrate_required_str is the 5th whitespace-delimited token on
         * the ACTIVATE line, or NULL/absent for Phase 4 activations. */
        if (migrate_required_str && sscanf(migrate_required_str, "%d", &migrate_required) == 1
                && migrate_required) {
            /* Build the migrate symbol name: __migrate_<name>
             * where dots in <name> are replaced with double-underscore. */
            char migrate_sym[512];
            snprintf(migrate_sym, sizeof(migrate_sym), "__migrate_%s", name);
            for (char *p = migrate_sym + 10; *p; p++) {
                if (*p == '.') { *p = '_'; }
            }

            void *(*migrate_fn)(void *) = NULL;
            void *raw_sym = dlsym(handle, migrate_sym);
            if (raw_sym) {
                memcpy(&migrate_fn, &raw_sym, sizeof(migrate_fn));
            } else {
                dprintf(client_fd, "WARN __migrate symbol not found: %s\n", migrate_sym);
            }

            uint32_t name_id = 0;
            if (march_dispatch_name_to_id(name, &name_id) == 0 && name_id) {
                march_actor_broadcast_migrate(name_id, migrate_fn);
            }
        }
```

You also need to capture `migrate_required_str` from the ACTIVATE line parsing. Find where the current handler parses `name impl_hash cas_hash sig_b64` (probably with `sscanf` or successive `strtok` calls) and add a 5th optional capture:

**If using sscanf:** Change the existing 4-field `sscanf` (something like `sscanf(line, "ACTIVATE %s %s %s %s", name, impl_hash, cas_hash, sig_b64)`) to a 5-field one:

```c
char migrate_required_str[8] = {0};
int parsed = sscanf(cmd, "ACTIVATE %63s %64s %64s %512s %7s",
                    name, impl_hash, cas_hash, sig_b64, migrate_required_str);
/* parsed == 4 is Phase 4 (no migration); parsed == 5 is Phase 5 */
```

**If using strtok-style parsing:** after parsing `sig_b64`, do:
```c
char *migrate_required_str = strtok(NULL, " \t\n");
/* NULL if absent (Phase 4 activation) */
```

Adapt to the actual parsing style in the file.

- [ ] **Step 3: Build**

```bash
/Users/80197052/.opam/march/bin/dune build 2>&1 | head -20
echo "exit: $?"
```

Expected: exit 0.

- [ ] **Step 4: Quick tests — no regressions**

```bash
scripts/run-tests.sh -q 2>&1 | tail -5
echo "exit: $?"
```

Expected: exit 0.

- [ ] **Step 5: Commit**

```bash
git add runtime/march_reload.c
git commit -m "feat(hcr5): ACTIVATE handler: parse migrate_required, dlsym __migrate_*, broadcast"
```

---

### Task 5: State Indirection in lower_actor

**Files:**
- Modify: `lib/tir/lower.ml`

**Interfaces:**
- Consumes: `~hot_reload:bool` parameter (new, threaded from `lower_module`)
- Produces: When `hot_reload=true`, `lower_actor` emits actors with a separate `Name_State` record type and a `$f_state` pointer field; handler field loads/writes go through state ptr; spawn passes state record directly

The state indirection layout changes the actor struct from:

```
actor: [("$d_dispatch", TPtr TUnit); ("$e_alive", TBool); ("count", TInt); ...]
```
to:
```
actor: [("$d_dispatch", TPtr TUnit); ("$e_alive", TBool); ("$f_state", TCon("Name_State", []))]
state: [("count", TInt); ...]  ← separate heap record
```

In the C runtime, this means:
- `a[2]` = dispatch closure (unchanged)  
- `a[3]` = alive flag (unchanged)
- `a[4]` = pointer to state record (NEW — was first state field)

The `$` prefix sorts before any letter, so `$d < $e < $f` and field 2 = `$f_state` → `a[4]`. ✓

- [ ] **Step 1: Add ~hot_reload parameter to lower_module**

In `lib/tir/lower.ml`, find the `lower_module` signature (line 1715):

```ocaml
let lower_module ?type_map ?(stdlib_context : Ast.decl list = []) ?(test_mode=false) (m : Ast.module_) : Tir.tir_module =
```

Change to:

```ocaml
let lower_module ?type_map ?(stdlib_context : Ast.decl list = []) ?(test_mode=false) ?(hot_reload=false) (m : Ast.module_) : Tir.tir_module =
```

Also update `lower_actor` to accept `~hot_reload`:

Find the `lower_actor` definition (line 1412):
```ocaml
let lower_actor (name : string) (actor : Ast.actor_def) : Tir.type_def list * Tir.fn_def list =
```
Change to:
```ocaml
let lower_actor ~hot_reload (name : string) (actor : Ast.actor_def) : Tir.type_def list * Tir.fn_def list =
```

Find where `lower_actor` is called inside `lower_module` (grep for `lower_actor` to find the callsite) and pass `~hot_reload`.

- [ ] **Step 2: Add state type name constant inside lower_actor**

Inside `lower_actor`, right after `let state_fields_sorted = ...` (line ~1414), add:

```ocaml
  let state_type_name = name ^ "_State" in
  (* In hot_reload mode, state_type_name is used for the SEPARATE state record.
     In non-hot_reload mode, it already exists (TDRecord at line 1696). *)
```

Note: `name ^ "_State"` is ALREADY used later in the function (line 1489 `let state_ty = Tir.TCon (name ^ "_State", [])` and line 1696 `let state_record = Tir.TDRecord (name ^ "_State", ...)`). So `state_type_name` is just a convenience alias — no new logic yet.

- [ ] **Step 3: Conditionally change the actor struct fields**

Find the actor struct definition block (lines 1432–1442):

```ocaml
  (* ── 2. Actor struct type ────────────────────────────────── *)
  let actor_type_name = name ^ "_Actor" in
  let actor_struct_fields : (string * Tir.ty) list =
    [("$d_dispatch", Tir.TPtr Tir.TUnit); ("$e_alive", Tir.TBool)]
    @ state_fields_sorted
  in
  let actor_record = Tir.TDRecord (actor_type_name, actor_struct_fields) in
```

Replace with:

```ocaml
  (* ── 2. Actor struct type ────────────────────────────────── *)
  let actor_type_name = name ^ "_Actor" in
  (* In hot_reload mode, state fields are NOT inline in the actor struct.
     Instead, the actor has a single "$f_state" pointer to a separate
     state record (Name_State).  This allows the runtime to swap state
     at migration time without reallocating the actor. *)
  let actor_struct_fields : (string * Tir.ty) list =
    if hot_reload then
      [("$d_dispatch", Tir.TPtr Tir.TUnit);
       ("$e_alive", Tir.TBool);
       ("$f_state", Tir.TCon (state_type_name, []))]
    else
      [("$d_dispatch", Tir.TPtr Tir.TUnit); ("$e_alive", Tir.TBool)]
      @ state_fields_sorted
  in
  let actor_record = Tir.TDRecord (actor_type_name, actor_struct_fields) in
```

- [ ] **Step 4: Conditionally change handler field loads**

Inside `lower_handler`, find the block that loads state fields (lines 1543–1548):

```ocaml
    (* Wrap: let $sf_fi = EField(actor, fi) for each state field *)
    let inner_with_state_loads =
      List.fold_right (fun (fname, sfv) acc ->
          Tir.ELet (sfv, Tir.EField (actor_atom, fname), acc)
        ) state_field_vars inner_with_state
    in
```

Replace with:

```ocaml
    (* Wrap: load state fields.
       In hot_reload mode: first load the state ptr from actor, then load
       each field from the state ptr (two-level dereference).
       In normal mode: load each field directly from the actor struct. *)
    let state_ptr_var = actor_var "$f_state_v" (Tir.TCon (state_type_name, [])) in
    let inner_with_state_loads =
      if hot_reload then
        (* Outer: let $f_state_v = EField(actor, "$f_state") *)
        Tir.ELet (state_ptr_var,
          Tir.EField (actor_atom, "$f_state"),
          (* Inner: let $sf_fi = EField($f_state_v, fname) for each field *)
          List.fold_right (fun (fname, sfv) acc ->
              Tir.ELet (sfv, Tir.EField (Tir.AVar state_ptr_var, fname), acc)
            ) state_field_vars inner_with_state)
      else
        List.fold_right (fun (fname, sfv) acc ->
            Tir.ELet (sfv, Tir.EField (actor_atom, fname), acc)
          ) state_field_vars inner_with_state
    in
```

- [ ] **Step 5: Conditionally change handler write-back (EReuse)**

Find the reuse_args and reuse_expr block (lines 1501–1515):

```ocaml
    (* Step 4: build EReuse args: $d_dispatch, $e_alive, then new state fields *)
    let dispatch_var = actor_var "$d_dispatch_v" (Tir.TPtr Tir.TUnit) in
    let alive_var    = actor_var "$e_alive_v" Tir.TBool in

    (* Build the innermost expression: ESeq(EReuse(...), unit) *)
    let reuse_args : Tir.atom list =
      [Tir.AVar dispatch_var; Tir.AVar alive_var]
      @ List.map (fun (_, v) -> Tir.AVar v) new_field_vars
    in
    let reuse_expr =
      Tir.ESeq (
        Tir.EReuse (actor_atom, Tir.TCon (actor_type_name, []), reuse_args),
        Tir.EAtom (Tir.ALit (Ast.LitAtom "unit"))
      )
    in
```

Replace with:

```ocaml
    (* Step 4: build EReuse args: $d_dispatch, $e_alive, then new state fields *)
    let dispatch_var = actor_var "$d_dispatch_v" (Tir.TPtr Tir.TUnit) in
    let alive_var    = actor_var "$e_alive_v" Tir.TBool in

    (* Build the innermost expression: ESeq(EReuse(...), unit)
       In hot_reload mode: first EReuse the state record (FBIP), then
       EReuse the actor with just the new state ptr. *)
    let reuse_expr =
      if hot_reload then
        (* state_ptr_var was bound in inner_with_state_loads above *)
        let new_state_var = actor_var "$new_state" (Tir.TCon (state_type_name, [])) in
        let state_reuse_args = List.map (fun (_, v) -> Tir.AVar v) new_field_vars in
        let actor_reuse_args =
          [Tir.AVar dispatch_var; Tir.AVar alive_var; Tir.AVar new_state_var]
        in
        Tir.ELet (new_state_var,
          Tir.EReuse (Tir.AVar state_ptr_var,
                      Tir.TCon (state_type_name, []),
                      state_reuse_args),
          Tir.ESeq (
            Tir.EReuse (actor_atom, Tir.TCon (actor_type_name, []), actor_reuse_args),
            Tir.EAtom (Tir.ALit (Ast.LitAtom "unit"))
          ))
      else
        let reuse_args : Tir.atom list =
          [Tir.AVar dispatch_var; Tir.AVar alive_var]
          @ List.map (fun (_, v) -> Tir.AVar v) new_field_vars
        in
        Tir.ESeq (
          Tir.EReuse (actor_atom, Tir.TCon (actor_type_name, []), reuse_args),
          Tir.EAtom (Tir.ALit (Ast.LitAtom "unit"))
        )
    in
```

Note: `state_ptr_var` is defined in Step 4 (inside `inner_with_state_loads`). In the `if hot_reload` branch of `reuse_expr`, we reference it. Since `inner_with_state_loads` and `reuse_expr` are both computed inside `lower_handler`, the OCaml binding is in scope. The `state_ptr_var` binding must be moved out of the `inner_with_state_loads` conditional so it is accessible in `reuse_expr`. Concretely, define `state_ptr_var` BEFORE the `inner_with_state_loads` block:

```ocaml
    (* state_ptr_var is referenced in both inner_with_state_loads and reuse_expr
       in hot_reload mode, so define it before both. *)
    let state_ptr_var = actor_var "$f_state_v" (Tir.TCon (state_type_name, [])) in
    let inner_with_state_loads = ...
    let reuse_expr = ...
```

- [ ] **Step 6: Conditionally change handler dispatch_var/alive_var loads**

The dispatch_var and alive_var are loaded from actor in the `full_body` at lines 1550–1558:

```ocaml
    (* Wrap: let $e_alive_v = EField(actor, "$e_alive") *)
    let inner_with_alive =
      Tir.ELet (alive_var, Tir.EField (actor_atom, "$e_alive"), inner_with_state_loads)
    in

    (* Wrap: let $d_dispatch_v = EField(actor, "$d_dispatch") *)
    let full_body =
      Tir.ELet (dispatch_var, Tir.EField (actor_atom, "$d_dispatch"), inner_with_alive)
    in
```

These don't need changes — `$d_dispatch` and `$e_alive` are always in the actor struct (both modes). ✓

- [ ] **Step 7: Conditionally change spawn function**

Find the spawn function body (lines 1607–1640). Currently it extracts state fields from `init_var` (the init() result) and re-injects them into the actor alloc. In hot_reload mode, `init_var` IS the state record — we can pass it directly.

Find the `spawn_with_fields` and `alloc_expr` block (lines 1627–1639):

```ocaml
  let alloc_args : Tir.atom list =
    [Tir.AVar dispatch_fn_ptr_var; Tir.ALit (Ast.LitBool true)]
    @ List.map (fun (_, v) -> Tir.AVar v) init_field_vars
  in
  let alloc_expr = Tir.EAlloc (Tir.TCon (actor_type_name, []), alloc_args) in
  let actor_result_var = actor_var "$spawned" (Tir.TPtr Tir.TUnit) in
  let spawn_inner =
    Tir.ELet (actor_result_var, alloc_expr, Tir.EAtom (Tir.AVar actor_result_var))
  in
  let spawn_with_fields =
    List.fold_right (fun (fname, ifv) acc ->
        Tir.ELet (ifv, Tir.EField (Tir.AVar init_var, fname), acc)
      ) init_field_vars spawn_inner
  in
```

Replace with:

```ocaml
  let alloc_args : Tir.atom list =
    if hot_reload then
      (* State record (init_var) is passed directly as the $f_state ptr. *)
      [Tir.AVar dispatch_fn_ptr_var; Tir.ALit (Ast.LitBool true); Tir.AVar init_var]
    else
      [Tir.AVar dispatch_fn_ptr_var; Tir.ALit (Ast.LitBool true)]
      @ List.map (fun (_, v) -> Tir.AVar v) init_field_vars
  in
  let alloc_expr = Tir.EAlloc (Tir.TCon (actor_type_name, []), alloc_args) in
  let actor_result_var = actor_var "$spawned" (Tir.TPtr Tir.TUnit) in
  let spawn_inner =
    Tir.ELet (actor_result_var, alloc_expr, Tir.EAtom (Tir.AVar actor_result_var))
  in
  let spawn_with_fields =
    if hot_reload then
      (* In hot_reload mode, init_var IS the state record; no field extraction needed. *)
      spawn_inner
    else
      List.fold_right (fun (fname, ifv) acc ->
          Tir.ELet (ifv, Tir.EField (Tir.AVar init_var, fname), acc)
        ) init_field_vars spawn_inner
  in
```

- [ ] **Step 8: Pass ~hot_reload to lower_module call in bin/main.ml**

In `bin/main.ml`, find line 1178:
```ocaml
    let tir = March_tir.Lower.lower_module ~type_map ~test_mode:!do_test desugared in
```

Change to:
```ocaml
    let tir = March_tir.Lower.lower_module ~type_map ~test_mode:!do_test ~hot_reload:(Option.is_some !hot_reload_prefix) desugared in
```

- [ ] **Step 9: Build**

```bash
/Users/80197052/.opam/march/bin/dune build 2>&1 | head -30
echo "exit: $?"
```

Expected: exit 0. If there are type errors, they will be about the `state_ptr_var` scope (Step 5 note) or wrong atom types in EReuse args — fix those inline before proceeding.

- [ ] **Step 10: Run actor-specific tests**

```bash
scripts/run-tests.sh -q compiler eval 2>&1 | tail -10
echo "exit: $?"
```

Expected: exit 0. If any actor-related tests fail, examine the failure output. The most likely issue is the `state_ptr_var` being referenced outside its let scope — move the `let state_ptr_var = ...` definition earlier in `lower_handler` as noted in Step 5.

- [ ] **Step 11: Commit**

```bash
git add lib/tir/lower.ml bin/main.ml
git commit -m "feat(hcr5): state indirection in lower_actor for --hot-reload actors"
```

---

### Task 6: __migrate_* Symbol Export in llvm_emit.ml

**Files:**
- Modify: `lib/tir/llvm_emit.ml`

**Interfaces:**
- Consumes: Functions named `*_migrate_state` in TIR with return type `TCon(*_State, [])`
- Produces: Each such function is emitted with an additional LLVM alias `__migrate_<actor>` so the reload server can dlsym it

The naming convention: a function `Mod.Counter_migrate_state` (where return type is `Mod.Counter_State`) is aliased to `__migrate_Mod_Counter` (dots → `_`, the `_State` suffix is stripped from the type name to get the actor name).

- [ ] **Step 1: Find where functions are emitted in llvm_emit.ml**

Grep for `define_function\|emit_fn_def\|fn_name` in `lib/tir/llvm_emit.ml` to find where individual function definitions are emitted. Look for the pattern that emits a function and appends it to the module.

- [ ] **Step 2: Add __migrate_* alias emission**

After each function definition is emitted, check if the function name ends with `_migrate_state` and if so, add a global alias. Find the function emission loop (it iterates over `tir.tm_fns` or similar) and add:

```ocaml
    (* Phase 5: export __migrate_<actor> alias for migrate_state functions.
     * Convention: Mod.Counter_migrate_state → __migrate_Mod_Counter
     * The alias lets dlsym find the function without needing to know the
     * full mangled March name. *)
    let migrate_suffix = "_migrate_state" in
    let slen = String.length fn_def.fn_name in
    let mlen = String.length migrate_suffix in
    if slen > mlen && String.sub fn_def.fn_name (slen - mlen) mlen = migrate_suffix then begin
      (* Strip "_migrate_state" suffix to get qualified actor name *)
      let actor_qualified = String.sub fn_def.fn_name 0 (slen - mlen) in
      (* Replace dots with underscores for the C symbol name *)
      let actor_mangled = String.map (fun c -> if c = '.' then '_' else c) actor_qualified in
      let alias_name = "__migrate_" ^ actor_mangled in
      (* Emit an LLVM global alias: @__migrate_Mod_Counter = alias ... @march_Mod_Counter_migrate_state *)
      (* The actual LLVM function name is the mangled form of fn_def.fn_name *)
      let llvm_fn_name = mangle fn_def.fn_name in  (* use existing mangle function *)
      ignore (Llvm.add_alias the_module
        (Llvm.function_type (Llvm.pointer_type (Llvm.i8_type ctx)) [| |])
        Llvm.Linkage.External
        llvm_fn_name
        alias_name)
    end;
```

**Important:** the exact LLVM API calls depend on the version of `llvm-ocaml` in use. Find how other aliases or global values are created elsewhere in `llvm_emit.ml`. The key semantics: create a global alias named `alias_name` that points to the function with mangled name `llvm_fn_name`, with external linkage (so it's exported from the .so).

Alternative if `Llvm.add_alias` isn't the right API: emit a thin wrapper function:

```ocaml
      (* Fallback: emit a named wrapper that just calls the migrate function *)
      let fn_ty = Llvm.function_type void_ty [| ptr_ty |] in
      let wrapper = Llvm.define_function alias_name fn_ty the_module in
      let bb = Llvm.append_block ctx "entry" wrapper in
      let b = Llvm.builder_at_end ctx bb in
      let orig_fn = Llvm.lookup_function llvm_fn_name the_module in
      match orig_fn with
      | Some f ->
        let arg = Llvm.param wrapper 0 in
        let result = Llvm.build_call fn_ty f [| arg |] "" b in
        ignore (Llvm.build_ret result b)
      | None -> ()
```

Find the actual `Llvm` bindings used in this file to use the right API. Search for `Llvm.define_function` or `Llvm.add_alias` in the existing code to understand the pattern.

- [ ] **Step 3: Add march_actor_set_dispatch_id call in spawn functions for hot-reload actors**

This connects to Task 5: when `--hot-reload` is active, the spawn function should call `march_actor_set_dispatch_id(actor, NAME_ID)` after `march_spawn`. The NAME_ID is the dispatch slot for the actor's `_dispatch` function.

In `llvm_emit.ml`, find where `EApp` calls to `march_spawn` are emitted. When `hot_reload` is enabled in the `ctx` and the spawn function being emitted is for an actor (i.e., the function is `Name_spawn`), after the `march_spawn` call, emit:

```ocaml
      (* In hot-reload mode: register this actor's dispatch slot ID so the
         runtime can use the dispatch table for fn updates and migration walk. *)
      if ctx.hr_config <> None then begin
        (* Look up the NAME_ID for Name_dispatch in the hot-reload name table *)
        let actor_name = String.sub fn_name 0 (String.length fn_name - 6) (* strip "_spawn" *) in
        let dispatch_name = actor_name ^ "_dispatch" in
        match hot_reload_name_id ctx dispatch_name with
        | Some name_id ->
          let set_dispatch_id_fn = get_or_declare_fn "march_actor_set_dispatch_id"
            (Llvm.function_type void_ty [| ptr_ty; i32_ty |]) the_module in
          ignore (Llvm.build_call
            (Llvm.function_type void_ty [| ptr_ty; i32_ty |])
            set_dispatch_id_fn
            [| spawned_actor_val; Llvm.const_int (Llvm.i32_type ctx) name_id |]
            "" builder)
        | None -> ()
      end
```

Find `hot_reload_name_id` in `llvm_emit.ml` — there should already be a function for looking up NAME_IDs (used for `march_dispatch_enter`/`leave` calls in the hot boundary). Use the same lookup mechanism.

- [ ] **Step 4: Build**

```bash
/Users/80197052/.opam/march/bin/dune build 2>&1 | head -30
echo "exit: $?"
```

Expected: exit 0.

- [ ] **Step 5: Verify alias is emitted**

Compile a small hot-reload actor test program with `--compile-so` and check the exported symbols:

```bash
# Create a minimal test actor
cat > /tmp/migrate_test_actor.march << 'EOF'
mod TestMigrate do
  actor Counter do
    state = 0
    on Inc() -> state + 1
    on Get() -> state
  end

  fn migrate_state(old : Counter_State) : Counter_State do
    old
  end

  fn main() do
    ()
  end
end
EOF

/Users/80197052/.opam/march/bin/dune build
./_build/default/bin/main.exe --hot-reload /tmp/test_hr --compile-so \
  -o /tmp/migrate_test_actor.so /tmp/migrate_test_actor.march 2>&1 | head -10

# Check exported symbols
nm -D /tmp/migrate_test_actor.so | grep "__migrate" | head -5
```

Expected: see `__migrate_TestMigrate_Counter` (or similar) in the output.

- [ ] **Step 6: Run tests**

```bash
scripts/run-tests.sh -q compiler eval 2>&1 | tail -10
echo "exit: $?"
```

Expected: exit 0.

- [ ] **Step 7: Commit**

```bash
git add lib/tir/llvm_emit.ml
git commit -m "feat(hcr5): export __migrate_<actor> alias from migrate_state functions in --hot-reload .so"
```

---

### Task 7: .schemas.json Emission in bin/main.ml + Schema_diff Module

**Files:**
- Modify: `bin/main.ml`
- Create: `forge/lib/schema_diff.ml`
- Modify: `forge/lib/dune`

**Interfaces:**
- Produces: `.schemas.json` sidecar alongside every `--hot-reload --compile-so` artifact; `Schema_diff.diff` and `Schema_diff.check_compat` for Task 8

The `.schemas.json` format (emitted by the compiler alongside each CAS `.so`):
```json
{
  "TestMigrate.Counter": {
    "compat": "full",
    "state_fields": [
      { "name": "count", "ty": "Int" }
    ]
  }
}
```

- [ ] **Step 1: Collect actor state schemas in bin/main.ml**

In `bin/main.ml`, find the TIR lowering result: `let tir = March_tir.Lower.lower_module ...`. The `tir` value has type `Tir.tir_module`. Actor type information is in `tir.tm_types` (the list of type definitions). State record types are named `Name_State`.

After lowering, when `--hot-reload` and `--compile-so` are both active, walk the type definitions and collect actor state schemas:

```ocaml
    (* Phase 5: collect actor state schemas for .schemas.json *)
    let actor_schemas =
      if !hot_reload_prefix <> None && !compile_so then
        List.filter_map (fun td ->
            match td with
            | March_tir.Tir.TDRecord (tname, fields)
              when let n = String.length tname in
                   n > 6 && String.sub tname (n - 6) 6 = "_State" ->
                (* actor name = strip "_State" suffix *)
                let actor_name = String.sub tname 0 (String.length tname - 6) in
                let field_schemas = List.map (fun (fname, fty) ->
                    Printf.sprintf {|{"name":%s,"ty":%s}|}
                      (Yojson_safe.to_string (`String fname))
                      (Yojson_safe.to_string (`String (March_tir.Tir.show_ty fty)))
                  ) fields
                in
                Some (actor_name, field_schemas)
            | _ -> None
          ) tir.March_tir.Tir.tm_types
      else []
    in
```

Note: `March_tir.Tir.show_ty` may or may not exist. If it doesn't, write a local `ty_to_string` function that converts a `Tir.ty` to a string (e.g., `TInt → "Int"`, `TBool → "Bool"`, `TCon(n, []) → n`, etc.).

- [ ] **Step 2: Emit .schemas.json**

Find the existing hcr_manifest emission block in `bin/main.ml` (around lines 1754–1772):

```ocaml
        (if !compile_so && Hashtbl.length hr_impl_hashes > 0 then begin
          let mf = out_bin ^ ".hcr_manifest" in
          ...
        end);
```

After this block, add the schema emission:

```ocaml
        (* Phase 5: emit .schemas.json for actor state schema checking at deploy time *)
        (if !compile_so && actor_schemas <> [] then begin
          let schema_path = out_bin ^ ".schemas.json" in
          (try
            let oc = open_out schema_path in
            Printf.fprintf oc "{\n";
            List.iteri (fun i (actor_name, field_schemas) ->
                Printf.fprintf oc "  %S: {\n    \"compat\": \"full\",\n    \"state_fields\": [%s]\n  }%s\n"
                  actor_name
                  (String.concat ", " field_schemas)
                  (if i < List.length actor_schemas - 1 then "," else "")
              ) actor_schemas;
            Printf.fprintf oc "}\n";
            close_out oc
          with Sys_error e ->
            Printf.eprintf "warning: could not write %s: %s\n" schema_path e)
        end);
```

- [ ] **Step 3: Create forge/lib/schema_diff.ml**

```bash
ls /Users/80197052/code/march/.claude/worktrees/elastic-bartik-a66d15/forge/lib/
```

Create the file:

```ocaml
(** Schema_diff — compare two actor state schemas for hot-code-reload compatibility.
    
    Schemas are loaded from .schemas.json files emitted by the compiler alongside
    each --hot-reload --compile-so artifact. *)

type field = { name: string; ty: string }
type actor_schema = {
  compat: string;   (* "full", "forward", "any" *)
  state_fields: field list;
}

type field_change =
  | FieldAdded of field
  | FieldRemoved of field
  | FieldTypeChanged of { name: string; old_ty: string; new_ty: string }

type actor_diff = {
  actor: string;
  changes: field_change list;
}

(** Parse a .schemas.json file.  Returns a map from actor name to schema. *)
let parse_schemas_file (path : string) : (string * actor_schema) list =
  if not (Sys.file_exists path) then []
  else
    let ic = open_in path in
    let content = In_channel.input_all ic in
    close_in ic;
    (* Minimal JSON parser: extract top-level keys and their state_fields arrays.
       Using Scanf for a dependency-free parse of our own fixed format. *)
    let schemas = ref [] in
    (* Split on top-level actor entries — each is: "ActorName": { ... } *)
    let lines = String.split_on_char '\n' content in
    let current_actor = ref "" in
    let current_compat = ref "full" in
    let current_fields = ref [] in
    let in_fields = ref false in
    List.iter (fun line ->
        let line = String.trim line in
        (* Detect actor key: "ActorName": { *)
        if String.length line > 3 && line.[0] = '"' && not !in_fields then begin
          (* Try to parse as actor name key *)
          (match String.split_on_char '"' line with
          | "" :: name :: _ when name <> "compat" && name <> "state_fields"
                               && name <> "name" && name <> "ty" ->
            if !current_actor <> "" then
              schemas := (!current_actor,
                { compat = !current_compat; state_fields = List.rev !current_fields })
                :: !schemas;
            current_actor := name;
            current_compat := "full";
            current_fields := []
          | _ -> ())
        end;
        (* Detect "compat": "value" *)
        if String.length line > 10 && String.sub line 0 10 = "\"compat\":" then begin
          (match String.split_on_char '"' line with
          | _ :: "compat" :: _ :: v :: _ -> current_compat := v
          | _ -> ())
        end;
        (* Detect state_fields array start *)
        if line = "\"state_fields\": [" || String.sub (String.trim line) 0
             (min 15 (String.length (String.trim line))) = "\"state_fields\":" then
          in_fields := true;
        (* Detect field entry: {"name":"x","ty":"Int"} *)
        if !in_fields && line.[0] = '{' then begin
          let name = ref "" and ty = ref "" in
          (match String.split_on_char '"' line with
          | _ :: "name" :: _ :: n :: _ :: "ty" :: _ :: t :: _ ->
            name := n; ty := t
          | _ -> ());
          if !name <> "" then
            current_fields := { name = !name; ty = !ty } :: !current_fields
        end;
        (* Detect end of fields *)
        if !in_fields && (line = "]" || String.length line > 0 && line.[String.length line - 1] = ']') then
          in_fields := false;
      ) lines;
    (* Flush the last actor *)
    if !current_actor <> "" then
      schemas := (!current_actor,
        { compat = !current_compat; state_fields = List.rev !current_fields })
        :: !schemas;
    List.rev !schemas

(** Compute the diff between old and new actor schemas. *)
let diff_actor (old_s : actor_schema) (new_s : actor_schema) : field_change list =
  let old_map = List.map (fun f -> (f.name, f.ty)) old_s.state_fields in
  let new_map = List.map (fun f -> (f.name, f.ty)) new_s.state_fields in
  let removed =
    List.filter_map (fun (name, ty) ->
        if not (List.mem_assoc name new_map) then Some (FieldRemoved { name; ty })
        else None)
      old_map
  in
  let added =
    List.filter_map (fun (name, ty) ->
        if not (List.mem_assoc name old_map) then Some (FieldAdded { name; ty })
        else None)
      new_map
  in
  let changed =
    List.filter_map (fun (name, old_ty) ->
        match List.assoc_opt name new_map with
        | Some new_ty when new_ty <> old_ty ->
          Some (FieldTypeChanged { name; old_ty; new_ty })
        | _ -> None)
      old_map
  in
  removed @ added @ changed

(** Check whether [changes] are compatible with [compat_policy].
    Returns Ok () or Error with a human-readable explanation. *)
let check_compat (compat : string) (changes : field_change list) : (unit, string) result =
  if changes = [] then Ok ()
  else match compat with
  | "any" -> Ok ()
  | "forward" ->
    (* forward: adding fields is ok, removing/changing is not *)
    let bad = List.filter (function
        | FieldAdded _ -> false
        | FieldRemoved _ | FieldTypeChanged _ -> true) changes in
    if bad = [] then Ok ()
    else
      let desc = List.map (function
          | FieldRemoved f -> Printf.sprintf "field removed: %s" f.name
          | FieldTypeChanged c -> Printf.sprintf "type changed: %s (%s → %s)" c.name c.old_ty c.new_ty
          | FieldAdded _ -> "") bad
      in
      Error (Printf.sprintf "@compat(forward) violated: %s" (String.concat ", " desc))
  | _ (* "full" default *) ->
    (* full: no structural changes allowed without explicit migrate_state *)
    let desc = List.map (function
        | FieldAdded f -> Printf.sprintf "field added: %s : %s" f.name f.ty
        | FieldRemoved f -> Printf.sprintf "field removed: %s" f.name
        | FieldTypeChanged c -> Printf.sprintf "type changed: %s (%s → %s)" c.name c.old_ty c.new_ty)
      changes
    in
    Error (Printf.sprintf "@compat(full) violated: %s — provide migrate_state or add @compat(any)"
             (String.concat ", " desc))

(** Compute diffs for all actors that appear in both old and new schemas. *)
let diff_schemas
    (old_schemas : (string * actor_schema) list)
    (new_schemas : (string * actor_schema) list) : actor_diff list =
  List.filter_map (fun (actor, new_s) ->
      match List.assoc_opt actor old_schemas with
      | None -> None  (* new actor — no old schema to diff against *)
      | Some old_s ->
        let changes = diff_actor old_s new_s in
        if changes = [] then None
        else Some { actor; changes }
    ) new_schemas

(** Returns true if changes require a migrate_state function to be present. *)
let requires_migration (changes : field_change list) : bool =
  List.exists (function
      | FieldAdded _ | FieldRemoved _ | FieldTypeChanged _ -> true) changes
```

- [ ] **Step 4: Add schema_diff to forge/lib/dune**

Open `forge/lib/dune` and find the `(library ...)` stanza. Add `schema_diff` to the `(modules ...)` list (or the equivalent). Example:

```
(library
 (name march_forge)
 (modules
  ...existing modules...
  schema_diff)
 ...)
```

- [ ] **Step 5: Build**

```bash
/Users/80197052/.opam/march/bin/dune build 2>&1 | head -20
echo "exit: $?"
```

Expected: exit 0.

- [ ] **Step 6: Verify schema file emitted**

```bash
./_build/default/bin/main.exe --hot-reload /tmp/test_hr --compile-so \
  -o /tmp/test_counter.so /tmp/migrate_test_actor.march 2>&1 | head -5
cat /tmp/test_counter.so.schemas.json 2>/dev/null || echo "not found"
```

Expected: a `.schemas.json` file with the Counter actor's state fields.

- [ ] **Step 7: Quick tests**

```bash
scripts/run-tests.sh -q 2>&1 | tail -5
echo "exit: $?"
```

- [ ] **Step 8: Commit**

```bash
git add bin/main.ml forge/lib/schema_diff.ml forge/lib/dune
git commit -m "feat(hcr5): emit .schemas.json alongside CAS artifacts; Schema_diff module"
```

---

### Task 8: @compat Annotation + Deploy-Time Schema Enforcement

**Files:**
- Modify: `lib/ast/ast.ml` (add `Compat` to attribute type)
- Modify: `lib/parser/parser.mly` (parse `@compat(...)`)
- Modify: `forge/lib/cmd_deploy_hot.ml` (load schemas, diff, enforce, add migrate_required)

**Interfaces:**
- Consumes: `Schema_diff` from Task 7; `actor_schema.compat` field
- Produces: Deploy aborts on compat violation unless `migrate_state` is present; `migrate_required` flag in ACTIVATE payload

- [ ] **Step 1: Add @compat to AST attributes**

In `lib/ast/ast.ml`, find the attribute/annotation type. Attributes in March are attached to declarations via `decl_attrs` or similar. Find how `@[attribute_name]` is currently represented and add a `compat` variant.

If there is an existing `attr` type like:
```ocaml
type attr = AttrDerive | AttrExtern | ...
```
Add:
```ocaml
  | AttrCompat of string  (* "full" | "forward" | "any" *)
```

If attributes are represented as `string * string option` pairs, no AST change is needed — the parser just stores `("compat", Some "full")`.

Look at how `@extern` or `@derive` is implemented in `ast.ml` to follow the existing pattern.

- [ ] **Step 2: Parse @compat(...) in parser.mly**

In `lib/parser/parser.mly`, find where `@attribute_name` or `@[...]` is parsed. Add a rule for `@compat(IDENT)` or `@compat(STRING)`. Follow the existing attribute parsing pattern.

For example, if attributes are currently:
```
attribute:
  | AT LIDENT { AttrSimple $2 }
  | AT LIDENT LPAREN ... RPAREN { ... }
```

Add:
```
  | AT "compat" LPAREN LIDENT RPAREN { AttrCompat $4 }
```

Adapt to the actual grammar token names used in this parser.

- [ ] **Step 3: Load .schemas.json in cmd_deploy_hot.ml**

In `forge/lib/cmd_deploy_hot.ml`, find the `run` function. After the VERSIONS and ABI_QUERY step (which gives us the CAS hash of the old build), add schema loading.

The old CAS hash is available from the VERSIONS response. The `.schemas.json` for the old build is at `<cas_dir>/<old_cas_hash>.schemas.json`. The new build's schema is at `<new_so_path>.schemas.json` (written by the compiler in Task 7).

```ocaml
    (* Phase 5: load old and new actor state schemas for compat checking *)
    let cas_dir = Filename.concat deploy_prefix ".march/cas/artifacts" in
    let old_schemas_path = Filename.concat cas_dir (old_cas_hash ^ ".schemas.json") in
    let new_schemas_path = new_so_path ^ ".schemas.json" in
    let old_schemas = March_forge.Schema_diff.parse_schemas_file old_schemas_path in
    let new_schemas = March_forge.Schema_diff.parse_schemas_file new_schemas_path in
    let actor_diffs = March_forge.Schema_diff.diff_schemas old_schemas new_schemas in
```

- [ ] **Step 4: Enforce compat and derive migrate_required in cmd_deploy_hot.ml**

Before sending each ACTIVATE command, check whether the function is an actor dispatch (`_dispatch` suffix) and if so, look up its diff:

```ocaml
    (* For each function to activate: *)
    List.iter (fun fm ->
      ...existing ACTIVATE logic...
      
      (* Phase 5: determine migrate_required for actor dispatch functions *)
      let migrate_required =
        if String.length fm.fn_name > 9 &&
           String.sub fm.fn_name (String.length fm.fn_name - 9) 9 = "_dispatch"
        then begin
          let actor_name = String.sub fm.fn_name 0 (String.length fm.fn_name - 9) in
          match List.find_opt (fun d -> d.March_forge.Schema_diff.actor = actor_name) actor_diffs with
          | None -> 0
          | Some diff ->
            (* Check compat policy for this actor *)
            let compat = match List.assoc_opt actor_name new_schemas with
              | Some s -> s.March_forge.Schema_diff.compat
              | None -> "full"
            in
            (match March_forge.Schema_diff.check_compat compat diff.changes with
            | Ok () ->
              (* Changes are compat-safe, but migration may still be needed
                 (e.g. adding a field with @compat(any)) *)
              if March_forge.Schema_diff.requires_migration diff.changes then 1 else 0
            | Error msg ->
              (* Check if migrate_state is available in the new .so *)
              let migrate_sym = "__migrate_" ^ String.map (fun c -> if c = '.' then '_' else c) actor_name in
              if so_exports_symbol new_so_path migrate_sym then 1
              else begin
                Printf.eprintf "forge deploy hot: aborting — %s\nProvide a migrate_state function or add @compat annotation.\n" msg;
                exit 1
              end)
        end
        else 0
      in
      
      (* Append migrate_required to ACTIVATE payload *)
      let activate_cmd = Printf.sprintf "ACTIVATE %s %s %s %s %d"
        fm.fn_name fm.fn_impl_hash cas_hash sig_b64 migrate_required
      in
      send_command activate_cmd
    ) functions_to_activate
```

Where `so_exports_symbol so_path sym` checks if `sym` is exported from the .so:
```ocaml
    let so_exports_symbol (so_path : string) (sym : string) : bool =
      let cmd = Printf.sprintf "nm -D %s 2>/dev/null | grep -q ' T %s$'" so_path sym in
      Sys.command cmd = 0
```

- [ ] **Step 5: Build**

```bash
/Users/80197052/.opam/march/bin/dune build 2>&1 | head -20
echo "exit: $?"
```

Expected: exit 0.

- [ ] **Step 6: Test compat enforcement**

Write a test March file where state type changes without migrate_state:

```bash
cat > /tmp/bad_migration.march << 'EOF'
mod BadActor do
  actor Counter do
    state = 0
    on Inc() -> state + 1
  end

  fn main() do
    ()
  end
end
EOF
```

Simulate a deploy where old state has `count: Int` and new state adds `label: String` without a migrate function. The deploy should abort with a compat error. (This is integration-level and can be tested manually with a live deploy session or via a forge unit test.)

- [ ] **Step 7: Quick tests**

```bash
scripts/run-tests.sh -q 2>&1 | tail -5
echo "exit: $?"
```

Expected: exit 0.

- [ ] **Step 8: Commit**

```bash
git add lib/ast/ast.ml lib/parser/parser.mly forge/lib/cmd_deploy_hot.ml
git commit -m "feat(hcr5): @compat annotation, deploy-time schema enforcement, migrate_required in ACTIVATE"
```

---

### Task 9: End-to-End Demo + Integration Tests

**Files:**
- Create: `demo/hcr_actor_demo/counter_v1.march`, `demo/hcr_actor_demo/counter_v2.march`, `demo/hcr_actor_demo/run_demo.sh`
- Modify: `specs/todos.md`, `specs/progress.md`

**Interfaces:**
- Consumes: Everything from Tasks 1–8
- Produces: End-to-end demo that spawns a Counter actor, sends 10 Inc messages, hot-reloads to v2 (adding history: List(Int) field), verifies the migrated state

- [ ] **Step 1: Write Counter v1**

```bash
mkdir -p demo/hcr_actor_demo
```

```march
-- demo/hcr_actor_demo/counter_v1.march
mod Counter do

  type CounterState = { count: Int }

  actor Counter do
    state = { count = 0 }
    on Inc() -> { count = state.count + 1 }
    on Get() -> state
  end

  fn main() do
    let pid = spawn(Counter)
    pid <- Inc()
    pid <- Inc()
    pid <- Inc()
    let result = Actor.call(pid, Get(), 5000)
    match result do
      Ok(s) -> println("v1 count = ${s.count}")
      Err(e) -> println("error: ${e}")
    end
  end

end
```

- [ ] **Step 2: Write Counter v2 with migrate_state**

```march
-- demo/hcr_actor_demo/counter_v2.march  
mod Counter do

  type CounterState_V1 = { count: Int }

  @compat(any)
  type CounterState = { count: Int, history: List(Int) }

  actor Counter do
    state = { count = 0, history = [] }
    on Inc() -> { count = state.count + 1, history = [state.count + 1] ++ state.history }
    on Get() -> state
  end

  fn migrate_state(old : CounterState_V1) : CounterState do
    { count = old.count, history = [] }
  end

  fn main() do
    let pid = spawn(Counter)
    pid <- Inc()
    let result = Actor.call(pid, Get(), 5000)
    match result do
      Ok(s) -> println("v2 count = ${s.count}, history = ${s.history}")
      Err(e) -> println("error: ${e}")
    end
  end

end
```

- [ ] **Step 3: Write run_demo.sh**

```bash
#!/usr/bin/env bash
set -e
REPO="$(cd "$(dirname "$0")/../.." && pwd)"
BUILD="$REPO/_build/default/bin/main.exe"
DEMO_DIR="$REPO/demo/hcr_actor_demo"
HR_PREFIX="/tmp/hcr_actor_demo_$$"
SOCKET="$HR_PREFIX.sock"
KEY_PUB="$HR_PREFIX.pub"

echo "=== Building v1 binary ==="
"$BUILD" --hot-reload "$HR_PREFIX" --signing-pubkey "$KEY_PUB" \
  -o "$HR_PREFIX.bin" "$DEMO_DIR/counter_v1.march"

echo "=== Starting v1 binary in background ==="
MARCH_HOT_RELOAD_SOCKET="$SOCKET" "$HR_PREFIX.bin" &
PID=$!
sleep 1

echo "=== Building v2 patch ==="
"$BUILD" --hot-reload "$HR_PREFIX" --signing-pubkey "$KEY_PUB" --compile-so \
  -o "$HR_PREFIX.v2.so" "$DEMO_DIR/counter_v2.march"

echo "=== Deploying v2 patch ==="
# Use forge deploy hot or the raw ACTIVATE protocol
# (Adapt this to use your actual deploy command)
# forge deploy hot --socket "$SOCKET" "$HR_PREFIX.v2.so"

echo "=== Waiting for migration ==="
sleep 1

echo "=== Done. Check output above for v2 count + history ==="
kill $PID 2>/dev/null || true
```

```bash
chmod +x demo/hcr_actor_demo/run_demo.sh
```

- [ ] **Step 4: Verify the full pipeline builds**

```bash
/Users/80197052/.opam/march/bin/dune build 2>&1 | head -20
echo "exit: $?"
```

- [ ] **Step 5: Run full test suite**

```bash
scripts/run-tests.sh 2>&1 | tail -20
echo "exit: $?"
```

Expected: exit 0. All tests (including Slow) pass.

- [ ] **Step 6: Update specs/todos.md**

Move the HCR Phase 5 item from the TODO section to the Done section:

```markdown
## Done
...
- [x] HCR Phase 5: Actor state migration (state indirection, MARCH_MIGRATE_TAG, migrate_state, Schema_diff, @compat)
```

- [ ] **Step 7: Update specs/progress.md**

Add to the feature list:
```
- HCR Phase 5: actor state migration — state indirection for --hot-reload actors, MARCH_MIGRATE_TAG system messages, migrate_state magic-name convention, __migrate_* symbol export, Schema_diff compat checking, @compat annotation, migrate_required ACTIVATE protocol extension
```

Update test counts if they changed.

- [ ] **Step 8: Commit everything**

```bash
git add demo/hcr_actor_demo/ specs/todos.md specs/progress.md
git commit -m "feat(hcr5): end-to-end actor migration demo; update specs"
```

---

## Self-Review Checklist

**Spec coverage:**
- [x] MARCH_MIGRATE_TAG + march_migrate_msg_t — Task 1
- [x] actor_green_thread migrate dispatch — Task 2
- [x] march_actor_broadcast_migrate — Task 3
- [x] ACTIVATE extension (migrate_required, dlsym __migrate_*) — Task 4
- [x] State indirection in lower_actor — Task 5
- [x] __migrate_* symbol export — Task 6
- [x] .schemas.json emission + Schema_diff — Task 7
- [x] @compat annotation + deploy enforcement — Task 8
- [x] migrate_required in ACTIVATE payload (forge side) — Task 8
- [x] End-to-end demo + full test run — Task 9
- [x] dispatch_name_id in march_actor_meta — Task 1
- [x] march_actor_set_dispatch_id + hot-reload spawn call — Tasks 2 + 6
- [x] Dispatch-table path in actor_green_thread — Task 2

**Gaps identified and addressed:**
- The `dispatch_name_id` approach replaces per-actor `handler_impl_hash`: simpler and doesn't require impl_hash tracking at spawn time.
- `state_ptr_var` must be declared before `inner_with_state_loads` to be in scope for `reuse_expr` — noted in Task 5 Step 5.
- `march_migrate_msg_t` uses `malloc`/`free` (not march heap) — Task 2 checks the tag BEFORE the `march_decrc` dead-actor path to avoid freeing with the wrong allocator.
- The dispatch table approach means `a[2]` (old closure) is passed as env to the new dispatch fn — safe because March actor dispatch fns ignore their env argument.

**Type consistency:**
- `Schema_diff.parse_schemas_file` → `(string * actor_schema) list` — used consistently in Tasks 7 and 8
- `Schema_diff.diff_schemas old new` → `actor_diff list` — Task 8 consumes this
- `Schema_diff.check_compat compat changes` → `(unit, string) result` — Task 8 uses this
- `MARCH_MIGRATE_TAG` defined in Task 1, used in Tasks 2 and 3
- `march_actor_broadcast_migrate(dispatch_name_id, migrate_fn)` — declared Task 1, implemented Task 3, called Task 4
