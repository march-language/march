# `[P3]` `pid_to_int` (and the supervise glue's `pid_index_of`) leaks a reference to its Pid

**Status: FIXED 2026-09-24.** Filed as
`specs/todos/2026-09-23-pid-to-int-leaks-its-pid.md`; the original report follows the
resolution below.

## Resolution

### Cause (two layers)

1. **Classification.** `lib/tir/borrow.ml` kept the rest of the read-only pid family in
   `extern_owned_builtins`, which the 2026-09-14 audit that moved `send`/`kill`/… to
   `extern_borrow_table` did not reach: `pid_to_int`, `pid_index_of`, `actor_get_int`,
   `actor_set_mailbox_limit`, `register_supervisor`, `register_supervisor_child`. Perceus
   passed each an owned reference that the C side never releases.
2. **The supervise glue never reached the table.** `register_supervisor` and
   `register_supervisor_child` (emitted by `lib/tir/lower_actor.ml`) were missing from
   `Defun.builtin_names`, and their vars are `TFn`-typed, so Defun's indirect-call rewrite
   turned them into `ECallPtr`s. Perceus treats every `ECallPtr` argument as owned without
   consulting the borrow table, so the supervisor got `inc_rc $spawned` before each call
   (two leaked refs per supervisor) and the child pid was consumed by
   `register_supervisor_child` (one leaked ref per child). Codegen was unaffected: the
   no-slot `ECallPtr` arm and the `EApp` builtin arm both emit a direct call to the C symbol.

Hence the todo's measurements: a supervised child at 3 (its own reference, `pid_index_of`'s,
`register_supervisor_child`'s), a plain actor +1 per `pid_to_int`.

### C audit (2026-09-24)

Each of these only reads its pid: `march_pid_index_of` (tombstone lookup, returns the
index), `march_actor_get_int` (one word load), `march_actor_set_mbox_limit` (meta lookup,
sets the green thread's limit), `march_register_supervisor` (writes meta fields),
`march_actor_register_child` (links the two metas and activates the child; the child's own
reference was already taken by `march_spawn_common`, deferred activation or not). The one
thing `register_child` stores is `spawn_clo`, which stays owned. Every producer of the pids
involved returns an owned reference (spawn, spawn_supervised, pid_of_int).

### Fix

- `borrow.ml`: the six names (plus their C names) moved from `extern_owned_builtins` to
  `extern_borrow_table`, pid positions borrowed, `spawn_clo` owned.
- `defun.ml`: `register_supervisor` and `register_supervisor_child` added to
  `builtin_names`, so they stay `EApp` and Perceus consults the table. The glue now reads
  `register_supervisor_child($spawned, $sup_child_ptr_child, …); dec_rc $sup_child_ptr_child`.

### Not changed: `get_actor_field`

It also only reads its pid and is also owned, so each call still leaks one reference
(visible in the fixture: the supervisor stays at 2 after `get_actor_field(boss, …)`). It is
left alone on purpose: `march_get_actor_field` returns a non-Int field's raw pointer
WITHOUT a reference of its own, and the leaked pid is what keeps a dead actor's record,
and so that field, alive. Borrowing the pid would turn a leak into a possible use-after-free
on a dead actor. Filed as `specs/todos/2026-09-24-get-actor-field-pid-and-result-ownership.md`.

### Evidence

`test/native/pid_to_int_leak_probe.march` (dune rule `native_pid_to_int_leak_probe`) reads the
record's count word through `ffi_test_actor_rc`:

| line | base (origin/main 12e9f647b) | borrow.ml half only | fixed |
|---|---|---|---|
| worker held by `w` and itself (rc == 2) | false | true | true |
| `pid_to_int` x3 leaves the count alone | false | true | true |
| `Actor.set_queue_limit` x2 leaves the count alone | false | true | true |
| supervised child held only by itself (rc == 1) | false | **false** | true |

Raw counts from a scratch probe: base `plain: 3 5`, `child: 3`, `boss: 5`; fixed
`plain: 2 2`, `child: 1`, `boss: 2` (the remaining boss reference is `get_actor_field`'s,
above). An rc of 1 is the running actor's own reference, released by
`actor_green_thread` at its last access, so the record is freed when the actor exits.

---

Found 2026-09-23 while reproducing the `march_pid_of_int` use-after-free for the metas
PR of [[2026-09-23-proc-struct-reclamation-metas]].

## Symptom

A record that has ever been passed to `pid_to_int` is never freed. Measured in the Linux
container with a debug print at `actor_green_thread`'s final `march_decrc`:

| program | record refcount at the green thread's last release |
|---|---|
| `let w = spawn(W)` / `kill(w)` | 1 (freed) |
| the same plus `let n = pid_to_int(w)` | 2 (never freed) |
| a supervise-block child (glue calls `pid_index_of(child)`) | 3 |

## Cause

`lib/tir/borrow.ml`'s `extern_borrow_table` lists the actor builtins that only read their
Pid (`send`, `kill`, `is_alive`, `mailbox_size`, `get_cap`, …, audited 2026-09-14), but
not `pid_to_int` / `pid_index_of` / `march_pid_index_of`. Perceus therefore treats the
argument as consumed and passes an owned reference, and `march_pid_index_of` never
releases it. The supervise-block spawn glue (`lib/tir/lower_actor.ml`, the
`pid_index_of_var` application on `$sup_child_ptr_*`) goes through the same builtin, which
is presumably the extra reference on every supervised child.

## Why it matters

A leaked Pid keeps a dead actor's record (and, through Perceus drop functions, whatever
its state holds) forever. It also masked the metas PR's reproduction: with the leak, the
record is never freed, so `march_pid_of_int` on a dead pid could not be shown to touch
freed memory. `test/native/pid_of_int_dead_pid.march` avoids `pid_to_int` for that reason.

## Fix sketch

Add `pid_to_int`, `pid_index_of` and `march_pid_index_of` to the borrow table
(`march_pid_index_of` reads its argument and stores nothing). Then check that the
supervise glue's `$sup_child_ptr_*` is still released exactly once, and add an rc-probe
fixture like `actor_send_to_self` that asserts the record's count after `pid_to_int`.
