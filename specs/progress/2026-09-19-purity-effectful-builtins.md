# A discarded await still waits: the purity oracle's effect families

Shipped 2026-09-19. Found while chasing "concurrent cluster sessions sometimes crash a
node" (the first item of the choreography hardening pass).

## The bug

`lib/tir/purity.ml` decides what DCE, fusion and inlining may delete, duplicate or
reorder. It listed the builtins with side effects (`impure_builtins`) and treated
every other builtin as pure. `task_await` and `task_await_unwrap` were not on the
list, so dead-code elimination deleted any await whose result was not used:

```march
let t = task_spawn(fn _ -> work())
let _ = task_await_unwrap(t)        -- compiled: no wait at all
let unused = task_await_unwrap(t)   -- the same
let _ = task_await_unwrap(a) + task_await_unwrap(b)   -- the same
```

The interpreter waited; compiled code ran on at once. In the cluster access-point
scenario, node-b's `main` did `let _ = task_await_unwrap(held1) + task_await_unwrap(held2)`
and then `ClusterNode.stop(h)`: it stopped the node while both sessions were still
running, so they failed "connection lost" -- and, once, with a SIGBUS as the node's
state was torn down under them. It looked like a concurrency bug in cluster sessions;
it was a miscompile.

A sweep of the builtins against the list found 74 more effectful ones treated as pure
(`file_delete`, `dir_rm_rf`, `task_cancel`, `tcp_accept`, `process_kill_proc`,
`vault_ns_set`, `ws_send`, ...) and more outside those families: `panic`, `todo_`,
in-place writers (`native_*_arr_set`, `ring_buf_push`, `simd_*_store`), `logger_*`,
`uuid_v7`, `mint_cap` / `revoke_cap`, reads of mutable runtime state (`self`,
`is_alive`, `mailbox_size`). Not every one was being deleted in practice (a discarded
`file_delete` or `panic` survived in a probe), but nothing guaranteed it.

## The fix

A builtin is impure when it is on the list, OR its family is effectful
(`impure_prefixes`: `task_`, `tcp_`, `tls_`, `http_`, `file_`, `dir_`, `process_`,
`actor_`, `vault_`, `dist_`, `signal_`, `ws_`, `logger_`, `ring_buf_`, `remote_`, `csv_`,
`dns_`, ...), OR it writes in place (`impure_suffixes`: `_set`, `_store`), OR it is in
`impure_named`. `pure_exceptions` keeps the two pure HTTP string functions pure. The
rules err wide on purpose: a pure builtin caught by them only loses an optimisation;
an impure one missed miscompiles.

## Tests

- `test/native/task_await_discarded`: a discarded await, an unused binding and a
  discarded sum of awaits must each wait; expected output is the interpreter's. Red
  with main's `purity.ml` (every "after" line printed before any task finished).
- `test_codegen` purity group: `effect families` checks the await family and a sample
  of the newly covered builtins impure, and a few pure ones still pure.
- The IR oracle over ~240 programs, main's `purity.ml` against the fix, lists every
  program whose emitted IR changed (see the PR).
