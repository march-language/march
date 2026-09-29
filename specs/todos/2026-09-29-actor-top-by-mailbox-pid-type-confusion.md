`[P1]` **`Actor.top_by_mailbox` and `Actor.over_mailbox` return a type-confused pid.**

Filed 2026-09-29 from the observe quick wins
([`progress/2026-09-29-observe-quick-wins-results.md`](../progress/2026-09-29-observe-quick-wins-results.md), QW1 and QW3).

Both functions are annotated `: List((Pid, Int))` (`stdlib/actor.march:221`, `:241`).
The bare `Pid` resolves to the stdlib record type
`GlobalPid.Pid = { node_id : String, local_pid : Int, creation : Int }`
(`stdlib/global_pid.march:11`), not the builtin `Pid(a)`.

Observed:
- **Typecheck:** `pid_to_int(p)` on an element fails with "expected `Pid(d)` but
  got `Pid`", so callers cannot use the result as a pid at all.
- **Compiled:** `to_string(Actor.top_by_mailbox(intro, 3))` printed
  `[({ creation: 4309141808, local_pid: 1, node_id: "\000" }, 0)]`: the actor
  pointer is read as a three-field record. That is an out-of-type memory read.

Fix: annotate with the builtin pid type (`List((Pid(a), Int))` or whatever spelling
`Actor.list` uses), and add a native test that calls `pid_to_int` and
`mailbox_size` on `top_by_mailbox`'s first element. Also grep the stdlib for other
bare `Pid` annotations outside `global_pid.march`.
