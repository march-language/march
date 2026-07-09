# Compiled Actor Supervision Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make March's `supervise do ... end` actor-supervision feature actually work when compiled — today `get_actor_field`/`pid_of_int` corrupt memory or hang, and a supervised child crash kills the whole OS process instead of triggering a restart. `examples/supervision_strategies.march` must compile and run with output matching the (already-correct) interpreter.

**Architecture:** Six tasks, each independently testable via a compiled native golden test. Tasks 1-3 fix the "static" half (pid encoding, field reads, spawn-time child injection) — after Task 3, a supervised actor tree can be built and inspected compiled, but a crash still kills the process. Tasks 4-5 add the "dynamic" half — a `setjmp`/`longjmp` crash trap isolates a supervised child's panic to its own green thread instead of exiting the process, and the three restart strategies (`one_for_one`, `one_for_all`, `rest_for_one`) are ported from `lib/eval/eval.ml` to C, matching its semantics (including `max_restarts`-within-`window_secs` throttling and epoch inheritance) line for line. Task 6 validates end-to-end against the example file and updates the docs that currently warn this path is broken. Task 2 (`get_actor_field`) has no dependency on Tasks 1/3-5 and can be done in any order relative to them.

**Tech Stack:** OCaml (compiler: `lib/tir/lower_actor.ml`, `lib/tir/llvm_builtins.ml`, `lib/tir/llvm_emit.ml`), C (runtime: `runtime/march_runtime.c`), March (test fixtures), dune (test wiring).

## Global Constraints

- Build with `dune build --root .` from inside the worktree; `dune`/`opam` are on PATH via `/Users/80197052/.opam/march/bin` — **never** run `eval $(opam env ...)` or any opam-env preamble.
- **Never** `git stash` in this repo (worktrees share one stash stack across concurrent sessions). Never `git add -A`/`.`/`-am` — stage files explicitly by name. Always create NEW commits; never `--amend`.
- **Never** pipe `march --compile` output through another command (e.g. `| tail`) — the compiler child holds the pipe open and the shell wedges. Redirect to a file, check `$?`, then read the file separately.
- Judge every `dune runtest` by its exit code (`$?`), not by scanning tail output — rule failures can hide above a green Alcotest summary line.
- A timed-out foreground `dune` invocation can orphan a lock-holding child process that wedges every subsequent build; if a build hangs, check `lsof _build/.lock` and `kill -9` the orphan PIDs before retrying.
- Run the full six-runner suite (`scripts/run-tests.sh`, no `-q`) + `check_types.sh` + `check-docs.sh` before this branch lands on `main` — Task 6 is the gate for that; do not skip the 24 `Slow`-marked stdlib tests before merging.
- No `Co-Authored-By` trailers in any commit.
- This touches actor-struct layout, RC/FBIP, and now a brand-new C-level crash/longjmp path — the single highest-risk category this project has: every prior touch to this exact area (actor structs, message dispatch, RC-encoding) has produced 2-3 rounds of genuine Critical findings under adversarial review. Task reviews for Tasks 2-5 must get an adversarial (opus-model) pass, not a routine one.
- Rhythm: implement -> adversarial review -> land, per task. Do not batch multiple tasks into one review.

---

## File Structure

- `runtime/march_runtime.c` — all new/changed C. Touches: `march_actor_meta` struct (new fields), `march_is_cap_valid` (dedupe its scan), new `find_meta_by_pid_index`, new dead-actor sentinel + `march_pid_of_int` rewrite (Task 1); new `march_sup_child` struct + `march_actor_register_child` + `march_pid_index_of` (Task 3); `march_kill` refactored into `do_actor_death` + crash-trap plumbing in `actor_green_thread` + `march_panic` + the three C restart functions (Tasks 4-5).
- `lib/tir/llvm_builtins.ml` — two new builtin-table entries (`register_supervisor_child`, `pid_index_of`) plus their `PDeclare` lines (Task 3).
- `lib/tir/lower_actor.ml` — spawn-time child-injection logic added to the existing `spawn_body_with_sup` / `spawn_with_fields` construction (Task 3).
- `lib/tir/llvm_emit.ml` — one new `EApp` match arm resolving `get_actor_field` at compile time via a runtime field-name compare chain (Task 2).
- `test/dune` — one new `(rule ...)` pair (compile+run+diff) per task's native golden.
- `test/native/*.march` + `*.expected` — new fixtures, one or more per task.
- `test/test_codegen.ml` — `golden_preamble_native_actor` string literal gets the two new `declare` lines appended in Task 3 (byte-identical preamble golden, W3C2.4/H2).
- `examples/supervision_strategies.march` — unchanged source, used as Task 6's end-to-end acceptance fixture (compile, run, diff against interpreter output).
- `specs/lang/golden/g35_actor_spawn_send.march`, `g37_actor_lifecycle.march` — stale "broken in compiled runtime" comments corrected (Task 6).
- `specs/todos.md`, `specs/progress.md` — bookkeeping (Task 6).

---

### Task 1: `pid_of_int` round-trip — pid_index reverse lookup + dead-actor sentinel

**Files:**
- Modify: `runtime/march_runtime.c:3269-3286` (`march_is_cap_valid`), `runtime/march_runtime.c:3324-3326` (`march_pid_of_int`)
- Create: `test/native/pid_of_int_roundtrip.march`, `test/native/pid_of_int_roundtrip.expected`
- Modify: `test/dune` (new rule pair)

**Interfaces:**
- Produces: `static march_actor_meta *find_meta_by_pid_index(int64_t pid_index)` — reused by Task 4/5's restart code to resolve a supervisor's Int-encoded child-pid field back to a `march_actor_meta*`.
- Produces: `march_dead_actor_sentinel` (static, file-scope in `march_runtime.c`) — a pre-built "already dead" actor struct. Any later code that needs a safe not-found return value for an actor-pointer-typed builtin can return `&march_dead_actor_sentinel`.

Today, `march_is_cap_valid` (runtime/march_runtime.c:3270-3286) inlines a linear scan over `g_actor_tbl` to find an actor by `pid_index`:

```c
int64_t march_is_cap_valid(int64_t pid_index, int64_t epoch) {
    if (revoc_contains(pid_index, epoch)) return 0;
    /* Look up actor by pid_index to check liveness and current epoch. */
    pthread_mutex_lock(&g_tbl_mu);
    march_actor_meta *m = NULL;
    for (int i = 0; i < MARCH_SCHED_BUCKETS; i++) {
        march_actor_meta *cur = g_actor_tbl[i];
        while (cur) {
            if (cur->pid_index == pid_index) { m = cur; break; }
            cur = cur->tbl_next;
        }
        if (m) break;
    }
    pthread_mutex_unlock(&g_tbl_mu);
    if (!m || !march_is_alive(m->actor)) return 0;
    if (m->epoch != epoch) return 0;
    return 1;
}
```

And `march_pid_of_int` (runtime/march_runtime.c:3324-3326) is a naive, unsafe pointer cast:

```c
void *march_pid_of_int(int64_t n) {
    return (void *)(intptr_t)n;
}
```

`n` is a *sequential spawn counter value* (`pid_index`), not a pointer — this reinterprets a small integer like `3` as address `0x3` and hands it straight to `march_send`/`march_kill`/`march_is_alive`, all of which dereference their `actor` argument's word 3 (`((int64_t*)actor)[3]`, the `$e_alive` flag) completely unconditionally, with no NULL or range check. This is the exact SIGSEGV/hang reported against `examples/supervision_strategies.march`.

- [ ] **Step 1: Extract the shared lookup helper and use it from `march_is_cap_valid`**

Add this new `static` function immediately above `march_is_cap_valid` (i.e. just before line 3270):

```c
/* Shared by march_is_cap_valid and march_pid_of_int: locate an actor's meta
 * entry by its sequential spawn index — the value a compiled Int field uses
 * to encode a Pid (see march_actor_register_child, Task 3). Returns NULL if
 * no actor was ever assigned this index. */
static march_actor_meta *find_meta_by_pid_index(int64_t pid_index) {
    pthread_mutex_lock(&g_tbl_mu);
    march_actor_meta *m = NULL;
    for (int i = 0; i < MARCH_SCHED_BUCKETS; i++) {
        march_actor_meta *cur = g_actor_tbl[i];
        while (cur) {
            if (cur->pid_index == pid_index) { m = cur; break; }
            cur = cur->tbl_next;
        }
        if (m) break;
    }
    pthread_mutex_unlock(&g_tbl_mu);
    return m;
}
```

Then replace `march_is_cap_valid`'s body with:

```c
int64_t march_is_cap_valid(int64_t pid_index, int64_t epoch) {
    if (revoc_contains(pid_index, epoch)) return 0;
    march_actor_meta *m = find_meta_by_pid_index(pid_index);
    if (!m || !march_is_alive(m->actor)) return 0;
    if (m->epoch != epoch) return 0;
    return 1;
}
```

- [ ] **Step 2: Add the dead-actor sentinel and rewrite `march_pid_of_int`**

Add this immediately above `march_pid_of_int` (replacing its current body):

```c
/* march_pid_of_int(n) is an escape hatch: March code that stores a child's
 * pid as a plain Int (e.g. a supervisor's Int-typed state field, see Task 3)
 * converts it back to a usable Pid via this call. When n does not name any
 * actor this process has spawned (a stale/garbage index), march_send /
 * march_kill / march_is_alive all read their `actor` argument's $e_alive
 * flag (word index 3) UNCONDITIONALLY with no NULL check — returning NULL
 * here would crash every one of them. Instead return a pointer to a static,
 * already-"dead" actor struct: same header/dispatch/alive word layout as a
 * real actor, with $e_alive already 0, so every caller's EXISTING
 * "actor already dead" early-return path (march_kill's `if (!fields[3])
 * return;`, march_send's `if (!a[3]) { ...none...; return; }`,
 * march_is_alive's plain read) handles it exactly like any other actor
 * that was already killed — no new code path, nothing to get wrong.
 * rc starts at a billion: no realistic amount of incrc/decrc traffic on a
 * Pid value approaches that within one process's lifetime, so this static
 * object is never freed. */
static struct { march_hdr hdr; int64_t dispatch; int64_t alive; }
    march_dead_actor_sentinel = { .hdr = { .rc = 1000000000, .tag = 0, .pad = 0 },
                                   .dispatch = 0, .alive = 0 };

void *march_pid_of_int(int64_t n) {
    march_actor_meta *m = find_meta_by_pid_index(n);
    if (m) return m->actor;
    return &march_dead_actor_sentinel;
}
```

- [ ] **Step 3: Build**

```bash
dune build --root . 2>&1 | tee /tmp/hopeful-kapitsa-9f49f3-t1-build.log
echo "exit: $?"
```

Expected: exit 0, no warnings from the new code.

- [ ] **Step 4: Write the failing native golden fixture**

Create `test/native/pid_of_int_roundtrip.march`:

```march
mod PidRoundtrip do

  actor Echo do
    state { n : Int }
    init  { n: 0 }

    on Bump() do
      { n: state.n + 1 }
    end
  end

  fn main() do
    let p = spawn(Echo)
    println(bool_to_string(is_alive(p)))

    let stale = pid_of_int(999999)
    println(bool_to_string(is_alive(stale)))

    kill(stale)
    println(bool_to_string(is_alive(stale)))
  end

end
```

