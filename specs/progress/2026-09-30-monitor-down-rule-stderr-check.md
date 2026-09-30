# `native_actor_monitor_down_reason` loop rule: stderr is not dropped

Investigation only, from `specs/todos/2026-09-04-actor-monitor-down-reason-sigsegv-on-linux.md`
(third CI sighting: no `march: fatal` line in the log). The todo asked to check whether the
`test/dune` loop rule's `out=$(...)` capture loses stderr. It does not: a scratch dune project
using the rule's exact shape around a program that writes a `march: fatal ...` line to stderr
and then `raise(SIGSEGV)` showed the line in dune's failure log, ahead of the rule's own
`binary exited 139` report. No rule change was needed. The finding and the consequence
(the missing line means the crash bypassed the runtime's handler) are recorded in the todo,
which stays open; the crash itself is still unreproduced.
