# `march_actor_register_child` grew `sup_children` outside every lock

Surfaced during review of PR #300 (per-child restart types); pre-existing since
the original compiled-supervision implementation, not introduced there.

## The defect

`march_actor_register_child` (`runtime/march_runtime.c`) appended a
`march_sup_child` slot with no mutex held at all:

```c
int idx = sup_meta->sup_num_children;
sup_meta->sup_children = realloc(sup_meta->sup_children,
                                  (size_t)(idx + 1) * sizeof(march_sup_child));
... assign fields ...
sup_meta->sup_num_children = idx + 1;
```

Two threads registering children of the **same** supervisor interleave as:

| step | thread A | thread B |
| --- | --- | --- |
| 1 | reads `idx = N` | |
| 2 | | reads `idx = N` |
| 3 | `realloc` → block P′, stores `sup_children = P′` | |
| 4 | | `realloc` of the **stale** P → block P″, frees P under A; stores `sup_children = P″` |
| 5 | writes slot N of P′ — now unreachable | writes slot N of P″ |
| 6 | `sup_num_children = N+1` | `sup_num_children = N+1` |

A's child is silently lost (its slot never reachable), the array is left at
length N+1 for two registrations, and any concurrent reader that latched the
old `sup_children` pointer between steps 3 and 4 dereferences freed memory.
The `realloc` return was also unchecked — an OOM would both leak the old block
and immediately NULL-deref.

Note the same function already took `g_tbl_mu` for the two-field
`child_meta` write, and it computed `child_meta->sup_child_index` from a
`sup_num_children` read **inside** that lock and then re-read the counter
outside it — so even single-threaded the two reads were not guaranteed to agree
under any future concurrency.

## Reachability: LATENT, not live

`lib/tir/lower_actor.ml` (`mk_reg_child_calls`, ~line 400) emits one
`register_supervisor_child` call per declared `supervise` field as a
straight-line `Tir.ELet` chain **inside the supervisor's own `<Name>_spawn`
body**, against the freshly-allocated `$spawned` pointer. That pointer is not
reachable from any other thread until registration completes, and the children
are not activated until `activate_actor_green_thread` at the end of each
registration call. So one supervisor's children are always registered
sequentially, by one green thread. `march_respawn_child` writes existing slots
in place and never appends.

Two *different* supervisors registering concurrently touch different
`march_actor_meta`, so they do not share this state.

Consequently this is a **hardening fix with no observable behavior change** —
hence no `CHANGELOG.md` entry. It converts an invariant that currently holds by
accident of lowering into one the runtime enforces.

## The fix

`g_supervise_mu` now covers the read of `sup_num_children`, the `realloc`, the
field assignments, and the counter bump as one indivisible step — the same leaf
lock, and the same discipline, `march_restart_budget_ok` already applies to the
sibling `sup_restart_ts` realloc.

The interleaving excluded, mechanically: with the lock, thread B cannot read
`idx` until thread A has published both `sup_children = P′` and
`sup_num_children = N+1`, so B reads `N+1`, reallocs from P′ (never a stale
pointer), and writes slot N+1. No lost update, no realloc of a freed block, no
reader observing a torn `sup_children`/`sup_num_children` pair.

Leaf-lock contract (documented above `g_supervise_mu`'s declaration: nothing
that can take another lock, run a March closure, or yield a green thread may
run while it is held) is preserved:

- both `find_or_create_meta` calls (which take `g_tbl_mu`) stay **before** the
  critical section, as they already were;
- `activate_actor_green_thread` (which allocates a stack and takes
  scheduler-internal locks) stays **after** it — the detach-then-act shape used
  elsewhere in this file;
- everything inside the lock is a plain C field read/write plus one `realloc`.

Two secondary corrections ride along in the same lines:

- `child_meta->sup_child_index` is now the `idx` this thread *claimed* under
  `g_supervise_mu`, not an independent re-read of `sup_num_children`.
- The child's back-pointer (`child_meta->supervisor`, still under `g_tbl_mu`) is
  published **after** its slot exists, so a crash-trap lookup that finds
  `supervisor` set can always index `sup_children[sup_child_index]`. Previously
  the back-pointer went out first.
- `realloc` failure is now checked (message + `exit(1)`, matching
  `find_or_create_meta`'s and `march_monitor`'s OOM handling) instead of
  leaking the old block and NULL-dereferencing.

## Not changed, deliberately

`march_respawn_child` mutates `sup_children[i]` in place on restart and does so
without `g_supervise_mu`. Adding the lock there would **violate** the leaf-lock
contract — it calls the child's `spawn_clo`, which is compiled March code that
can yield — so it must not be done that way. It is safe today for the same
reason registration is: appends only ever happen during `<Name>_spawn`, before
any child is activated, so no restart can overlap a `realloc`. Recorded here so
the next reader does not "fix" it into a deadlock; the existing deadlock
post-mortem in `g_supervise_mu`'s declaration comment is the long version.

`march_supervisor_notify`'s reads of `sup_children`/`sup_num_children` were
likewise left alone (a concurrent change was in flight in that region).

## Verification

- Four native supervision goldens byte-match `.expected`:
  `supervisor_spawn_children`, `supervisor_one_for_one_restart`,
  `supervisor_one_for_all_restart`, `supervisor_rest_for_one_restart`.
- `run_codegen`, `run_stdlib`, and `dune build --root . @test/runtest` clean.