Create `test/native/pid_of_int_roundtrip.expected`:

```
true
false
false
```

- [ ] **Step 5: Wire the dune rule**

Add to `test/dune` (deps list copied verbatim from the existing `native_actor_counter` rule so runtime-source coverage matches exactly):

```
(rule
 (targets native_pid_of_int_roundtrip native_pid_of_int_roundtrip.out)
 (deps (file %{exe:../bin/main.exe})
       (file ../runtime/march_runtime.c) (file ../runtime/march_runtime.h)
       (file ../runtime/march_scheduler.c) (file ../runtime/march_scheduler.h)
       (file ../runtime/march_heap.c) (file ../runtime/march_heap.h)
       (file ../runtime/march_gc.c) (file ../runtime/march_gc.h)
       (file ../runtime/march_message.c) (file ../runtime/march_message.h)
       (file ../runtime/march_deque.h)
       (file ../runtime/march_extras.c) (file ../runtime/march_compress.c)
       (file ../runtime/base64.c) (file ../runtime/sha1.c)
       (file native/pid_of_int_roundtrip.march))
 (action
  (progn
   (run %{exe:../bin/main.exe} --compile -o native_pid_of_int_roundtrip
        native/pid_of_int_roundtrip.march)
   (with-stdout-to native_pid_of_int_roundtrip.out
        (system "./native_pid_of_int_roundtrip")))))

(rule
 (alias runtest)
 (action (diff native/pid_of_int_roundtrip.expected native_pid_of_int_roundtrip.out)))
```

- [ ] **Step 6: Run it and confirm PASS**

```bash
dune build --root . test/native_pid_of_int_roundtrip 2>&1 | tail -30
./_build/default/test/native_pid_of_int_roundtrip
echo "exit: $?"
```

Expected: prints `true` / `false` / `false`, exit 0, no SIGSEGV (this exact call sequence previously hung/crashed).

Then confirm via dune's own diff rule:

```bash
scripts/run-tests.sh compiler 2>&1 | tail -40
echo "exit: $?"
```

Expected: exit 0.

- [ ] **Step 7: Commit**

```bash
git add runtime/march_runtime.c test/dune test/native/pid_of_int_roundtrip.march test/native/pid_of_int_roundtrip.expected
git commit -m "fix: march_pid_of_int returns a real actor pointer, not a raw int-to-ptr cast"
```

---

### Task 2: `get_actor_field` via the runtime shape registry

**Design note (post-implementation):** the plan originally called for resolving
`get_actor_field` entirely at COMPILE time (a runtime string-compare chain
driven by the actor's field table, gated on the pid argument's static type
being a concrete `Pid(SomeActorRecord)`). Implementing and testing that
design surfaced a real gap: the realistic call pattern —
`examples/supervision_strategies.march`'s `child_int(sup, field)` helper —
NEVER gives `sup` a concrete monomorphized type inside `child_int`'s body,
because nothing in `get_actor_field`'s own signature (`Pid(a) -> String ->
Option(b)`) structurally forces specialization on `a`. The compile-time
guard correctly detected this and fell back to the OLD always-None stub —
i.e. the fix silently didn't fire for the one case that matters. This
section documents the design that was ACTUALLY implemented instead, which
fixes the problem for both direct and indirected call sites uniformly.

**Files:**
- Modify: `lib/tir/llvm_emit.ml` (stamp a runtime shape id on actor structs at spawn time, in the `EAlloc` Boxed-alloc branch)
- Modify: `runtime/march_extras.c` (real `march_get_actor_field` implementation, added next to `march_record_field_dyn`)
- Modify: `runtime/march_runtime.c` (delete the old stub — the symbol now lives in `march_extras.c`; a duplicate definition would fail to link)
- Create: `test/native/get_actor_field_direct.march`, `.expected`
- Modify: `test/dune` (new rule pair)

**Interfaces:**
- Consumes: `get_record_fields` (`llvm_data.ml`), `emit_set_shape` (`llvm_data.ml`, aliased in `llvm_emit.ml`), `Tir_names.is_actor_struct_name` — all pre-existing, unmodified. Consumes the existing runtime shape registry (`rec_shape_of`, `rec_find_field`, `rec_field_raw`, `march_record_shape` — all `static` in `runtime/march_extras.c`, already used by `march_record_field_dyn`).
- Produces: nothing new for other tasks to consume. `march_get_actor_field`'s C signature (`void *march_get_actor_field(void *pid, void *name)`) and the March-level `get_actor_field` builtin declaration are unchanged — this task only changes the implementation behind the existing extern-call path.

The compiler already has a generic runtime reflection mechanism for exactly
this "type-erased generic flow" situation: ordinary `Tir.EField` access on
a record whose static shape isn't known falls back to
`march_record_field_dyn` (`lib/tir/llvm_emit.ml:2991-3005`), which looks up
a field BY NAME using a "shape id" — a runtime-interned integer, keyed off a
canonical `"name:kind;name:kind;..."` descriptor string, stamped into the
record's header pad word (`march_hdr.pad`, byte offset 12) via
`emit_set_shape`/`march_record_set_shape`. Crucially, the shape id is a
property of the RUNTIME OBJECT ITSELF (read from its own header), not of the
static type at whatever call site is inspecting it — so a lookup driven by
the object's own shape id works identically whether the caller's static
type is concrete or still an unresolved type variable.

Actor structs do NOT currently get a shape stamped (`lower_actor.ml`'s
`Name_spawn()` allocates via `EAlloc (Tir.TCon (actor_type_name, []), ...)`,
which — since an actor struct is neither a Newtype nor niche-shaped — falls
to the plain Boxed-alloc branch (`llvm_emit.ml:2473-2510`), and none of the
three existing `emit_set_shape` call sites (`EReuse`, `ERecord`, `EUpdate`)
cover `EAlloc`). This task adds that stamp, scoped to actor structs only,
and rewrites `march_get_actor_field` to do a PARTIAL shape-based lookup
(returning niche-`None` on a missing field, unlike `march_record_field_dyn`,
which panics — appropriate for `Tir.EField`'s total access but not for
`get_actor_field`'s explicitly partial `Option` return).

This applies to actors compiled in normal mode. In `--hot-reload` mode the
actor struct holds a single `$f_state` pointer to a SEPARATE state record
rather than inlining state fields — stamping the actor struct's own shape
would not expose those fields. Hot-reload is an orthogonal, unrelated
feature to supervision; this gap is not addressed here.

- [ ] **Step 1: Stamp a shape id on actor structs at allocation time**

In `lib/tir/llvm_emit.ml`, in the `EAlloc (Tir.TCon (ctor, alloc_params), args)`
match arm's Boxed-alloc branch (the `| _ ->` arm reached when the type is
neither Newtype nor niche-shaped), immediately after the field-store loop
and before the existing HCR dispatch-id wiring:

```ocaml
         let (v_ty, v_val) = emit_atom ctx atom in
         let v_coerced = coerce ctx v_ty v_val field_ty in
         emit_store_field ctx ptr i field_ty v_coerced
       ) args;
       (* Actor structs get a runtime shape id stamped into the header pad
          word so get_actor_field's C implementation (march_get_actor_field,
          runtime/march_extras.c) can look up a named state field by the
          actor's own shape at runtime, regardless of whether the caller's
          static Pid(a) type is concrete at that call site (it usually is
          NOT — a call routed through a small generic helper like
          child_int(sup, field) never resolves `a` past an abstract type
          variable, since nothing in get_actor_field's own signature forces
          monomorphization on it). Scoped to actor structs only via
          is_actor_struct_name — not a general shape-stamping change for
          every Boxed EAlloc/ctor-application site. *)
       if Tir_names.is_actor_struct_name alloc_type_name then
         emit_set_shape ctx ptr (get_record_fields ctx (Tir.TCon (alloc_type_name, [])));
       (* HCR: if this is a known actor type, wire the dispatch slot ID immediately
          after allocation so the actor green thread uses the hot-reload table.
          ... (existing code, unchanged) ... *)
```

`alloc_type_name` is already bound at the top of this match arm (used by
the existing `audit`/`Repr.repr_of_ty` calls a few lines above); `ctor`/
`ptr`/`args` are all already in scope. `Tir_names.is_actor_struct_name` is
the same guard the existing HCR wiring already uses two lines below.

- [ ] **Step 2: Replace `march_get_actor_field`'s C implementation**

In `runtime/march_runtime.c`, remove the stub entirely:

```c
/* get_actor_field: retrieve a named field from an actor's state. Stub: returns None. */
void *march_get_actor_field(void *pid, void *name) {
    (void)pid; (void)name;
    void *none = march_alloc(16);
    /* tag 0 = None, already zeroed by march_alloc */
    return none;
}
```

In `runtime/march_extras.c`, immediately after `march_record_field_dyn`
(which ends `return (void *)(intptr_t)raw; }`), add:

```c
/* get_actor_field(pid, field): a PARTIAL lookup, unlike march_record_field_dyn
 * above (a total EField read that panics on a missing name) — March code,
 * most often through a small generic helper (e.g. supervision_strategies
 * .march's child_int), reads a named actor state field without statically
 * knowing whether it exists, and expects Option(b): None if absent. Reuses
 * the SAME runtime shape registry march_record_field_dyn consults — a shape
 * id stamped into the actor struct header's pad word at spawn time (the
 * EAlloc actor-struct branch in llvm_emit.ml, guarded by
 * Tir_names.is_actor_struct_name) — so this works regardless of whether the
 * caller's static Pid(a) type is concrete or still an unresolved type
 * variable (the realistic case: nothing in get_actor_field's own signature
 * forces monomorphization on `a` through an indirecting helper function).
 * Returns a niche-tagged Option: NULL = None, (n<<1)|1 = Some(n) for an 'i'
 * (Int/Bool/Unit/Atom) field, the raw pointer verbatim for anything else —
 * matching march_record_field_dyn's found-value convention exactly. */
void *march_get_actor_field(void *pid, void *name) {
    march_string *ns = (march_string *)name;
    march_record_shape *s = rec_shape_of(pid);
    if (!s) return NULL;
    int32_t i = rec_find_field(s, ns->data, ns->len);
    if (i < 0) return NULL;
    int64_t raw = rec_field_raw(pid, i);
    if (s->kinds[i] == 'i') return (void *)(intptr_t)((raw << 1) | 1);
    return (void *)(intptr_t)raw;
}
```

`march_string` (`{ int64_t rc; int32_t tag; int32_t pad; int64_t len; char
data[]; }`, `runtime/march_runtime.h:11,105`) is the runtime representation
of the March `String` argument — `name` arrives as a `march_string*`, not a
raw C string, unlike `march_record_field_dyn`'s `(const char*, int64_t)`
pair (that function is called from a compile-time-known field-name literal
already split into pointer+length; `get_actor_field`'s `field` argument is
a full March value). `rec_shape_of`/`rec_find_field`/`rec_field_raw`/
`march_record_shape` are all `static` in `march_extras.c` — placing the new
function in the SAME file (rather than `march_runtime.c`, where the old
stub lived) is what makes them callable without exposing any new symbols.

- [ ] **Step 3: Build**

```bash
dune build --root . bin/main.exe > /tmp/hopeful-kapitsa-9f49f3-t2-build.log 2>&1
echo "exit: $?"
```

Expected: exit 0.

- [ ] **Step 4: Write the failing native golden fixture**

Create `test/native/get_actor_field_direct.march` — deliberately structured
with a `field_int` helper identical in shape to `child_int`, so this test
exercises the realistic indirected call pattern, not just a direct one:

```march
mod GetActorFieldDirect do

  actor Holder do
    state { wa : Int, wb : Int }
    init  { wa: 11, wb: 22 }

    on Noop() do
      state
    end
  end

  fn field_int(h, field) do
    match get_actor_field(h, field) do
    None    -> -1
    Some(n) -> n
    end
  end

  fn main() do
    let h = spawn(Holder)
    println(int_to_string(field_int(h, "wa")))
    println(int_to_string(field_int(h, "wb")))
    println(int_to_string(field_int(h, "nope")))
  end

