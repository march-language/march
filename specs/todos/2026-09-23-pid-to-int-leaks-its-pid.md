# `[P3]` `pid_to_int` (and the supervise glue's `pid_index_of`) leaks a reference to its Pid

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
