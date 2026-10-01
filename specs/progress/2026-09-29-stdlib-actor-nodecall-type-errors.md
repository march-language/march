# `actor.march` and `node_call.march` hidden type errors fixed

Sub-item of `specs/todos/2026-09-22-stdlib-distributed-module-errors.md`.

- `actor.march` (2): `Actor.top_by_mailbox` / `Actor.over_mailbox` were annotated
  `List((Pid, Int))`, but `mailbox_size` and `Actor.list` work on the parameterized
  `Pid(a)`. The annotations are now `List((Pid(a), Int))`. (The error lines had drifted
  from the todo's `:185`/`:205`.)
- `node_call.march` (5): `NoConnection` is a constructor of `NodeQueue.EnqueueError`,
  `NodeSend.SendError` and `RemoteCall.CallError`; the bare name resolved to the wrong one
  and cascaded into the `CallError`/`EnqueueError` mismatches. Both uses are now
  `RemoteCall.NoConnection`.
- The rows for both files are gone from `stdlib_known_internal_errors`
  (test/test_compiler.ml); the ratchet passes with the lower counts. `session_node` (3) and
  `cluster_node` (1) are untouched.