end
```

Create `test/native/get_actor_field_direct.expected`:

```
11
22
-1
```

This fixture does NOT depend on Task 3 (it reads plain `Int` fields off a
normal, non-supervised actor's own `init` values) — it isolates Task 2's
fix from Task 3's spawn-injection, so it can run and pass independently of
task execution order. `test/native/supervisor_spawn_children.march` (Task
3, Step 11) additionally exercises this same code path against a
*supervised* actor's fields once Task 3 has also landed.

- [ ] **Step 5: Wire the dune rule** (same deps list as Task 1's rule)

```
(rule
 (targets native_get_actor_field_direct native_get_actor_field_direct.out)
 (deps (file %{exe:../bin/main.exe})
       (file ../runtime/march_runtime.c) (file ../runtime/march_runtime.h)
       (file ../runtime/march_scheduler.c) (file ../runtime/march_scheduler.h)
       (file ../runtime/march_heap.c) (file ../runtime/march_heap.h)
       (file ../runtime/march_gc.c) (file ../runtime/march_gc.h)
       (file ../runtime/march_message.c) (file ../runtime/march_message.h)
       (file ../runtime/march_deque.h)
       (file ../runtime/march_extras.c) (file ../runtime/march_compress.c)
       (file ../runtime/base64.c) (file ../runtime/sha1.c)
       (file native/get_actor_field_direct.march))
 (action
  (progn
   (run %{exe:../bin/main.exe} --compile -o native_get_actor_field_direct
        native/get_actor_field_direct.march)
   (with-stdout-to native_get_actor_field_direct.out
        (system "./native_get_actor_field_direct")))))

(rule
 (alias runtest)
 (action (diff native/get_actor_field_direct.expected native_get_actor_field_direct.out)))
```

- [ ] **Step 6: Run it and confirm PASS**

```bash
rm -rf .march/cas/artifacts/   # runtime C changed; clear the content-hash cache
dune build --root . test/native_get_actor_field_direct > /tmp/hopeful-kapitsa-9f49f3-t2-golden.log 2>&1
echo "exit: $?"
./_build/default/test/native_get_actor_field_direct
echo "exit: $?"
scripts/run-tests.sh -q 2>&1 | tail -20
echo "exit: $?"
```

Expected: prints `11` / `22` / `-1`, exit 0.

- [ ] **Step 7: Commit**

```bash
git add lib/tir/llvm_emit.ml runtime/march_runtime.c runtime/march_extras.c test/dune test/native/get_actor_field_direct.march test/native/get_actor_field_direct.expected
git commit -m "fix: get_actor_field resolves fields via the runtime shape registry"
```

---

### Task 3: Spawn-time child injection

**Files:**
- Modify: `runtime/march_runtime.c` (new `march_sup_child` struct + fields on `march_actor_meta`, new `march_actor_register_child`, new `march_pid_index_of`)
- Modify: `lib/tir/llvm_builtins.ml` (two new builtin-table entries + `PDeclare` lines, ~line 647-648 for placement precedent)
- Modify: `lib/tir/lower_actor.ml` (~lines 286-358, `spawn_with_fields` / `spawn_body_with_sup`)
- Modify: `test/test_codegen.ml` (`golden_preamble_native_actor`, ~line 7391, byte-identical preamble golden)
- Create: `test/native/supervisor_spawn_children.march`, `.expected`
- Modify: `test/dune` (new rule pair)

**Interfaces:**
- Consumes: `find_meta_by_pid_index` (Task 1).
- Produces: `void march_actor_register_child(void *supervisor, void *child, void *(*spawn_fn)(void), int64_t word_idx)` — called once per declared child, right after the supervisor's own struct is allocated. Task 4/5's restart code reads the `sup_children`/`sup_num_children` fields this populates.
- Produces: `int64_t march_pid_index_of(void *actor)` — exposed as the March builtin `pid_index_of`, used by the lowering below to get the Int value to store in a supervisor's state field.
- Produces new `march_actor_meta` fields: `void *supervisor`, `int sup_child_index`, `march_sup_child *sup_children`, `int sup_num_children` (all zero/NULL-initialized by `find_or_create_meta`'s existing calloc-style allocation — confirm this at Step 1, don't assume).

Today (`lib/tir/lower_actor.ml:272-365`), a supervisor's `Name_spawn()` only *registers* supervision metadata — it never spawns the declared children at all. The generated body (`spawn_body_with_sup`, lines 338-358) wraps the actor's own `EAlloc` with a call to `register_supervisor`, but `actor.actor_state`'s init values (e.g. `wa: 0, wb: 0` from `init { wa: 0, wb: 0 }`) flow straight through unchanged — so a supervisor's state fields are always the literal init values, never a real child's pid.

The existing (unconditional, for every actor) field-loading step, in `lower_actor.ml`:

```ocaml
  let init_field_vars : (string * Tir.var) list =
    List.map (fun (fname, fty) ->
        (fname, actor_var ("$init_" ^ fname) fty)
      ) state_fields_sorted
  in
  ...
  let spawn_with_fields =
    if hot_reload then
      spawn_inner
    else
      List.fold_right (fun (fname, ifv) acc ->
          Tir.ELet (ifv, Tir.EField (Tir.AVar init_var, fname), acc)
        ) init_field_vars spawn_inner
  in
```

`spawn(Worker)` itself already lowers (lib/tir/lower.ml:686-704) to:

```ocaml
    Tir.ELet (raw_var, Tir.EApp (spawn_fn, []),
              Tir.EApp (march_spawn, [Tir.AVar raw_var]))
```

i.e. `let $raw_actor = Worker_spawn() in spawn($raw_actor)` (the TIR builtin var literally named `"spawn"`, which `llvm_builtins.ml` maps to the C symbol `march_spawn`). This task reproduces that exact two-call shape for each declared child, INSIDE the supervisor's own spawn body, instead of loading the field from `init`.

Also existing (`lower_actor.ml:280-284`), the proven pattern for passing a top-level function NAME as a first-class pointer value (not calling it) — reused below for the child's spawn-fn pointer:

```ocaml
  let dispatch_fn_ptr_var : Tir.var = {
    v_name = name ^ Tir_names.actor_dispatch_suffix;
    v_ty   = Tir.TFn ([Tir.TPtr Tir.TUnit; Tir.TPtr Tir.TUnit], Tir.TUnit);
    v_lin  = Tir.Unr;
  } in
```

- [ ] **Step 1: Confirm `find_or_create_meta` zero-initializes new fields**

```bash
grep -n "find_or_create_meta" runtime/march_runtime.c | head -5
```

Read the function body at the printed line. It must allocate via `calloc` (or explicitly zero every field) — if it uses `malloc` and hand-sets only some fields, the new `supervisor`/`sup_children`/`sup_num_children` fields added in Step 2 need an explicit `= NULL` / `= 0` added to that function. Do not skip this check — an uninitialized `sup_children` pointer is a wild-pointer crash the very first time Task 4 reads it.

- [ ] **Step 2: Add the new meta fields and `march_sup_child` struct**

In `runtime/march_runtime.c`, immediately above the `march_actor_meta` typedef (~line 1146), add:

```c
/* One entry per child declared in a `supervise do ... end` block. Set once
 * at initial spawn time (march_actor_register_child) and read by every
 * restart (Task 4/5's C restart functions). */
typedef struct {
    void *(*spawn_fn)(void);  /* <ActorName>_spawn — called fresh on every restart */
    int64_t word_idx;         /* position among this supervisor's alphabetically-sorted
                                  state fields; this child's Int-encoded pid lives at
                                  ((int64_t*)supervisor)[4 + word_idx] */
} march_sup_child;
```

Then add these fields to `march_actor_meta` (inside the existing typedef, alongside the other "Supervision metadata" fields already there — `supervisor_strategy`/`supervisor_max_restarts`/`supervisor_window_secs`):

```c
    /* Set on a CHILD when it is spawned by a supervisor (Task 3); NULL for
     * every other actor, including a supervisor's own meta. */
    void                        *supervisor;
    int                          sup_child_index;
    /* Set on a SUPERVISOR (an actor that itself declares `supervise do ... end`);
     * NULL/0 for every other actor, including its own children. */
    march_sup_child             *sup_children;
    int                          sup_num_children;
```

- [ ] **Step 3: Add `march_actor_register_child` and `march_pid_index_of`**

Immediately after `march_register_supervisor` in `runtime/march_runtime.c`, add:

```c
/* Called once per declared supervise-block child, from the generated
 * Name_spawn() body, right after BOTH the child and the supervisor itself
 * have been spawned (march_spawn already ran on both). Links parent->child
 * (for Task 4's crash-trap to find "is this actor supervised, and by
 * whom") and records enough for a later restart: which function respawns
 * this child (spawn_fn), and which Int-typed state-field slot of the
 * supervisor holds its encoded pid (word_idx, see march_sup_child above). */
void march_actor_register_child(void *supervisor, void *child,
                                 void *(*spawn_fn)(void), int64_t word_idx) {
    march_actor_meta *sup_meta = find_or_create_meta(supervisor);
    march_actor_meta *child_meta = find_or_create_meta(child);
    child_meta->supervisor = supervisor;
    child_meta->sup_child_index = sup_meta->sup_num_children;
    int idx = sup_meta->sup_num_children;
    sup_meta->sup_children = realloc(sup_meta->sup_children,
                                      (size_t)(idx + 1) * sizeof(march_sup_child));
    sup_meta->sup_children[idx].spawn_fn = spawn_fn;
    sup_meta->sup_children[idx].word_idx = word_idx;
    sup_meta->sup_num_children = idx + 1;
}

/* pid_index_of: the Int a compiled supervisor stores in its own state field
 * to represent a just-spawned child's Pid (see march_pid_of_int, Task 1,
 * for the reverse direction). */
int64_t march_pid_index_of(void *actor) {
    return find_or_create_meta(actor)->pid_index;
}
```

- [ ] **Step 4: Register the two new builtins**

In `lib/tir/llvm_builtins.ml`, immediately after the existing `register_supervisor` entry (~line 647-648):

```ocaml
  { march_name = "register_supervisor_child"; c_name = Some "march_actor_register_child"; ret_ty = Some Tir.TUnit;
    in_is_builtin = true; declare_sig = Some "declare void @march_actor_register_child(ptr %sup, ptr %child, ptr %spawn_fn, i64 %word_idx)" };
  { march_name = "pid_index_of"; c_name = Some "march_pid_index_of"; ret_ty = Some Tir.TInt;
    in_is_builtin = true; declare_sig = Some "declare i64  @march_pid_index_of(ptr %actor)" };
