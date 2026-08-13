# march_send_checked reads meta->epoch as a plain field — same pre-fix pattern as the pid_index race

Discovered during Task 15's review (`.superpowers/sdd/2026-08-11-actor-system-hardening/`)
while auditing other plain (non-`_Atomic`) cross-thread reads of per-meta
fields after fixing the `pid_index` double-insert race. Pre-existing.

## The bug

`march_actor_meta.epoch` is written without any lock or atomic by
`march_respawn_child` (`runtime/march_runtime.c:2672`, `new_meta->epoch =
inherited_epoch;`) on the supervisor's thread, and read as a plain field by
`march_send_checked` (`runtime/march_runtime.c:5709`, `meta->epoch != epoch`)
on an arbitrary sender's thread — no synchronization between the two. Same
shape as the `pid_index` race Task 15 fixed (a plain write on one thread,
a plain read on another, no memory barrier ordering the two), just on a
different field that backs the same epoch-Cap capability-revocation plane
(`march_get_cap`/`march_is_cap_valid`/`march_send_checked`, all around
`:5580`-`:5717`).

Concretely: a sender holding a `Cap` captured before a supervised restart
can race `march_send_checked`'s epoch comparison against the respawn's write
to `new_meta->epoch`. On most architectures a torn read of a single aligned
`int64_t` is not itself observable, but the *ordering* is unsynchronized —
nothing prevents the sender's read from being reordered relative to other
state the respawn also updates unlocked (`new_meta->supervisor`,
`new_meta->sup_child_index` at `:2670`-`:2671`), so a compiler or CPU is free
to let the epoch compare observe the *new* epoch while other respawn-visible
state is still stale, or vice versa — exactly the kind of gap the `pid_index`
fix closed for that field.

## Suggested fix

Convert `march_actor_meta.epoch` to `_Atomic int64_t` (matching the
`pid_index`/`green_thread` precedent from Tasks 10/15) — release-store on
write (`march_respawn_child`'s `:2672`), acquire-load on read
(`march_send_checked`'s `:5709`, and `march_is_cap_valid`'s `:5673` which has
the same plain-read shape). Low risk, mechanical, same pattern already
proven out twice in this plan.
