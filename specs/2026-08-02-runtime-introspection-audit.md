# Runtime introspection audit (phase 0)

Date: 2026-08-02. Question: the positioning is "services that must stay up." Can an
operator attach to a running March node, list actors, inspect a supervision tree, and
see mailbox depths?

**Short answer: no. Nothing is attachable from outside the process.** The runtime holds
essentially all of the underlying data; none of it is exposed over any control channel,
and most of it is not exposed to March code either.

## What exists

| Capability | Status | Evidence |
|---|---|---|
| Mailbox depth, in-process | **Yes** | `mailbox_size(pid)` builtin — typechecked (`lib/typecheck/typecheck.ml:2155`), interpreted (`lib/eval/eval.ml:3937`), and compiled (`march_mailbox_size`, `lib/tir/llvm_builtins.ml:665`) |
| Actor state peek, in-process | Partial | `actor_get_int(pid, idx)` — int fields only, index-addressed, no field names |
| Per-process table with supervisor links, restart counts, strategy, window | **Yes, internal only** | actor meta struct, `runtime/march_runtime.c:1530-1590` |
| Find a process by pid | Internal only | `march_sched_find`, `runtime/march_scheduler.h:347` |
| Total spawned count | Internal only | `march_sched_total_spawned`, `runtime/march_scheduler.h:292` |
| Mailbox count primitive | Internal | `march_mailbox_count`, `runtime/march_message.h:156` |
| Enumerate live processes | **No** | no iterator over the process table at any layer |
| Supervision tree query | **No** | `supervise do … end` is parse-time (`lib/parser/parser.mly:609`) and registered into runtime meta; there is no reflection API. `Actor` exposes only `cast`/`call`/`reply` (`stdlib/actor.march`) |
| Attach to a running node | **No** | no control socket, no debug server, no remote shell anywhere in `runtime/` |
| Operator CLI (`observe`/`top`/`ps`) | **No** | not in `bin/main.ml` flags nor `forge/bin/main.ml` subcommands |
| Metrics/stats endpoint | **No** | `Logger` has OpenTelemetry-shaped JSON output and span helpers (`stdlib/logger.march:376,621`), but that is application logging, not runtime introspection |
| Debugger | Interpreter only | `--debug`, `--debug-tui`, `march dap`; nothing for a compiled running service |

Two adjacent things do exist and are worth not confusing with introspection:
`march_monitor_registry.c` / `DistLink` monitors (failure *notification*, not inspection),
and hot code reload's control plane (`--hot-reload`, `forge deploy-hot`), which is a
one-way deploy channel with capability admission, not a query channel.

## Consequences for the plan

1. **The gap is one of exposure, not of data.** The process table already carries the
   supervisor pointer, strategy, restart counter, and window per actor; mailbox depth is
   already a shipped builtin in all three backends. A first cut — enumerate the process
   table, walk `meta->supervisor` upward to build the tree, report mailbox depth and
   restart counts — is a runtime enumeration API plus a serializer, not new bookkeeping.
2. **The hot-reload control plane is the natural transport for attach.** It already has a
   socket, a framing, and capability-gated admission. An introspection query verb belongs
   there rather than in a second, separately-authenticated channel.
3. **Homepage claim scoping (phase 4/5).** "Supervision, clustering, hot reload" are
   defensible; anything implying operational visibility into a live node is not. The
   honest framing today is: failures are *handled* (supervision, monitors, restart
   strategies) but not *observable* from outside the process.
4. **State this publicly as a roadmap item.** This is the first thing an Elixir-native
   evaluator will reach for — `:observer`, `Process.info/1`, `:sys.get_state/1` are
   reflexes. A named roadmap entry reads as a known gap; silence reads as unawareness.
5. **The unglamorous layer is unaudited.** DWARF quality, whether `lldb` gives a usable
   backtrace across a green-thread/actor boundary, and what a crash report looks like are
   not covered here and are still open.