```

And in the `PDeclare` list, immediately after `PDeclare "march_register_supervisor";` (~line 1215):

```ocaml
  PDeclare "march_actor_register_child";
  PDeclare "march_pid_index_of";
```

- [ ] **Step 5: Update the byte-identical preamble golden**

In `test/test_codegen.ml`, `golden_preamble_native_actor` (~line 7391), immediately after the `declare void @march_register_supervisor(...)` line, add:

```
declare void @march_actor_register_child(ptr %sup, ptr %child, ptr %spawn_fn, i64 %word_idx)
declare i64  @march_pid_index_of(ptr %actor)
```

Match the existing column alignment exactly: return-type keyword left-justified in a 5-character field before `@` (`void ` / `ptr  ` / `i64  `).

- [ ] **Step 6: Build**

```bash
dune build --root . 2>&1 | tee /tmp/hopeful-kapitsa-9f49f3-t3-build.log
echo "exit: $?"
```

Expected: exit 0.

- [ ] **Step 7: Run the preamble golden test to confirm it still passes**

```bash
dune build --root . test/run_codegen.exe && ./_build/default/test/run_codegen.exe -e -t llvm_builtins_preamble_golden 2>&1 | tail -40
echo "exit: $?"
```

Expected: exit 0 (confirms Step 5's edit matches Step 4's `PDeclare` additions exactly).

- [ ] **Step 8: Add spawn-time child injection to `lower_actor.ml`**

This is the core of the task. In `lower_actor.ml`, the state-field-loading fold (~lines 306-313) must branch per field: a field named in `actor.actor_supervise`'s `sc_fields` gets a spawn-child expression instead of an `EField` load on `init`. The spawned child's raw actor pointer must stay in scope past the supervisor's own `EAlloc`, because the registration call (in the existing `wrap_sup`, which already runs AFTER `$spawned`'s `EAlloc`) needs it.

Replace the existing unconditional block:

```ocaml
  let alloc_expr = Tir.EAlloc (Tir.TCon (actor_type_name, []), alloc_args) in
  let actor_result_var = actor_var "$spawned" (Tir.TPtr Tir.TUnit) in
  let spawn_inner =
    Tir.ELet (actor_result_var, alloc_expr, Tir.EAtom (Tir.AVar actor_result_var))
  in
  let spawn_with_fields =
    if hot_reload then
      spawn_inner
    else
      List.fold_right (fun (fname, ifv) acc ->
          Tir.ELet (ifv, Tir.EField (Tir.AVar init_var, fname), acc)
        ) init_field_vars spawn_inner
  in
```

with:

```ocaml
  let alloc_expr = Tir.EAlloc (Tir.TCon (actor_type_name, []), alloc_args) in
  let actor_result_var = actor_var "$spawned" (Tir.TPtr Tir.TUnit) in
  let spawn_inner =
    Tir.ELet (actor_result_var, alloc_expr, Tir.EAtom (Tir.AVar actor_result_var))
  in
  (* For a supervised field, spawn its declared child actor now (the
     supervisor struct doesn't exist yet — that's fine, spawning doesn't
     need it) and bind $init_<fname> to the child's pid_index Int instead
     of loading it from `init`. The child's raw pointer is also bound
     ($sup_child_ptr_<fname>) and stays in lexical scope all the way past
     the EAlloc below, for wrap_sup (Step 9) to register against $spawned. *)
  let supervised_child_name (fname : string) : string option =
    match actor.actor_supervise with
    | None -> None
    | Some sc ->
      List.find_opt (fun (sf : Ast.supervise_field) -> sf.Ast.sf_name.txt = fname) sc.Ast.sc_fields
      |> Option.map (fun sf -> match sf.Ast.sf_ty with
          | Ast.TyCon (n, []) -> n.txt
          | _ -> failwith ("supervise field " ^ fname ^ ": child type must be a bare actor name"))
  in
  let spawn_with_fields =
    if hot_reload then
      spawn_inner
    else
      List.fold_right (fun (fname, ifv) acc ->
          match supervised_child_name fname with
          | None -> Tir.ELet (ifv, Tir.EField (Tir.AVar init_var, fname), acc)
          | Some child_actor_name ->
            let child_spawn_var : Tir.var = {
              v_name = child_actor_name ^ Tir_names.actor_spawn_suffix;
              v_ty   = Tir.TFn ([], Tir.TPtr Tir.TUnit);
              v_lin  = Tir.Unr;
            } in
            let march_spawn_var : Tir.var = { v_name = "spawn"; v_ty = Tir.TPtr Tir.TUnit; v_lin = Tir.Unr } in
            let pid_index_of_var : Tir.var = { v_name = "pid_index_of"; v_ty = Tir.TInt; v_lin = Tir.Unr } in
            let raw_var = actor_var ("$sup_child_raw_" ^ fname) (Tir.TPtr Tir.TUnit) in
            let child_ptr_var = actor_var ("$sup_child_ptr_" ^ fname) (Tir.TPtr Tir.TUnit) in
            Tir.ELet (raw_var, Tir.EApp (child_spawn_var, []),
              Tir.ELet (child_ptr_var, Tir.EApp (march_spawn_var, [Tir.AVar raw_var]),
                Tir.ELet (ifv, Tir.EApp (pid_index_of_var, [Tir.AVar child_ptr_var]),
                  acc)))
        ) init_field_vars spawn_inner
  in
```

- [ ] **Step 9: Register each spawned child against the supervisor, right after `mk_reg_sup_call`**

In the existing `Some sc ->` branch of `spawn_body_with_sup` (~lines 341-357), `wrap_sup` currently only inserts `mk_reg_sup_call`. Extend it to also insert one `register_supervisor_child` call per supervised field, using the `$sup_child_ptr_<fname>` variables Step 8 bound (still in lexical scope at this point in the tree — they were bound as outer lets around the whole `spawn_with_fields` structure, including the `$spawned` `EAlloc` `wrap_sup` inserts after).

Replace:

```ocaml
    | Some sc ->
      (* Replace the final EAtom($spawned) with:
           let $reg_sup_result = register_supervisor($spawned, strat, max, window) in
           EAtom($spawned)
         We thread the $spawned var through by wrapping the full body. *)
      let rec wrap_sup (e : Tir.expr) : Tir.expr =
        match e with
        | Tir.ELet (v, Tir.EAlloc (ty, args), rest) when v.Tir.v_name = "$spawned" ->
          (* After allocating, call march_spawn, then register_supervisor, then return *)
          Tir.ELet (v, Tir.EAlloc (ty, args),
            Tir.ELet ({ v_name = "$sup_reg"; v_ty = Tir.TUnit; v_lin = Tir.Unr },
              mk_reg_sup_call (Tir.AVar v) sc,
              rest))
        | Tir.ELet (v, rhs, body) -> Tir.ELet (v, rhs, wrap_sup body)
        | other -> other
      in
      Tir.ELet (init_var, Lower_match.lower_expr env actor.actor_init, wrap_sup spawn_with_fields)
```

with:

```ocaml
    | Some sc ->
      let field_word_idx (fname : string) : int =
        let rec find i = function
          | [] -> failwith ("supervise field " ^ fname ^ " not found in actor state")
          | (n, _) :: _ when n = fname -> i
          | _ :: rest -> find (i + 1) rest
        in find 0 state_fields_sorted
      in
      let mk_reg_child_calls (sup_atom : Tir.atom) (rest : Tir.expr) : Tir.expr =
        List.fold_right (fun (sf : Ast.supervise_field) acc ->
            let fname = sf.Ast.sf_name.txt in
            let child_actor_name = match sf.Ast.sf_ty with
              | Ast.TyCon (n, []) -> n.txt
              | _ -> failwith ("supervise field " ^ fname ^ ": child type must be a bare actor name")
            in
            let child_ptr_var = actor_var ("$sup_child_ptr_" ^ fname) (Tir.TPtr Tir.TUnit) in
            let child_spawn_fn_var : Tir.var = {
              v_name = child_actor_name ^ Tir_names.actor_spawn_suffix;
              v_ty   = Tir.TFn ([], Tir.TPtr Tir.TUnit);
              v_lin  = Tir.Unr;
            } in
            let reg_child_var : Tir.var = {
              v_name = "register_supervisor_child";
              v_ty   = Tir.TFn ([Tir.TPtr Tir.TUnit; Tir.TPtr Tir.TUnit; Tir.TPtr Tir.TUnit; Tir.TInt], Tir.TUnit);
              v_lin  = Tir.Unr;
            } in
            Tir.ELet ({ v_name = "$reg_child_" ^ fname; v_ty = Tir.TUnit; v_lin = Tir.Unr },
              Tir.EApp (reg_child_var, [
                sup_atom; Tir.AVar child_ptr_var; Tir.AVar child_spawn_fn_var;
                Tir.ALit (Ast.LitInt (field_word_idx fname));
              ]),
              acc)
          ) sc.Ast.sc_fields rest
      in
      let rec wrap_sup (e : Tir.expr) : Tir.expr =
        match e with
        | Tir.ELet (v, Tir.EAlloc (ty, args), rest) when v.Tir.v_name = "$spawned" ->
          Tir.ELet (v, Tir.EAlloc (ty, args),
            Tir.ELet ({ v_name = "$sup_reg"; v_ty = Tir.TUnit; v_lin = Tir.Unr },
              mk_reg_sup_call (Tir.AVar v) sc,
              mk_reg_child_calls (Tir.AVar v) rest))
        | Tir.ELet (v, rhs, body) -> Tir.ELet (v, rhs, wrap_sup body)
        | other -> other
      in
      Tir.ELet (init_var, Lower_match.lower_expr env actor.actor_init, wrap_sup spawn_with_fields)
```

- [ ] **Step 10: Build**

```bash
dune build --root . 2>&1 | tee /tmp/hopeful-kapitsa-9f49f3-t3b-build.log
echo "exit: $?"
```

Expected: exit 0. If `state_fields_sorted`, `actor_var`, `init_field_vars`, or `Tir_names.actor_spawn_suffix` are not in scope at the point Step 9's code is inserted, move `field_word_idx`/`mk_reg_child_calls` to sit alongside `mk_reg_sup_call`'s existing definition (same scope, defined once, both closed over the same outer `let`s) rather than duplicating them.

- [ ] **Step 11: Write the failing native golden fixture**

Create `test/native/supervisor_spawn_children.march`:

```march
mod SupervisorSpawnChildren do

  actor Worker do
    state { count : Int }
    init  { count: 0 }

    on Work() do
      { count: state.count + 1 }
    end
  end

  actor Sup do
    state { wa : Int, wb : Int }
    init  { wa: 0, wb: 0 }

    supervise do
      strategy one_for_one
      max_restarts 5 within 60
      Worker wa
      Worker wb
    end
  end

  fn child_int(sup, field) do
    match get_actor_field(sup, field) do
    None    -> -1
    Some(n) -> n
    end
  end

  fn main() do
    let sup = spawn(Sup)
    let wa = child_int(sup, "wa")
    let wb = child_int(sup, "wb")
    println(bool_to_string(wa >= 0))
    println(bool_to_string(wb >= 0))
    println(bool_to_string(wa != wb))
    println(bool_to_string(is_alive(pid_of_int(wa))))
    println(bool_to_string(is_alive(pid_of_int(wb))))
    send(pid_of_int(wa), Work())
    run_until_idle()
    println("ok")
  end

end
```

Create `test/native/supervisor_spawn_children.expected`:

```
true
true
true
true
true
ok
```

Note: this fixture calls `get_actor_field` — it depends on Task 2 landing first. If Task 2 has not yet landed when this task is executed, skip Steps 11-13 and re-open them as part of Task 2 instead (Task 2's own acceptance test can be exactly this fixture). Do not write a version of this test that avoids `get_actor_field` — the whole point of this task is unobservable without it, and a same-shaped assertion via a different (untested) path would hide integration bugs between Tasks 2 and 3.

- [ ] **Step 12: Wire the dune rule** (same deps list as Task 1's rule, `native/supervisor_spawn_children.march` substituted)

```
(rule
 (targets native_supervisor_spawn_children native_supervisor_spawn_children.out)
 (deps (file %{exe:../bin/main.exe})
       (file ../runtime/march_runtime.c) (file ../runtime/march_runtime.h)
       (file ../runtime/march_scheduler.c) (file ../runtime/march_scheduler.h)
       (file ../runtime/march_heap.c) (file ../runtime/march_heap.h)
       (file ../runtime/march_gc.c) (file ../runtime/march_gc.h)
       (file ../runtime/march_message.c) (file ../runtime/march_message.h)
       (file ../runtime/march_deque.h)
       (file ../runtime/march_extras.c) (file ../runtime/march_compress.c)
       (file ../runtime/base64.c) (file ../runtime/sha1.c)
       (file native/supervisor_spawn_children.march))
 (action
  (progn
   (run %{exe:../bin/main.exe} --compile -o native_supervisor_spawn_children
        native/supervisor_spawn_children.march)
   (with-stdout-to native_supervisor_spawn_children.out
        (system "./native_supervisor_spawn_children")))))

(rule
 (alias runtest)
 (action (diff native/supervisor_spawn_children.expected native_supervisor_spawn_children.out)))
```

- [ ] **Step 13: Run it and confirm PASS**

```bash
dune build --root . test/native_supervisor_spawn_children 2>&1 | tail -40
./_build/default/test/native_supervisor_spawn_children
echo "exit: $?"
scripts/run-tests.sh compiler 2>&1 | tail -40
echo "exit: $?"
```

Expected: matches `.expected`, exit 0.

- [ ] **Step 14: Commit**

```bash
git add runtime/march_runtime.c lib/tir/llvm_builtins.ml lib/tir/lower_actor.ml test/test_codegen.ml test/dune test/native/supervisor_spawn_children.march test/native/supervisor_spawn_children.expected
git commit -m "feat: compiled supervisors spawn their declared children at spawn time"
```

---

### Task 4: Crash isolation + `one_for_one` restart

**Files:**
- Modify: `runtime/march_runtime.c` (`march_kill` refactor, `actor_green_thread`, `march_panic`, new restart-budget helper, new `march_respawn_child`, new `march_one_for_one_restart`, new `march_supervisor_notify` dispatcher)
- Create: `test/native/supervisor_one_for_one_restart.march`, `.expected`
- Modify: `test/dune`

**Interfaces:**
- Consumes: `find_meta_by_pid_index` (Task 1), `march_sup_child`/`sup_children`/`sup_num_children`/`supervisor`/`sup_child_index` (Task 3).
- Produces: `static void do_actor_death(void *actor)` — the ONE place that marks an actor dead, runs its cleanup/monitor-notify, and (new) notifies its supervisor if it has one. `march_kill` becomes a thin wrapper around it; Task 5's `one_for_all`/`rest_for_one` also call it directly on siblings.
- Produces: `static void *march_respawn_child(void *supervisor, march_actor_meta *sup_meta, int child_idx)` — spawns a fresh replacement for `sup_children[child_idx]`, re-links it, writes its pid_index into the supervisor's state field. Task 5 reuses this unchanged.
- Produces: `static int march_restart_budget_ok(march_actor_meta *sup_meta)` — max_restarts/window throttle check + history update. Task 5 reuses this unchanged.

Today, `march_panic` (runtime/march_runtime.c, full body below) has exactly two behaviors: in test mode, `longjmp` back to the Alcotest runner; otherwise, print and `exit(1)` — unconditionally killing the whole OS process, even for a panic inside one supervised actor's message handler:

```c
void march_panic(void *s) {
    march_string *ms = (march_string *)s;
    if (march_test_in_test) {
        march_frame_reset();
        int len = (int)ms->len < (int)sizeof(march_test_fail_buf) - 1
                  ? (int)ms->len : (int)sizeof(march_test_fail_buf) - 1;
        memcpy(march_test_fail_buf, ms->data, (size_t)len);
        march_test_fail_buf[len] = '\0';
        longjmp(march_test_jmp_buf, 1);
    }
    fprintf(stderr, "panic: ");
    fwrite(ms->data, 1, (size_t)ms->len, stderr);
    fputc('\n', stderr);
    march_print_backtrace();
    fflush(stderr);
    exit(1);
}
```

The interpreter has no such gap: `kill(pid)` and an actual runtime panic are the SAME code path (`lib/eval/eval.ml:3004-3006`, `kill(pid) = crash_actor pid "killed"`), and `crash_actor` (`lib/eval/eval.ml:1809-1860`) always marks the actor dead, runs cleanup, notifies monitors/links, and — only at the very end, only if the actor had a supervisor — calls `notify_supervisor`. This task brings the compiled runtime to the same shape, but scoped conservatively: **only** actors spawned as a declared supervise-block child (i.e. `meta->supervisor != NULL`) get crash-isolated; every other actor keeps today's `exit(1)`-on-panic behavior unchanged. (Extending isolation to ALL actors, supervised or not, is a strictly bigger runtime-semantics change than "make supervision work" and is out of scope here — flag it as a follow-up if wanted, don't fold it in.)

`march_kill` today (runtime/march_runtime.c:1373-1415ish) does the mark-dead/cleanup/monitor-notify sequence but has NO supervisor-notify step at all:

```c
void march_kill(void *actor) {
    int64_t *fields = (int64_t *)actor;
    if (!fields[3]) return;   /* Already dead */
    march_actor_meta *meta = find_meta(actor);
    if (meta && meta->cleanup_head) { /* ...cleanup callbacks... */ }
    if (meta && meta->monitor_head) { /* ...Down notifications... */ }
    if (meta) { march_dist_monitor_fire_pid(meta->pid_index, MARCH_DIST_REASON_NORMAL, NULL); }
    fields[3] = 0;   /* $alive flag at byte offset 24 */
    if (meta && meta->green_thread) { march_sched_wake(meta->green_thread); }
}
```

`actor_green_thread` (runtime/march_runtime.c:1287-1362+) is the dispatch loop; the two calls that actually run user handler code are:

```c
        if (meta->dispatch_name_id) {
            ...
            dispatch_fn(actor, msg);
        } else {
            typedef void (*closure_fn_t)(void *, void *, void *);
            char *closure = (char *)(uintptr_t)a[2];
            closure_fn_t fn = *(closure_fn_t *)(closure + 16);
            fn((void *)(uintptr_t)a[2], actor, msg);
        }
```

and after the loop exits (killed, or woken with no message):

```c
    pthread_mutex_lock(&g_tbl_mu);
    meta->green_thread = NULL;
    pthread_mutex_unlock(&g_tbl_mu);
}
```

— this final cleanup (preventing later `march_kill`/`march_send` use-after-free on a proc about to be freed by the scheduler) must ALSO run on the crash-longjmp path, not be skipped by it.

- [ ] **Step 1: Refactor `march_kill` into `do_actor_death` + a thin wrapper, no behavior change yet**

Replace `march_kill`'s body with:

```c
/* Mark `actor` dead, run its cleanup callbacks and monitor Down-notifications,
 * wake its green thread — and, new in this task, notify its supervisor (if
 * it has one) for a possible restart. The ONE place that does this, called
 * both by an explicit kill() and (Step 4 below) by a panic inside a
 * supervised actor's handler — mirrors the interpreter's kill = crash_actor
 * unification (eval.ml:3004-3006). */
static void do_actor_death(void *actor) {
    int64_t *fields = (int64_t *)actor;
    if (!fields[3]) return;   /* Already dead */

    march_actor_meta *meta = find_meta(actor);
    if (meta && meta->cleanup_head) {
        march_cleanup_node *node = meta->cleanup_head;
        while (node) {
            march_cleanup_node *next = node->next;
            void *clo = node->cleanup_fn;
            if (clo && IS_HEAP_PTR(clo)) {
                typedef void *(*clo_fn_t)(void *, void *);
                void **clo_fields = (void **)((char *)clo + 16);
                clo_fn_t fn_ptr = (clo_fn_t)(*(clo_fields));
                if (fn_ptr) {
                    void *unit_arg = march_alloc(16);
                    fn_ptr(clo, unit_arg);
                    march_decrc(unit_arg);
                }
            }
            free(node);
            node = next;
        }
        meta->cleanup_head = NULL;
    }

    if (meta && meta->monitor_head) {
        march_monitor_node *mn = meta->monitor_head;
        while (mn) {
            march_monitor_node *next_mn = mn->next;
            march_actor_meta *watcher_meta = find_meta(mn->watcher);
            if (watcher_meta) {
                atomic_fetch_add_explicit(&watcher_meta->down_count, 1,
                                          memory_order_relaxed);
            }
            free(mn);
            mn = next_mn;
        }
        meta->monitor_head = NULL;
    }

    if (meta) {
        march_dist_monitor_fire_pid(meta->pid_index, MARCH_DIST_REASON_NORMAL, NULL);
    }

    fields[3] = 0;   /* $alive flag at byte offset 24 */

    if (meta && meta->green_thread) {
        march_sched_wake(meta->green_thread);
    }

    if (meta && meta->supervisor) {
        march_supervisor_notify(meta->supervisor, meta);
    }
}

void march_kill(void *actor) {
    do_actor_death(actor);
}
```

`march_supervisor_notify` doesn't exist yet — Step 3 adds it. Forward-declare it above `do_actor_death` for now:

```c
static void march_supervisor_notify(void *supervisor, march_actor_meta *crashed_meta);
```

- [ ] **Step 2: Build and re-run Task 1/3's goldens to confirm no regression**

```bash
dune build --root . 2>&1 | tee /tmp/hopeful-kapitsa-9f49f3-t4a-build.log
echo "exit: $?"
scripts/run-tests.sh compiler 2>&1 | tail -60
echo "exit: $?"
```

Expected: exit 0 on both; `pid_of_int_roundtrip` and `supervisor_spawn_children` still pass (they exercise `kill`, which just changed shape).

- [ ] **Step 3: Add the restart-budget helper, `march_respawn_child`, `one_for_one`, and the dispatcher**

Add these `static` functions, in this order, immediately before `do_actor_death` (so the forward declaration from Step 1 can be deleted once `march_supervisor_notify` has a real body below it):

```c
/* Returns 1 (and appends `now` to sup_meta's restart history) if a restart
 * is currently permitted under its max_restarts-within-window budget;
 * returns 0 (budget exceeded — caller must crash the supervisor itself)
 * otherwise. Mirrors the identical window-check inlined in all three of
 * eval.ml's one_for_one_restart / one_for_all_restart / rest_for_one_restart
 * (eval.ml:1616-1627 and its two near-duplicates). */
static int march_restart_budget_ok(march_actor_meta *sup_meta) {
    struct timeval tv;
    gettimeofday(&tv, NULL);
    double now = (double)tv.tv_sec + (double)tv.tv_usec / 1e6;
    double window = (double)sup_meta->supervisor_window_secs;
    int kept = 0;
    for (int i = 0; i < sup_meta->sup_restart_len; i++) {
        if (now - sup_meta->sup_restart_ts[i] < window) {
            sup_meta->sup_restart_ts[kept++] = sup_meta->sup_restart_ts[i];
        }
    }
    sup_meta->sup_restart_len = kept;
    if (kept >= sup_meta->supervisor_max_restarts) return 0;
    sup_meta->sup_restart_ts = realloc(sup_meta->sup_restart_ts,
                                        (size_t)(kept + 1) * sizeof(double));
    sup_meta->sup_restart_ts[kept] = now;
    sup_meta->sup_restart_len = kept + 1;
    return 1;
}

/* Spawn a fresh replacement for sup_children[child_idx], link it to the
 * supervisor in that SAME slot (never appends — march_actor_register_child,
 * Task 3, is only for a child's initial spawn), inherit the crashed child's
 * epoch+1 (matching eval.ml spawn_child_actor's stale-capability-detection
 * inheritance), and write the new pid_index into the supervisor's state. */
static void *march_respawn_child(void *supervisor, march_actor_meta *sup_meta, int child_idx) {
    march_sup_child *child = &sup_meta->sup_children[child_idx];
    int64_t old_pid_index = ((int64_t *)supervisor)[4 + child->word_idx];
    march_actor_meta *old_meta = find_meta_by_pid_index(old_pid_index);
    int64_t inherited_epoch = old_meta ? old_meta->epoch + 1 : 0;

    void *raw = child->spawn_fn();
    void *new_child = march_spawn(raw);
    march_actor_meta *new_meta = find_or_create_meta(new_child);
    new_meta->supervisor = supervisor;
    new_meta->sup_child_index = child_idx;
    new_meta->epoch = inherited_epoch;
    ((int64_t *)supervisor)[4 + child->word_idx] = new_meta->pid_index;
    return new_child;
}

/* one_for_one: only the crashed child is respawned; siblings untouched.
 * Mirrors eval.ml:1588-1637. */
static void march_one_for_one_restart(void *supervisor, march_actor_meta *sup_meta, int child_idx) {
    if (child_idx < 0 || child_idx >= sup_meta->sup_num_children) return;
    if (!march_restart_budget_ok(sup_meta)) {
        do_actor_death(supervisor);
        return;
    }
    march_respawn_child(supervisor, sup_meta, child_idx);
}

static void march_supervisor_notify(void *supervisor, march_actor_meta *crashed_meta) {
    march_actor_meta *sup_meta = find_meta(supervisor);
    if (!sup_meta) return;
    int child_idx = crashed_meta->sup_child_index;
    switch (sup_meta->supervisor_strategy) {
        case 0: march_one_for_one_restart(supervisor, sup_meta, child_idx); break;
        /* case 1 (one_for_all) and case 2 (rest_for_one): Task 5. */
        default: break;
    }
}
```

Remove the forward declaration from Step 1 (no longer needed — `march_supervisor_notify` is now defined above `do_actor_death`'s call site, since it comes textually AFTER these new functions but BEFORE `do_actor_death` in this ordering... check: `do_actor_death` calls `march_supervisor_notify`, so `march_supervisor_notify` must be declared or defined ABOVE `do_actor_death` in the file. Place the four new functions above (before) `do_actor_death`, keep `do_actor_death`/`march_kill` immediately after them, as one contiguous block replacing the old `march_kill`.

Also add `#include <sys/time.h>` near the top of `runtime/march_runtime.c` if `gettimeofday` isn't already available transitively (check first — line ~3802 already calls `gettimeofday`, so the header is very likely already included; only add it if the build in Step 5 fails on an implicit-declaration warning/error for `gettimeofday`).

- [ ] **Step 4: Add the crash trap to `actor_green_thread` and wire `march_panic`**

Add a new thread-local pointer, near the existing `_Thread_local int g_in_scheduler = 0;` (runtime/march_runtime.c:1179):

```c
static _Thread_local jmp_buf *g_current_actor_crash_jmp = NULL;
```

Change `actor_green_thread`'s signature area and its final cleanup so a setjmp wraps the whole dispatch loop, restoring exactly the same tail cleanup on either exit path:

```c
static void actor_green_thread(void *arg) {
    march_actor_meta *meta = (march_actor_meta *)arg;
    void *actor = meta->actor;
    int64_t *a = (int64_t *)actor;

    jmp_buf crash_jmp;
    jmp_buf *saved_jmp = g_current_actor_crash_jmp;
    if (meta->supervisor) {
        /* Only a supervised child gets crash-isolated — an unsupervised
         * actor's panic keeps today's exit(1) behavior (see march_panic). */
        g_current_actor_crash_jmp = &crash_jmp;
    }
    if (meta->supervisor && setjmp(crash_jmp) != 0) {
        /* march_panic longjmp'd here instead of exit(1)-ing the process.
         * do_actor_death mirrors what march_kill would have done, and (since
         * this actor has a supervisor) triggers a restart — kill/crash-notify
         * parity with eval.ml:3004-3006. */
        g_current_actor_crash_jmp = saved_jmp;
        do_actor_death(actor);
        pthread_mutex_lock(&g_tbl_mu);
        meta->green_thread = NULL;
        pthread_mutex_unlock(&g_tbl_mu);
        return;
    }

    while (a[3]) {  /* while alive */
        ... (existing loop body, UNCHANGED) ...
    }

    g_current_actor_crash_jmp = saved_jmp;
    pthread_mutex_lock(&g_tbl_mu);
    meta->green_thread = NULL;
    pthread_mutex_unlock(&g_tbl_mu);
}
```

Note the existing final cleanup block (`meta->green_thread = NULL` under `g_tbl_mu`) stays exactly where it is; this step only adds the `jmp_buf`/`g_current_actor_crash_jmp` save-restore around it, and duplicates that SAME cleanup on the crash-recovery path so both exits leave identical state.

Now wire `march_panic` to use it — insert a new branch between the existing test-mode check and the production `exit(1)` fallback:

```c
void march_panic(void *s) {
    march_string *ms = (march_string *)s;
    if (march_test_in_test) {
        march_frame_reset();
        int len = (int)ms->len < (int)sizeof(march_test_fail_buf) - 1
                  ? (int)ms->len : (int)sizeof(march_test_fail_buf) - 1;
        memcpy(march_test_fail_buf, ms->data, (size_t)len);
        march_test_fail_buf[len] = '\0';
        longjmp(march_test_jmp_buf, 1);
    }
    if (g_current_actor_crash_jmp) {
        longjmp(*g_current_actor_crash_jmp, 1);
    }
    fprintf(stderr, "panic: ");
    fwrite(ms->data, 1, (size_t)ms->len, stderr);
    fputc('\n', stderr);
    march_print_backtrace();
    fflush(stderr);
    exit(1);
}
```

- [ ] **Step 5: Build**

```bash
dune build --root . 2>&1 | tee /tmp/hopeful-kapitsa-9f49f3-t4b-build.log
echo "exit: $?"
```

Expected: exit 0. If `jmp_buf` / `setjmp` / `longjmp` aren't already visible in this translation unit, add `#include <setjmp.h>` near the top (check first: `march_test_jmp_buf` is `extern jmp_buf` in `march_runtime.h:345`, which this file already includes, so the header is almost certainly already pulled in transitively).

- [ ] **Step 6: Re-run Task 1/3's goldens to confirm no regression**

```bash
scripts/run-tests.sh compiler 2>&1 | tail -60
echo "exit: $?"
```

Expected: exit 0.

- [ ] **Step 7: Write the failing native golden fixture**

Create `test/native/supervisor_one_for_one_restart.march`:

```march
mod SupervisorOneForOneRestart do

  actor Worker do
    state { count : Int }
    init  { count: 0 }

    on Work() do
      { count: state.count + 1 }
    end
  end

  actor Sup do
    state { wa : Int, wb : Int }
    init  { wa: 0, wb: 0 }

    supervise do
      strategy one_for_one
      max_restarts 5 within 60
      Worker wa
      Worker wb
    end
  end

  fn child_int(sup, field) do
    match get_actor_field(sup, field) do
    None    -> -1
    Some(n) -> n
    end
  end

  fn main() do
    let sup = spawn(Sup)
    let wa1 = child_int(sup, "wa")
    let wb1 = child_int(sup, "wb")

    kill(pid_of_int(wa1))

    let wa2 = child_int(sup, "wa")
    let wb2 = child_int(sup, "wb")

    println(bool_to_string(wa2 != wa1))
    println(bool_to_string(wb2 == wb1))
    println(bool_to_string(is_alive(pid_of_int(wa2))))
    println(bool_to_string(is_alive(pid_of_int(wb2))))
  end

end
```

Create `test/native/supervisor_one_for_one_restart.expected`:

```
true
true
true
true
```

This is the load-bearing test for this task: before Step 1-4's changes, `kill(pid_of_int(wa1))` on a supervised child does nothing (no restart), so `wa2 == wa1` and this test would FAIL against the pre-Task-4 runtime — confirming the fixture actually exercises the new code path (this is also, not incidentally, the FIRST scenario from `examples/supervision_strategies.march`'s `demo_one_for_one`).

- [ ] **Step 8: Wire the dune rule** (same deps as Task 1's rule)

```
(rule
 (targets native_supervisor_one_for_one_restart native_supervisor_one_for_one_restart.out)
 (deps (file %{exe:../bin/main.exe})
       (file ../runtime/march_runtime.c) (file ../runtime/march_runtime.h)
       (file ../runtime/march_scheduler.c) (file ../runtime/march_scheduler.h)
       (file ../runtime/march_heap.c) (file ../runtime/march_heap.h)
       (file ../runtime/march_gc.c) (file ../runtime/march_gc.h)
       (file ../runtime/march_message.c) (file ../runtime/march_message.h)
       (file ../runtime/march_deque.h)
       (file ../runtime/march_extras.c) (file ../runtime/march_compress.c)
       (file ../runtime/base64.c) (file ../runtime/sha1.c)
       (file native/supervisor_one_for_one_restart.march))
 (action
  (progn
   (run %{exe:../bin/main.exe} --compile -o native_supervisor_one_for_one_restart
        native/supervisor_one_for_one_restart.march)
   (with-stdout-to native_supervisor_one_for_one_restart.out
        (system "./native_supervisor_one_for_one_restart")))))

(rule
 (alias runtest)
 (action (diff native/supervisor_one_for_one_restart.expected native_supervisor_one_for_one_restart.out)))
```

- [ ] **Step 9: Run it and confirm PASS**

```bash
dune build --root . test/native_supervisor_one_for_one_restart 2>&1 | tail -60
./_build/default/test/native_supervisor_one_for_one_restart
echo "exit: $?"
scripts/run-tests.sh compiler 2>&1 | tail -60
echo "exit: $?"
```

Expected: matches `.expected`, exit 0. Also run this binary a second and third time in a loop (`for i in 1 2 3; do ./_build/default/test/native_supervisor_one_for_one_restart; done`) to catch any nondeterminism from the green-thread scheduling around the crash/restart race — a hang or a differing result on any iteration is a real bug, not flake, given this scenario.

- [ ] **Step 10: Commit**

```bash
git add runtime/march_runtime.c test/dune test/native/supervisor_one_for_one_restart.march test/native/supervisor_one_for_one_restart.expected
git commit -m "feat: compiled supervised-actor crash isolation + one_for_one restart"
```

---

### Task 5: `one_for_all` + `rest_for_one` restart strategies

**Files:**
- Modify: `runtime/march_runtime.c` (`march_one_for_all_restart`, `march_rest_for_one_restart`, extend `march_supervisor_notify`'s switch)
- Create: `test/native/supervisor_one_for_all_restart.march`, `.expected`, `test/native/supervisor_rest_for_one_restart.march`, `.expected`
- Modify: `test/dune`

**Interfaces:**
- Consumes: `march_restart_budget_ok`, `march_respawn_child`, `do_actor_death`, `find_meta_by_pid_index` (all Task 4/1).

Both strategies share a "snapshot every affected sibling's actor pointer and detach it from the supervisor BEFORE crashing any of them" step — detaching first prevents `do_actor_death`'s new supervisor-notify call from re-entering `march_supervisor_notify` once per sibling while this function is still in the middle of handling the original crash (mirrors eval.ml's `one_for_all_restart`/`rest_for_one_restart`, both of which set `ci.ai_supervisor <- None` before calling `crash_actor cpid ...` on each sibling — eval.ml:1662-1668 and :1731-1736).

- [ ] **Step 1: Add `march_one_for_all_restart` and `march_rest_for_one_restart`**

Add these two functions immediately after `march_one_for_one_restart` (before `march_supervisor_notify`):

```c
/* one_for_all: every child is killed and respawned when any one crashes.
 * Mirrors eval.ml:1640-1687. child_idx (which one originally crashed) is
 * unused here — ALL children are affected identically. */
static void march_one_for_all_restart(void *supervisor, march_actor_meta *sup_meta, int child_idx) {
    (void)child_idx;
    if (!march_restart_budget_ok(sup_meta)) {
        do_actor_death(supervisor);
        return;
    }
    int n = sup_meta->sup_num_children;
    void *live_children[n];
    for (int i = 0; i < n; i++) {
        live_children[i] = NULL;
        int64_t stored_pid_index = ((int64_t *)supervisor)[4 + sup_meta->sup_children[i].word_idx];
        march_actor_meta *cm = find_meta_by_pid_index(stored_pid_index);
        /* The originally-crashed child is already dead at this point (Task 4's
         * do_actor_death ran on it before calling march_supervisor_notify) —
         * march_is_alive is false for it, so it's correctly skipped here and
         * only respawned (not double-killed) in the loop below. */
        if (cm && march_is_alive(cm->actor)) {
            live_children[i] = cm->actor;
            cm->supervisor = NULL;
        }
    }
    for (int i = 0; i < n; i++) {
        if (live_children[i]) do_actor_death(live_children[i]);
    }
    for (int i = 0; i < n; i++) {
        march_respawn_child(supervisor, sup_meta, i);
    }
}

/* rest_for_one: the crashed child and every child declared AFTER it (in
 * sup_children array order, which matches sc_order — Task 3's field
 * injection walks sc.sc_fields in declaration order) are killed and
 * respawned; earlier siblings are untouched. Mirrors eval.ml:1691-1761. */
static void march_rest_for_one_restart(void *supervisor, march_actor_meta *sup_meta, int child_idx) {
    if (child_idx < 0 || child_idx >= sup_meta->sup_num_children) return;
    if (!march_restart_budget_ok(sup_meta)) {
        do_actor_death(supervisor);
        return;
    }
    int n = sup_meta->sup_num_children;
    void *live_children[n];
    for (int i = 0; i < n; i++) live_children[i] = NULL;
    for (int i = child_idx + 1; i < n; i++) {
        int64_t stored_pid_index = ((int64_t *)supervisor)[4 + sup_meta->sup_children[i].word_idx];
        march_actor_meta *cm = find_meta_by_pid_index(stored_pid_index);
        if (cm && march_is_alive(cm->actor)) {
            live_children[i] = cm->actor;
            cm->supervisor = NULL;
        }
    }
    for (int i = child_idx + 1; i < n; i++) {
        if (live_children[i]) do_actor_death(live_children[i]);
    }
    for (int i = child_idx; i < n; i++) {
        march_respawn_child(supervisor, sup_meta, i);
    }
}
```

- [ ] **Step 2: Wire both into `march_supervisor_notify`'s switch**

Replace:

```c
    switch (sup_meta->supervisor_strategy) {
        case 0: march_one_for_one_restart(supervisor, sup_meta, child_idx); break;
        /* case 1 (one_for_all) and case 2 (rest_for_one): Task 5. */
        default: break;
    }
```

with:

```c
    switch (sup_meta->supervisor_strategy) {
        case 0: march_one_for_one_restart(supervisor, sup_meta, child_idx); break;
        case 1: march_one_for_all_restart(supervisor, sup_meta, child_idx); break;
        case 2: march_rest_for_one_restart(supervisor, sup_meta, child_idx); break;
        default: break;
    }
```

- [ ] **Step 3: Build**

```bash
dune build --root . 2>&1 | tee /tmp/hopeful-kapitsa-9f49f3-t5-build.log
echo "exit: $?"
```

Expected: exit 0. A `void *live_children[n]` VLA with `n == 0` is technically zero-length; if the compiler warns/errors on this, guard with `int n = sup_meta->sup_num_children; if (n == 0) return;` at the top of each function instead of chasing a VLA-specific workaround — a supervisor with zero declared children can't happen from `lower_actor.ml`'s Task 3 output but the C code shouldn't assume that.

- [ ] **Step 4: Write the failing native golden fixtures**

Create `test/native/supervisor_one_for_all_restart.march`:

```march
mod SupervisorOneForAllRestart do

  actor Worker do
    state { count : Int }
    init  { count: 0 }

    on Work() do
      { count: state.count + 1 }
    end
  end

  actor Sup do
    state { wa : Int, wb : Int }
    init  { wa: 0, wb: 0 }

    supervise do
      strategy one_for_all
      max_restarts 5 within 60
      Worker wa
      Worker wb
    end
  end

  fn child_int(sup, field) do
    match get_actor_field(sup, field) do
    None    -> -1
    Some(n) -> n
    end
  end

  fn main() do
    let sup = spawn(Sup)
    let wa1 = child_int(sup, "wa")
    let wb1 = child_int(sup, "wb")

    kill(pid_of_int(wa1))

    let wa2 = child_int(sup, "wa")
    let wb2 = child_int(sup, "wb")

    println(bool_to_string(wa2 != wa1))
    println(bool_to_string(wb2 != wb1))
    println(bool_to_string(is_alive(pid_of_int(wa2))))
    println(bool_to_string(is_alive(pid_of_int(wb2))))
  end

end
```

`test/native/supervisor_one_for_all_restart.expected`:

```
true
true
true
true
```

Create `test/native/supervisor_rest_for_one_restart.march`:

```march
mod SupervisorRestForOneRestart do

  actor Worker do
    state { count : Int }
    init  { count: 0 }

    on Work() do
      { count: state.count + 1 }
    end
  end

  actor Sup do
    state { reader : Int, parser : Int, writer : Int }
    init  { reader: 0, parser: 0, writer: 0 }

    supervise do
      strategy rest_for_one
      max_restarts 5 within 60
      Worker reader
      Worker parser
      Worker writer
    end
  end

  fn child_int(sup, field) do
    match get_actor_field(sup, field) do
    None    -> -1
    Some(n) -> n
    end
  end

  fn main() do
    let sup = spawn(Sup)
    let r1 = child_int(sup, "reader")
    let p1 = child_int(sup, "parser")
    let w1 = child_int(sup, "writer")

    kill(pid_of_int(p1))

    let r2 = child_int(sup, "reader")
    let p2 = child_int(sup, "parser")
    let w2 = child_int(sup, "writer")

    println(bool_to_string(r2 == r1))
    println(bool_to_string(p2 != p1))
    println(bool_to_string(w2 != w1))
    println(bool_to_string(is_alive(pid_of_int(r2))))
    println(bool_to_string(is_alive(pid_of_int(p2))))
    println(bool_to_string(is_alive(pid_of_int(w2))))
  end

end
```

`test/native/supervisor_rest_for_one_restart.expected`:

```
true
true
true
true
true
true
```

- [ ] **Step 5: Wire the dune rules** (same deps list as Task 1's rule, substitute filenames for both fixtures)

```
(rule
 (targets native_supervisor_one_for_all_restart native_supervisor_one_for_all_restart.out)
 (deps (file %{exe:../bin/main.exe})
       (file ../runtime/march_runtime.c) (file ../runtime/march_runtime.h)
       (file ../runtime/march_scheduler.c) (file ../runtime/march_scheduler.h)
       (file ../runtime/march_heap.c) (file ../runtime/march_heap.h)
       (file ../runtime/march_gc.c) (file ../runtime/march_gc.h)
       (file ../runtime/march_message.c) (file ../runtime/march_message.h)
       (file ../runtime/march_deque.h)
       (file ../runtime/march_extras.c) (file ../runtime/march_compress.c)
       (file ../runtime/base64.c) (file ../runtime/sha1.c)
       (file native/supervisor_one_for_all_restart.march))
 (action
  (progn
   (run %{exe:../bin/main.exe} --compile -o native_supervisor_one_for_all_restart
        native/supervisor_one_for_all_restart.march)
   (with-stdout-to native_supervisor_one_for_all_restart.out
        (system "./native_supervisor_one_for_all_restart")))))

(rule
 (alias runtest)
 (action (diff native/supervisor_one_for_all_restart.expected native_supervisor_one_for_all_restart.out)))

(rule
 (targets native_supervisor_rest_for_one_restart native_supervisor_rest_for_one_restart.out)
 (deps (file %{exe:../bin/main.exe})
       (file ../runtime/march_runtime.c) (file ../runtime/march_runtime.h)
       (file ../runtime/march_scheduler.c) (file ../runtime/march_scheduler.h)
       (file ../runtime/march_heap.c) (file ../runtime/march_heap.h)
       (file ../runtime/march_gc.c) (file ../runtime/march_gc.h)
       (file ../runtime/march_message.c) (file ../runtime/march_message.h)
       (file ../runtime/march_deque.h)
       (file ../runtime/march_extras.c) (file ../runtime/march_compress.c)
       (file ../runtime/base64.c) (file ../runtime/sha1.c)
       (file native/supervisor_rest_for_one_restart.march))
 (action
  (progn
   (run %{exe:../bin/main.exe} --compile -o native_supervisor_rest_for_one_restart
        native/supervisor_rest_for_one_restart.march)
   (with-stdout-to native_supervisor_rest_for_one_restart.out
        (system "./native_supervisor_rest_for_one_restart")))))

(rule
 (alias runtest)
 (action (diff native/supervisor_rest_for_one_restart.expected native_supervisor_rest_for_one_restart.out)))
```

- [ ] **Step 6: Run both and confirm PASS**

```bash
dune build --root . test/native_supervisor_one_for_all_restart test/native_supervisor_rest_for_one_restart 2>&1 | tail -60
./_build/default/test/native_supervisor_one_for_all_restart
echo "exit: $?"
./_build/default/test/native_supervisor_rest_for_one_restart
echo "exit: $?"
scripts/run-tests.sh compiler 2>&1 | tail -60
echo "exit: $?"
```

Expected: both match their `.expected`, exit 0.

- [ ] **Step 7: Commit**

```bash
git add runtime/march_runtime.c test/dune test/native/supervisor_one_for_all_restart.march test/native/supervisor_one_for_all_restart.expected test/native/supervisor_rest_for_one_restart.march test/native/supervisor_rest_for_one_restart.expected
git commit -m "feat: compiled one_for_all and rest_for_one supervisor restart strategies"
```

---

### Task 6: End-to-end validation + docs bookkeeping

**Files:**
- No source changes — this task validates Tasks 1-5 against the ORIGINAL motivating example and corrects stale documentation.
- Modify: `specs/lang/golden/g35_actor_spawn_send.march:9`, `specs/lang/golden/g37_actor_lifecycle.march:7` (stale "broken"/"SIGSEGV" comments)
- Modify: `specs/todos.md`, `specs/progress.md`

- [ ] **Step 1: Compile and run the original motivating example**

```bash
dune exec march -- --compile -o /tmp/hopeful-kapitsa-9f49f3-supervision_strategies examples/supervision_strategies.march > /tmp/hopeful-kapitsa-9f49f3-compile.log 2>&1
echo "compile exit: $?"
/tmp/hopeful-kapitsa-9f49f3-supervision_strategies > /tmp/hopeful-kapitsa-9f49f3-compiled.out 2>&1
echo "run exit: $?"
cat /tmp/hopeful-kapitsa-9f49f3-compiled.out
```

Expected: exit 0 on both compile and run — this exact program is the one that used to hang/crash with garbage pid output (`wa=2343576600 wb=2343576624`, then a hang). It must now run to completion and print the full `=== Supervision Strategies Demo ===` ... `=== Done ===` output.

- [ ] **Step 2: Diff compiled output against interpreter output**

```bash
dune exec march -- examples/supervision_strategies.march > /tmp/hopeful-kapitsa-9f49f3-interp.out 2>&1
echo "interp exit: $?"
diff /tmp/hopeful-kapitsa-9f49f3-interp.out /tmp/hopeful-kapitsa-9f49f3-compiled.out
echo "diff exit: $?"
```

Expected: `diff exit: 0` — byte-identical output between interpreted and compiled runs. If they differ ONLY in pid numbers (e.g. `wa=3` vs `wa=7`) — the two runtimes' pid-assignment counters aren't required to line up 1:1 (the interpreter's `next_pid` and the compiled runtime's `g_next_pid_index` are independent counters with no shared numbering contract) — inspect the diff by hand and confirm every non-pid-number line (the `wa restarted with new pid: true`-style boolean assertions, `alive: true`, etc.) matches; if so this is an acceptable pass, not a bug. Do not silently accept a diff that changes any `true`/`false` assertion line.

- [ ] **Step 3: Add `examples/supervision_strategies.march` as a permanent native golden**

If Steps 1-2 pass, wire this file into `test/dune` exactly like Tasks 1/3/4/5's fixtures (same runtime deps list), with the `.expected` file being the `/tmp/hopeful-kapitsa-9f49f3-compiled.out` captured in Step 1 (after removing the `/tmp` scratch prefix from any paths it happens to contain — it shouldn't contain any, but check). This guards the exact bug this whole plan fixes against regression.

```
(rule
 (targets native_supervision_strategies native_supervision_strategies.out)
 (deps (file %{exe:../bin/main.exe})
       (file ../runtime/march_runtime.c) (file ../runtime/march_runtime.h)
       (file ../runtime/march_scheduler.c) (file ../runtime/march_scheduler.h)
       (file ../runtime/march_heap.c) (file ../runtime/march_heap.h)
       (file ../runtime/march_gc.c) (file ../runtime/march_gc.h)
       (file ../runtime/march_message.c) (file ../runtime/march_message.h)
       (file ../runtime/march_deque.h)
       (file ../runtime/march_extras.c) (file ../runtime/march_compress.c)
       (file ../runtime/base64.c) (file ../runtime/sha1.c)
       (file ../examples/supervision_strategies.march))
 (action
  (progn
   (run %{exe:../bin/main.exe} --compile -o native_supervision_strategies
        ../examples/supervision_strategies.march)
   (with-stdout-to native_supervision_strategies.out
        (system "./native_supervision_strategies")))))

(rule
 (alias runtest)
 (action (diff native/supervision_strategies.expected native_supervision_strategies.out)))
```

Save the captured output as `test/native/supervision_strategies.expected`.

- [ ] **Step 4: Run the FULL six-runner suite, `check_types.sh`, and `check-docs.sh`**

```bash
scripts/run-tests.sh 2>&1 | tee /tmp/hopeful-kapitsa-9f49f3-full-suite.log
echo "exit: $?"
./check_types.sh 2>&1 | tail -40
echo "exit: $?"
scripts/check-docs.sh 2>&1 | tail -40
echo "exit: $?"
```

Expected: exit 0 on all three. This is the pre-merge gate per this project's CLAUDE.md — do not skip the 24 `Slow`-marked stdlib tests here (no `-q`).

- [ ] **Step 5: Correct the stale "broken in compiled runtime" golden comments**

```bash
grep -n "broken\|SIGSEGV" specs/lang/golden/g35_actor_spawn_send.march specs/lang/golden/g37_actor_lifecycle.march
```

Read each flagged line in context and update the comment to reflect that `get_actor_field`/`pid_of_int` now work compiled (reference this plan's date/commit range rather than re-describing the fix in detail). If either golden file was deliberately avoiding these builtins ONLY because of the bug, and exercising them would now make the golden a better regression check, that's a judgment call for whoever executes this step — don't rewrite the golden's actual test content without confirming its existing assertions still hold under this task's own build.

- [ ] **Step 6: Update `specs/todos.md` and `specs/progress.md`**

In `specs/todos.md`: move the `get_actor_field`/`pid_of_int` compiled-crash finding (line ~243) and the "compiled supervisor doesn't run children's init" finding (line ~245) from wherever they currently live to the "Done" section, each annotated with this plan's task numbers (e.g. "Fixed: Tasks 1-5, specs/plans/2026-07-08-compiled-actor-supervision-plan.md").

In `specs/progress.md`: update the "Current State" test count (add the 7 new native goldens: `pid_of_int_roundtrip`, `supervisor_spawn_children`, `supervisor_one_for_one_restart`, `supervisor_one_for_all_restart`, `supervisor_rest_for_one_restart`, `supervision_strategies`, plus Task 2's own fixture) and add a bullet under the actors/supervision feature area noting compiled actor supervision (spawn, field-read, and all three restart strategies) is now implemented, not interpreter-only.

- [ ] **Step 7: Commit**

```bash
git add test/dune test/native/supervision_strategies.expected specs/lang/golden/g35_actor_spawn_send.march specs/lang/golden/g37_actor_lifecycle.march specs/todos.md specs/progress.md
git commit -m "docs: close out compiled actor supervision — golden + bookkeeping"
```

---

## Self-Review

**Spec coverage:**
- Pid encoding + reverse lookup (Task A from the original survey) → Task 1. ✓
- `get_actor_field` compile-time resolution (Task C) → Task 2. ✓
- Spawn-time child injection (Task B) → Task 3. ✓
- `pid_of_int` fix (Task D) → folded into Task 1 (same lookup table, same round-trip test). ✓
- Crash-detection + auto-restart (Task E: setjmp trap, `march_panic` conditional longjmp, kill/panic unification, C child table, three restart strategies with max_restarts/window/epoch semantics) → Tasks 4-5. ✓
- End-to-end validation against `examples/supervision_strategies.march` + goldens g35/g37 + specs bookkeeping → Task 6. ✓

**Placeholder scan:** every task has complete, non-placeholder code, exact file/line targets, and exact expected test output. No task uses "add appropriate error handling," "similar to Task N," or an unshown code block for a step that changes code. Task 2's design was filled in after a targeted investigation of `llvm_emit.ml`'s existing type-directed-codegen precedent (the `to_string`/`EField`/`EReuse`-phi-merge patterns it now cites by exact line number).

**Type/signature consistency:**
- `find_meta_by_pid_index` (Task 1) — signature `static march_actor_meta *find_meta_by_pid_index(int64_t pid_index)` used identically in Task 4/5's `march_respawn_child`/`one_for_all`/`rest_for_one`.
- `march_actor_register_child(void *supervisor, void *child, void *(*spawn_fn)(void), int64_t word_idx)` (Task 3) matches its `llvm_builtins.ml` `declare_sig` and its `test_codegen.ml` golden line exactly.
- `march_sup_child { spawn_fn; word_idx }` (Task 3) is the ONLY struct Task 4/5 index into (`sup_children[i].spawn_fn`, `sup_children[i].word_idx`) — no renamed fields between tasks.
- `do_actor_death(void *actor)` (Task 4) is called identically from `march_kill`, `actor_green_thread`'s crash-recovery branch, and Task 5's sibling-kill loops.
- `march_restart_budget_ok` / `march_respawn_child` (Task 4) are reused verbatim (not reimplemented) by Task 5 — confirmed by Task 5 Step 1 explicitly saying "immediately after `march_one_for_one_restart`" rather than redefining either helper.
- Task 2's `word_idx`-to-absolute-field-index relationship (`get_record_fields`-index = `word_idx + 2`) is derived from, and consistent with, Task 3's `field_word_idx` helper (0-based count of state fields only) and Task 4's `((int64_t*)supervisor)[4 + word_idx]` — all three rest on the same fact (`$d_dispatch`/`$e_alive` always sort first, `lib/tir/tir_names.ml:335-345`) rather than restating it independently.
- Task 2's fixture (`get_actor_field_direct.march`) intentionally does NOT depend on Task 3, so it can be implemented/tested in any order relative to Task 3; Task 3's own fixture (`supervisor_spawn_children.march`) is the integration point that exercises both together, and its Step 11 says so explicitly.

No open items remain — every task is fully specified and ready to dispatch.

## Execution Handoff

Two execution options:

**1. Subagent-Driven (recommended)** — fresh subagent per task, review between tasks, fast iteration. Given this touches actor-struct layout, RC, and new crash-safety C code (this session's highest-risk category, with a track record of real Critical findings on every prior touch), each of Tasks 2, 3, 4, and 5 should get an adversarial (opus-model) task review, not a routine one — flag this explicitly in each of those four dispatch prompts. Task ordering: 1 and 2 have no dependency on each other and can be dispatched in either order (or even in parallel, since they touch disjoint files); 3 depends on 1; 4 depends on 1 and 3; 5 depends on 4; 6 depends on all of 1-5.

**2. Inline Execution** — execute tasks in this session using `executing-plans`, batch execution with checkpoints for review.
